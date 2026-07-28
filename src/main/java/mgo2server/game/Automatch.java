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
import java.util.LinkedHashSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

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

		/** The match this searcher was folded into, once the tick has elected one. */
		private volatile PendingMatch match;

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

	/**
	 * A group that has been told to form a game, and the host elected to create it.
	 *
	 * <p>The flat searcher map cannot express this: the release pass has to answer "which searchers
	 * belong to the match this host is creating", and the failure path has to answer "who gets
	 * {@code 0x43f3} when this host never creates".
	 */
	public static final class PendingMatch {
		private final long hostCharaId;

		private final List<Long> members;

		private final Instant electedAt;

		/**
		 * The game the elected host already hosted when we chose them, or 0.
		 * <p>
		 * Guards a real race: {@code getHostedGame} returns <em>any</em> game that character hosts, so
		 * a ghost row from a cohort whose teardown did not run would be released as the new game id
		 * and send every joiner to the wrong match. Only a <em>different</em> id counts as the create.
		 */
		private final long gameIdBefore;

		private volatile long gameId;

		private volatile boolean hostLost;

		PendingMatch(long hostCharaId, List<Long> members, long gameIdBefore) {
			this.hostCharaId = hostCharaId;
			this.members = List.copyOf(members);
			this.electedAt = Instant.now();
			this.gameIdBefore = gameIdBefore;
		}

		public long hostCharaId() {
			return hostCharaId;
		}

		public List<Long> members() {
			return members;
		}
	}

	/**
	 * How long an elected host has to create the game before the group is told it failed.
	 * <p>
	 * The client's own create handshake is two round trips inside the standard ~40 s command
	 * deadline, so a host that has not produced a game row in this long is not slow, it is stuck —
	 * most likely on the silent refusal that happens when a character has never named a hosted game.
	 */
	public static final Duration HOST_CREATE_TIMEOUT = Duration.ofSeconds(45);

	/**
	 * The maps automatching may pick, and the whole pool.
	 * <p>
	 * From the disc's own {@code map_bit 4252} = bits 2, 3, 4, 7, 12, which is exactly the five stage
	 * directories that ship (`n002a`, `n003a`, `n004a`, `n007a`, `n012a`); map 12 is capture-confirmed
	 * as Midtown Maelstrom. Every rule carries the same mask, so the pool does not vary — matching the
	 * observed "random map from a pool that never changes".
	 */
	public static final int[] MAP_POOL = {2, 3, 4, 7, 12};

	private final AutomatchPolicy policy;

	private final long lobbyId;

	private final int lobbySubtype;

	private final GameLookup games;

	private final Map<Long, Searcher> searchers = new ConcurrentHashMap<>();

	private final List<PendingMatch> pending = new CopyOnWriteArrayList<>();

	private final java.util.Random random = new java.util.Random();

	/**
	 * The two questions the matchmaker asks the database, as an interface so this class stays
	 * testable without one.
	 */
	public interface GameLookup {
		/** The id of a game this character hosts in this lobby, or 0. */
		long hostedGameId(long lobbyId, long hostCharaId);
	}

	public Automatch(AutomatchPolicy policy, long lobbyId, int lobbySubtype, GameLookup games) {
		this.policy = policy;
		this.lobbyId = lobbyId;
		this.lobbySubtype = lobbySubtype;
		this.games = games;
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
				// If they were the elected host, the group is provably never getting a game. Say so
				// on the next tick rather than making everyone wait out HOST_CREATE_TIMEOUT for a
				// host we already know is gone.
				var match = searcher.match;
				if (match != null && match.hostCharaId == charaId && match.gameId == 0) {
					match.hostLost = true;
				}
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
		if (policy.forms()) {
			releaseCreatedMatches();
			formMatches();
		}
		pushSearchPanels();
	}

	/**
	 * Elects a host for every group large enough to play, and tells the group.
	 *
	 * <p>Groups are formed across rule filters rather than within them: a searcher asking for TDM and
	 * one asking for SNE play together, on a rotation carrying both. That is observed behaviour — a
	 * real session whose searchers wanted TDM, SNE and BASE ran all three — and it is also the only
	 * way a small server ever reaches the minimum.
	 */
	private void formMatches() {
		var waiting = searchers.values().stream()
			.filter(searcher -> searcher.state() == State.SEARCHING)
			.filter(searcher -> searcher.channel().isActive())
			.sorted(java.util.Comparator.comparing(Searcher::joinedAt))
			.toList();
		if (waiting.size() < policy.minPlayers()) {
			return;
		}

		// Longest-waiting first, and skip anyone who already hosts here: electing them would make
		// their existing game look like the one they just created.
		var host = waiting.stream()
			.filter(searcher -> games.hostedGameId(lobbyId, searcher.charaId()) == 0)
			.findFirst()
			.orElse(null);
		if (host == null) {
			logger.warn("{} searchers waiting but every one of them already hosts a game here; "
				+ "cannot elect.", waiting.size());
			return;
		}

		var members = waiting.stream().map(Searcher::charaId).toList();
		var rules = new LinkedHashSet<Integer>();
		for (var searcher : waiting) {
			if (searcher.ruleFilter() != ANY_RULE) {
				rules.add(searcher.ruleFilter());
			}
		}
		if (rules.isEmpty()) {
			// Everyone said "no preference", so the server picks. Deathmatch is the least
			// presumptuous default: no teams to balance and no objective to explain.
			rules.add(0);
		}

		var map = MAP_POOL[random.nextInt(MAP_POOL.length)];
		var settings = AutomatchSettingsBlock.build(rules, map);
		var match = new PendingMatch(host.charaId(), members, 0);

		for (var searcher : waiting) {
			searcher.state = State.AWAITING_HOST_CREATE;
			searcher.match = match;
		}
		pending.add(match);

		logger.info("Automatch formed: host {} of {} players, rules {}, map {}.", host.charaId(),
			members.size(), rules, map);

		for (var searcher : waiting) {
			push(searcher.channel(), AutomatchPackets.MATCH_FOUND,
				AutomatchPackets.MATCH_FOUND_SIZE,
				buffer -> AutomatchPackets.writeMatchFound(buffer, match.hostCharaId, lobbyId,
					lobbySubtype, settings));
		}
	}

	/**
	 * Releases groups whose host has produced a game, and gives up on those whose host has not.
	 *
	 * <p>{@code 0x43f2} must not go out before the host's {@code 0x4310} and {@code 0x4316} have
	 * landed, or the host quits with error 4945. Waiting for the row is what guarantees that: it
	 * exists only once {@code createGame} has committed.
	 */
	private void releaseCreatedMatches() {
		for (var match : pending) {
			if (match.gameId == 0 && !match.hostLost) {
				var hosted = games.hostedGameId(lobbyId, match.hostCharaId);
				if (hosted != 0 && hosted != match.gameIdBefore) {
					match.gameId = hosted;
				}
			}

			if (match.gameId != 0) {
				logger.info("Automatch releasing {} players into game {}.", match.members.size(),
					match.gameId);
				// The host is included deliberately: its own handler expects this packet, and a
				// spurious one to a host that has left is dropped, where omitting it can park it
				// forever.
				for (var charaId : match.members) {
					var searcher = searchers.get(charaId);
					if (searcher != null) {
						searcher.state = State.MATCHED;
						push(searcher.channel(), AutomatchPackets.MATCH_GAME, 4,
							buffer -> AutomatchPackets.writeMatchGame(buffer, match.gameId));
						forget(charaId);
					}
				}
				pending.remove(match);
				continue;
			}

			var expired = match.electedAt.isBefore(Instant.now().minus(HOST_CREATE_TIMEOUT));
			if (match.hostLost || expired) {
				var told = 0;
				// 0x43f3 only reaches a client that has NOT yet had 0x43f2 — that packet unregisters
				// the push channel. Everyone here is by definition still waiting, so this is the last
				// moment they are reachable at all.
				for (var charaId : match.members) {
					var searcher = searchers.get(charaId);
					if (searcher != null) {
						push(searcher.channel(), AutomatchPackets.MATCH_FAILED, 4,
							buffer -> AutomatchPackets.writeMatchFailed(buffer, 0));
						forget(charaId);
						told++;
					}
				}
				// Counted as pushed, not as elected: the host is usually the one who left, so the
				// group size would overstate who was actually told.
				logger.warn("Automatch host {} {}; told {} of {} players it failed.",
					match.hostCharaId, match.hostLost ? "disconnected" : "never created a game",
					told, match.members.size());
				pending.remove(match);
			}
		}
	}

	/**
	 * Told by {@code HostGameController} that a game now exists, so the tick need not wait to notice.
	 *
	 * <p>Notification rather than polling alone, because {@code createGame} commits the row and
	 * {@code applyHostSettings} runs <em>after</em> it: a tick landing between the two would hand
	 * joiners a game whose rule and map are still zero. This fires after both.
	 */
	public void gameCreated(long hostCharaId, long gameId) {
		for (var match : pending) {
			if (match.hostCharaId == hostCharaId && match.gameId == 0) {
				match.gameId = gameId;
				logger.info("Automatch host {} created game {}.", hostCharaId, gameId);
			}
		}
	}

	private void forget(long charaId) {
		var removed = searchers.remove(charaId);
		if (removed != null) {
			removed.detach();
		}
	}

	private void push(io.netty.channel.Channel channel, int command, int size,
			java.util.function.Consumer<io.netty.buffer.ByteBuf> body) {
		if (!channel.isActive()) {
			return;
		}
		var buffer = channel.alloc().buffer(size);
		body.accept(buffer);
		channel.writeAndFlush(new GamePacket(command, buffer));
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
				// The closeFuture listener normally does this, but it and this loop race: a tick can
				// see isActive() == false in the window before the listener runs, and then nothing
				// would mark the match. The group would sit out the full HOST_CREATE_TIMEOUT waiting
				// for a host we already know is gone. Microseconds wide, but it is a real
				// interleaving, so both paths set the flag.
				var match = removed.match;
				if (match != null && match.hostCharaId == charaId && match.gameId == 0) {
					match.hostLost = true;
				}
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
			// Only clients still searching. Once a match has been announced the client has left state
			// 6 for state 12 or 18, and while event 42 is documented as repainting in place, nothing
			// establishes that it is harmless off that screen — so we stop rather than assume.
			if (searcher.state() != State.SEARCHING) {
				continue;
			}
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
