package nomad.game;

import nomad.common.Services;
import nomad.game.controller.AccountGameController;
import nomad.game.controller.CommonGameController;
import nomad.game.controller.CharacterConnectController;
import nomad.game.controller.CharacterGameController;
import nomad.game.controller.EchoGameController;
import nomad.game.controller.GameListGameController;
import nomad.game.controller.HostGameController;
import nomad.game.controller.HubGameController;
import nomad.game.controller.LobbyGameController;
import nomad.game.controller.MessageGameController;
import nomad.game.controller.NewsGameController;
import nomad.game.controller.PersonalInfoController;

import java.util.ArrayList;

public class GameServerFactory {
	/**
	 * Builds a server for one lobby. Which commands are answered depends on the lobby type, so a
	 * gate cannot be asked to create a character and a game lobby cannot be asked for the lobby
	 * list — the same split the original gets from running a separate server per lobby.
	 */
	public static GameServer createGameServer(Services services, int port, LobbyType lobbyType,
			long lobbyId, int lobbySubtype) {
		var controllers = new ArrayList<IGameController>();

		// Disconnect and ping, which every lobby answers.
		controllers.add(new CommonGameController());

		// Useful for smoke-testing a connection regardless of lobby type.
		controllers.add(new EchoGameController());

		switch (lobbyType) {
			case GATE -> {
				controllers.add(new LobbyGameController(services.getLobbyService()));
				controllers.add(new NewsGameController(services.getNewsService()));
			}
			case ACCOUNT -> {
				controllers.add(new AccountGameController(services.getAccountService(), lobbyType));
				controllers.add(new CharacterGameController(services.getAccountService(),
					services.getCharacterService()));
			}
			case GAME -> {
				controllers.add(new AccountGameController(services.getAccountService(), lobbyType));
				controllers.add(new CharacterConnectController(services.getCharacterService()));
				controllers.add(new GameListGameController(services.getGameService(), lobbyId));
				controllers.add(new MessageGameController());
				controllers.add(new HubGameController(services.getLobbyService()));
				controllers.add(new PersonalInfoController(services.getCharacterService()));
				controllers.add(new HostGameController(services.getGameService(),
					services.getCharacterService(), lobbyId, lobbySubtype));
			}
		}

		return new GameServer(controllers, port);
	}
}
