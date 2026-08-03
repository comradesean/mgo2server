package mgo2server.game.controller;

import mgo2server.common.ClientVersion;

import io.netty.buffer.Unpooled;
import mgo2server.TestClient;
import mgo2server.TestDatabase;
import mgo2server.common.AutomatchPolicy;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.Automatch;
import mgo2server.game.AutomatchPackets;
import mgo2server.game.AutomatchSettingsBlock;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.GameServer;
import mgo2server.game.IGameController;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Two clients searching at once, and the three pushes that turn them into a game — {@code 0x43f1},
 * {@code 0x43f2} and {@code 0x43f3}.
 *
 * <h2>Why this needs a second client at all</h2>
 * Everything here is invisible to a single connection. A match forms only when several searchers are
 * simultaneously queued, and the whole point of {@code 0x43f1} is that <b>exactly one</b> of the
 * recipients is named host: the client compares the leading u32 against its own character id at
 * {@code 0xD5B7F4} and goes to state 12 to create the game if it matches, or parks at state 18 if it
 * does not ({@code 0x93DBF4}). Get that wrong in either direction and either nobody hosts or two
 * clients do — and neither failure produces an error dialog, because both of the client's own
 * failure paths return to state 1 silently ({@code AUTOMATCH.md} §6). One client can never observe
 * the difference, so this file is the first thing that exercises the {@code 0x43f1} writer at all.
 *
 * <h2>What is protocol here and what is ours</h2>
 * The <b>sizes</b> are protocol and are asserted as literals rather than against the writer's own
 * constants, because a constant that agrees with a miscounted writer proves nothing: {@code 0x43f1}
 * is 223 bytes at parser {@code 0xD5B664}, {@code 0x43f2} 4 at {@code 0xD5B588} and {@code 0x43f3} 4
 * at {@code 0xD5B4D0}. So is the <b>rotation index of 0</b>, because the client copies entry
 * {@code idx} into entry 0 without clearing entry {@code idx} ({@code 0x93D3BC}), and the
 * <b>ordering rule</b> that {@code 0x43f2} must not precede the game's existence, because a host
 * that receives it before its own create has landed quits with error 4945 ({@code 0x93DE40}).
 * Everything about <em>who</em> is matched with whom — the minimum, the election, the map draw — is
 * operator policy.
 */
public class AutomatchMatchFormingIT extends BaseGameClientServerIT {

	/** The matchmaker interval under test. The deployed default is five seconds. */
	private static final Duration TICK = Duration.ofSeconds(1);

	private static final Duration TIMEOUT = Duration.ofSeconds(20);

	/**
	 * Long enough to be sure several ticks have run, for the assertions that something did
	 * <em>not</em> happen. Anything shorter proves only that the matchmaker had not run yet.
	 */
	private static final Duration QUIET = Duration.ofMillis(3500);

	/**
	 * Open at every instant, matching two players, ticking every second.
	 * <p>
	 * The 2 is {@code MIN_PLAYERS} and is the whole reason two clients suffice; a deployment would set
	 * something larger. Built directly rather than parsed so the test does not lean on the
	 * midnight-wrapping rule, which {@code AutomatchPolicyTest} owns.
	 */
	private static final AutomatchPolicy ALWAYS_OPEN = new AutomatchPolicy(true,
		List.of(new AutomatchPolicy.Window(LocalTime.MIN, LocalTime.MAX)), ZoneId.of("UTC"),
		AutomatchPolicy.Mode.BOTH, 2, TICK, Set.of(),
		// The widest band from the outset, so level never decides whether these tests match. Level
		// windowing has its own coverage; here it would only make the outcome depend on whatever
		// experience the fixtures happen to give a character.
		AutomatchPolicy.DEFAULT_BAND_MAX, Duration.ofSeconds(30), AutomatchPolicy.DEFAULT_BAND_MAX,
		// Zero relaxation: every searcher accepts any mode immediately, so rule filters never decide
		// whether these tests match. Mode grouping has its own coverage; here it would only make the
		// outcome depend on which filter a fixture happened to send.
		Duration.ZERO,
		// No decay: the requirement is MIN_PLAYERS from the outset, so these tests match as soon as
		// enough clients are queued rather than waiting out a countdown. The decay has its own
		// coverage.
		2, Duration.ZERO);

	/** Team Deathmatch, menu row 2. */
	private static final int RULE_TDM = 1;

	/** Base Mission, menu row 6. */
	private static final int RULE_BASE = 5;

