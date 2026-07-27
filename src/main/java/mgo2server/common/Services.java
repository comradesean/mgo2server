package mgo2server.common;

import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
import mgo2server.common.service.LobbyService;
import mgo2server.common.service.NewsService;

public class Services {
	private final AccountService accountService;
	private final CharacterService characterService;
	private final ClanService clanService;
	private final GameService gameService;
	private final LobbyService lobbyService;
	private final NewsService newsService;

	public Services(AccountService accountService, CharacterService characterService,
			ClanService clanService, GameService gameService, LobbyService lobbyService,
			NewsService newsService) {
		this.accountService = accountService;
		this.characterService = characterService;
		this.clanService = clanService;
		this.gameService = gameService;
		this.lobbyService = lobbyService;
		this.newsService = newsService;
	}

	public AccountService getAccountService() {
		return accountService;
	}

	public CharacterService getCharacterService() {
		return characterService;
	}

	public ClanService getClanService() {
		return clanService;
	}

	public GameService getGameService() {
		return gameService;
	}

	public LobbyService getLobbyService() {
		return lobbyService;
	}

	public NewsService getNewsService() {
		return newsService;
	}
}
