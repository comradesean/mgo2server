package mgo2server;

import io.jooby.Jooby;
import io.jooby.Server;
import io.jooby.ServerOptions;
import mgo2server.common.Config;
import mgo2server.common.Database;
import mgo2server.common.ServicesFactory;
import mgo2server.common.database.Migrations;
import mgo2server.common.model.Lobby;
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

		// Write our own lobby row, if we were told an address to advertise.
		//
		// Skipped when MGO2SERVER_ADVERTISE_IP is unset, and that is the important half: the ip
		// column is what the client is told to dial next, so a wrong value breaks login for
		// everyone. An unconfigured instance leaves whatever dev/tools/seed.sql put there rather
		// than overwriting it with a guess.
		if (!config.advertiseIp().isBlank()) {
			var lobby = new Lobby();
			lobby.setId(config.lobbyId());
			lobby.setType(config.lobbyType());
			lobby.setSubtype(config.lobbySubtype());
			lobby.setIp(config.advertiseIp());
			lobby.setPort(config.gamePort());
			lobby.setBeginnersOnly(config.lobbyBeginnersOnly());
			lobby.setName("Lobby " + config.lobbyId());

			var name = services.getLobbyService().register(lobby, config.lobbyNames());
			logger.info("Registered lobby {} as \"{}\" ({}:{}, subtype {}{}).", config.lobbyId(),
				name, config.advertiseIp(), config.gamePort(), config.lobbySubtype(),
				config.lobbyBeginnersOnly() ? ", beginners only" : "");
		}

		// Games do not survive the server that hosts their lobby: the host's connection is gone,
		// so any game row left over from a previous run is a ghost that clutters the browser.
		var lobbyType = LobbyType.fromId(config.lobbyType());
		if (lobbyType == LobbyType.GAME) {
			var purged = services.getGameService().deleteGamesInLobby(config.lobbyId());
			if (purged > 0) {
				logger.info("Cleared {} stale game(s) from lobby {} on startup.",
					purged, config.lobbyId());
			}
		}

		GameServerFactory.createGameServer(services, config.gamePort(),
			lobbyType, config.lobbyId(), config.lobbySubtype()).run();
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