	/** The scalars before the settings block: {@code AUTOMATCH.md} §3, "the six scalars". */
	private static final int HOST_CHARA_ID = 0x00;

	private static final int LOBBY_ID = 0x04;

	private static final int LOBBY_SUBTYPE = 0x08;

	private static final int ROTATION_INDEX = 0x12;

	/** Where the 204-byte settings block starts. {@code 19 + 204 = 223}, the parser's own size. */
	private static final int SETTINGS_BLOCK = 0x13;

	/**
	 * The rotation is <b>16 interleaved {@code [rule, map, flags]} triples</b> in the block's first
	 * 48 bytes.
	 *
	 * <p>Not three parallel arrays — that is the client's <em>in-memory</em> form after the reader
	 * scatters the stream. These accessors read it the way the client reads the wire, which is the
	 * point: this file previously carried parallel offsets under a comment correctly saying
	 * "interleaved triples", and so agreed with a server that was encoding it wrongly. Two requested
	 * modes reached the client as one entry with a map id of 1 — a stage that does not exist — which
	 * is one mode in the "Rules:" popup and a black loading screen.
	 */
	private static int rotationRule(byte[] block, int entry) {
		return block[entry * 3] & 0xFF;
	}

	private static int rotationMap(byte[] block, int entry) {
		return block[entry * 3 + 1] & 0xFF;
	}

	private static int rotationFlags(byte[] block, int entry) {
		return block[entry * 3 + 2] & 0xFF;
	}

	/** Timer-array indices for Team Deathmatch: time, rounds, tickets. */
	private static final int TDM_TIME = 6;

	private static final int TDM_ROUNDS = 7;

	private static final int TDM_TICKETS = 8;

	/** An id no fixture could produce by accident, so a wrong one cannot look right. */
	private static final long GAME_ID = 0x00BADA55L;

	/** The automatch commands are only registered for a game lobby. */
	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	/**
	 * Automatching's own subtype, so the byte at wire {@code 0x08} is checked against a real value.
	 * It is the same field as {@code 0x4310}'s byte at wire {@code 0xA2} and {@code 0x4316}'s single
	 * u8 ({@code AUTOMATCH.md} §4).
	 */
	@Override
	protected int lobbySubtype() {
		return 2;
	}

	@Override
	protected AutomatchPolicy automatchPolicy() {
		return ALWAYS_OPEN;
	}

	/**
	 * Two searchers, queued in a known order, both already answered {@code 0x43e1} result 0.
	 *
	 * <p>The order is not incidental and is not a sleep: {@code startAutomatch} enqueues
	 * <em>before</em> it writes the reply, so waiting for A's {@code 0x43e1} to arrive proves A was in
	 * the queue before B's {@code 0x43e0} was even sent. That is what makes "longest-waiting" a
	 * decidable claim rather than a coin flip.
	 */
	private List<TestClient> givenTwoSearchers(int ruleA, int ruleB) {
		return List.of(givenSearcher("A", "alice", "Alice", ruleA),
			givenSearcher("B", "bob", "Bob", ruleB));
	}

	/**
	 * Which character each test client is playing, so a test can tell the elected host from the
	 * joiners — the two are now treated differently on release.
	 */
	private final java.util.Map<TestClient, Long> charaIds = new java.util.HashMap<>();

	private long charaIdOf(TestClient client) {
		var charaId = charaIds.get(client);
		assertThat(charaId).as("%s was not created through givenSearcher", client.name()).isNotNull();
		return charaId;
	}

	private TestClient givenSearcher(String name, String username, String charaName, int rule) {
		var charaId = givenCharacter(username, charaName);
		var client = connect(name).login(charaId, token(username));
		charaIds.put(client, charaId);
		client.send(start(rule));

		var accepted = client.await(AutomatchGameController.START_AUTOMATCH_RESULT, TIMEOUT);
		assertThat(accepted.getPayload().getInt(0))
			.as("%s must be queued before anything can match it", name)
			.isEqualTo(GameError.NONE.result());
		return client;
	}

	/**
	 * Waits for every client to be told about the match, and returns the announcements in the order
	 * the clients were given.
	 */
	private static List<GamePacket> awaitMatchFound(List<TestClient> clients) {
		return clients.stream()
			.map(client -> client.await(AutomatchPackets.MATCH_FOUND, TIMEOUT))
			.toList();
	}

