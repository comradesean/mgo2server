package nomad.web;

import io.jooby.Jooby;
import io.jooby.Server;
import io.jooby.ServerOptions;
import nomad.TestDatabase;
import nomad.TestUtil;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import okhttp3.OkHttpClient;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;

public abstract class BaseWebClientServerIT {
	protected static final OkHttpClient client = new OkHttpClient();

	protected Services services;

	protected Server server;

	/** Base URL of the server under test, bound to an ephemeral port. */
	protected String host;

	@BeforeEach
	public void setup() {
		var database = TestDatabase.get();
		TestDatabase.reset();

		services = ServicesFactory.createServices(database.jdbi());

		var port = TestUtil.freePort();
		host = "http://localhost:" + port;

		var jooby = new Jooby();
		jooby.setServerOptions(new ServerOptions().setPort(port));
		var webServer = WebServerFactory.createWebServer(services, database.dataSource());
		webServer.use(jooby);
		server = jooby.start();
	}

	@AfterEach
	public void teardown() {
		if (server != null) {
			server.stop();
		}
	}
}
