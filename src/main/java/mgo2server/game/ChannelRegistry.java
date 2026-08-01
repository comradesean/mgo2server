package mgo2server.game;

import io.netty.channel.Channel;
import mgo2server.common.service.PresenceService;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
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
 *
 * <h2>Presence</h2>
 * This map is per-process, so it answers "is this character on <em>my</em> server". The shared
 * answer to "which lobby is this character in" lives in {@code chara_presence}, and this class is
 * what keeps it current — the two have exactly the same lifecycle, so tracking them anywhere else
 * would mean a second set of hooks that could drift. See {@code dev/docs/PRESENCE.md}.
 *
 * <p><b>Presence writes happen on transitions only, never per packet.</b> {@link #onPacket} fires
 * for every inbound packet on every controller; a database write there would be a write per packet.
 * The write lives in {@link #track}, which only touches the database when the character was not
 * already in the map.
 */
public class ChannelRegistry implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	private final Map<Long, Channel> channels = new ConcurrentHashMap<>();

	/**
	 * Null when this server is not recording presence — the unit tests, which have no database.
	 * Every use is guarded, so presence is strictly additive to the map's existing behaviour.
	 */
	private final PresenceService presenceService;

	private final long lobbyId;

	/**
	 * Whether this server records presence at all.
	 * <p>
	 * <b>Only a real lobby can.</b> Gate and account servers are constructed with {@code lobbyId}
	 * 0, which is not a row in {@code lobby} — and more to the point, a connection to one is not
	 * "in a lobby" in any sense a player would recognise: the character may not even be selected
	 * yet. Recording presence there would both violate the foreign key and assert something false.
	 * <p>
	 * The reaper still runs on those servers; see {@link #refreshPresence}.
	 */
	private final boolean recordsPresence;

	/** A registry that keeps the channel map only. Used where there is no database to write to. */
	public ChannelRegistry() {
		this(null, 0L);
	}

	/**
	 * A registry that also maintains this lobby's rows in {@code chara_presence}.
	 *
	 * @param presenceService the shared store, or null to keep the channel map only
	 * @param lobbyId which lobby this process is; every presence write is scoped to it
	 */
	public ChannelRegistry(PresenceService presenceService, long lobbyId) {
		this.presenceService = presenceService;
		this.lobbyId = lobbyId;
		this.recordsPresence = presenceService != null && lobbyId != 0;
	}

	/**
	 * Drops any presence rows this lobby left behind, and returns how many there were.
	 * <p>
	 * Call once after a successful bind. <b>Nobody is connected to a process that has just
	 * started</b>, so this is exact rather than heuristic and recovers from hard kills and
	 * crash-loops immediately. A nonzero count after a clean shutdown means disconnects were not
	 * being processed, which is worth knowing.
	 */
	public int clearStalePresence() {
		if (!recordsPresence) {
			return 0;
		}
		var cleared = presenceService.clearLobby(lobbyId);
		if (cleared > 0) {
			logger.info("Cleared {} stale presence row(s) for lobby {} at startup.", cleared,
				lobbyId);
		}
		return cleared;
	}

	/**
	 * Refreshes this lobby's presence rows and removes rows left by processes that are gone.
	 * <p>
	 * Driven by {@code GameServer}'s scheduler. Both statements are batched, so this is two round
	 * trips per tick regardless of how many players are connected.
	 */
	public void refreshPresence() {
		if (presenceService == null) {
			return;
		}
		// The reap runs even on a server that records nothing. It is the only thing that cleans up
		// after a lobby process that died and never came back, and it is scoped to no lobby, so the
		// more servers running it the sooner that happens.
		if (recordsPresence) {
			heartbeat();
		}
		var reaped = presenceService.reapStale();
		if (reaped > 0) {
			logger.info("Reaped {} presence row(s) from lobby processes that are no longer running.",
				reaped);
		}
	}

	private void heartbeat() {
		var live = liveCharacterIds();
		var touched = presenceService.heartbeat(live);
		if (touched < live.size()) {
			// Rows went missing under a live connection: either the reaper is too aggressive or
			// another process took ownership of the character. Both are worth a line.
			logger.warn("Presence heartbeat touched {} of {} live characters in lobby {}.", touched,
				live.size(), lobbyId);
		}
	}

	/** The characters with a live channel here, which is what the heartbeat asserts is still true. */
	public Set<Long> liveCharacterIds() {
		return channels.entrySet().stream()
			.filter(entry -> entry.getValue().isActive())
			.map(Map.Entry::getKey)
			.collect(java.util.stream.Collectors.toSet());
	}

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
		if (previous == null && recordsPresence) {
			// First sighting on this server, so this is the arrival. Writing only on the transition
			// is what keeps onPacket -- which fires for every inbound packet -- off the database.
			presenceService.enter(charaId, lobbyId);
		}
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
			var charaId = account.getCurrentCharaId();
			channels.remove(charaId);
			if (recordsPresence) {
				// Scoped to this lobby ON PURPOSE -- see PresenceService.leave. A hop is two
				// processes racing, and an unscoped delete here would erase the arrival the
				// destination lobby has already recorded.
				presenceService.leave(charaId, lobbyId);
			}
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