	/**
	 * Both searchers are told about the same match, in a packet the client's parser can read.
	 * <p>
	 * The 223 is the parser's fixed read at {@code 0xD5B664} and is asserted as a literal on purpose —
	 * a short packet here does not fail loudly, it makes the client parse the settings block from
	 * whatever follows in its receive buffer, which is a game with a zero-length round rather than an
	 * error. The single-host property is the other half: {@code 0xD5B7F4} compares the leading u32
	 * against {@code net+0x57D8}, the id we sent at {@code 0x4101 + 0x00}.
	 */
	@Test
	public void bothSearchersAreToldAboutOneMatchNamingExactlyOneOfThemHost() {
		var clients = givenTwoSearchers(AutomatchGameController.ANY_RULE,
			AutomatchGameController.ANY_RULE);

		var announcements = awaitMatchFound(clients);

		for (var index = 0; index < clients.size(); index++) {
			assertThat(announcements.get(index).getPayload().readableBytes())
				.as("%s's 0x43f1", clients.get(index).name())
				.isEqualTo(223);
		}

		var hostSeenByA = hostCharaId(announcements.get(0));
		var hostSeenByB = hostCharaId(announcements.get(1));

		assertThat(hostSeenByA)
			.as("both copies must name the same host, or two clients create or none does")
			.isEqualTo(hostSeenByB);
		assertThat(hostSeenByA)
			.as("the host must be one of the matched searchers")
			.isIn(clients.get(0).charaId(), clients.get(1).charaId());
	}

	/**
	 * The elected host is the searcher who has been waiting longest.
	 * <p>
	 * Operator policy rather than protocol — the client will host whoever it is told to — but it is
	 * the policy the queue documents and the only one that is fair, so it is worth a guard. The
	 * ordering is established by A's {@code 0x43e1} landing before B's {@code 0x43e0} is sent, not by
	 * a sleep; see {@link #givenTwoSearchers}.
	 */
	@Test
	public void theElectedHostIsTheLongestWaitingSearcher() {
		var clients = givenTwoSearchers(AutomatchGameController.ANY_RULE,
			AutomatchGameController.ANY_RULE);

		var announcements = awaitMatchFound(clients);

		assertThat(hostCharaId(announcements.get(0))).isEqualTo(clients.get(0).charaId());
	}

	/**
	 * {@code 0x43f2} carries the game id, and must not arrive before there is a game.
	 * <p>
	 * This is the one ordering rule in the feature that is a silent failure in both directions.
	 * Too early and the host quits with 4945 — the client raises it on a {@code 0x43f2} naming it as
	 * host after its own create has failed ({@code 0x93DE40}). Never at all and every joiner parks at
	 * state 18 forever with no error, no timeout and no dialog ({@code AUTOMATCH.md} §6). Processing
	 * it also unregisters push channel 60 ({@code 0x93DDA0}), so it is one-shot: nothing can reach the
	 * client afterwards to correct a premature one.
	 * <p>
	 * The quiet window is several ticks long, so the absence is evidence that the matchmaker looked
	 * and declined rather than that it had not yet run.
	 */
	@Test
	public void theGameIdIsNotPushedUntilTheHostHasCreated() {
		var clients = givenTwoSearchers(AutomatchGameController.ANY_RULE,
			AutomatchGameController.ANY_RULE);

		var announcements = awaitMatchFound(clients);
		var hostCharaId = hostCharaId(announcements.get(0));

		TestClient.letTicksPass(QUIET);
		for (var client : clients) {
			assertThat(client.received(AutomatchPackets.MATCH_GAME))
				.as("%s must not be released before a game exists", client.name())
				.isEmpty();
		}

		automatch().gameCreated(hostCharaId, GAME_ID);

		// EVERYONE is released, the elected host included, and this test exists partly to stop that
		// being "tidied" away again. 0x43f2 is what moves a client off the match-found screen; the
		// host has just finished creating the game and is parked at state 18 with nothing else to
		// advance it.
		//
		// Excluded briefly on 2026-07-28 on the strength of a live host reporting 0x4322 after this
		// push, which looked like the push putting it in the joiner branch. Excluding it produced a
		// host that never left the match-found screen at all, with no error — the 0x4322 had been its
		// join genuinely failing for a peer-to-peer reason, not a state-machine mistake.
		for (var client : clients) {
			var released = client.await(AutomatchPackets.MATCH_GAME, TIMEOUT);
			assertThat(released.getPayload().readableBytes())
				.as("%s's 0x43f2", client.name())
				.isEqualTo(4);
			assertThat(released.getPayload().getInt(0) & 0xFFFFFFFFL)
				.as("%s must be sent to the game the host actually created", client.name())
				.isEqualTo(GAME_ID);
		}
	}

