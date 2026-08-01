package mgo2server.common.service;

import org.jdbi.v3.core.Jdbi;

import java.time.Duration;
import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * Which lobby each character is connected to, right now.
 * <p>
 * The server has never known this. Production runs a process per lobby and
 * {@link mgo2server.game.ChannelRegistry} is deliberately per-instance, so no process can answer
 * "where is this character" about anyone outside itself. This is the shared answer, and it is what
 * {@code 0x4582}'s wire {@code 0x14} and {@code 0x4602}'s five-field tail want — see
 * {@code dev/docs/PRESENCE.md}.
 * <p>
 * <b>The rows are ephemeral.</b> Each one is a claim about a live TCP connection, not durable state.
 * Losing the table costs a reconnect and nothing else, which is why the recovery strategy below is
 * allowed to be blunt.
 */
public class PresenceService {
	/**
	 * How long a row may go untouched before the reaper removes it.
	 * <p>
	 * This only ever catches a lobby process that died and <b>never came back</b>. A process that
	 * restarts clears its own rows on boot ({@link #clearLobby}), which is exact rather than
	 * heuristic, so the timeout does not need to be tight — and should not be, because a tight one
	 * would evict live players during a long GC pause or a database hiccup.
	 */
	public static final Duration STALE_AFTER = Duration.ofSeconds(120);

	/**
	 * How often {@link #heartbeat} should run. Four beats inside {@link #STALE_AFTER}, so three
	 * consecutive misses are needed before a live player is evicted.
	 */
	public static final Duration HEARTBEAT_INTERVAL = Duration.ofSeconds(30);

	private final Jdbi jdbi;

	public PresenceService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/**
	 * Records that a character is now in this lobby.
	 * <p>
	 * <b>An upsert, and the other half of the hop race.</b> A lobby change is two processes racing —
	 * the destination's insert against the origin's disconnect-delete, in either order. This side
	 * unconditionally claims the character; {@link #leave} is the side that must check ownership.
	 * Together they make the destination win regardless of ordering.
	 * <p>
	 * {@code since} is reset on a hop because it means "entered this lobby", not "came online".
	 */
	public void enter(long charaId, long lobbyId) {
		jdbi.useHandle(handle -> handle.createUpdate("""
				insert into chara_presence (chara_id, lobby_id, since, last_seen)
				values (:chara, :lobby, now(), now())
				on conflict (chara_id) do update
					set lobby_id = excluded.lobby_id, since = now(), last_seen = now()
				""")
			.bind("chara", charaId)
			.bind("lobby", lobbyId)
			.execute());
	}

	/**
	 * Removes a character's presence, but <b>only if this lobby still owns it</b>.
	 * <p>
	 * The {@code and lobby_id = :lobby} clause is the whole point of this method and must not be
	 * dropped as redundant. A disconnect from the origin lobby can be processed <em>after</em> the
	 * destination has already recorded the arrival; without the clause that late delete erases a
	 * presence that is currently correct, and the player intermittently vanishes from every friend
	 * list in the game. The symptom depends on process scheduling, so it is hard to reproduce and
	 * easy to misattribute.
	 *
	 * @return true if a row was removed, false if the character had already moved on
	 */
	public boolean leave(long charaId, long lobbyId) {
		return jdbi.withHandle(handle -> handle.createUpdate("""
				delete from chara_presence where chara_id = :chara and lobby_id = :lobby
				""")
			.bind("chara", charaId)
			.bind("lobby", lobbyId)
			.execute()) > 0;
	}

	/**
	 * Drops every row for a lobby. Called by that lobby's process at startup.
	 * <p>
	 * <b>Unconditionally correct, because nobody is connected to a process that has just started.</b>
	 * That is what makes this better than a staleness sweep for the common failure: hard kills,
	 * {@code docker restart} and crash-loops all recover exactly and immediately. This project has
	 * had a container crash-loop roughly 1300 times in one incident; a TTL-only design would have
	 * left every one of those players listed as present until the timer expired.
	 *
	 * @return how many rows were cleared — worth logging, since a nonzero count after a clean
	 *         shutdown means disconnects were not being processed
	 */
	public int clearLobby(long lobbyId) {
		return jdbi.withHandle(handle -> handle.createUpdate("""
				delete from chara_presence where lobby_id = :lobby
				""")
			.bind("lobby", lobbyId)
			.execute());
	}

