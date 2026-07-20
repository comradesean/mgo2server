package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.Lobby;
import mgo2server.common.service.LobbyService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The lobby list a client fetches from the gate before choosing where to connect.
 * <p>
 * The reply is a three-part sequence: a start packet, then one packet per batch of entries, then
 * an end packet. Entries are batched because a payload cannot exceed 1023 bytes.
 */
public class LobbyGameController implements IGameController {
	public static final int GET_LOBBY_LIST = 0x2005;

	public static final int LOBBY_LIST_START = 0x2002;

	public static final int LOBBY_LIST_ENTRIES = 0x2003;

	public static final int LOBBY_LIST_END = 0x2004;

	/** Bytes per entry on the wire. */
	private static final int ENTRY_SIZE = 0x2e;

	/** Entries per packet, bounded by the maximum payload size. */
	private static final int ENTRIES_PER_PACKET = 22;

	private static final int NAME_LENGTH = 16;

	private static final int IP_LENGTH = 15;

	private final LobbyService lobbyService;

	public LobbyGameController(LobbyService lobbyService) {
		this.lobbyService = lobbyService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_LOBBY_LIST, this::getLobbyList);
	}

	private void getLobbyList(GameControllerContext ctx) {
		var lobbies = lobbyService.getLobbies();

		ctx.write(LOBBY_LIST_START, GameError.NONE);

		for (var start = 0; start < lobbies.size(); start += ENTRIES_PER_PACKET) {
			var end = Math.min(start + ENTRIES_PER_PACKET, lobbies.size());
			var batch = lobbies.subList(start, end);

			var buffer = ctx.buffer(batch.size() * ENTRY_SIZE);
			for (var i = 0; i < batch.size(); i++) {
				writeEntry(buffer, start + i, batch.get(i));
			}

			ctx.write(new GamePacket(LOBBY_LIST_ENTRIES, buffer));
		}

		ctx.write(LOBBY_LIST_END, GameError.NONE);
	}

	private static void writeEntry(ByteBuf buffer, int index, Lobby lobby) {
		var restriction = 0;
		if (lobby.isBeginnersOnly()) {
			restriction |= 0b1;
		}
		if (lobby.isExpansionRequired()) {
			restriction |= 0b1000;
		}
		if (lobby.isNoHeadshots()) {
			restriction |= 0b10000;
		}

		buffer.writeInt(index).writeInt(lobby.getType());
		BufferUtil.writeString(buffer, lobby.getName(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
		BufferUtil.writeString(buffer, lobby.getIp(), StandardCharsets.ISO_8859_1, IP_LENGTH);
		buffer.writeShort(lobby.getPort())
			// Player counts are not tracked yet; the client renders 0 without complaint.
			.writeShort(0)
			.writeShort((int) lobby.getId())
			.writeByte(restriction);
	}

	/** Exposed so tests can assert the batching rule without duplicating the constant. */
	public static int entriesPerPacket() {
		return ENTRIES_PER_PACKET;
	}

	static List<Lobby> batch(List<Lobby> lobbies, int start) {
		return lobbies.subList(start, Math.min(start + ENTRIES_PER_PACKET, lobbies.size()));
	}
}