	/**
	 * When the elected host goes away, the rest of the group is told with {@code 0x43f3} rather than
	 * left parked.
	 * <p>
	 * {@code 0x43f3} raises 4945, the sentence Konami shipped for exactly this, and it is only useful
	 * <em>before</em> {@code 0x43f2}, which unregisters the push channel. Everyone still waiting is by
	 * definition reachable, so this is the last moment the server can say anything at all — the
	 * alternative is the first of the three silent failures in {@code AUTOMATCH.md} §6.
	 * <p>
	 * <b>This exercises the host-lost shortcut, not the elapsed {@link Automatch#HOST_CREATE_TIMEOUT}
	 * branch.</b> That branch compares against {@code Instant.now()} read inside the class, so testing
	 * it means either a 45-second wait or a clock seam in main code, and putting test scaffolding in
	 * the server for it was not worth it. Both branches converge on the same push in the same loop.
	 * Three clients rather than two, so the assertion covers every non-host member of the group.
	 */
	@Test
	public void theGroupIsToldWhenTheElectedHostDisappears() {
		var host = givenSearcher("A", "alice", "Alice", AutomatchGameController.ANY_RULE);
		var first = givenSearcher("B", "bob", "Bob", AutomatchGameController.ANY_RULE);
		var second = givenSearcher("C", "carl", "Carl", AutomatchGameController.ANY_RULE);
		var joiners = List.of(first, second);

		var announcements = awaitMatchFound(List.of(host, first, second));
		assertThat(hostCharaId(announcements.get(0)))
			.as("the fixture depends on the longest-waiting searcher being the one that leaves")
			.isEqualTo(host.charaId());

		host.close();

		for (var joiner : joiners) {
			var failed = joiner.await(AutomatchPackets.MATCH_FAILED, TIMEOUT);
			assertThat(failed.getPayload().readableBytes())
				.as("%s's 0x43f3", joiner.name())
				.isEqualTo(4);
			assertThat(joiner.received(AutomatchPackets.MATCH_GAME))
				.as("%s was never released into a game that does not exist", joiner.name())
				.isEmpty();
		}
	}

	/**
	 * The settings block is the game, not a description of one.
	 * <p>
	 * It lands at {@code +752} of the 968-byte struct the elected host hands straight to the create
	 * task, whose {@code 0x4310} builder ({@code 0xD446C8}) reads nothing else and validates no number
	 * at all — so a zero here is a zero in the match. Rotation entry 0 has to carry a rule the group
	 * asked for and a <b>nonzero</b> map, because the client discards an entry whose map is zero and
	 * silently falls back to entry 0 ({@code 0x93D3BC}), and the accompanying rotation index has to be
	 * 0 for the same reason.
	 * <p>
	 * The TDM figures are the one part of the block with observed provenance: a real Konami-era
	 * automatch game ran 5 minutes, 4 rounds, 25 tickets where the client's own default is 3/4/15, at
	 * timer indices 6, 7 and 8 ({@code AUTOMATCH.md} §3). Everything else in the block is a client
	 * default standing in for a value nobody has captured.
	 */
	@Test
	public void theSettingsBlockCarriesTheRequestedRuleAPoolMapAndTheObservedTdmTimers() {
		var clients = givenTwoSearchers(RULE_TDM, RULE_TDM);

		var announcement = awaitMatchFound(clients).get(0);
		var payload = announcement.getPayload();

		assertThat(payload.getInt(LOBBY_ID) & 0xFFFFFFFFL).isEqualTo(lobbyId);
		assertThat(payload.getUnsignedByte(LOBBY_SUBTYPE)).isEqualTo((short) lobbySubtype());
		assertThat(payload.getUnsignedByte(ROTATION_INDEX))
			.as("any other index makes that rule play twice per cycle")
			.isEqualTo((short) 0);

		var block = settingsBlock(announcement);

		assertThat(rotationRule(block, 0)).isEqualTo(RULE_TDM);
		assertThat(Automatch.MAP_POOL)
			.as("a map outside the disc's five stages cannot load")
			.contains(rotationMap(block, 0));
		assertThat(rotationFlags(block, 0))
			.as("0 is the one rule-option value the disc's ruleopt_bit allows for every rule")
			.isZero();
		assertThat(rotationMap(block, 1))
			.as("one requested rule is one rotation entry; every loop that walks the rotation stops "
				+ "at the first zero map")
			.isZero();

		assertThat(AutomatchSettingsBlock.timer(block, TDM_TIME)).isEqualTo(5);
		assertThat(AutomatchSettingsBlock.timer(block, TDM_ROUNDS)).isEqualTo(4);
		assertThat(AutomatchSettingsBlock.timer(block, TDM_TICKETS)).isEqualTo(25);
	}

