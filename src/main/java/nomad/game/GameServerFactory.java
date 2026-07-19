package nomad.game;

import nomad.common.Database;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import nomad.game.controller.EchoGameController;
import nomad.game.controller.NewsGameController;

import java.util.ArrayList;

public class GameServerFactory {
	public static GameServer createGameServer() {
		var jdbi = Database.getJdbi();
		var services = ServicesFactory.createServices(jdbi);
		return createGameServer(services);
	}

	public static GameServer createGameServer(Services services) {
		var controllers = new ArrayList<IGameController>();

		controllers.add(new EchoGameController());

		controllers.add(new NewsGameController(services.getNewsService()));

		return new GameServer(controllers);
	}
}
