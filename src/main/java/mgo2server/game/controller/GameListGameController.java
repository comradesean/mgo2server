package mgo2server.game.controller;

import mgo2server.common.service.CharacterService;
import mgo2server.common.service.GameService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameDetails;
import mgo2server.game.GameError;
import mgo2server.game.GameJoin;
import mgo2server.game.GameListEntry;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * The game browser: the list of games hosted in this lobby.
 * <p>
 * Answered as a start packet, one packet per batch of entries, then an end packet — the same shape
 * as the lobby list, and for the same reason: a payload cannot exceed 1023 bytes.
 */
public class GameListGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int GET_GAME_LIST = 0x4300;

	public static final int GAME_LIST_START = 0x4301;

	public static final int GAME_LIST_ENTRIES = 0x4302;

	public static final int GAME_LIST_END = 0x4303;

	public static final int GET_GAME_DETAILS = 0x4312;

	public static final int GAME_DETAILS = 0x4313;

	public static final int JOIN_GAME = 0x4320;

	public static final int JOIN_GAME_RESULT = 0x4321;

	public static final int JOIN_FAILED = 0x4322;

	public static final int JOIN_FAILED_RESULT = 0x4323;

	/** Fixed-width password field the client sends after the game id. */
	private static final int PASSWORD_LENGTH = 16;

	private final GameService gameService;

	private final CharacterService characterService;

	private final long lobbyId;

	private final int lobbySubtype;

	public GameListGameController(GameService gameService, CharacterService characterService,
			long lobbyId, int lobbySubtype) {
		this.characterService = characterService;
		this.gameService = gameService;
		this.lobbyId = lobbyId;
		this.lobbySubtype = lobbySubtype;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_GAME_LIST, this::getGameList);
		handlers.put(GET_GAME_DETAILS, this::getGameDetails);
		handlers.put(JOIN_GAME, this::joinGame);
		handlers.put(JOIN_FAILED, this::joinFailed);
	}

	private void getGameList(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(GAME_LIST_START, GameError.INVALID_SESSION);
			return;
		}

		// The client sends a filter here. The original distinguishes clan rooms from ordinary
		// games by a name prefix; clan rooms are not modelled yet, so every game in the lobby is
		// listed regardless of the requested type.
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			var type = payload.readInt();
			logger.debug("Game list requested with type {}.", type);
		}

		var games = gameService.getGames(lobbyId);

		ctx.write(GAME_LIST_START, GameError.NONE);

		for (var start = 0; start < games.size(); start += GameListEntry.PER_PACKET) {
			var end = Math.min(start + GameListEntry.PER_PACKET, games.size());
			var batch = games.subList(start, end);

			var buffer = ctx.buffer(batch.size() * GameListEntry.SIZE);
			for (var game : batch) {
				// Friend and blocked lists are not modelled yet, so the browser cannot yet
				// highlight games containing them.
				GameListEntry.write(buffer, game,
					gameService.countPlayers(game.getId()),
					gameService.averageExperience(game.getId()),
					false, false);
			}

			ctx.write(new GamePacket(GAME_LIST_ENTRIES, buffer));
		}

		ctx.write(GAME_LIST_END, GameError.NONE);
	}

	/**
	 * Game details ({@code 0x4312}): the details, join and player-list screens all gate on this
	 * reply, and each of them stalled into {@code 0B10:FFFFFF60} while it went unanswered.
	 * <p>
	 * The request payload is read as a u32 game id. That is what both references parse and it fits
	 * the reply's echo of the id, but the sender side has not been read out of the binary yet —
	 * hence the log line when the payload is not exactly four bytes.
	 */
	private void getGameDetails(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(GAME_DETAILS, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() != Integer.BYTES) {
			logger.warn("Game details request with {} payload bytes; expected 4.",
				payload.readableBytes());
		}
		if (payload.readableBytes() < Integer.BYTES) {
			ctx.write(GAME_DETAILS, GameError.GENERAL);
			return;
		}
		var gameId = payload.readInt();

		var game = gameService.get(gameId);
		if (game.isEmpty()) {
			// A nonzero result makes the client surface the error instead of waiting; this is
			// the browser-raced-a-teardown case, not a protocol failure — and the client has a
			// sentence for precisely that. "Unable to locate host." says the game went away;
			// GENERAL's "Unable to acquire host information." reads as a server fault.
			ctx.write(GAME_DETAILS, GameError.GAME_HOST_NOT_FOUND);
			return;
		}

		var players = gameService.getPlayers(gameId, game.get().getHostCharaId());
		if (players.size() > GameDetails.MAX_PLAYERS) {
			players = players.subList(0, GameDetails.MAX_PLAYERS);
		}

		var buffer = ctx.buffer(GameDetails.FIXED_SIZE + players.size() * GameDetails.PLAYER_SIZE);
		GameDetails.write(buffer, game.get(), lobbySubtype,
			gameService.averageExperience(gameId), players);
		ctx.write(new GamePacket(GAME_DETAILS, buffer));
	}

	/**
	 * Join a game ({@code 0x4320}): the client is handed the host's peer-to-peer endpoints so the
	 * two can connect directly. Payload arrives Blowfish-decrypted; both references read a u32
	 * game id, and echo a 16-byte password after it, which is read when present.
	 * <p>
	 * A failure is a bare result — the reply parser at {@code 0xD440DC} skips the body on a
	 * nonzero result — so a missing game, a wrong password or a host that never registered its
	 * endpoint all return an error rather than a malformed success.
	 */
	private void joinGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(JOIN_GAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId == null) {
			ctx.write(JOIN_GAME_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < Integer.BYTES) {
			logger.warn("Join request with {} payload bytes; expected at least 4.",
				payload.readableBytes());
			ctx.write(JOIN_GAME_RESULT, GameError.GENERAL);
			return;
		}
		var gameId = payload.readInt();
		var password = payload.readableBytes() >= PASSWORD_LENGTH
			? readNulTerminated(payload, PASSWORD_LENGTH)
			: "";

		var game = gameService.get(gameId);
		if (game.isEmpty()) {
			ctx.write(JOIN_GAME_RESULT, GameError.GENERAL);
			return;
		}

		var stored = game.get().getPassword();
		if (stored != null && !stored.isEmpty() && !stored.equals(password)) {
			// "Password is incorrect." — the client has a sentence for exactly this, and we spent a
			// long time not sending it. GENERAL prints "Unable to connect to host.", which is true,
			// useless, and reads as the server being broken rather than as a typo. This is the most
			// common failure a player will ever hit.
			ctx.write(JOIN_GAME_RESULT, GameError.GAME_PASSWORD_INCORRECT);
			return;
		}

		// A host who blocked you cannot be joined. The game list has its own "only show games with
		// no blocked players" filter (lobby strings 12788/12794), but that is a display preference
		// on the joiner's side; the block itself is server state, so it is enforced here.
		if (characterService.hasBlocked(game.get().getHostCharaId(), charaId)) {
			logger.info("Join of game {} refused: host character {} has blocked character {}.",
				gameId, game.get().getHostCharaId(), charaId);
			ctx.write(JOIN_GAME_RESULT, GameError.GENERAL);
			return;
		}

		var hostEndpoint = gameService.getConnectionInfo(game.get().getHostCharaId());
		if (hostEndpoint.isEmpty()) {
			// The host never registered an endpoint (0x4700). Without it a peer connection is
			// impossible, so this is a real failure rather than an empty success.
			logger.warn("Join of game {} refused: host character {} has no registered endpoint.",
				gameId, game.get().getHostCharaId());
			ctx.write(JOIN_GAME_RESULT, GameError.GENERAL);
			return;
		}

		gameService.addPlayer(gameId, charaId);

		var buffer = ctx.buffer(GameJoin.SIZE);
		GameJoin.write(buffer, hostEndpoint.get(), game.get().getRule(), game.get().getMap());
		ctx.write(new GamePacket(JOIN_GAME_RESULT, buffer));
	}

	/**
	 * Join failed ({@code 0x4322}): the client could not establish the peer-to-peer connection to
	 * the host it was handed by {@code 0x4321}, and is backing out. Empty request; the reply
	 * parser at {@code 0xD40904} reads only a u32 result, so an acknowledgement is all it needs.
	 * <p>
	 * Unanswered, the client hangs on the loader and eventually fails {@code 0B08:FFFFFF60} — the
	 * spinner is it waiting for this reply. The joiner is removed from the game they never managed
	 * to enter so the roster stays honest.
	 */
	private void joinFailed(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(JOIN_FAILED_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId != null) {
			gameService.removePlayerFromGames(charaId);
		}

		ctx.write(JOIN_FAILED_RESULT, GameError.NONE);
	}

	/** Reads a fixed-width field the client pads with NULs. */
	private static String readNulTerminated(io.netty.buffer.ByteBuf buffer, int length) {
		var bytes = new byte[Math.min(length, buffer.readableBytes())];
		buffer.readBytes(bytes);

		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, 0, end, java.nio.charset.StandardCharsets.ISO_8859_1);
	}
}
