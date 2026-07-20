package mgo2server.game.controller;

import mgo2server.common.service.CharacterService;
import mgo2server.common.service.GameService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * Hosting: turning a character's saved host settings into a live game.
 * <p>
 * Only creation is implemented. The client can also push new settings (0x4310) and read them back
 * (0x4304), and can join, leave and administer a game once it exists (0x4312, 0x4320, 0x4340
 * onwards) — none of which are here yet. Settings therefore come from the character's stored row,
 * which is materialised with defaults on first use.
 */
public class HostGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/**
	 * The host's saved game settings, asked for when the player opens Create Game so the screen can
	 * be pre-filled with whatever they hosted last time.
	 */
	public static final int GET_HOST_SETTINGS = 0x4304;

	/**
	 * The reply, and <b>the only payload this server encrypts on the way out</b> — see
	 * {@code GameCrypto.ENCRYPT_COMMANDS}. Until this command existed nothing exercised the
	 * Blowfish encrypt direction at all, so a fault there would have been invisible.
	 */
	public static final int HOST_SETTINGS_RESULT = 0x4305;

	/**
	 * Fixed reply size. A host with nothing saved gets this many zero bytes, which is what both
	 * references send and what the client reads as "no saved settings, use the defaults".
	 */
	private static final int HOST_SETTINGS_SIZE = 128;

	/**
	 * The settings the player just configured, pushed before the game is created.
	 * <p>
	 * Its payload arrives Blowfish-encrypted — see {@code GameCrypto.DECRYPT_COMMANDS}.
	 */
	public static final int CHECK_HOST_SETTINGS = 0x4310;

	public static final int CHECK_HOST_SETTINGS_RESULT = 0x4311;

	/** Host assigns a player to a team. Acknowledged; team state is not tracked yet. */
	public static final int SET_PLAYER_TEAM = 0x4344;

	public static final int SET_PLAYER_TEAM_RESULT = 0x4345;

	/** Host reports round-trip times for the players in its game. */
	public static final int UPDATE_PINGS = 0x4398;

	public static final int UPDATE_PINGS_RESULT = 0x4399;

	/** Sent on leaving a game. Unanswered, the client sits on a black screen. */
	public static final int QUIT_GAME = 0x4380;

	public static final int QUIT_GAME_RESULT = 0x4381;

	public static final int CREATE_GAME = 0x4316;

	public static final int CREATE_GAME_RESULT = 0x4317;

	private final GameService gameService;

	private final CharacterService characterService;

	private final long lobbyId;

	private final int lobbySubtype;

	public HostGameController(GameService gameService, CharacterService characterService,
			long lobbyId, int lobbySubtype) {
		this.gameService = gameService;
		this.characterService = characterService;
		this.lobbyId = lobbyId;
		this.lobbySubtype = lobbySubtype;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_HOST_SETTINGS, this::getHostSettings);
		handlers.put(CHECK_HOST_SETTINGS, this::checkHostSettings);
		handlers.put(CREATE_GAME, this::createGame);
		handlers.put(SET_PLAYER_TEAM, this::acknowledge);
		handlers.put(UPDATE_PINGS, this::acknowledge);
		handlers.put(QUIT_GAME, this::quitGame);
	}

	/**
	 * Returns the host's saved settings, or an empty block when there are none.
	 * <p>
	 * Nothing is persisted here yet: {@code chara_host_settings} exists but is never written, so
	 * this always takes the empty path. That is correct rather than a stub — a player who has not
	 * hosted has no settings to restore — but it means the populated path is untested.
	 */
	private void getHostSettings(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var buffer = ctx.buffer(HOST_SETTINGS_SIZE);
		buffer.writeZero(HOST_SETTINGS_SIZE);
		ctx.write(new GamePacket(HOST_SETTINGS_RESULT, buffer));
	}

	/**
	 * Accepts the host's configured settings. The reply carries no payload; the client only waits
	 * for the acknowledgement before moving on to create the game.
	 * <p>
	 * The settings are read but <b>not stored</b>. Our {@code chara_host_settings} table is
	 * structured per field, while the client sends an opaque blob whose layout is not decoded here,
	 * so there is nowhere faithful to put it. The consequence is visible but small: the Create Game
	 * screen will not remember these settings next time, because {@link #getHostSettings} has
	 * nothing to return. Hosting itself is unaffected.
	 */
	private void checkHostSettings(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			var type = payload.readInt();
			logger.info("Host settings from account {}: type {}, {} bytes (not stored).",
				account.getId(), type, payload.readableBytes());
		}

		ctx.write(new GamePacket(CHECK_HOST_SETTINGS_RESULT, ctx.buffer(0)));
	}

	/**
	 * Acknowledges an in-match report the host sends but which nothing here consumes yet.
	 * <p>
	 * {@link #SET_PLAYER_TEAM} and {@link #UPDATE_PINGS} both carry real information — team
	 * assignments and per-player latency — that a server tracking a live match would use. We track
	 * neither, so the data is dropped. They are answered because the client blocks on the reply,
	 * not because the work is done: implementing the match state is what makes them meaningful.
	 */
	private void acknowledge(GameControllerContext ctx) {
		var reply = ctx.packet().getCommand() + 1;
		ctx.write(new GamePacket(reply, ctx.buffer(0)));
	}

	/**
	 * Leaves a game, and tears it down if the leaver was hosting it.
	 * <p>
	 * Without a reply the client sits on a black screen after Quit Game — it has already left as
	 * far as it is concerned and is waiting for the server to agree.
	 * <p>
	 * A host leaving deletes the game, which matches both references: the match cannot continue
	 * without the peer everyone else connects to. Players other than the host are not tracked, so
	 * for them this is only an acknowledgement.
	 */
	private void quitGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(QUIT_GAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId != null) {
			for (var game : gameService.getGames(lobbyId)) {
				if (game.getHostCharaId() == charaId) {
					logger.info("Character {} left game {}, which it hosted; removing it.",
						charaId, game.getId());
					gameService.deleteGame(game.getId());
				}
			}
		}

		ctx.write(new GamePacket(QUIT_GAME_RESULT, ctx.buffer(0)));
	}

	private void createGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		var chara = characterService.get(charaId).orElse(null);
		if (chara == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		// Defaults are named after the host, which is what a player sees if they never edit them.
		var settings = gameService.getOrCreateHostSettings(charaId, lobbySubtype, chara.getName());

		long gameId;
		try {
			gameId = gameService.createGame(lobbyId, charaId, settings);
		} catch (RuntimeException e) {
			logger.warn("Failed to create game for character {}.", charaId, e);
			ctx.write(CREATE_GAME_RESULT, GameError.GENERAL);
			return;
		}

		logger.info("Character {} created game {} in lobby {}.", charaId, gameId, lobbyId);

		var buffer = ctx.buffer(8);
		buffer.writeInt(GameError.NONE.result()).writeInt((int) gameId);
		ctx.write(new GamePacket(CREATE_GAME_RESULT, buffer));
	}
}
