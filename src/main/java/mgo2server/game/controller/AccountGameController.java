package mgo2server.game.controller;

import mgo2server.common.crypto.SessionField;
import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.LobbyService;
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

	private final LobbyService lobbyService;

	private final long lobbyId;

	public AccountGameController(AccountService accountService,
			CharacterService characterService, LobbyType lobbyType,
			LobbyService lobbyService, long lobbyId) {
		this.characterService = characterService;
		this.accountService = accountService;
		this.lobbyType = lobbyType;
		this.lobbyService = lobbyService;
		this.lobbyId = lobbyId;
	}

	/**
	 * Whether a beginners-only lobby should turn this character away.
	 * <p>
	 * <b>Enforced here, on the server, because the client does not enforce it.</b> The client has
	 * the whole mechanism — {@code 0x884300} matches a lobby id against the gate list's restriction
	 * bit, and its callers raise dialog 2355 when the player's {@code profile+13097} is zero — and
	 * observed 2026-07-28 it simply does not fire: a character joined a lobby with the bit
	 * confirmed on the wire and no refusal, with the connect burst logged server-side. Rather than
	 * keep guessing at why, the refusal is made where it cannot be ignored. That is also how the
	 * original service would have had to do it: a client cannot be trusted to keep itself out.
	 * <p>
	 * <b>Level is experience.</b> The client displays one more than the number of thresholds
	 * cleared, and {@link CharacterService#LEVEL_4_EXPERIENCE} is measured rather than derived —
	 * 499 displays as level 3 and 500 as level 4 on a live client. So "above level 3" is exactly
	 * "experience at or past that threshold", with no rounding to argue about.
	 * <p>
	 * Operator policy, not protocol: the game has no opinion about who counts as a beginner, only
	 * that a lobby can be marked and that a connect can be refused.
	 */
	private boolean refusedAsTooExperienced(long charaId) {
		if (lobbyType != LobbyType.GAME) {
			return false;
		}

		var lobby = lobbyService.getLobbies().stream()
			.filter(l -> l.getId() == lobbyId)
			.findFirst()
			.orElse(null);
		if (lobby == null || !lobby.isBeginnersOnly()) {
			return false;
		}

		return characterService.experienceOf(charaId) >= CharacterService.LEVEL_4_EXPERIENCE;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CHECK_SESSION, this::checkSession);
	}

	private void checkSession(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();

		if (payload.readableBytes() < Integer.BYTES + SessionField.FIELD_LENGTH) {
			logger.warn("Check session: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(CHECK_SESSION_RESULT, sessionRefusal());
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
			ctx.write(CHECK_SESSION_RESULT, sessionRefusal());
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
				ctx.write(CHECK_SESSION_RESULT, sessionRefusal());
				return;
			}

			if (refusedAsTooExperienced(claimedId)) {
				logger.info("Refusing character {} entry to beginners-only lobby {}: {} experience.",
					claimedId, lobbyId, characterService.experienceOf(claimedId));
				ctx.write(CHECK_SESSION_RESULT, GameError.LOBBY_ENTRY_REFUSED);
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
				ctx.write(CHECK_SESSION_RESULT, sessionRefusal());
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
	/**
	 * The refusal for a session we will not accept, chosen by lobby type.
	 * <p>
	 * This handler serves <b>both</b> lobby types, and the two are read by different chains on
	 * different wait slots — the game lobby's {@code 0x3003} completes slot 6, the account lobby's
	 * completes slot 5. {@code -240} is <em>"You must login again to connect to the lobby"</em> on
	 * slot 6, which is exactly the instruction the player needs, but on slot 5 it is
	 * <em>"Unable to connect to server."</em> — worse than that chain's own default. So it is
	 * gated rather than sent unconditionally.
	 * <p>
	 * The account lobby keeps {@link GameError#INVALID_SESSION}, which masks and falls through to
	 * <em>"Unable to login to server."</em> No better code was found for it; that is a documented
	 * generic, not an oversight.
	 */
	private GameError sessionRefusal() {
		return lobbyType == LobbyType.GAME ? GameError.LOBBY_LOGIN_AGAIN : GameError.INVALID_SESSION;
	}

}
