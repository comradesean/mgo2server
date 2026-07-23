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
 * The social family: player search ({@code 0x4600}) and match history ({@code 0x4680}/
 * {@code 0x4684}). All three are start/item/end list triples like the game browser, traced from
 * the binary 2026-07-23 (senders {@code 0xD46128}/{@code 0xD3B864}/{@code 0xD3B778}; parsers
 * {@code 0xD45DF0}+ / {@code 0xD3ADF4}+ / {@code 0xD3ABC8}+). Unanswered, each stalls its screen
 * into {@code FFFFFF60}.
 * <p>
 * The start and end packets carry a bare u32 <em>count</em>, not a result code — none of these
 * replies has a status field. Item packets carry records back to back with no per-packet count;
 * the client reads until the payload ends, so records may be split across packets freely.
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
	}

	/**
	 * Player search: a u8 match-criteria toggle (0 partial, 1 full — the builder at
	 * {@code 0xD46128} rejects anything else), a u8 match-case toggle, and a 16-byte name.
	 */
	private void playerSearch(GameControllerContext ctx) {
		// These replies have no status field, so a missing session cannot be refused with an
		// error code the way other handlers do it; an empty result unblocks the client instead.
		if (ctx.connection().account() == null) {
			writeCountedList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END, 0);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < 2 + NAME_LENGTH) {
			logger.warn("Player search with {} payload bytes; expected {}.",
				payload.readableBytes(), 2 + NAME_LENGTH);
			writeCountedList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END, 0);
			return;
		}
		var fullMatch = payload.readByte() != 0;
		var caseSensitive = payload.readByte() != 0;
		var name = readNulTerminated(payload, NAME_LENGTH);

		if (name.isEmpty()) {
			writeCountedList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END, 0);
			return;
		}

		var matches = characterService.search(name, fullMatch, caseSensitive, SEARCH_LIMIT);

		ctx.write(countPacket(ctx, PLAYER_SEARCH_START, matches.size()));

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

		ctx.write(countPacket(ctx, PLAYER_SEARCH_END, matches.size()));
	}

	/**
	 * Match history ({@code 0x4680}, u32 character id): match outcomes are not recorded yet, so
	 * every history is empty — start and end with a zero count, no item packets. When they are,
	 * the record is 25 bytes (u32, u32, 16-byte string, u8) and the client's table caps at 64.
	 */
	private void getMatchHistory(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			logger.debug("Match history requested for character {}.", payload.readInt());
		}
		writeCountedList(ctx, MATCH_HISTORY_START, MATCH_HISTORY_END, 0);
	}

	/**
	 * Match details ({@code 0x4684}, u32 entry id from the history list). Unreachable while every
	 * history is empty, but answered anyway so a stale selection can never stall. The record is
	 * 93 bytes (u32, 64-byte string, 16-byte string, u8, u32, u32); the client's table caps at 32.
	 */
	private void getMatchDetails(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			logger.debug("Match details requested for entry {}.", payload.readInt());
		}
		writeCountedList(ctx, MATCH_DETAILS_START, MATCH_DETAILS_END, 0);
	}

	/** An empty list: the start/end pair with the same count and nothing between. */
	private void writeCountedList(GameControllerContext ctx, int startCommand, int endCommand,
			int count) {
		ctx.write(countPacket(ctx, startCommand, count));
		ctx.write(countPacket(ctx, endCommand, count));
	}

	private GamePacket countPacket(GameControllerContext ctx, int command, int count) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(count);
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
