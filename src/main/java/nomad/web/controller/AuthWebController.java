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
 * The reply is plain text, comma separated, and the client's parser is strict — three decimal
 * integers each followed immediately by a comma, then a token of exactly 16 characters:
 * <pre>
 *   0,&lt;account id&gt;,&lt;perks&gt;,&lt;16 hex session&gt;   success
 *   1,0,0,0000000000000000                        failure
 * </pre>
 * Anything else is rejected as 090B:00000001. See {@link #PERKS}.
 * A token is 32 hex characters. The first 8 are stored and are what the game server sees after
 * the client encrypts them into the check-session packet; the first 16 go back to the client.
 */
public class AuthWebController implements IWebController {
	private static final Logger logger = LogManager.getLogger();

	public static final String PATH = "/us/mgo2/kid/gidauth5.html";

	private static final String FAILURE = "1,0,0,0000000000000000";

	/**
	 * The third field of the login reply, which <em>must be a single decimal integer</em>.
	 * <p>
	 * mgo2-server calls this perks and sends "1000000" joined ten times by underscores. That is
	 * wrong for this client, and was the cause of error 090B:00000001. The parser in the game's
	 * own binary (MGO2.elf, {@code 0xBB16B0}) reads the reply as three {@code strtol} calls each
	 * followed by a literal comma; at {@code 0xBB172C} it loads the byte after the third integer
	 * and branches to the failure path unless it is {@code ','}. An underscore-joined list dies on
	 * the first separator.
	 * <p>
	 * The parsed value is then discarded — {@code strtol}'s result is never stored — so only the
	 * syntax matters. Overridable so values can still be tried without a rebuild, but any
	 * replacement must remain a bare integer:
	 *
	 *   NOMAD_LOGIN_PERKS=2000000000
	 */
	private static final String PERKS = perksFromEnv();

	private static String perksFromEnv() {
		var configured = System.getenv("NOMAD_LOGIN_PERKS");
		if (configured != null && !configured.isBlank()) {
			return configured.trim();
		}
		return "1000000";
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
			return successReply(account.getId(), token.substring(0, CLIENT_LENGTH));
		});
	}

	/**
	 * Formats a successful login reply.
	 * <p>
	 * Kept separate so the grammar the client enforces can be tested directly. See
	 * {@link #PERKS} for why the third field cannot be a list.
	 */
	static String successReply(long accountId, String sessionToken) {
		return "0,%d,%s,%s".formatted(accountId, PERKS, sessionToken);
	}

	/** 32 hex characters from 16 random bytes. */
	private static String newToken() {
		var bytes = new byte[16];
		RANDOM.nextBytes(bytes);
		return HexFormat.of().formatHex(bytes);
	}
}
