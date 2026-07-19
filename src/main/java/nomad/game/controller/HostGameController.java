package nomad.game.controller;

import nomad.common.service.CharacterService;
import nomad.common.service.GameService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;
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
		handlers.put(CREATE_GAME, this::createGame);
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
