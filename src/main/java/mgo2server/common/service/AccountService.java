package mgo2server.common.service;

import mgo2server.common.model.Account;
import mgo2server.common.model.Chara;
import org.jdbi.v3.core.Jdbi;

import java.util.List;
import java.util.Optional;

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

	/** Looks up the account holding an active session token. */
	public Optional<Account> findBySession(String session) {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from account where session=:session")
				.bind("session", session)
				.mapTo(Account.class)
				.findOne();
		}
	}

	/**
	 * Looks up an account by the credentials the client presents at login.
	 * <p>
	 * The client sends the password already MD5-hashed, so that hash is what is stored and
	 * compared. That is the game's scheme, not a choice — MD5 is not acceptable for storing
	 * passwords, and anything beyond a test deployment should sit behind a real account system
	 * that never sees this value.
	 */
	public Optional<Account> findByCredentials(String username, String passwordHash) {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from account where username=:username and password=:password")
				.bind("username", username)
				.bind("password", passwordHash)
				.mapTo(Account.class)
				.findOne();
		}
	}

	/**
	 * Clears the selected character. The client re-selects one after checking in, and leaving a
	 * stale value behind would let a reconnect resume as a character the player did not pick.
	 */
	public void clearCurrentCharacter(long accountId) {
		try (var handle = jdbi.open()) {
			handle.createUpdate("update account set current_chara_id=null where id=:id")
				.bind("id", accountId)
				.execute();
		}
	}

	public void setSession(long accountId, String session) {
		try (var handle = jdbi.open()) {
			handle.createUpdate("update account set session=:session where id=:id")
				.bind("session", session)
				.bind("id", accountId)
				.execute();
		}
	}

	public List<Chara> getAllCharacters(long accountId) {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from chara where account_id=:id and active=true")
				.bind("id", accountId).mapTo(Chara.class).list();
		}
	}
}
