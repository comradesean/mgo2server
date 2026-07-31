package mgo2server.game;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.Channel;
import io.netty.channel.ChannelOption;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class GameServer {
	private static final Logger logger = LogManager.getLogger();

	/**
	 * How long {@code stop()} waits for a periodic run already in flight.
	 * <p>
	 * Its own constant rather than the caller's timeout: {@code stop(0, 0, SECONDS)} is what the
	 * integration suite uses, and taking that literally would skip the wait in the one situation it
	 * was added for — a run outliving its server and failing against the next test's truncated
	 * schema.
	 */
	private static final long SCHEDULER_STOP_TIMEOUT_SECONDS = 5;

	private final CompletableFuture<Void> stopFuture = new CompletableFuture<>();

	private final List<IGameController> controllers;

	private final int port;

	private EventLoopGroup bossGroup;

	private EventLoopGroup workerGroup;

	private Channel serverChannel;

	private final PeriodicTask periodicTask;

	private ScheduledExecutorService scheduler;

	/**
	 * Work this server runs on a timer rather than in response to a packet.
	 *
	 * <p>Automatching is why this exists and is the shape it needs: a searching client
	 * <b>sends nothing at all</b> while it waits, so nothing the server does on the request path can
	 * ever advance a search. Something has to run on its own.
	 *
	 * @param name used for the thread name, so a stack trace says which job is stuck
	 * @param interval the gap <em>between</em> runs, not the period — see {@link #startScheduler}
	 * @param body run repeatedly until the server stops. Exceptions are caught and logged
	 */
	public record PeriodicTask(String name, Duration interval, Runnable body) {
	}

	/**
	 * @param port port to listen on, or 0 to bind an ephemeral port (see {@link #boundPort()})
	 */
	public GameServer(List<IGameController> controllers, int port) {
		this(controllers, port, null);
	}

	/**
	 * @param periodicTask work to run on a timer once the port is bound, or {@code null} for none
	 */
	public GameServer(List<IGameController> controllers, int port, PeriodicTask periodicTask) {
		this.controllers = controllers;
		this.port = port;
		this.periodicTask = periodicTask;
	}

	public CompletableFuture<Void> start() {
		bossGroup = new MultiThreadIoEventLoopGroup(NioIoHandler.newFactory());
		workerGroup = new MultiThreadIoEventLoopGroup(NioIoHandler.newFactory());

		var b = new ServerBootstrap();

		b.group(bossGroup, workerGroup);

		b.channel(NioServerSocketChannel.class);

		var serverHandler = new GameServerHandler(controllers);
		b.childHandler(new GameServerChannelInitializer(serverHandler));

		b.option(ChannelOption.SO_BACKLOG, 128);

		b.childOption(ChannelOption.SO_KEEPALIVE, true);

		var future = new CompletableFuture<Void>();
		var bindFuture = b.bind(port);
		bindFuture.addListener(e -> {
			if (e.isSuccess()) {
				serverChannel = bindFuture.channel();
				logger.info("Game server listening on port {}.", boundPort());
				// After the bind, not before: a job that touches connections should not run against a
				// server that never came up.
				startScheduler();
				future.complete(null);
			} else {
				// Without this the bind failure was swallowed and the server looked started.
				logger.error("Failed to bind game server to port {}.", port, e.cause());
				future.completeExceptionally(e.cause());
			}
		});
		return future;
	}

	/** The port actually bound, which differs from the requested port when that port was 0. */
	public int boundPort() {
		if (serverChannel == null) {
			throw new IllegalStateException("Server is not started.");
		}
		return ((InetSocketAddress) serverChannel.localAddress()).getPort();
	}

	/**
	 * Starts the periodic task, if there is one, on a single daemon thread of its own.
	 *
	 * <p>Three details here are each a real bug if changed, and none is obvious:
	 *
	 * <ul>
	 * <li><b>A dedicated thread, not a Netty event loop.</b> An {@code EventLoopGroup} is already a
	 * {@code ScheduledExecutorService} and would give lifecycle for free, which is tempting — but the
	 * body does blocking JDBC, and parking a worker loop on Postgres stalls every channel assigned to
	 * that loop. Writing to a channel from this thread is still safe: Netty queues the write onto the
	 * channel's own loop, so the encoder's sequence counter stays single-threaded.</li>
	 * <li><b>{@code scheduleWithFixedDelay}, not {@code scheduleAtFixedRate}.</b> Fixed-rate bursts to
	 * catch up after a slow run; fixed-delay waits out the gap. A matchmaker that has just spent four
	 * seconds in the database should not immediately run again.</li>
	 * <li><b>{@code catch (Throwable)} around the body.</b> A scheduled task that throws is cancelled
	 * <em>permanently and silently</em> — one transient database error would stop the job for the
	 * lifetime of the process with nothing in the log to say so.</li>
	 * </ul>
	 *
	 * <p>Single-threaded is also load-bearing beyond simplicity: it means two runs can never overlap,
	 * which removes a whole class of race from whatever the body does.
	 */
	private void startScheduler() {
		if (periodicTask == null) {
			return;
		}
		scheduler = Executors.newSingleThreadScheduledExecutor(runnable -> {
			var thread = new Thread(runnable, "mgo2-" + periodicTask.name());
			// Daemon so a wedged job cannot keep a shut-down JVM alive; stop() joins it properly.
			thread.setDaemon(true);
			return thread;
		});
		var millis = periodicTask.interval().toMillis();
		scheduler.scheduleWithFixedDelay(() -> {
			try {
				periodicTask.body().run();
			} catch (Throwable t) {
				logger.error("Periodic task {} threw; it will run again in {} ms.",
					periodicTask.name(), millis, t);
			}
		}, millis, millis, TimeUnit.MILLISECONDS);
		logger.info("Periodic task {} scheduled every {} ms.", periodicTask.name(), millis);
	}

	/**
	 * Stops the periodic task and waits for a run in progress to finish.
	 *
	 * <p>The wait is not politeness. {@code BaseGameClientServerIT} stops the server and the next
	 * test truncates the database; a run still in flight against a truncated schema fails in a
	 * <em>different</em> test class, which is about the worst diagnostic a suite can produce.
	 */
	private void stopScheduler() {
		if (scheduler == null) {
			return;
		}
		scheduler.shutdownNow();
		try {
			if (!scheduler.awaitTermination(SCHEDULER_STOP_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
				logger.warn("Periodic task {} did not stop within {} s; it ignored an interrupt.",
					periodicTask.name(), SCHEDULER_STOP_TIMEOUT_SECONDS);
			}
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
		}
		scheduler = null;
	}

	public CompletableFuture<Void> stop() {
		return stop(2L, 15L, TimeUnit.SECONDS);
	}

	public CompletableFuture<Void> stop(long quietPeriod, long timeout, TimeUnit unit) {
		// Before the event loops, so the job cannot write to a channel that is being torn down.
		//
		// Deliberately NOT bounded by this call's timeout argument: the integration suite stops with
		// stop(0, 0, SECONDS), and honouring a zero here would mean never waiting at all — in exactly
		// the case the wait exists for. shutdownNow interrupts, so a well-behaved body returns at
		// once and this costs nothing.
		stopScheduler();

		var futures = new ArrayList<CompletableFuture<Void>>();

		if (workerGroup != null) {
			var future = new CompletableFuture<Void>();
			workerGroup.shutdownGracefully(quietPeriod, timeout, unit).addListener(e -> future.complete(null));
			futures.add(future);
		}

		if (bossGroup != null) {
			var future = new CompletableFuture<Void>();
			bossGroup.shutdownGracefully(quietPeriod, timeout, unit).addListener(e -> future.complete(null));
			futures.add(future);
		}

		return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
			.whenComplete((v, e) -> stopFuture.complete(null));
	}

	public void run() {
		Runtime.getRuntime().addShutdownHook(new Thread(() -> {
			logger.info("Shutting down game server...");
			stop().join();
		}));

		start().join();

		stopFuture.join();
	}
}