	/**
	 * Marks the given characters as still connected, in one statement.
	 * <p>
	 * One round trip per lobby per tick regardless of how many players are in it. Called with the
	 * live channel set, so a character whose row was reaped by mistake is <b>not</b> resurrected
	 * here — the update touches existing rows only. That is deliberate: resurrection would hide a
	 * reaper that is too aggressive instead of surfacing it.
	 *
	 * @return how many rows were touched; fewer than {@code charaIds.size()} means rows went missing
	 */
	public int heartbeat(Collection<Long> charaIds) {
		if (charaIds.isEmpty()) {
			return 0;
		}
		return jdbi.withHandle(handle -> handle.createUpdate("""
				update chara_presence set last_seen = now()
				where chara_id in (<ids>)
				""")
			.bindList("ids", charaIds.stream().toList())
			.execute());
	}

	/**
	 * Removes rows untouched for longer than {@link #STALE_AFTER}.
	 * <p>
	 * Scoped to no lobby on purpose: the whole point is to clean up after a process that is not
	 * running, so a surviving process has to do it on its behalf. Every lobby runs this, and the
	 * delete is idempotent, so whichever gets there first wins and the rest are no-ops.
	 *
	 * @return how many stale rows were removed
	 */
	public int reapStale() {
		// WRITTEN WITH `>` AND NOT `<` ON PURPOSE. Jdbi renders through StringTemplate, which reads
		// a `<` as the start of an expression and consumes everything up to the next `>` -- and
		// `make_interval(secs => ...)` supplies one. The natural form,
		// `where last_seen < now() - make_interval(secs => :seconds)`, fails at render time with
		// "'-' came as a complete surprise to me", which says nothing about the real cause.
		// GameService.metPlayers carries the same warning for `!=`; this is the third time the
		// project has hit it, so the rule is: no bare `<` in a Jdbi SQL literal, reverse the
		// comparison instead.
		return jdbi.withHandle(handle -> handle.createUpdate("""
				delete from chara_presence
				where now() > last_seen + make_interval(secs => :seconds)
				""")
			.bind("seconds", (double) STALE_AFTER.toSeconds())
			.execute());
	}

	/** The lobby a character is in, or empty if they are not connected anywhere. */
	public Optional<Long> lobbyOf(long charaId) {
		return jdbi.withHandle(handle -> handle.createQuery("""
				select lobby_id from chara_presence where chara_id = :chara
				""")
			.bind("chara", charaId)
			.mapTo(Long.class)
			.findOne());
	}

	/**
	 * The lobby each of the given characters is in, omitting those who are not connected.
	 * <p>
	 * The bulk form exists because every consumer is a list screen — a roster or a search result —
	 * and asking per row would be one query per entry for up to 100 entries.
	 */
	public Map<Long, Long> lobbiesOf(Collection<Long> charaIds) {
		if (charaIds.isEmpty()) {
			return Map.of();
		}
		return jdbi.withHandle(handle -> handle.createQuery("""
				select chara_id, lobby_id from chara_presence where chara_id in (<ids>)
				""")
			.bindList("ids", charaIds.stream().toList())
			.map((rs, ctx) -> Map.entry(rs.getLong("chara_id"), rs.getLong("lobby_id")))
			.stream()
			.collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue)));
	}

	/** How many characters are recorded in a lobby. Diagnostics and tests. */
	public int countIn(long lobbyId) {
		return jdbi.withHandle(handle -> handle.createQuery("""
				select count(*) from chara_presence where lobby_id = :lobby
				""")
			.bind("lobby", lobbyId)
			.mapTo(Integer.class)
			.one());
	}
}
