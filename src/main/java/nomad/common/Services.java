package nomad.common;

import nomad.common.service.AccountService;
import nomad.common.service.NewsService;

public class Services {
	private final AccountService accountService;
	private final NewsService newsService;

	public Services(AccountService accountService, NewsService newsService) {
		this.accountService = accountService;
		this.newsService = newsService;
	}

	public AccountService getAccountService() {
		return accountService;
	}

	public NewsService getNewsService() {
		return newsService;
	}
}
