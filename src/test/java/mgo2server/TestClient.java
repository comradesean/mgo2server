package mgo2server;

import io.netty.bootstrap.Bootstrap;
import io.netty.buffer.Unpooled;
import io.netty.channel.Channel;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelOption;
import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import mgo2server.common.ClientVersion;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.GameError;
import mgo2server.game.controller.AccountGameController;
import mgo2server.game.packet.GamePacket;
import mgo2server.game.packet.GamePacketDecoder;
import mgo2server.game.packet.GamePacketEncoder;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * One connected client that stays open, collects everything the server says, and can be waited on.
 *
 * <h2>Why this exists alongside {@link GameClient}</h2>
 * {@link GameClient#run} <b>blocks the calling thread</b> until the handler closes the channel, so a
 * test written against it owns exactly one connection: the second client would have to be driven from
 * inside the first one's handler, or from a thread the test then has to join. That is fine for a
 * request/reply exchange and impossible for anything where two clients have to be simultaneously
 * <em>present</em> before the server will act.
 *
 * <p>Automatching is the case that forces the change and the reason to read this class as protocol
 * rather than convenience. A searching client <b>sends nothing at all</b> — state 6 of the screen's
 * state machine ({@code 0x93CF78}) makes no network call, there is no heartbeat, and the search is
 * driven purely by pushes ({@code AUTOMATCH.md} §2). So the only way to observe a match forming is to
 * have two sockets open, both quiet, both listening. Nothing about that is expressible as a sequence
 * of exchanges.
 *
 * <h2>Retaining packets is safe here</h2>
 * {@link GamePacketDecoder} emits {@code Unpooled.wrappedBuffer} over a freshly copied heap array, so
 * a packet held past its {@code channelRead} is not a reference-counting hazard and its payload can
 * be read from the test thread after the fact. Every accessor below uses absolute {@code getXxx},
 * which leaves the reader index alone so a packet can be asserted on more than once.
 *
 * <h2>Threading</h2>
 * Netty's event loop appends; the test thread waits and reads. Both go through the monitor on the
 * packet list, and every wait is woken by the append, so a push that lands between the predicate
 * being evaluated and the wait starting cannot be missed.
 */
public final class TestClient implements AutoCloseable {

	/**
	 * How long a wait runs before it is a failure.
	 * <p>
	 * Generous on purpose: everything waited on here is driven by the server's matchmaker tick, and a
	 * test that shortens this to make a run faster converts a slow CI box into a red build. The
	 * failure message names what was being waited for and lists what did arrive, which is the thing
	 * that actually shortens debugging.
	 */
	public static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(20);

	private final String name;

	private final MultiThreadIoEventLoopGroup group;

	private final Channel channel;

	/** Also the monitor every wait parks on. */
	private final List<GamePacket> received = new ArrayList<>();

	private volatile long charaId;

	/**
	 * Connects, and does not return until the socket is up.
	 *
	 * @param name used in failure messages; with several clients open, "client B timed out" is the
	 *     whole diagnosis and an anonymous timeout is none of it
	 */
	public TestClient(String name, int port) {
		this.name = name;
		// One thread per client rather than a shared group, so a client that is deliberately hung or
		// closed mid-test cannot stall another one's reads.
		this.group = new MultiThreadIoEventLoopGroup(1, NioIoHandler.newFactory());

		var bootstrap = new Bootstrap()
			.group(group)
			.channel(NioSocketChannel.class)
			.option(ChannelOption.SO_KEEPALIVE, true)
			.handler(new ChannelInitializer<SocketChannel>() {
				@Override
				protected void initChannel(SocketChannel ch) {
					// Both codecs are stateful — the decoder tracks the expected sequence and the
					// encoder counts the outgoing one — so each channel gets its own pair.
					ch.pipeline()
						.addLast(GamePacketEncoder.forClient())
						.addLast(GamePacketDecoder.forClient())
						.addLast(new ChannelInboundHandlerAdapter() {
							@Override
							public void channelRead(ChannelHandlerContext ctx, Object msg) {
								if (msg instanceof GamePacket packet) {
									synchronized (received) {
										received.add(packet);
										received.notifyAll();
									}
								}
							}
						});
				}
			});

		this.channel = bootstrap.connect("localhost", port).syncUninterruptibly().channel();
	}

	/** The character this client checked in as. */
	public long charaId() {
		return charaId;
	}

	public String name() {
		return name;
	}

	/**
	 * Sends {@code 0x3003} and waits for a zero {@code 0x3004}.
	 * <p>
	 * Fails rather than returns on a nonzero result: every test using this class is about what happens
	 * <em>after</em> a login, and a silent failure here would surface as an unexplained timeout on the
	 * first thing actually being tested.
	 */
	public TestClient login(long charaId, String token) {
		this.charaId = charaId;
		var payload = Unpooled.buffer();
		payload.writeInt((int) charaId);
		payload.writeBytes(SessionField.of(ClientVersion.V1_0, token));

		send(new GamePacket(AccountGameController.CHECK_SESSION, payload));

		var reply = await(AccountGameController.CHECK_SESSION_RESULT, DEFAULT_TIMEOUT);
		assertThat(reply.getPayload().getInt(0))
			.as("%s check-session result", name)
			.isEqualTo(GameError.NONE.result());
		return this;
	}

	/** Writes and flushes, and does not return until the bytes are on the socket. */
	public void send(GamePacket packet) {
		channel.writeAndFlush(packet).syncUninterruptibly();
	}

	/** Every packet with this command, oldest first. */
	public List<GamePacket> received(int command) {
		synchronized (received) {
			return received.stream().filter(packet -> packet.getCommand() == command).toList();
		}
	}

	public int count(int command) {
		return received(command).size();
	}

	/** Waits for the first packet with this command and returns it. */
	public GamePacket await(int command, Duration timeout) {
		return awaitAtLeast(command, 1, timeout).get(0);
	}

	/** Waits until at least {@code count} packets with this command have arrived. */
	public List<GamePacket> awaitAtLeast(int command, int count, Duration timeout) {
		awaitCondition(count + " × command " + hex(command), timeout, () -> count(command) >= count);
		return received(command);
	}

	/**
	 * Waits for an arbitrary predicate over what has arrived.
	 *
	 * @param what named in the failure message, because a timeout with no subject is the least useful
	 *     assertion failure there is
	 */
	public void awaitCondition(String what, Duration timeout, BooleanSupplier condition) {
		var deadline = System.nanoTime() + timeout.toNanos();
		synchronized (received) {
			while (!condition.getAsBoolean()) {
				var remaining = deadline - System.nanoTime();
				if (remaining <= 0) {
					throw new AssertionError(name + " waited " + timeout + " for " + what
						+ " and it never arrived; it received " + summary());
				}
				try {
					// Ceiling rather than floor, so a sub-millisecond remainder cannot become wait(0),
					// which in Netty's own idiom means "wait forever".
					received.wait((remaining + 999_999) / 1_000_000);
				} catch (InterruptedException e) {
					Thread.currentThread().interrupt();
					throw new AssertionError(name + " was interrupted waiting for " + what, e);
				}
			}
		}
	}

	/**
	 * Lets the server run for a while so that an <em>absence</em> can be asserted afterwards.
	 * <p>
	 * A plain sleep, and deliberately so: the assertion this supports is "nothing arrived", and there
	 * is no event to wait for. Pass a window worth several matchmaker ticks or the absence proves only
	 * that the tick had not run yet.
	 */
	public static void letTicksPass(Duration window) {
		try {
			Thread.sleep(window.toMillis());
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			throw new AssertionError("Interrupted while letting ticks pass", e);
		}
	}

	/** What arrived, by command, for a failure message. */
	public String summary() {
		synchronized (received) {
			if (received.isEmpty()) {
				return "nothing at all";
			}
			var counts = new LinkedHashMap<Integer, Integer>();
			for (var packet : received) {
				counts.merge(packet.getCommand(), 1, Integer::sum);
			}
			var text = new StringBuilder();
			counts.forEach((command, count) -> text.append(text.isEmpty() ? "" : ", ")
				.append(hex(command)).append(" ×").append(count));
			return text.toString();
		}
	}

	private static String hex(int command) {
		return "0x" + Integer.toHexString(command);
	}

	/**
	 * Closes the socket and the event loop.
	 * <p>
	 * Idempotent, because tests close a client deliberately — a disconnecting host is a real automatch
	 * path ({@code AUTOMATCH.md} §6) — and the fixture then closes it again on the way out.
	 */
	@Override
	public void close() {
		channel.close().awaitUninterruptibly();
		group.shutdownGracefully(0L, 0L, TimeUnit.SECONDS).awaitUninterruptibly();
	}
}
