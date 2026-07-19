package nomad.common;

import nomad.common.service.AccountService;
import nomad.common.service.CharacterService;
import nomad.common.service.LobbyService;
import nomad.common.service.NewsService;

public class Services {
	private final AccountService accountService;
	private final CharacterService characterService;
	private final LobbyService lobbyService;
	private final NewsService newsService;

	public Services(AccountService accountService, CharacterService characterService,
			LobbyService lobbyService, NewsService newsService) {
		this.accountService = accountService;
		this.characterService = characterService;
		this.lobbyService = lobbyService;
		this.newsService = newsService;
	}

	public AccountService getAccountService() {
		return accountService;
	}

	public CharacterService getCharacterService() {
		return characterService;
	}

	public LobbyService getLobbyService() {
		return lobbyService;
	}

	public NewsService getNewsService() {
		return newsService;
	}
}
