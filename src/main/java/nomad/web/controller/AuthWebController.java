package nomad.web.controller;

import io.jooby.Jooby;
import nomad.common.service.AccountService;
import nomad.web.IWebController;
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
 * The reply is plain text, comma separated:
 * <pre>
 *   0,&lt;account id&gt;,&lt;perks&gt;,&lt;16 hex session&gt;   success
 *   1,0,0,0000000000000000                        failure
 * </pre>
 * A token is 32 hex characters. The first 8 are stored and are what the game server sees after
 * the client encrypts them into the check-session packet; the first 16 go back to the client.
 */
public class AuthWebController implements IWebController {
	private static final Logger logger = LogManager.getLogger();

	public static final String PATH = "/us/mgo2/kid/gidauth5.html";

	private static final String FAILURE = "1,0,0,0000000000000000";

	/**
	 * The third field of the login reply. mgo2-server calls it perks and sends "1000000" ten
	 * times; what the client does with it is unknown, and it is the last field of the reply whose
	 * meaning has not been pinned down. Overridable so values can be tried without a rebuild:
	 *
	 *   NOMAD_LOGIN_PERKS=2000000000_2000000000_...
	 */
	private static final String PERKS = perksFromEnv();

	private static String perksFromEnv() {
		var configured = System.getenv("NOMAD_LOGIN_PERKS");
		if (configured != null && !configured.isBlank()) {
			return configured.trim();
		}
		return String.join("_", java.util.Collections.nCopies(10, "1000000"));
	}

	/** Characters of the token kept in the database, and sent to the client, respectively. */
	private static final int STORED_LENGTH = 8;

	private static final int CLIENT_LENGTH = 16;

	private static final SecureRandom RANDOM = new SecureRandom();

	private final AccountService accountService;

	public AuthWebController(AccountService accountService) {
		this.accountService = accountService;
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

			var token = newToken();
			accountService.setSession(account.getId(), token.substring(0, STORED_LENGTH));

			logger.info("Account {} logged in as '{}'.", account.getId(), name);
			return "0,%d,%s,%s".formatted(account.getId(), PERKS, token.substring(0, CLIENT_LENGTH));
		});
	}

	/** 32 hex characters from 16 random bytes. */
	private static String newToken() {
		var bytes = new byte[16];
		RANDOM.nextBytes(bytes);
		return HexFormat.of().formatHex(bytes);
	}
}
