package nomad.game;

import nomad.GameClient;
import nomad.common.Database;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import nomad.common.database.Migrator;
import org.jdbi.v3.core.Jdbi;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public abstract class BaseGameClientServerTest {
	protected Jdbi jdbi;

	protected Services services;

	protected GameServer server;

	protected GameClient client;

	private static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

	@BeforeAll
	public static void setupAll() {
		postgres.start();
	}

	@AfterAll
	public static void teardownAll() {
		postgres.stop();
	}

	@BeforeEach
	public void setup() {
		jdbi = Database.getJdbi(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());

		var migrator = new Migrator(jdbi);
		migrator.run();

		services = ServicesFactory.createServices(jdbi);

		server = GameServerFactory.createGameServer(services);
		server.start().join();

		client = new GameClient();
	}

	@AfterEach
	public void teardown() {
		var clientDisconnectFuture = client.disconnect(0L, 0L, TimeUnit.SECONDS);
		var serverStopFuture = server.stop(0L, 0L, TimeUnit.SECONDS);
		CompletableFuture.allOf(clientDisconnectFuture, serverStopFuture).join();
	}
}
