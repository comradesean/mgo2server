package nomad.game;

import nomad.GameClient;
import nomad.TestDatabase;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;

import java.util.ArrayList;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public abstract class BaseGameClientServerIT {
	protected Services services;

	protected GameServer server;

	protected GameClient client;

	@BeforeEach
	public void setup() {
		var database = TestDatabase.get();
		TestDatabase.reset();

		services = ServicesFactory.createServices(database.jdbi());

		// Port 0 lets the OS pick, so parallel test classes never fight over a port.
		server = GameServerFactory.createGameServer(services, 0);
		server.start().join();

		client = new GameClient(server.boundPort());
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
