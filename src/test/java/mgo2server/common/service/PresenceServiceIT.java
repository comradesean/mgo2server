package mgo2server.common.service;

import mgo2server.TestDatabase;
import mgo2server.common.ServicesFactory;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Per-character presence: which lobby a character is connected to. See {@code dev/docs/PRESENCE.md}.
 * <p>
 * <b>These are correctness checks, not regression guards.</b> The behaviour under test is ours —
 * nothing in the client knows this table exists — but the reason each rule is shaped the way it is
 * comes from a real failure mode, and the hop tests below are the ones that matter. A presence row
 * that is wrong makes {@code 0x4582} aim "move to lobby" at the wrong place, which is worse than
 * having no presence at all.
 */
public class PresenceServiceIT {
	private static PresenceService presence;

	/** Two lobbies, so the ownership rules have something to be wrong about. */
	private static long lobbyA;

	private static long lobbyB;

	@BeforeAll
	public static void setUp() {
		presence = ServicesFactory.createServices(TestDatabase.get().jdbi()).getPresenceService();
		lobbyA = lobby("presA");
		lobbyB = lobby("presB");
	}

	@Test
	public void enteringRecordsTheLobbyAndLeavingRemovesIt() {
		var chara = character("pres1");

		assertThat(presence.lobbyOf(chara)).isEmpty();

		presence.enter(chara, lobbyA);
		assertThat(presence.lobbyOf(chara)).contains(lobbyA);

		assertThat(presence.leave(chara, lobbyA)).isTrue();
		assertThat(presence.lobbyOf(chara)).isEmpty();
	}

	/** Re-entering the same lobby is not an error; a reconnect races its own teardown routinely. */
	@Test
	public void enteringTwiceKeepsOneRow() {
		var chara = character("pres2");
		presence.enter(chara, lobbyA);
		presence.enter(chara, lobbyA);

		assertThat(presence.lobbyOf(chara)).contains(lobbyA);
		assertThat(countRows(chara)).isEqualTo(1);
	}

	/**
	 * A hop in the ordinary order: the origin's disconnect is processed first, then the arrival.
	 */
	@Test
	public void hoppingLobbiesMovesTheCharacter() {
		var chara = character("pres3");
		presence.enter(chara, lobbyA);

		presence.leave(chara, lobbyA);
		presence.enter(chara, lobbyB);

		assertThat(presence.lobbyOf(chara)).contains(lobbyB);
		assertThat(countRows(chara)).isEqualTo(1);
	}

	/**
	 * <b>The test this whole design exists for.</b> A hop is two processes racing, and the origin's
	 * disconnect can be processed <em>after</em> the destination has recorded the arrival. The
	 * destination must survive it.
	 * <p>
	 * Delete the {@code and lobby_id = :lobby} clause in {@link PresenceService#leave} and this
	 * fails — and in production the symptom would be a player intermittently vanishing from every
	 * friend list in the game, depending on process scheduling. That is close to undiagnosable
	 * after the fact, which is why it is pinned here.
	 */
	@Test
	public void aLateDisconnectFromTheOldLobbyDoesNotEraseTheNewPresence() {
		var chara = character("pres4");
		presence.enter(chara, lobbyA);

		// The destination records the arrival first...
		presence.enter(chara, lobbyB);
		// ...and only then does the origin get round to processing the disconnect.
		assertThat(presence.leave(chara, lobbyA))
			.as("the origin no longer owns the row, so its delete must be a no-op")
			.isFalse();

		assertThat(presence.lobbyOf(chara))
			.as("the character must still be in the lobby they actually reached")
			.contains(lobbyB);
	}

	/**
	 * A process clears its own lobby at startup, and must not touch anyone else's.
	 * <p>
	 * This is the crash-recovery path: it is exact rather than heuristic because nobody is connected
	 * to a process that has just started.
	 */
	@Test
	public void clearingALobbyLeavesOtherLobbiesAlone() {
		var here = character("pres5");
		var elsewhere = character("pres6");
		presence.enter(here, lobbyA);
		presence.enter(elsewhere, lobbyB);

		assertThat(presence.clearLobby(lobbyA)).isPositive();

		assertThat(presence.lobbyOf(here)).isEmpty();
		assertThat(presence.lobbyOf(elsewhere)).contains(lobbyB);
	}

