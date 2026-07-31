package mgo2server;

import io.jooby.Jooby;
import io.jooby.Server;
import io.jooby.ServerOptions;
import mgo2server.common.Config;
import mgo2server.common.Database;
import mgo2server.common.ServicesFactory;
import mgo2server.common.database.Migrations;
import mgo2server.game.GameServerFactory;
import mgo2server.game.LobbyType;
import mgo2server.web.WebServerFactory;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.file.Path;

/**
 * Single entrypoint for the shaded jar: {@code java -jar mgo2server.jar <game|web|migrate>}.
 * <p>
 * Migrations run before either server starts serving, so a deploy can never end up handling
 * traffic against a schema it was not built for.
 */
public final class Main {
	private static final Logger logger = LogManager.getLogger();

	private Main() {
	}

	public static void main(String[] args) {
		var mode = args.length > 0 ? args[0] : "game";

		var config = Config.fromEnv();
		logger.info("Starting mgo2server in {} mode with {}", mode, config);

		switch (mode) {
			case "game" -> runGame(config);
			case "web" -> runWeb(config, args);
			case "migrate" -> runMigrate(config);
			default -> {
				System.err.println("Unknown mode: " + mode);
				System.err.println("Usage: java -jar mgo2server.jar <game|web|migrate>");
				System.exit(2);
			}
		}
	}

	private static void runGame(Config config) {
		var database = Database.create(config);
		Runtime.getRuntime().addShutdownHook(new Thread(database::close));

		Migrations.migrate(database.dataSource());

		var services = ServicesFactory.createServices(database.jdbi());
		GameServerFactory.createGameServer(services, config.gamePort(),
			LobbyType.fromId(config.lobbyType()), config.lobbyId(), config.lobbySubtype()).run();
	}

	private static void runWeb(Config config, String[] args) {
		var database = Database.create(config);
		Runtime.getRuntime().addShutdownHook(new Thread(database::close));

		Migrations.migrate(database.dataSource());

		var services = ServicesFactory.createServices(database.jdbi());
		var webServer = WebServerFactory.createWebServer(services, database.dataSource());

		var server = Server.loadServer(new ServerOptions().setPort(config.webPort()));
		Jooby.runApp(args, server, app -> {
			// Jooby defaults its tmpdir to <working dir>/tmp. In the container the working
			// directory is not writable by the runtime user, and it should stay that way.
			app.setTmpdir(Path.of(System.getProperty("java.io.tmpdir")));
			webServer.use(app);
		});
	}

	private static void runMigrate(Config config) {
		try (var database = Database.create(config)) {
			Migrations.migrate(database.dataSource());
		}
	}
}
