package mgo2server.web.controller;

import io.jooby.Jooby;
import mgo2server.common.ClientVersion;
import mgo2server.common.crypto.SessionField;
import mgo2server.common.service.AccountService;
import mgo2server.web.IWebController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.security.SecureRandom;
import java.util.HexFormat;

/**
 * The login endpoint the game client posts to before it will connect to a lobby.
 * <p>
 * Observed from a real client (MGS4, BLUS30109):
 * <pre>
 *   POST https://mgo2auth.konami.com/us/mgo2/kid/gidauth5.html
 *   name=&lt;game id&gt;&amp;passwd=&lt;md5&gt;&amp;product=..&amp;lang=..&amp;tz=..&amp;disk=..&amp;ps3=..&amp;stime=..
 *   &amp;seed=&lt;48 hex&gt;&amp;np=&lt;psn name&gt;
 * </pre>
 * The reply is plain text, comma separated, and the client's parser is strict — three decimal
 * integers each followed immediately by a comma, then a token of exactly 16 characters:
 * <pre>
 *   0,&lt;account id&gt;,&lt;perks&gt;,&lt;16 hex session&gt;   success
 *   1,0,0,0000000000000000                        failure
 * </pre>
 * Anything else is rejected as 090B:00000001. See {@link ClientVersion#loginPerks()} — the
 * third field's grammar differs between the two client builds and has no value valid for both.
 * A token is 32 hex characters, of which the first 16 go to the client. The client never sends
 * them back: it derives a sixteen-byte value from them at login and presents that on
 * check-session, so the account stores that derived value. See {@link SessionField}.
 */
public class AuthWebController implements IWebController {
	private static final Logger logger = LogManager.getLogger();

	public static final String PATH = "/us/mgo2/kid/gidauth5.html";

	private static final String FAILURE = "1,0,0,0000000000000000";

	/** Characters of the token handed to the client; it derives its session value from these. */
	private static final int CLIENT_LENGTH = 16;

	private static final SecureRandom RANDOM = new SecureRandom();

	private final AccountService accountService;

	/**
	 * Which build we serve. Decides the perks grammar and the session key — neither of which has a
	 * value valid for both builds, which is why this is a constructor argument and no longer an
	 * environment read on a static field.
	 */
	private final ClientVersion version;

	public AuthWebController(AccountService accountService, ClientVersion version) {
		this.accountService = accountService;
		this.version = version;
	}

	@Override
	public void use(Jooby jooby) {
		jooby.post(PATH, ctx -> {
			var name = ctx.form("name").value("");
			var password = ctx.form("passwd").value("");

			ctx.setResponseType(io.jooby.MediaType.text);

			if (name.isBlank() || password.isBlank()) {
				logger.warn("Login rejected: missing credentials.");
				return FAILURE;
			}

			var account = accountService.findByCredentials(name, password).orElse(null);
			if (account == null) {
				logger.warn("Login rejected for '{}': no matching account.", name);
				return FAILURE;
			}

			// The client keeps these sixteen characters and derives the value it will present on
			// check-session from them, so that derived value is what the account stores.
			var token = newToken().substring(0, CLIENT_LENGTH);
			accountService.setSession(account.getId(), SessionField.stored(version, token));

			logger.info("Account {} logged in as '{}'.", account.getId(), name);
			return successReply(version, account.getId(), token);
		});
	}

	/**
	 * Formats a successful login reply.
	 * <p>
	 * Kept separate so the grammar the client enforces can be tested directly. See
	 * {@link ClientVersion#loginPerks()} for why the grammar differs between builds.
	 */
	static String successReply(ClientVersion version, long accountId, String sessionToken) {
		return "0,%d,%s,%s".formatted(accountId, version.loginPerks(), sessionToken);
	}

	/** 32 hex characters from 16 random bytes. */
	private static String newToken() {
		var bytes = new byte[16];
		RANDOM.nextBytes(bytes);
		return HexFormat.of().formatHex(bytes);
	}
}
