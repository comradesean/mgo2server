package mgo2server.game;

import io.netty.channel.Channel;
import io.netty.util.concurrent.Future;
import io.netty.util.concurrent.GenericFutureListener;
import mgo2server.common.AutomatchPolicy;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The automatch queue and the periodic work that drives it.
 *
 * <h2>Why this lives in {@code game/} and not {@code common/service/}</h2>
 * It holds channels, a queue and the id of one lobby — all per-server state. {@code Services} is
 * lobby-agnostic, constructed once per process from a {@code Jdbi} and shared, so putting a queue
 * behind it would re-create exactly the hazard {@link ChannelRegistry} documents avoiding: the
 * integration tests stand several servers up in one JVM, and shared mutable state silently joins
 * them together.
 *
 * <h2>Why the channel is captured rather than looked up</h2>
 * {@link ChannelRegistry} could resolve a character to a channel, and this deliberately does not use
 * it. The {@code 0x43e0} handler is <em>the same event</em> as the client registering its own push
 * channel 60 — answering result 0 is what registers it ({@code 0x93CF04}). Capturing the channel
 * there makes the server's record and the client's record the same event by construction, which is a
 * stronger guarantee than looking one up and hoping the map is populated. It also gives precise
 * removal for free, via {@code closeFuture}.
 *
 * <h2>Threading</h2>
 * {@link #enqueue} and {@link #cancel} run on channel event loops, many threads; {@link #tick} runs
 * on the server's single scheduler thread. The map is concurrent and the handlers only ever touch
 * one key, so they need no coordination. Multi-entry transitions — electing a host, releasing a
 * group — belong to the tick alone, and the scheduler being single-threaded means two ticks can
 * never overlap.
 */
public class Automatch {
	private static final Logger logger = LogManager.getLogger();

	/**
	 * How long a searcher may sit in the queue before we drop them.
	 * <p>
	 * The client gives up on its own at roughly twenty minutes and sends {@code 0x43e2}, so this is
	 * a backstop for the searcher whose socket died without a close: it exists so the queue cannot
	 * grow without bound, not to enforce a deadline the client already enforces. Deliberately longer
	 * than the client's own timeout so the client is always the one that gives up first.
	 */
	public static final Duration MAX_WAIT = Duration.ofMinutes(25);

	/**
	 * "Do not specify rules" — the sentinel the client's own menu row 0 carries ({@code 0x93B610}),
	 * deliberately outside the 0–10 range its rule-label mapper accepts.
	 * <p>
	 * Repeated from the controller rather than shared, so this class stays free of packet concerns.
	 * It is a value the client fixes, not one either side chooses, so the duplication cannot drift.
	 */
	public static final int ANY_RULE = 11;

	/** What happened to a cancel, which decides the result code {@code 0x43e3} carries. */
	public enum CancelOutcome {
		/** Removed from the queue, or was never in it. Result 0. */
		CANCELLED,

		/**
		 * Already matched, and the pushes are on their way. Result {@code -953}, the one code that
		 * parks the client silently rather than raising a dialog — erroring here would be a lie and
		 * succeeding would strand the match.
		 */
		TOO_LATE
	}

	/** Where a searcher is in the process. */
	public enum State {
		SEARCHING,

		/** Named in a match; the elected host is creating the game. */
		AWAITING_HOST_CREATE,

		/** Released into a game. */
		MATCHED
	}

	/**
	 * One queued searcher.
	 *
	 * <p>Mutable in exactly one field, {@code state}, which only the tick writes. Everything else is
	 * fixed at enqueue.
	 */
	public static final class Searcher {
		private final long charaId;

		private final int ruleFilter;

		private final int experience;

		private final Instant joinedAt;

		private final Channel channel;

		private volatile State state = State.SEARCHING;

		private volatile GenericFutureListener<Future<? super Void>> onClose;

		Searcher(long charaId, int ruleFilter, int experience, Instant joinedAt, Channel channel) {
			this.charaId = charaId;
			this.ruleFilter = ruleFilter;
			this.experience = experience;
			this.joinedAt = joinedAt;
			this.channel = channel;
		}

		public long charaId() {
			return charaId;
		}

		public int ruleFilter() {
			return ruleFilter;
		}

		public int experience() {
			return experience;
		}

		public Instant joinedAt() {
			return joinedAt;
		}

		public Channel channel() {
			return channel;
		}

		public State state() {
			return state;
		}

		/** Stops this entry's close listener from firing once the entry is no longer in the queue. */
		void detach() {
			var listener = onClose;
			if (listener != null) {
				channel.closeFuture().removeListener(listener);
				onClose = null;
			}
		}
	}

	private final AutomatchPolicy policy;

	private final Map<Long, Searcher> searchers = new ConcurrentHashMap<>();

	public Automatch(AutomatchPolicy policy) {
		this.policy = policy;
	}

	/**
	 * Adds a searcher, replacing any earlier entry for the same character.
	 *
	 * <p>Registering a {@code closeFuture} listener here rather than relying on a disconnect hook is
	 * what makes removal exact: the listener fires on that specific channel closing, so a reconnect
	 * that races its own teardown cannot evict the new entry.
	 */
	public void enqueue(long charaId, int ruleFilter, int experience, Channel channel) {
		var searcher = new Searcher(charaId, ruleFilter, experience, Instant.now(), channel);
		// The listener is held on the entry and detached when the entry goes, because a channel
		// outlives any one search: a player who searches, cancels and searches again on the same
		// connection would otherwise leave a listener behind every time. Each one is harmless on its
		// own — the removal is keyed on the exact Searcher — but they accumulate for the life of the
		// connection, which is a leak rather than a bug only until someone does it a thousand times.
		GenericFutureListener<Future<? super Void>> onClose = future -> {
			if (searchers.remove(charaId, searcher)) {
				logger.info("Chara {} left automatching by disconnecting; {} searching.", charaId,
					searchers.size());
			}
		};
		searcher.onClose = onClose;
		// Replacing an entry has to detach the old listener too, or the same accumulation happens
		// through re-entry rather than through cancel.
		var previous = searchers.put(charaId, searcher);
		if (previous != null) {
			previous.detach();
		}
		channel.closeFuture().addListener(onClose);
		logger.info("Chara {} is searching for rule {}; {} searching.", charaId,
			ruleFilter == ANY_RULE ? "any" : ruleFilter, searchers.size());
	}

	/**
	 * Removes a searcher.
	 *
	 * <p>The outcome is decided by the state at the moment this runs, which is what makes the race
	 * with the tick decidable rather than a coin flip: if the tick has already marked this searcher
	 * matched, the cancel is too late no matter how the wall clock happened to fall.
	 */
	public CancelOutcome cancel(long charaId) {
		var searcher = searchers.get(charaId);
		if (searcher == null) {
			// Never queued, or already reaped. Cancelling nothing succeeds.
			return CancelOutcome.CANCELLED;
		}
		if (searcher.state() != State.SEARCHING) {
			return CancelOutcome.TOO_LATE;
		}
		if (searchers.remove(charaId, searcher)) {
			searcher.detach();
		}
		logger.info("Chara {} cancelled automatching; {} searching.", charaId, searchers.size());
		return CancelOutcome.CANCELLED;
	}

	/** How many are searching right now. */
	public int size() {
		return searchers.size();
	}

	/** A snapshot, for the tick and for tests. */
	public Collection<Searcher> searchers() {
		return List.copyOf(searchers.values());
	}

	/**
	 * How many more players this searcher is waiting for, for the client's "Players Needed" figure.
	 * <p>
	 * Zero is not "nobody else needed" — the client renders zero as the placeholder string rather
	 * than a number (disc strings 916/917 and 48), which is the right thing to show when the answer
	 * is not meaningful yet.
	 */
	public int playersNeeded() {
		return Math.max(0, policy.minPlayers() - searchers.size());
	}

	/**
	 * One pass of the matchmaker.
	 *
	 * <p>Runs on the server's scheduler thread. Currently it only reaps and repaints; matching
	 * arrives in the next step. It is deliberately whole-hearted about the order — reap first, so a
	 * dead searcher is never counted into the figures the survivors are shown.
	 */
	public void tick() {
		reap();
		pushSearchPanels();
	}

	private void reap() {
		var cutoff = Instant.now().minus(MAX_WAIT);
		var dropped = new ArrayList<Long>();
		for (var searcher : searchers.values()) {
			if (!searcher.channel().isActive()) {
				dropped.add(searcher.charaId());
			} else if (searcher.state() == State.SEARCHING && searcher.joinedAt().isBefore(cutoff)) {
				dropped.add(searcher.charaId());
			}
		}
		for (var charaId : dropped) {
			var removed = searchers.remove(charaId);
			if (removed != null) {
				removed.detach();
			}
		}
		if (!dropped.isEmpty()) {
			logger.info("Dropped {} stale automatch searcher(s): {}; {} searching.", dropped.size(),
				dropped, searchers.size());
		}
	}

	/**
	 * Repaints every searcher's panel.
	 *
	 * <p>Nothing asks for this — the client sends no heartbeat while searching — so if we do not push
	 * it, the panel never changes. The payload differs per recipient because "players needed" is
	 * relative to the recipient, which is why each gets its own buffer rather than one being
	 * broadcast. That is also required for a separate reason: the encoders are per-channel and carry
	 * sequence counters, so a buffer cannot be shared.
	 */
	private void pushSearchPanels() {
		if (searchers.isEmpty()) {
			return;
		}
		// Both series are zero until matching lands and there is something real to count. An all-zero
		// panel renders a flat graph, which is honest and cannot stall anything.
		var matching = new int[AutomatchPackets.COLUMNS];
		var inGame = new int[AutomatchPackets.COLUMNS];
		var needed = playersNeeded();

		for (var searcher : searchers.values()) {
			var channel = searcher.channel();
			if (!channel.isActive()) {
				continue;
			}
			var buffer = channel.alloc().buffer(AutomatchPackets.SEARCH_PANEL_SIZE);
			AutomatchPackets.writeSearchPanel(buffer, matching, inGame, 0, needed);
			channel.writeAndFlush(new GamePacket(AutomatchPackets.SEARCH_PANEL, buffer));
		}
	}
}
