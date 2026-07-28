package mgo2server.game;

import mgo2server.common.Services;
import mgo2server.game.controller.AccountGameController;
import mgo2server.game.controller.CommonGameController;
import mgo2server.game.controller.CharacterConnectController;
import mgo2server.game.controller.CharacterGameController;
import mgo2server.game.controller.ChatGameController;
import mgo2server.game.controller.ClanGameController;
import mgo2server.game.controller.EchoGameController;
import mgo2server.game.controller.GameListGameController;
import mgo2server.game.controller.HostGameController;
import mgo2server.game.controller.HubGameController;
import mgo2server.game.controller.LobbyGameController;
import mgo2server.game.controller.MessageGameController;
import mgo2server.game.controller.NewsGameController;
import mgo2server.game.controller.PersonalInfoController;
import mgo2server.game.controller.PersonalStatsController;
import mgo2server.game.controller.SocialGameController;

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
				controllers.add(new LobbyGameController(services.getLobbyService(),
					services.getGameService()));
				controllers.add(new NewsGameController(services.getNewsService()));
			}
			case ACCOUNT -> {
				controllers.add(new AccountGameController(services.getAccountService(),
					services.getCharacterService(), lobbyType));
				controllers.add(new CharacterGameController(services.getAccountService(),
					services.getCharacterService()));
			}
			case GAME -> {
				controllers.add(new AccountGameController(services.getAccountService(),
					services.getCharacterService(), lobbyType));
				controllers.add(new CharacterConnectController(services.getCharacterService(),
					services.getClanService(), services.getGameService(),
					services.getAwardService()));
				controllers.add(new GameListGameController(services.getGameService(),
					services.getCharacterService(), lobbyId, lobbySubtype));
				controllers.add(new ChatGameController(services.getGameService()));
				controllers.add(new MessageGameController(services.getCharacterService(), services.getClanService()));
				controllers.add(new HubGameController(services.getLobbyService()));
				controllers.add(new PersonalInfoController(services.getCharacterService()));
				controllers.add(new SocialGameController(services.getCharacterService(),
					services.getClanService(), services.getGameService()));
				controllers.add(new PersonalStatsController(services.getCharacterService(),
					services.getClanService(), services.getAccountService(),
					services.getStatsService(), services.getAwardService()));
				controllers.add(new ClanGameController(services.getClanService(), services.getCharacterService()));
				controllers.add(new HostGameController(services.getGameService(),
					services.getCharacterService(), services.getClanService(),
					services.getAwardService(), lobbyId, lobbySubtype));
			}
		}

		return new GameServer(controllers, port);
	}
}
