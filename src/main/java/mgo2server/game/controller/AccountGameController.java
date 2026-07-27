package mgo2server.game.controller;

import mgo2server.common.crypto.SessionField;
import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * Account check-in: the first thing a client does after connecting to an account lobby.
 * <p>
 * The client presents an id plus the session token issued by the web side, and both must agree
 * with a live session before the connection counts as authenticated.
 * <p>
 * Which id depends on the lobby: an account lobby is entered before a character is chosen, so the
 * client sends its account id, and the selected character is cleared so the player must pick
 * again. A game lobby is entered with a character already selected, so it sends that character's
 * id and the selection is left alone.
 */
public class AccountGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int CHECK_SESSION = 0x3003;

	public static final int CHECK_SESSION_RESULT = 0x3004;

	private final AccountService accountService;

	private final CharacterService characterService;

	private final LobbyType lobbyType;

	public AccountGameController(AccountService accountService,
			CharacterService characterService, LobbyType lobbyType) {
		this.characterService = characterService;
		this.accountService = accountService;
		this.lobbyType = lobbyType;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CHECK_SESSION, this::checkSession);
	}

	private void checkSession(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();

		if (payload.readableBytes() < Integer.BYTES + SessionField.FIELD_LENGTH) {
			logger.warn("Check session: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var claimedId = payload.readInt() & 0xffffffffL;
		var sessionField = new byte[SessionField.FIELD_LENGTH];
		payload.readBytes(sessionField);

		// The client derived this from its login token, so the account already holds the same
		// value and it is matched directly. Nothing is decoded back into a token.
		var account = accountService.findBySession(SessionField.stored(sessionField)).orElse(null);
		if (account == null) {
			logger.warn("Check session: no account holds the presented session.");
			ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
			return;
		}

		// The session is real, but it has to belong to whoever the client says it is; otherwise a
		// leaked token would let any id be claimed.
		if (lobbyType == LobbyType.GAME) {
			// The client decides which of its characters is entering, so the check is OWNERSHIP,
			// not equality with whatever we last recorded. Requiring the two to match rejected a
			// legitimate login: creating a character points current_chara_id at the new one, and
			// entering the lobby as a DIFFERENT character then failed with
			// "Unable to connect to lobby.(0925:C0FFEE02)" — C0FFEE02 being our own INVALID_SESSION.
			//
			// A leaked token still cannot claim someone else's character: the id has to belong to
			// this account and be active. What it can do is pick between this account's own
			// characters, which is exactly what the character-select screen is for.
			var claimed = characterService.get(claimedId).orElse(null);
			if (claimed == null || claimed.getAccountId() != account.getId() || !claimed.isActive()) {
				logger.warn("Check session: account {} claimed character {}, which it does not own.",
					account.getId(), claimedId);
				ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
				return;
			}

			if (account.getCurrentCharaId() == null || account.getCurrentCharaId() != claimedId) {
				characterService.setCurrentCharacter(account.getId(), claimedId);
				account.setCurrentCharaId(claimedId);
			}
		} else {
			if (account.getId() != claimedId) {
				logger.warn("Check session: session belongs to account {}, client claimed {}.",
					account.getId(), claimedId);
				ctx.write(CHECK_SESSION_RESULT, GameError.INVALID_SESSION);
				return;
			}

			// Entering an account lobby means choosing a character, so drop any stale selection.
			accountService.clearCurrentCharacter(account.getId());
			account.setCurrentCharaId(null);
		}

		ctx.connection().authenticate(account);
		logger.info("Account {} checked in to {} lobby.", account.getId(), lobbyType);

		ctx.write(new GamePacket(CHECK_SESSION_RESULT, GameError.NONE.result()));
	}
}