	@Test
	public void theHeartbeatTouchesOnlyTheCharactersItIsGiven() {
		var beating = character("pres7");
		var silent = character("pres8");
		presence.enter(beating, lobbyA);
		presence.enter(silent, lobbyA);

		age(silent, 300);
		age(beating, 300);

		assertThat(presence.heartbeat(Set.of(beating))).isEqualTo(1);

		// The reaper then takes the one that was not refreshed, and spares the one that was.
		presence.reapStale();
		assertThat(presence.lobbyOf(beating)).contains(lobbyA);
		assertThat(presence.lobbyOf(silent)).isEmpty();
	}

	/**
	 * The heartbeat must not recreate a row that is gone. Resurrection would paper over a reaper
	 * that is evicting live players instead of making it visible.
	 */
	@Test
	public void theHeartbeatDoesNotResurrectAMissingRow() {
		var chara = character("pres9");

		assertThat(presence.heartbeat(Set.of(chara))).isZero();
		assertThat(presence.lobbyOf(chara)).isEmpty();
	}

	@Test
	public void emptyInputIsNotAQuery() {
		assertThat(presence.heartbeat(List.of())).isZero();
		assertThat(presence.lobbiesOf(List.of())).isEmpty();
	}

	/** The bulk lookup, which exists because every consumer is a list screen of up to 100 rows. */
	@Test
	public void bulkLookupOmitsCharactersWhoAreNotConnected() {
		var connected = character("presA1");
		var offline = character("presA2");
		presence.enter(connected, lobbyB);

		var found = presence.lobbiesOf(List.of(connected, offline));

		assertThat(found).containsEntry(connected, lobbyB);
		assertThat(found).doesNotContainKey(offline);
	}

	@Test
	public void countingALobbySeesOnlyItsOwnCharacters() {
		var lobbyC = lobby("presC");
		var one = character("presB1");
		var two = character("presB2");
		presence.enter(one, lobbyC);
		presence.enter(two, lobbyC);
		presence.enter(character("presB3"), lobbyA);

		assertThat(presence.countIn(lobbyC)).isEqualTo(2);
	}

	/** Backdates a row so the reaper will consider it stale, without sleeping for two minutes. */
	private static void age(long charaId, int seconds) {
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
				update chara_presence set last_seen = now() - make_interval(secs => :s)
				where chara_id = :chara
				""")
			.bind("s", (double) seconds)
			.bind("chara", charaId)
			.execute());
	}

	private static int countRows(long charaId) {
		return TestDatabase.get().jdbi().withHandle(handle -> handle
			.createQuery("select count(*) from chara_presence where chara_id = :chara")
			.bind("chara", charaId)
			.mapTo(Integer.class)
			.one());
	}

	private static long lobby(String name) {
		var suffix = String.valueOf(System.nanoTime() % 1000000L);
		return TestDatabase.get().jdbi().withHandle(handle -> handle
			.createUpdate("""
				insert into lobby (type, subtype, name, ip, port)
				values (2, 1, :n, '127.0.0.1', 0)
				""")
			.bind("n", (name + suffix).substring(0, Math.min(16, (name + suffix).length())))
			.executeAndReturnGeneratedKeys("id")
			.mapTo(Long.class)
			.one());
	}

	private static long character(String name) {
		var unique = name + (System.nanoTime() % 100000000L);
		return TestDatabase.get().jdbi().withHandle(handle -> {
			var accountId = handle
				.createUpdate("insert into account (username, password) values (:n, 'x')")
				.bind("n", unique)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one();
			return handle
				.createUpdate("insert into chara (account_id, name) values (:a, :n)")
				.bind("a", accountId)
				.bind("n", unique.substring(0, Math.min(16, unique.length())))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one();
		});
	}
}
