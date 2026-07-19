package nomad.common;

import nomad.common.service.AccountService;
import nomad.common.service.NewsService;
import org.jdbi.v3.core.Jdbi;

public class ServicesFactory {
	public static Services createServices(Jdbi jdbi) {
		var accountService = new AccountService(jdbi);
		var newsService = new NewsService(jdbi);
		return new Services(accountService, newsService);
	}
}
