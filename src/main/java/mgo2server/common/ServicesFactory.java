package mgo2server.common;

import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
import mgo2server.common.service.LobbyService;
import mgo2server.common.service.NewsService;
import mgo2server.common.service.RankingService;
import org.jdbi.v3.core.Jdbi;

public class ServicesFactory {
	public static Services createServices(Jdbi jdbi) {
		var accountService = new AccountService(jdbi);
		var characterService = new CharacterService(jdbi);
		var clanService = new ClanService(jdbi);
		var gameService = new GameService(jdbi);
		var lobbyService = new LobbyService(jdbi);
		var newsService = new NewsService(jdbi);
		var rankingService = new RankingService(jdbi);
		return new Services(accountService, characterService, clanService, gameService, lobbyService,
			newsService, rankingService);
	}
}
