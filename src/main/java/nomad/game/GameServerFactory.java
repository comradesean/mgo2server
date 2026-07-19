package nomad.game;

import nomad.common.Services;
import nomad.game.controller.AccountGameController;
import nomad.game.controller.EchoGameController;
import nomad.game.controller.LobbyGameController;
import nomad.game.controller.NewsGameController;

import java.util.ArrayList;

public class GameServerFactory {
	public static GameServer createGameServer(Services services, int port) {
		var controllers = new ArrayList<IGameController>();

		controllers.add(new EchoGameController());

		controllers.add(new AccountGameController(services.getAccountService()));

		controllers.add(new LobbyGameController(services.getLobbyService()));

		controllers.add(new NewsGameController(services.getNewsService()));

		return new GameServer(controllers, port);
	}
}
