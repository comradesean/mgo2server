package nomad.game;

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
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public class GameServer {
	private static final Logger logger = LogManager.getLogger();

	private final CompletableFuture<Void> stopFuture = new CompletableFuture<>();

	private final List<IGameController> controllers;

	private final int port;

	private EventLoopGroup bossGroup;

	private EventLoopGroup workerGroup;

	private Channel serverChannel;

	/**
	 * @param port port to listen on, or 0 to bind an ephemeral port (see {@link #boundPort()})
	 */
	public GameServer(List<IGameController> controllers, int port) {
		this.controllers = controllers;
		this.port = port;
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

	public CompletableFuture<Void> stop() {
		return stop(2L, 15L, TimeUnit.SECONDS);
	}

	public CompletableFuture<Void> stop(long quietPeriod, long timeout, TimeUnit unit) {
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
