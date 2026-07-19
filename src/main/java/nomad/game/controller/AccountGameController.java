package nomad.game.controller;

import nomad.common.crypto.SessionIds;
import nomad.common.service.AccountService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * Account check-in: the first thing a client does after connecting to an account lobby.
 * <p>
 * The client presents the account id it believes it has, plus the session token issued by the web
 * side. Both must agree with a live session before the connection counts as authenticated.
 */
public class AccountGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int CHECK_SESSION = 0x3003;

	public static final int CHECK_SESSION_RESULT = 0x3004;

	private final AccountService accountService;

	public AccountGameController(AccountService accountService) {
		this.accountService = accountService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CHECK_SESSION, this::checkSession);
	}

	private void checkSession(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();

		if (payload.readableBytes() < Integer.BYTES + SessionIds.FIELD_LENGTH) {
			logger.warn("Check session: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var claimedAccountId = payload.readInt() & 0xffffffffL;
		var sessionField = new byte[SessionIds.FIELD_LENGTH];
		payload.readBytes(sessionField);

		var token = SessionIds.decode(sessionField);

		var account = accountService.findBySession(token).orElse(null);
		if (account == null) {
			logger.warn("Check session: no account holds the presented session.");
			ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
			return;
		}

		if (account.getId() != claimedAccountId) {
			// The session is real but belongs to somebody else, so refuse rather than trust the
			// id the client asked for.
			logger.warn("Check session: session belongs to account {}, client claimed {}.",
				account.getId(), claimedAccountId);
			ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
			return;
		}

		accountService.clearCurrentCharacter(account.getId());
		account.setCurrentCharaId(null);

		ctx.connection().authenticate(account);
		logger.info("Account {} checked in.", account.getId());

		ctx.write(new GamePacket(CHECK_SESSION_RESULT, GameError.NONE.result()));
	}
}
