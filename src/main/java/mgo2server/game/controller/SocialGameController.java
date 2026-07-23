package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.service.CharacterService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The social family: player search ({@code 0x4600}), met-players history ({@code 0x4680}/
 * {@code 0x4684}), and player details ({@code 0x4220}). The first three are start/item/end list
 * triples like the game browser, traced from the binary 2026-07-23 (senders
 * {@code 0xD46128}/{@code 0xD3B864}/{@code 0xD3B778}; parsers {@code 0xD45DF0}+ /
 * {@code 0xD3ADF4}+ / {@code 0xD3ABC8}+); player details is a single-reply card. Unanswered,
 * each stalls its screen into {@code FFFFFF60}.
 * <p>
 * The start and end packets carry a u32 <em>result code</em>, 0 for success — <strong>not</strong>
 * a count. A nonzero start aborts the transaction and surfaces the value verbatim in the screen's
 * error dialog (search {@code 0C13:%08x}, history {@code 1032:%08x}, details {@code 1034:%08x});
 * the end packet's value overwrites the same result slot unconditionally, so both must be 0.
 * Observed live 2026-07-23 as {@code 1032:00000005} when a count of 5 was mistaken for a result.
 * Player search alone also accepts −611 ({@code -0x263}) as a "no results found" sentinel —
 * traced but untested, so not used. The client learns the entry count only by counting item
 * records itself. Item packets carry records back to back with no per-packet count; the client
 * reads until the payload ends, so records may be split across packets freely.
 */
