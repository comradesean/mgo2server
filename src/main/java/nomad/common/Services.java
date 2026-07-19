package nomad.common;

import nomad.common.service.AccountService;
import nomad.common.service.CharacterService;
import nomad.common.service.GameService;
import nomad.common.service.LobbyService;
import nomad.common.service.NewsService;

public class Services {
	private final AccountService accountService;
	private final CharacterService characterService;
	private final GameService gameService;
	private final LobbyService lobbyService;
	private final NewsService newsService;

	public Services(AccountService accountService, CharacterService characterService,
			GameService gameService, LobbyService lobbyService, NewsService newsService) {
		this.accountService = accountService;
		this.characterService = characterService;
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
