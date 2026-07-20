package nomad.game.controller;

import nomad.common.BufferUtil;
import nomad.common.model.Lobby;
import nomad.common.service.LobbyService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.IGameController;
import nomad.game.LobbyType;
import nomad.game.packet.GamePacket;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The hub screen a client sees once it is inside a game lobby: which game lobbies exist, and the
 * entry conditions for the one it is in.
 * <p>
 * Both commands are answered unconditionally because the client blocks on them. An unanswered
 * command here does not surface as a missing list — it stalls and then fails with
 * <em>A network server error has occurred (0A21:FFFFFF60)</em>, the same timeout the character
 * name check produced.
 */
public class HubGameController implements IGameController {
	public static final int GET_GAME_LOBBY_INFO = 0x4900;

	public static final int GAME_LOBBY_INFO_START = 0x4901;

	public static final int GAME_LOBBY_INFO_ENTRIES = 0x4902;

	public static final int GAME_LOBBY_INFO_END = 0x4903;

	public static final int GET_GAME_ENTRY_INFO = 0x4990;

	public static final int GAME_ENTRY_INFO_RESULT = 0x4991;

	private static final int NAME_LENGTH = 16;

	/** index, attributes, id, name, open and close times, and the open flag. */
	private static final int ENTRY_SIZE = 4 + 4 + 2 + NAME_LENGTH + 4 + 4 + 1;

	private static final int ENTRIES_PER_PACKET = 8;

	/** Two words the client reads, then a block it only skips. */
	private static final int ENTRY_INFO_PADDING = 0xa4;

	private final LobbyService lobbyService;

	public HubGameController(LobbyService lobbyService) {
		this.lobbyService = lobbyService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_GAME_LOBBY_INFO, this::getGameLobbyInfo);
		handlers.put(GET_GAME_ENTRY_INFO, this::getGameEntryInfo);
	}

	private void getGameLobbyInfo(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(GAME_LOBBY_INFO_START, GameError.INVALID_SESSION);
			return;
		}

		var lobbies = lobbyService.getLobbies().stream()
			.filter(lobby -> lobby.getType() == LobbyType.GAME.ordinal())
			.toList();

		ctx.write(GAME_LOBBY_INFO_START, GameError.NONE);

		for (var offset = 0; offset < lobbies.size(); offset += ENTRIES_PER_PACKET) {
			var batch = lobbies.subList(offset, Math.min(offset + ENTRIES_PER_PACKET, lobbies.size()));
			var buffer = ctx.buffer(batch.size() * ENTRY_SIZE);

			for (var index = 0; index < batch.size(); index++) {
				writeEntry(buffer, offset + index, batch.get(index));
			}

			ctx.write(new GamePacket(GAME_LOBBY_INFO_ENTRIES, buffer));
		}

		ctx.write(GAME_LOBBY_INFO_END, GameError.NONE);
	}

	private static void writeEntry(io.netty.buffer.ByteBuf buffer, int index, Lobby lobby) {
		// The subtype rides in the top byte of the attribute word; the rest is unused.
		var attributes = (lobby.getSubtype() & 0xff) << 24;

		buffer.writeInt(index).writeInt(attributes).writeShort((int) lobby.getId());
		BufferUtil.writeString(buffer, lobby.getName(), StandardCharsets.ISO_8859_1, NAME_LENGTH);

		// Open and close times are unset, and the lobby is always open.
		buffer.writeInt(0).writeInt(0).writeByte(1);
	}

	/**
	 * Entry conditions for the current lobby. Both references send the same fixed answer — a zero,
	 * a one, then a block of padding — so no restriction is expressed here.
	 */
	private void getGameEntryInfo(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(GAME_ENTRY_INFO_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var buffer = ctx.buffer(8 + ENTRY_INFO_PADDING);
		buffer.writeInt(0).writeInt(1).writeZero(ENTRY_INFO_PADDING);

		ctx.write(new GamePacket(GAME_ENTRY_INFO_RESULT, buffer));
	}
}
