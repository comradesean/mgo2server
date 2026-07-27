package mgo2server.game;

import mgo2server.GameClient;
import mgo2server.TestDatabase;
import mgo2server.common.model.CharaSkill;
import mgo2server.common.Services;
import mgo2server.common.ServicesFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;

import java.util.ArrayList;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public abstract class BaseGameClientServerIT {
	protected Services services;

	protected GameServer server;

	protected GameClient client;

	/** Which lobby the server under test is serving; override per test class. */
	protected LobbyType lobbyType() {
		return LobbyType.ACCOUNT;
	}

	/** Id of the lobby row created for this test, which hosted games reference. */
	protected long lobbyId;

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
					values (:type, 0, 'Test', '127.0.0.1', 5730)
					""")
				.bind("type", lobbyType().id())
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		// Port 0 lets the OS pick, so parallel test classes never fight over a port.
		server = GameServerFactory.createGameServer(services, 0, lobbyType(), lobbyId, 0);
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

	@AfterEach
	public void teardown() {
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
