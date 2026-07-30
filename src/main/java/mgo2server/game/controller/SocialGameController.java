package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.model.Chara;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
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

	/** The client's history table caps at 64 rows (parser {@code 0xD3B5FC}); more is dropped. */
	private static final int HISTORY_LIMIT = 64;

	/** 25-byte history records; 40 per item packet keeps the payload under the 1023-byte cap. */
	private static final int HISTORY_ENTRIES_PER_PACKET = 40;

	private final CharacterService characterService;

	private final ClanService clanService;

	private final GameService gameService;

	public SocialGameController(CharacterService characterService, ClanService clanService,
			GameService gameService) {
		this.characterService = characterService;
		this.clanService = clanService;
		this.gameService = gameService;
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
	 * {@code 0xD46128} rejects anything else), a u8 <b>ignore-case</b> toggle, and a 16-byte name.
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
		// The second byte is 1 for "ignore case", not for "match case". Live 2026-07-27: searching
		// "bob" with Partial matches and Case Insensitive selected arrived as {0, 1} and returned
		// nothing, because we ran a case-SENSITIVE query and the character is "Bob". The same {0, 1}
		// arrives from the clan search screen, so the polarity is the client's, not a per-screen
		// quirk. A case-sensitive search is still reachable — the byte is 0 then.
		var ignoreCase = payload.readByte() != 0;
		var name = readNulTerminated(payload, NAME_LENGTH);

		if (name.isEmpty()) {
			writeEmptyList(ctx, PLAYER_SEARCH_START, PLAYER_SEARCH_END);
			return;
		}

		var matches = characterService.search(name, fullMatch, !ignoreCase, SEARCH_LIMIT);

		ctx.write(resultPacket(ctx, PLAYER_SEARCH_START));

		for (var start = 0; start < matches.size(); start += SEARCH_ENTRIES_PER_PACKET) {
			var end = Math.min(start + SEARCH_ENTRIES_PER_PACKET, matches.size());
			var batch = matches.subList(start, end);

			var buffer = ctx.buffer(batch.size() * SEARCH_ENTRY_SIZE);
			for (var chara : batch) {
				buffer.writeInt((int) chara.getId());
				BufferUtil.writeString(buffer, chara.getName(), StandardCharsets.ISO_8859_1,
					NAME_LENGTH);
				// THE THREE UNKNOWN FIELDS ARE ZERO ON PURPOSE, and the "likely clan name" note that
				// used to sit on the first 16-byte field was wrong enough to be dangerous.
				// mgo2_cmd_4602_s2c.ksy reads the same bytes as CURRENT LOBBY NAME, with the second
				// 16-byte field as current game name and the trailing u8 as a lobby id. Both
				// readings are tier-4 candidates and neither is proven — but filling this with a
				// clan name on the strength of our guess would put the wrong text on a screen that
				// has room for exactly one string here.
				//
				// To settle it, send three distinguishable strings in the three fields and read the
				// search results on a live client; whichever slot renders names the field. Until
				// then zeros, which render as nothing rather than as something false.
				buffer.writeZero(2)     // u16 -> struct+0x16. Candidate: level/rank
					.writeZero(NAME_LENGTH) // 16 -> struct+0x18. Candidate: current LOBBY name
					.writeZero(4)       // u32 -> struct+0x2C. Candidate: in-game flag
					.writeZero(NAME_LENGTH) // 16 -> struct+0x30. Candidate: current GAME name
					.writeZero(1);      // u8  -> struct+0x41. Candidate: lobby id
			}
			ctx.write(new GamePacket(PLAYER_SEARCH_ENTRIES, buffer));
		}

		ctx.write(resultPacket(ctx, PLAYER_SEARCH_END));
	}

	/**
	 * Met-players history ({@code 0x4680}, u32 character id). 25-byte records, all fields
	 * live-confirmed 2026-07-23 (OBSERVED.md): u32 Unix timestamp of the last encounter, u32
	 * character id (echoed by the row's player-scoped menu actions), 16-byte player name, and a
	 * u8 that rendered nothing in the fingerprint (sent 0). Rows derive from {@code round_report}
	 * at query time — players who shared a game with the viewer, newest first.
	 */
	private void getMatchHistory(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < Integer.BYTES) {
			writeEmptyList(ctx, MATCH_HISTORY_START, MATCH_HISTORY_END);
			return;
		}
		var charaId = payload.readInt();
		var met = gameService.metPlayers(charaId, HISTORY_LIMIT);
		logger.debug("Match history for character {}: {} rows.", charaId, met.size());

		ctx.write(resultPacket(ctx, MATCH_HISTORY_START));
		for (var start = 0; start < met.size(); start += HISTORY_ENTRIES_PER_PACKET) {
			var end = Math.min(start + HISTORY_ENTRIES_PER_PACKET, met.size());
			var batch = met.subList(start, end);

			var buffer = ctx.buffer(batch.size() * 25);
			for (var player : batch) {
				buffer.writeInt((int) player.lastMetEpochSeconds());
				buffer.writeInt((int) player.charaId());
				BufferUtil.writeString(buffer, player.name(), StandardCharsets.ISO_8859_1,
					NAME_LENGTH);
				buffer.writeByte(0); // cosmetically inert in the fingerprint; meaning unknown
			}
			ctx.write(new GamePacket(MATCH_HISTORY_ENTRIES, buffer));
		}
		ctx.write(resultPacket(ctx, MATCH_HISTORY_END));
	}

	/**
	 * Match details ({@code 0x4684}, u32 entry id from the history list — the logged id reveals
	 * which list field the client echoes). 93-byte records (u32, 64-byte string, 16-byte string,
	 * u8, u32, u32), ELF-traced but <b>fully unlabelled</b>, so we serve an empty list.
	 * <p>
	 * The request is still logged: the echoed entry id is what identifies which field of the
	 * {@code 0x4682} record the client sends here, and that is worth keeping even while the reply
	 * is empty.
	 */
	private void getMatchDetails(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() >= Integer.BYTES) {
			// Deliberately INFO: this echo identifies the entry-id field of the 0x4682 record.
			logger.info("Match details requested for entry {}.", payload.readInt());
		}

		// AN EMPTY LIST, not invented rows. This sent three fingerprint records — literal
		// "FP-DETAIL-LONG-1" text and fabricated ids — to a real screen, unconditionally, for every
		// request. It was the last surviving fingerprint payload; its siblings were removed after
		// one of them ("FP-STR-C") was parsed as a bitfield and minted 17 medals nobody had earned.
		//
		// The 93-byte record is ELF-traced but entirely unlabelled, so there is nothing honest to
		// put in it. An empty list says "no details" — which is true — where invented rows say
		// something false in a way the player can read.
		writeEmptyList(ctx, MATCH_DETAILS_START, MATCH_DETAILS_END);
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

		// Real data, at last. This reply was a fingerprint payload — FP-DTL-NAME, FP-DTL-CLAN and
		// numbered constants — sent to find out which offset fed which label. It did its job: the
		// fields it identified are recorded in dev/proto/outbound/mgo2_cmd_4221_s2c.ksy, and the screen showed
		// placeholders ever since. The clan in particular read as "----" until the player opened
		// More Details, which fetches 0x4103 and does carry a real clan, so the value appeared to
		// arrive late when in truth this packet never had it.
		var chara = playerId == 0 ? java.util.Optional.<Chara>empty()
			: characterService.get(playerId);
		var name = chara.map(Chara::getName).orElse("");
		var comment = chara.map(Chara::getComment).orElse("");
		var clan = playerId == 0 ? ClanService.Membership.NONE : clanService.membershipOf(playerId);
		// The same total the personal stats screen shows: the sum across game modes.
		var playSeconds = playerId == 0 ? 0L : characterService.displayedPlaySeconds(playerId);
		var experience = playerId == 0 ? 0L : characterService.experienceOf(playerId);

		var buffer = ctx.buffer(201);
		buffer.writeInt(0);                                       // result: success
		buffer.writeInt(playerId);
		BufferUtil.writeString(buffer, name, StandardCharsets.ISO_8859_1, NAME_LENGTH);
		// Wire 0x18 is EXPERIENCE, not a level. The screen has no experience figure on it — it shows
		// a Level — so the client derives that from the number here, walking its own threshold table
		// (125, 250, 375, 500, 650, ...) and showing one more than the count of thresholds cleared.
		// CharacterService.LEVEL_3_EXPERIENCE and LEVEL_4_EXPERIENCE record two of those points.
		//
		// Proven by probe: four candidate fields were sent values chosen to land on four distinct
		// levels through that table — 1450 at 0x18, 250 at 0x1c, 130 at 0x1d, 500 at 0x1e — and every
		// character read Level 10, the value at 0x18. The round before it sent 11/22/33/44 and read
		// level 0 everywhere, which was the same answer unrecognised: all four were under the first
		// threshold.
		buffer.writeInt((int) experience);                        // [CONFIRMED] wire 0x18, experience
		buffer.writeByte(0);                                      // [UNKNOWN] wire 0x1c
		buffer.writeByte(0);                                      // [UNKNOWN] wire 0x1d
		buffer.writeInt(0);                                       // [UNKNOWN] wire 0x1e
		buffer.writeInt((int) playSeconds);                       // play time, seconds
		buffer.writeByte(0);                                      // [UNKNOWN] wire 0x26
		BufferUtil.writeString(buffer, comment == null ? "" : comment,
			StandardCharsets.ISO_8859_1, 128);
		// The clan record, as a {u32 id, name[16], u8 state} triple — the same shape this protocol
		// uses for a clan everywhere else (session record at +0x1AA0, 0x4122's block, 0x4b47,
		// 0x4b21's head, 0x4103's tail). The name alone was not enough: every reader traced so far
		// checks the ID first and treats zero as "no clan" whatever the name says, which is why the
		// field rendered as "----" while carrying "best clan".
		buffer.writeInt((int) clan.id());                         // wire 0xa7, clan id
		BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
		buffer.writeByte(clan.state());                           // wire 0xbb, membership state
		// [ELF] wire 0xbc/0xc0 -> profile+13016/+13020, read as a pair at 0x91858C and put through
		// 0x94258C, which is min(10, ((a*20)/b - 1)/10 + 1) and returns 0 if either is 0. They drive
		// a 1-of-10 star gauge, with the second also printed literally as " / N". So 0xbc is a
		// numerator and 0xc0 its total.
		//
		// WHAT THEY COUNT IS THE HOST RATING [ELF 2026-07-30, was "still unknown"]. profile+13016
		// and +13020 are entries 5 and 6 of 0x4103's rating_block (base 0x32C4, so 0x32C4+5*4 and
		// +6*4), and 0x918590 pairs them into the half-star gauge 0x94258C exactly as it pairs
		// 13040/13044 -- the confirmed Instructor Score pair -- three instructions earlier.
		//
		// They stay zero for now, which the gauge reads as "no bar" rather than as a wrong one.
		// Wiring them means reusing the same host-rating votes GameJoin already gates on: see the
		// 0x4321 wire 0x28 star-picker gate.
		buffer.writeInt(0);                                       // wire 0xbc, host rating numerator
		buffer.writeInt(0);                                       // wire 0xc0, host rating denominator

		// [CONFIRMED ELF] wire 0xc4 -> profile+6872: the clan emblem flag, the same byte 0x4122 and
		// 0x4b47 write. The parser stores it at 0xD3DA84, and the Player Details screen tests it at
		// 0x905A90 (cmpwi r0,3) — but only after 0x905A8C has checked the membership state at 0xbb
		// is 1 or 2. On a match it calls 0xD56704, which sends 0x4b4a and fetches the image.
		//
		// Sending 0 is not "no picture", it is "never ask" — the fetch is skipped and the emblem is
		// silently absent. This screen is the ONLY writer of 6872 on this path (0x4103 does not
		// touch it), so the emblem on Player Details depends on this byte alone.
		buffer.writeByte(clan.id() == 0 ? 0
			: (clanService.emblemFlagOf(clan.id()) == ClanService.EMBLEM_ON_DISPLAY
				? ClanService.EMBLEM_ON_DISPLAY : 0));       // wire 0xc4, emblem flag

		// [ELF] wire 0xc5 -> profile+292, read at 0x905E00 and 0x915F64. Both run it through the
		// level-from-experience walker 0x6F9260, clamp to 1..23, index a 24-entry table and render
		// "%s (%d)" — a title for its level, then the raw number. So it is a second experience-scale
		// quantity, distinct from wire 0x18 (which is the Level and renders bare). Which quantity is
		// unknown: the table holds resource hashes, not strings. Zero until that is answered.
		buffer.writeInt(0);                                       // [UNKNOWN] wire 0xc5
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
