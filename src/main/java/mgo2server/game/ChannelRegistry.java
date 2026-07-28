package mgo2server.game;

import io.netty.channel.Channel;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.Optional;
import java.util.function.Consumer;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Live channels on this server by character id — the only way to reach a client that is not the one
 * currently asking.
 *
 * <h2>Why this is a controller</h2>
 * It handles no commands. It implements {@link IGameController} purely to inherit
 * {@link IGameController#onPacket} and {@link IGameController#onDisconnect}, which is where the map
 * is kept current: {@code onPacket} fires for every inbound packet on every controller before
 * dispatch, whether or not anything handles that command, and {@code onDisconnect} fires on
 * {@code channelInactive}. Registering it in {@code GameServerFactory} alongside the real
 * controllers is what makes those hooks fire.
 *
 * <h2>Why it is not static</h2>
 * Production runs a process per lobby, so one instance per server is one instance per lobby. The
 * integration tests, though, stand several servers up in one JVM, and a static map would silently
 * join them together — a test would push to a character on another test's server and pass for the
 * wrong reason. This reasoning is inherited verbatim from {@code ChatGameController}, which owned
 * this map before it was extracted.
 *
 * <h2>Pushing</h2>
 * Callers must allocate <b>one buffer per recipient from that recipient's own channel</b> and use
 * {@code writeAndFlush}:
 *
 * <pre>{@code
 * var buffer = channel.alloc().buffer(size);
 * ...
 * channel.writeAndFlush(new GamePacket(command, buffer));
 * }</pre>
 *
 * The encoders are per-channel and carry sequence counters, so a buffer cannot be shared between
 * channels and a requesting client's {@link GameControllerContext} must never be reused to reach a
 * different client. {@code writeAndFlush} rather than {@code write} because no request handler will
 * follow to flush it — that only happens on the request path, in {@code GameServerHandler}.
 *
 * <p>Writing from a thread other than the channel's event loop is safe: Netty queues the write onto
 * that loop, so the encoder's sequence counter still advances single-threaded.
 */
public class ChannelRegistry implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	private final Map<Long, Channel> channels = new ConcurrentHashMap<>();

	/** Handles no commands. The hooks below are the entire point of this class being a controller. */
	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
	}

	/**
	 * Notes which channel belongs to which character.
	 * <p>
	 * This fires <em>before</em> dispatch while {@code authenticate()} happens <em>inside</em> it, so
	 * a character that has just checked in is not registered until its next packet. That is why
	 * {@link #track} exists and is called from the authenticating handler as well: a matchmaker
	 * that pushes to a searcher the moment they arrive cannot wait for a second packet, and a
	 * searching client sends nothing at all while it waits.
	 */
	@Override
	public void onPacket(GameConnection connection, Channel channel) {
		var account = connection.account();
		if (account == null || account.getCurrentCharaId() == null) {
			return;
		}
		track(account.getCurrentCharaId(), channel);
	}

	/** Notes a character's channel explicitly, for callers that cannot wait for the next packet. */
	public void track(long charaId, Channel channel) {
		var previous = channels.put(charaId, channel);
		if (previous != null && previous != channel && previous.isActive()) {
			// Same character on two live channels: a reconnect that raced its own teardown, or two
			// clients sharing a character. The newest wins; the old one is left to close on its own.
			logger.info("Character {} now has a second live channel; pushes will go to the newest.",
				charaId);
		}
	}

	@Override
	public void onDisconnect(GameConnection connection) {
		var account = connection.account();
		if (account != null && account.getCurrentCharaId() != null) {
			channels.remove(account.getCurrentCharaId());
		}
		// The account is cleared before teardown on some paths, so sweep anything already dead rather
		// than trusting the keyed removal alone.
		channels.values().removeIf(channel -> !channel.isActive());
	}

	/**
	 * The live channel for a character, or empty when there is none on this server.
	 * <p>
	 * A missing entry is not an error: the player may be connected to a different lobby process, or
	 * may have dropped without tearing down. Callers skip them.
	 */
	public Optional<Channel> channel(long charaId) {
		var channel = channels.get(charaId);
		return channel != null && channel.isActive() ? Optional.of(channel) : Optional.empty();
	}

	/** How many characters currently have a live channel here. Diagnostics and tests. */
	public int size() {
		return (int) channels.values().stream().filter(Channel::isActive).count();
	}
}