	/**
	 * Two searchers wanting different rules play both, on one rotation contiguous from entry 0.
	 * <p>
	 * Observed rather than assumed: a real session whose searchers had asked for TDM, SNE and BASE ran
	 * a rotation of all three ({@code AUTOMATCH.md} §3). The natural implementation — elect one rule
	 * and truncate — is the wrong one, and contiguity is protocol rather than tidiness, because the
	 * client's blob-save loop at {@code 0x8CA254} stops at the first zero map.
	 */
	@Test
	public void twoDifferentRequestedRulesRotateBothContiguouslyFromEntryZero() {
		var clients = givenTwoSearchers(RULE_TDM, RULE_BASE);

		var block = settingsBlock(awaitMatchFound(clients).get(0));

		assertThat(rotationRule(block, 0))
			.as("entry 0 is the longest-waiting searcher's rule")
			.isEqualTo(RULE_TDM);
		assertThat(rotationRule(block, 1)).isEqualTo(RULE_BASE);
		assertThat(Automatch.MAP_POOL).contains(rotationMap(block, 0));
		assertThat(rotationMap(block, 1))
			.as("a zero map would make the client stop after entry 0 and list one mode")
			.isEqualTo(rotationMap(block, 0));
		assertThat(rotationMap(block, 2))
			.as("the rotation ends where the requested rules do")
			.isZero();
	}

	private static long hostCharaId(GamePacket matchFound) {
		return matchFound.getPayload().getInt(HOST_CHARA_ID) & 0xFFFFFFFFL;
	}

	private static byte[] settingsBlock(GamePacket matchFound) {
		var block = new byte[AutomatchSettingsBlock.SIZE];
		matchFound.getPayload().getBytes(SETTINGS_BLOCK, block);
		return block;
	}

	private static GamePacket start(int ruleFilter) {
		var payload = Unpooled.buffer();
		payload.writeByte(ruleFilter);
		return new GamePacket(AutomatchGameController.START_AUTOMATCH, payload);
	}

	/**
	 * The server's own matchmaker, reached by reflection through the controller that holds it.
	 * <p>
	 * {@code GameServerFactory} constructs the {@link Automatch} internally and exposes it nowhere,
	 * which is right — nothing in production needs a handle on it, and adding an accessor purely for a
	 * test would put test scaffolding in the server. The alternatives were both worse: rebuilding the
	 * controller list here would test a wiring this server does not use, and inserting a {@code game}
	 * row so the tick's own poll finds it would test the polling fallback instead of the notification
	 * that {@code HostGameController} actually sends.
	 */
	private Automatch automatch() {
		try {
			var controllersField = GameServer.class.getDeclaredField("controllers");
			controllersField.setAccessible(true);
			@SuppressWarnings("unchecked")
			var controllers = (List<IGameController>) controllersField.get(server);

			for (var controller : controllers) {
				if (controller instanceof AutomatchGameController automatchController) {
					var queueField = AutomatchGameController.class.getDeclaredField("automatch");
					queueField.setAccessible(true);
					return (Automatch) queueField.get(automatchController);
				}
			}
			throw new AssertionError("The server under test registered no AutomatchGameController.");
		} catch (ReflectiveOperationException e) {
			throw new AssertionError("Could not reach the server's Automatch queue.", e);
		}
	}

	private long givenCharacter(String username, String charaName) {
		var accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values (:username, 'x', :session, 3)
					""")
				.bind("username", username)
				.bind("session", SessionField.stored(ClientVersion.V1_0, token(username)))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		var charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", charaName)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara
					where id = :id
					""")
			.bind("chara", charaId).bind("id", accountId).execute());

		return charaId;
	}

	/**
	 * A distinct sixteen-character session token per account.
	 * <p>
	 * Distinct because {@code checkSession} looks the account up <em>by</em> the session field
	 * ({@code findBySession}), so two accounts sharing one token would resolve to whichever row the
	 * database happened to return and the second client would silently log in as the first.
	 */
	private static String token(String username) {
		return (username + "0".repeat(SessionField.TOKEN_LENGTH))
			.substring(0, SessionField.TOKEN_LENGTH);
	}
}
