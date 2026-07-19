package nomad.game.controller;

import nomad.common.service.GameService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.GameListEntry;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;
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

	private final GameService gameService;

	private final long lobbyId;

	public GameListGameController(GameService gameService, long lobbyId) {
		this.gameService = gameService;
		this.lobbyId = lobbyId;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_GAME_LIST, this::getGameList);
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
}
