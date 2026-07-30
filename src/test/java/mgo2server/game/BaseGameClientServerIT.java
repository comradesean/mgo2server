package mgo2server.game;

import mgo2server.GameClient;
import mgo2server.TestClient;
import mgo2server.TestDatabase;
import mgo2server.common.AutomatchPolicy;
import mgo2server.common.model.CharaSkill;
import mgo2server.common.Services;
import mgo2server.common.ServicesFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public abstract class BaseGameClientServerIT {
	protected Services services;

	protected GameServer server;

	protected GameClient client;

	/**
	 * Connections opened by {@link #connect}, closed on the way out.
	 * <p>
	 * Separate from {@link #client} because the two have different shapes rather than different
	 * counts: {@code GameClient.run} blocks the calling thread until its handler closes the channel,
	 * so it can only ever drive one connection per test thread. Anything needing two clients
	 * simultaneously present — which is every automatch match — needs {@link TestClient} instead.
	 */
	private final List<TestClient> testClients = new ArrayList<>();

	/**
	 * Opens a second, third or n-th connection to the server under test.
	 *
	 * <p>Not authenticated: {@link TestClient#login} is a separate call because several tests care
	 * about the order two clients check in, and folding the login in here would hide it.
	 *
	 * @param name used in that client's failure messages
	 */
	protected TestClient connect(String name) {
		var testClient = new TestClient(name, server.boundPort());
		testClients.add(testClient);
		return testClient;
	}

	/** Which lobby the server under test is serving; override per test class. */
	protected LobbyType lobbyType() {
		return LobbyType.ACCOUNT;
	}

	/**
	 * The subtype the server under test is built with, and the subtype its lobby row carries;
	 * override per test class.
	 * <p>
	 * Zero is not a real subtype — it is "unset", which is what every test that has no opinion wants.
	 * A class that asserts on a subtype the server puts <em>on the wire</em> should name a real one
	 * instead, or the assertion is only checking that zero equals zero.
	 */
	protected int lobbySubtype() {
		return 0;
	}

	/** Id of the lobby row created for this test, which hosted games reference. */
	protected long lobbyId;

	/**
	 * The automatch policy the server under test is built with; override per test class.
	 * <p>
	 * Unlike {@code Policy}, this one is passed in rather than read from a process-wide static,
	 * precisely so a test can decide whether the availability window is open. The default is the
	 * production reading, which with no environment set means <b>disabled</b> — so every other test
	 * class sees {@code 0x43e0} refused with {@code AUTOMATCH_NOT_OPEN}, which is what a default
	 * deployment does.
	 */
	protected AutomatchPolicy automatchPolicy() {
		return AutomatchPolicy.from(System::getenv);
	}

	@BeforeEach
	public void setup() {
		var database = TestDatabase.get();
		TestDatabase.reset();

		services = ServicesFactory.createServices(database.jdbi());

		// Games reference a real lobby row, so a game lobby needs one to exist. Other lobby types
		// do not, and a gate lists lobbies, so creating one unconditionally would corrupt those
		// tests' expectations.
		lobbyId = lobbyType() != LobbyType.GAME ? 0 : database.jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into lobby (type, subtype, name, ip, port)
					values (:type, :subtype, 'Test', '127.0.0.1', 5730)
					""")
				.bind("type", lobbyType().id())
				.bind("subtype", lobbySubtype())
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		// Port 0 lets the OS pick, so parallel test classes never fight over a port.
		server = GameServerFactory.createGameServer(services, 0, lobbyType(), lobbyId, lobbySubtype(),
			automatchPolicy());
		server.start().join();

		client = new GameClient(server.boundPort());
	}

	/**
	 * Grants a character the starting skill set the service grants at creation.
	 * <p>
	 * Tests that insert a `chara` row directly bypass {@code CharacterService.create}, which is
	 * where skills are granted — so a fixture that wants a character with skills has to say so.
	 * That is the point of the design: ownership is data, not something a read invents.
	 */
	protected static void grantStartingSkills(long charaId) {
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					insert into chara_skill (chara_id, skill_id, experience, flag)
					select :chara, id, :experience, 0
					from skill
					where :maxId >= id
					on conflict (chara_id, skill_id) do nothing
					""")
			.bind("chara", charaId)
			.bind("experience", CharaSkill.MINIMUM_VISIBLE_EXPERIENCE)
			.bind("maxId", CharaSkill.STARTING_MAX_ID)
			.execute());
	}

	/**
	 * Grants a character the whole gear catalogue, as the service grants at creation.
	 * <p>
	 * Same reasoning as {@link #grantStartingSkills}: a fixture that inserts a {@code chara} row
	 * directly owns nothing, because ownership is data rather than something a read invents. Since
	 * V44 that is true of gear too, and a character with no rows sends a count of zero — which is a
	 * legitimate state, not a broken one.
	 * <p>
	 * Mirrors {@code CharacterService.create}: a character owns only what it chose at creation, one
	 * colour per item. A fixture that granted more would hide a narrowing bug in either gear writer.
	 *
	 * <p>Three items in one colour each, which is enough shape for the writers without pretending
	 * to be a real creation. Tests that care about a specific item grant it themselves.
	 */
	protected static void grantStartingGear(long charaId) {
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					insert into chara_gear (chara_id, item_id, colours) values
						(:chara, 11, 16384), (:chara, 22, 16384), (:chara, 57, 16384)
					on conflict (chara_id, item_id) do nothing
					""")
			.bind("chara", charaId)
			.execute());
	}

	@AfterEach
	public void teardown() {
		// Before the server, so a matchmaker tick cannot be writing to a channel that is going away.
		// close() is idempotent, which matters because a test may have closed one deliberately.
		for (var testClient : testClients) {
			testClient.close();
		}

		// Null-guarded so a failure in setup surfaces its own cause instead of an NPE from here.
		var futures = new ArrayList<CompletableFuture<Void>>();
		if (client != null) {
			futures.add(client.disconnect(0L, 0L, TimeUnit.SECONDS));
		}
		if (server != null) {
			futures.add(server.stop(0L, 0L, TimeUnit.SECONDS));
		}
		CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
	}
}
