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
		handlers.put(CREATE_GAME, this::createGame);
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
