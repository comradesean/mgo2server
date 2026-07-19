package nomad.common.service;

import nomad.common.model.Account;
import nomad.common.model.Chara;
import org.jdbi.v3.core.Jdbi;

import java.util.List;

public class AccountService {
	private final Jdbi jdbi;

	public AccountService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	public Account get(long accountId) {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from account where id=:id").bind("id", accountId)
				.mapTo(Account.class).findOne().orElse(null);
		}
	}

	public List<Chara> getAllCharacters(long accountId) {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from chara where account_id=:id")
				.bind("id", accountId).mapTo(Chara.class).list();
		}
	}
}
