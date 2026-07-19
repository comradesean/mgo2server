package nomad.web.controller;

import io.jooby.Jooby;
import nomad.common.service.AccountService;
import nomad.web.IWebController;

public class AccountWebController implements IWebController {
	private final AccountService accountService;

	public AccountWebController(AccountService accountService) {
		this.accountService = accountService;
	}

	public void use(Jooby jooby) {
		jooby.get("/account/{accountId}", ctx -> {
			var accountId = ctx.path("accountId").longValue(0);
			if (accountId == 0) {
				return "invalid account id";
			}

			var account = accountService.get(accountId);
			if (account == null) {
				return "account not found";
			}

			return account.toString();
		});

		jooby.get("/account/{accountId}/chara", ctx -> {
			var accountId = ctx.path("accountId").intValue(0);
			if (accountId == 0) {
				return "invalid account id";
			}

			var charas = accountService.getAllCharacters(accountId);
			return charas.toString();
		});
	}
}
