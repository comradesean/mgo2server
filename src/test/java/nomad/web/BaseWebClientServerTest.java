package nomad.web;

import io.jooby.Jooby;
import io.jooby.Server;
import nomad.common.Database;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import nomad.common.database.Migrator;
import okhttp3.OkHttpClient;
import org.jdbi.v3.core.Jdbi;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.testcontainers.containers.PostgreSQLContainer;

public abstract class BaseWebClientServerTest {
	protected static final String HOST = "http://localhost:8080";

	protected static final OkHttpClient client = new OkHttpClient();

	protected Jdbi jdbi;

	protected Services services;

	protected Server server;

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

		var jooby = new Jooby();
		var webServer = WebServerFactory.createWebServer(services);
		webServer.use(jooby);
		server = jooby.start();
	}

	@AfterEach
	public void teardown() {
		server.stop();
	}
}