public class SocialGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int PLAYER_SEARCH = 0x4600;

	public static final int PLAYER_SEARCH_START = 0x4601;

	public static final int PLAYER_SEARCH_ENTRIES = 0x4602;

	public static final int PLAYER_SEARCH_END = 0x4603;

	public static final int GET_MATCH_HISTORY = 0x4680;

	public static final int MATCH_HISTORY_START = 0x4681;

	public static final int MATCH_HISTORY_ENTRIES = 0x4682;

	public static final int MATCH_HISTORY_END = 0x4683;

	/**
	 * Player details ({@code 0x4220}, u32 character id): the history row's "Player Details"
	 * menu item (observed live 2026-07-23). Sender {@code 0xD3B950}, subsystem {@code 0x1C}.
	 */
	public static final int GET_PLAYER_DETAILS = 0x4220;

	/**
	 * Single reply (no triple): u32 result code (0 = success, nonzero surfaces via the open
	 * screen's error dialog), then 197 bytes of fields — parser {@code 0xD3D874}.
	 */
	public static final int PLAYER_DETAILS_RESULT = 0x4221;

	public static final int GET_MATCH_DETAILS = 0x4684;

	public static final int MATCH_DETAILS_START = 0x4685;

	public static final int MATCH_DETAILS_ENTRIES = 0x4686;

	public static final int MATCH_DETAILS_END = 0x4687;

	/** Fixed-width name field in the search request and its result records. */
	private static final int NAME_LENGTH = 16;

	/**
	 * The client's result table holds 100 search entries (parser {@code 0xD45F38}, index
	 * checked {@code <= 0x63}); anything past that would be dropped, so it is not sent.
	 */
	private static final int SEARCH_LIMIT = 100;

	/** 59-byte search record: u32 id, 16B name, u16, 16B, u32, 16B, u8 — tail fields unknown. */
	private static final int SEARCH_ENTRY_SIZE = 59;

	/** Payloads cap at 1023 bytes, so 17 records (1003 bytes) per item packet. */
	private static final int SEARCH_ENTRIES_PER_PACKET = 17;

	private final CharacterService characterService;

	public SocialGameController(CharacterService characterService) {
		this.characterService = characterService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(PLAYER_SEARCH, this::playerSearch);
		handlers.put(GET_MATCH_HISTORY, this::getMatchHistory);
		handlers.put(GET_MATCH_DETAILS, this::getMatchDetails);
		handlers.put(GET_PLAYER_DETAILS, this::getPlayerDetails);
	}

	/**
	 * Player search: a u8 match-criteria toggle (0 partial, 1 full — the builder at
	 * {@code 0xD46128} rejects anything else), a u8 match-case toggle, and a 16-byte name.
	 */
	private void playerSearch(GameControllerContext ctx) {
		// A nonzero result here would raise the 0xC13 error dialog; a missing session or bad
		// request gets the empty success list instead, which unblocks the client quietly.
		if (ctx.connection().account() == null) {
			writeEmptyList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < 2 + NAME_LENGTH) {
			logger.warn("Player search with {} payload bytes; expected {}.",
				payload.readableBytes(), 2 + NAME_LENGTH);
			writeEmptyList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END);
			return;
		}
		var fullMatch = payload.readByte() != 0;
		var caseSensitive = payload.readByte() != 0;
		var name = readNulTerminated(payload, NAME_LENGTH);

		if (name.isEmpty()) {
			writeEmptyList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END);
			return;
		}

		var matches = characterService.search(name, fullMatch, caseSensitive, SEARCH_LIMIT);

		ctx.write(resultPacket(ctx, PLAYER_SEARCH_START));

		for (var start = 0; start < matches.size(); start += SEARCH_ENTRIES_PER_PACKET) {
			var end = Math.min(start + SEARCH_ENTRIES_PER_PACKET, matches.size());
			var batch = matches.subList(start, end);

			var buffer = ctx.buffer(batch.size() * SEARCH_ENTRY_SIZE);
			for (var chara : batch) {
				buffer.writeInt((int) chara.getId());
				BufferUtil.writeString(buffer, chara.getName(), StandardCharsets.ISO_8859_1,
					NAME_LENGTH);
				buffer.writeZero(2)   // u16, meaning unknown
					.writeZero(NAME_LENGTH) // 16 bytes, likely clan name; clans are not modelled
					.writeZero(4)     // u32, meaning unknown
					.writeZero(NAME_LENGTH) // 16 bytes, meaning unknown
					.writeZero(1);    // u8, meaning unknown
			}
			ctx.write(new GamePacket(PLAYER_SEARCH_ENTRIES, buffer));
		}

		ctx.write(resultPacket(ctx, PLAYER_SEARCH_END));
	}

	/** TEMPORARY fingerprint rows served while the record fields are being mapped. */
	private static final int HISTORY_FINGERPRINT_ROWS = 5;

	/** 2001-01-01 00:00:00 UTC; each fingerprint row steps by one day, hour, minute, second. */
	private static final int HISTORY_FINGERPRINT_EPOCH = 978307200;

	private static final int DETAIL_FINGERPRINT_ROWS = 3;

	/**
	 * Match history ({@code 0x4680}, u32 character id). The 25-byte record layout (u32, u32,
	 * 16-byte string, u8) is ELF-traced but unlabelled; candidate labels {timestamp, entry id,
	 * name, ?} come from a tier-4 Nomad test payload (PROTOCOL.md).
	 * <p>
	 * TEMPORARY fingerprint payload, 2026-07-23: each field carries a recognizable marker —
	 * ascending 2001 dates if the first u32 renders as the history date, ids 91xx (echoed back
	 * in {@code 0x4684} if the second u32 is the entry id — watch the log), names FP-ROW-n,
	 * u8 4n. Replace with real match records once the mapping and storage design land.
	 */
	private void getMatchHistory(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			logger.debug("Match history requested for character {}.", payload.readInt());
		}

		ctx.write(resultPacket(ctx, MATCH_HISTORY_START));
		var buffer = ctx.buffer(HISTORY_FINGERPRINT_ROWS * 25);
		for (var i = 1; i <= HISTORY_FINGERPRINT_ROWS; i++) {
			buffer.writeInt(HISTORY_FINGERPRINT_EPOCH + i * 90061); // +1d 1h 1m 1s per row
			buffer.writeInt(9100 + i);
			BufferUtil.writeString(buffer, "FP-ROW-" + i, StandardCharsets.ISO_8859_1,
				NAME_LENGTH);
			buffer.writeByte(40 + i);
		}
		ctx.write(new GamePacket(MATCH_HISTORY_ENTRIES, buffer));
		ctx.write(resultPacket(ctx, MATCH_HISTORY_END));
	}

	/**
	 * Match details ({@code 0x4684}, u32 entry id from the history list — the logged id reveals
	 * which list field the client echoes). 93-byte records (u32, 64-byte string, 16-byte string,
	 * u8, u32, u32), ELF-traced, fully unlabelled; TEMPORARY fingerprint markers as above.
	 */
	private void getMatchDetails(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			// Deliberately INFO: this echo identifies the entry-id field of the 0x4682 record.
			logger.info("Match details requested for entry {}.", payload.readInt());
		}

		ctx.write(resultPacket(ctx, MATCH_DETAILS_START));
		var buffer = ctx.buffer(DETAIL_FINGERPRINT_ROWS * 93);
		for (var i = 1; i <= DETAIL_FINGERPRINT_ROWS; i++) {
			buffer.writeInt(9200 + i);
			BufferUtil.writeString(buffer, "FP-DETAIL-LONG-" + i, StandardCharsets.ISO_8859_1,
				64);
			BufferUtil.writeString(buffer, "FP-D16-" + i, StandardCharsets.ISO_8859_1,
				NAME_LENGTH);
			buffer.writeByte(50 + i);
			buffer.writeInt(9300 + i);
			buffer.writeInt(9400 + i);
		}
		ctx.write(new GamePacket(MATCH_DETAILS_ENTRIES, buffer));
		ctx.write(resultPacket(ctx, MATCH_DETAILS_END));
	}

	/**
	 * Player details ({@code 0x4220}). The 201-byte reply layout is ELF-traced field by field
	 * (parser {@code 0xD3D874}): u32 result, u32 (id echo?), 16B string, u32, u8, u8, u32, u32,
	 * u8, 128B string (comment?), u32, 16B string (clan?), u8, u32, u32, u8, u32. Only the
	 * result code's meaning is confirmed; everything else is TEMPORARY fingerprint markers —
	 * u32s 95xx in field order, u8s 6x, strings FP-*. The logged request id is the experiment:
	 * it reveals whether the history row's second u32 (91xx) is the character id.
	 */
	private void getPlayerDetails(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var playerId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() : 0;
		// Deliberately INFO: this echo identifies which history-record field the client sends.
		logger.info("Player details requested for character {}.", playerId);

		var buffer = ctx.buffer(201);
		buffer.writeInt(0);        // result code: 0 = success
		buffer.writeInt(playerId); // candidate id echo — echoed to test the label
		BufferUtil.writeString(buffer, "FP-DTL-NAME", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		buffer.writeInt(9501);
		buffer.writeByte(61);
		buffer.writeByte(62);
		buffer.writeInt(9502);
		buffer.writeInt(9503);
		buffer.writeByte(63);
		BufferUtil.writeString(buffer, "FP-DTL-COMMENT-128", StandardCharsets.ISO_8859_1, 128);
		buffer.writeInt(9504);
		BufferUtil.writeString(buffer, "FP-DTL-CLAN", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		buffer.writeByte(64);
		buffer.writeInt(9505);
		buffer.writeInt(9506);
		buffer.writeByte(65);
		buffer.writeInt(9507);
		ctx.write(new GamePacket(PLAYER_DETAILS_RESULT, buffer));
	}

	/** An empty list, delivered as success: the start/end pair with nothing between. */
	private void writeEmptyList(GameControllerContext ctx, int startCommand, int endCommand) {
		ctx.write(resultPacket(ctx, startCommand));
		ctx.write(resultPacket(ctx, endCommand));
	}

	/**
	 * A start/end packet: u32 result code 0, success. The end packet's value overwrites the
	 * client's result slot unconditionally, so both must be 0; anything else surfaces in the
	 * screen's error dialog.
	 */
	private GamePacket resultPacket(GameControllerContext ctx, int command) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(0);
		return new GamePacket(command, buffer);
	}

	/** Reads a fixed-width field the client pads with NULs. */
	private static String readNulTerminated(io.netty.buffer.ByteBuf buffer, int length) {
		var bytes = new byte[Math.min(length, buffer.readableBytes())];
		buffer.readBytes(bytes);

		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, 0, end, StandardCharsets.ISO_8859_1);
	}
}
