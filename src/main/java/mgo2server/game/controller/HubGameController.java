package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.model.Lobby;
import mgo2server.common.service.LobbyService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;

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

	/**
	 * Sent when the player backs out of a lobby to the screen before it.
	 * <p>
	 * Unanswered, the client hangs on the way <em>back</em> rather than on the way in, which is a
	 * confusing symptom: everything worked until you pressed cancel. Both references reply with an
	 * empty {@code 0x4151} and treat it as "this session has left the lobby".
	 */
	/**
	 * Purpose unknown. Sent repeatedly while in a game; neither reference names it beyond
	 * "unknown", and they disagree on the reply — echo sends a four-byte result, while mgo2-server
	 * registers <em>two</em> handlers for it in different files, one replying empty and one with
	 * five bytes, so whichever loads last wins. We follow echo, whose shape matches every other
	 * result packet in this protocol.
	 */
	public static final int UNKNOWN_4440 = 0x4440;

	public static final int UNKNOWN_4440_RESULT = 0x4441;

	public static final int LOBBY_DISCONNECT = 0x4150;

	public static final int LOBBY_DISCONNECT_RESULT = 0x4151;

	public static final int GET_TRAINING_PARAMS = 0x43d0;

	public static final int TRAINING_PARAMS_RESULT = 0x43d1;

	/**
	 * The five values behind {@code 0x43d1}, and the least evidenced thing in this class.
	 * <p>
	 * The <em>shape</em> is read from the binary: the parser at {@code 0xD3A560} performs exactly
	 * five u16 reads into a 10-byte block, copies it to {@code ctx+0x117EC} and signals
	 * request-status 31. The reset path at {@code 0xD35780} zeroes the same five halfwords, so
	 * unanswered they read 0.
	 * <p>
	 * The <em>values</em> are mgo2-server's, which is tier 4 and unexplained there too. They are
	 * used rather than zeros because at least one is rendered to the player: {@code 0x8978C8}
	 * loads the first halfword and passes it to the string formatter with message id 847, so a
	 * zero would put a zero on screen. Treat every number here as a placeholder with a plausible
	 * shape, not as protocol — the first capture of a real server's reply replaces it.
	 */
	private static final int[] TRAINING_PARAMS_DEFAULT = { 10, 21, 58, 8, 97 };

	/**
	 * Overridable so the five values can be swept against a live client without a rebuild:
	 * {@code MGO2SERVER_TRAINING_PARAMS=10,21,58,8,97}. Exactly five comma-separated numbers;
	 * anything else falls back to the defaults, because the count is protocol (the parser performs
	 * five u16 reads) while the values are not.
	 * <p>
	 * <b>These are display-only.</b> Settled 2026-07-26 by exhausting the xrefs: the whole binary
	 * touches the block at {@code ctx+0x117EC} in three places — the parser that fills it, the
	 * reset that zeroes it, and {@code 0x8978C8}, which passes the <em>first</em> u16 to the
	 * message-847 formatter. The other four are written and never read by anything. So this
	 * override changes one number on the training screen and nothing else; in particular it cannot
	 * affect the graduation requirement, whatever that turns out to read.
	 */
	private static final int[] TRAINING_PARAMS = trainingParams(System.getenv("MGO2SERVER_TRAINING_PARAMS"));

	static int[] trainingParams(String configured) {
		if (configured == null || configured.isBlank()) {
			return TRAINING_PARAMS_DEFAULT;
		}

		var fields = configured.trim().split(",");
		if (fields.length != TRAINING_PARAMS_DEFAULT.length) {
			return TRAINING_PARAMS_DEFAULT;
		}

		var values = new int[fields.length];
		for (var i = 0; i < fields.length; i++) {
			try {
				values[i] = Integer.parseInt(fields[i].trim());
			}
			catch (NumberFormatException malformed) {
				return TRAINING_PARAMS_DEFAULT;
			}
		}

		return values;
	}

	public static final int GET_AUTOMATCH_STATUS = 0x43e0;

	public static final int AUTOMATCH_STATUS_RESULT = 0x43e1;

	private static final int NAME_LENGTH = 16;

	/**
	 * A per-lobby text block the client reads straight after the name.
	 * <p>
	 * Read from the ELF, not from a reference server: the {@code 0x4902} parser at {@code 0xD47E18}
	 * pulls 64 bytes into the entry struct at {@code +0x1b}, and the hub menu builder at
	 * {@code 0x890504} hands that pointer to the string formatter for the one lobby subtype that
	 * displays it. Every other subtype ignores it, so NULs are fine — but the bytes must be on the
	 * wire or every entry after the first is parsed from the wrong offset.
	 */
	private static final int TEXT_LENGTH = 64;

	/** index, attributes, id, name, text, open and close times, and the open flag. */
	private static final int ENTRY_SIZE = 4 + 4 + 2 + NAME_LENGTH + TEXT_LENGTH + 4 + 4 + 1;

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
		handlers.put(LOBBY_DISCONNECT, this::lobbyDisconnect);
		handlers.put(UNKNOWN_4440, ctx -> ctx.write(UNKNOWN_4440_RESULT, GameError.NONE));
		handlers.put(GET_TRAINING_PARAMS, this::getTrainingParams);
		handlers.put(GET_AUTOMATCH_STATUS, this::getAutomatchStatus);
	}

	/**
	 * Answers the automatching lobby's status fetch, sent on entry with a single u8 argument
	 * (observed value 11).
	 * <p>
	 * Shape from the parser at {@code 0xD5BFC0}: a u32 result, and <em>only if it is zero</em> two
	 * u8s, which the client stores at {@code +0x14A1}/{@code +0x14A2} behind a "loaded" flag it
	 * sets at {@code +0x14A0}. Request-status 50 is signalled either way, so a nonzero result is a
	 * legitimate "nothing to report" rather than an error the client chokes on.
	 * <p>
	 * We send result 0 and two zero bytes. Neither reference server implements this command at
	 * all, so unlike {@code 0x43d0} there are no borrowed values to lean on — the two bytes are
	 * unidentified and zero is the only defensible placeholder. What they gate is unknown; if
	 * automatching misbehaves in a way that looks like a missing capability, this is the first
	 * thing to vary.
	 */
	private void getAutomatchStatus(GameControllerContext ctx) {
		var buffer = ctx.buffer(4 + 2);
		buffer.writeInt(GameError.NONE.result()).writeByte(0).writeByte(0);

		ctx.write(new GamePacket(AUTOMATCH_STATUS_RESULT, buffer));
	}

	/**
	 * Answers the training lobby's parameter fetch, sent once on entry with a single u8 argument
	 * (observed value 8, from the state machine at {@code 0x897758}).
	 * <p>
	 * Observed 2026-07-25: unanswered in both training lobbies, and with it unanswered the
	 * Graduate action does nothing at all — the client sends no request when it is pressed, so it
	 * is failing a precondition rather than waiting on us. The request argument is not read; there
	 * is only one caller and it always sends 8.
	 */
	private void getTrainingParams(GameControllerContext ctx) {
		var buffer = ctx.buffer(TRAINING_PARAMS.length * 2);
		for (var value : TRAINING_PARAMS) {
			buffer.writeShort(value);
		}

		ctx.write(new GamePacket(TRAINING_PARAMS_RESULT, buffer));
	}

	private void getGameLobbyInfo(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(GAME_LOBBY_INFO_START, GameError.INVALID_SESSION);
			return;
		}

		// Only game lobbies. The hub menu matches on subtype and ignores anything it has no
		// category for, so a gate or account row would be silently dropped anyway — but it would
		// still occupy one of the client's 64 entry slots.
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

		// The text block. Only the survival-host category renders it; the rest read past it.
		buffer.writeZero(TEXT_LENGTH);

		// Open and close times are unset, and the lobby is always open.
		buffer.writeInt(0).writeInt(0).writeByte(1);
	}

	/**
	 * Acknowledges the player leaving a lobby. The reply carries no payload — the client only waits
	 * for it before returning to the previous screen.
	 * <p>
	 * Nothing is torn down here. Lobby membership is not tracked yet, and the connection stays open
	 * because the client reuses it for whatever it shows next.
	 */
	private void lobbyDisconnect(GameControllerContext ctx) {
		ctx.write(new GamePacket(LOBBY_DISCONNECT_RESULT, ctx.buffer(0)));
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
