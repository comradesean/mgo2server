package nomad.common;

import nomad.common.service.AccountService;
import nomad.common.service.CharacterService;
import nomad.common.service.LobbyService;
import nomad.common.service.NewsService;
import org.jdbi.v3.core.Jdbi;

public class ServicesFactory {
	public static Services createServices(Jdbi jdbi) {
		var accountService = new AccountService(jdbi);
		var characterService = new CharacterService(jdbi);
		var lobbyService = new LobbyService(jdbi);
		var newsService = new NewsService(jdbi);
		return new Services(accountService, characterService, lobbyService, newsService);
	}
}
