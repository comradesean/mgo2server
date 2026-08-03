package mgo2server.web;

import mgo2server.common.ClientVersion;

import io.jooby.Jooby;
import io.jooby.Server;
import io.jooby.ServerOptions;
import mgo2server.TestDatabase;
import mgo2server.common.Services;
import mgo2server.common.ServicesFactory;
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

		var jooby = new Jooby();
		var webServer = WebServerFactory.createWebServer(services, database.dataSource(), ClientVersion.V1_0);
		webServer.use(jooby);
		// Port 0, not a pre-picked free port: jooby's Netty server only blocks for the bind to
		// finish (Server.start()) when the port is ephemeral. A pre-picked, explicit port binds
		// asynchronously and races the first request.
		server = Server.loadServer(new ServerOptions().setPort(0)).start(jooby);
		host = "http://localhost:" + server.getOptions().getPort();
	}

	@AfterEach
	public void teardown() {
		if (server != null) {
			server.stop();
		}
	}
}
