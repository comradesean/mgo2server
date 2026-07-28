package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.StatsService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import io.netty.buffer.ByteBuf;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The personal-stats screen ({@code 0x4102}, a u32 character id — the viewer's own or one picked
 * from a list). Traced from the binary 2026-07-23: the reply is a three-packet burst, all parsed
 * into one struct and all keyed to the same wait slot. {@code 0x4107} is the packet that releases
 * the client ({@code 0xd3e4b0} sets the slot complete), so it must be sent last. Unanswered, the
 * screen stalls into {@code FFFFFF60}.
 * <p>
 * {@code 0x4103} opens with a real status u32: on a nonzero value the client completes with that
 * error and skips the rest ({@code 0xd3ea38}), so a bad character id gets {@code 0x4103} alone.
 * {@code 0x4105} and {@code 0x4107} carry no status the client acts on.
 * <p>
 * Only the head of {@code 0x4103} is understood (id, name, the {@code 0x4101} constant block,
 * experience, login times, friend/blocked ids), and the rest of that packet still carries
 * fingerprint values. The totals are what the parsers consume
 * ({@code 0xd3e9ac}/{@code 0xd3e53c}/{@code 0xd3db1c}) and must not change.
 * <p>
 * <b>{@code 0x4105} and {@code 0x4107} carry real data as of 2026-07-28</b>, derived from
 * {@code round_report} by {@link mgo2server.common.service.StatsService} — both periods of each.
 * Anything not honestly derivable is <b>zero</b>, never a placeholder: the client mints medals and
 * titles itself from these values, so the {@code 1000 + slot} fingerprints this screen used to send
 * cleared every threshold in its table and handed a fresh character the full medal set.
 * <p>
 * Two ordering rules in the burst are load-bearing. {@code 0x4105} page 0 must precede page 1,
 * because receipt of page 0 zeroes the whole grid region including page 1; and {@code 0x4107} must
 * be last, because its parser unconditionally completes the wait slot.
 */
public class PersonalStatsController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int GET_PERSONAL_STATS = 0x4102;

	public static final int PERSONAL_STATS_INFO = 0x4103;

	public static final int PERSONAL_STATS_MATRIX = 0x4105;

	public static final int PERSONAL_STATS_TAIL = 0x4107;

	/** Fixed grids the three parsers consume. */
	private static final int INFO_SIZE = 0x288;

	private static final int MATRIX_SIZE = 0x248;

	private static final int TAIL_SIZE = 0x24C;

	/** Each {@code 0x4107} record is 292 bytes = 73 u32s. */
	private static final int TAIL_RECORD_INTS = 73;

	/** Page selector for the cumulative grid. Must be sent BEFORE the weekly one. */
	private static final int PERIOD_CUMULATIVE = 0;

	/** Page selector for the weekly grid. */
	private static final int PERIOD_WEEKLY = 1;

	/** The one signed column of the matrix — a round score can be negative. */
	private static final int SCORE_COLUMN = 3;

	/** Friend and blocked id arrays, 32 slots each, matching 0x4101. */
	private static final int RELATION_LIST_IDS = 32;

	private static final int NAME_LENGTH = 16;

	/** The 128-byte comment field at wire offset 413, confirmed live via fingerprint v3. */
	private static final int COMMENT_LENGTH = 128;

	/** The status the error path compares; any nonzero value surfaces as an error. */
	private static final int STATUS_NOT_FOUND = 1;

	private final CharacterService characterService;

	private final ClanService clanService;

	private final AccountService accountService;

	private final StatsService statsService;

	public PersonalStatsController(CharacterService characterService, ClanService clanService,
			AccountService accountService, StatsService statsService) {
		this.characterService = characterService;
		this.clanService = clanService;
		this.accountService = accountService;
		this.statsService = statsService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_PERSONAL_STATS, this::getPersonalStats);
	}

	private void getPersonalStats(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (ctx.connection().account() == null || payload.readableBytes() < Integer.BYTES) {
			writeError(ctx);
			return;
		}

		var charaId = payload.readInt();
		var chara = characterService.get(charaId);
		if (chara.isEmpty()) {
			logger.debug("Personal stats requested for unknown character {}.", charaId);
			writeError(ctx);
			return;
		}

		var owner = accountService.get(chara.get().getAccountId());
		var main = owner.getMainCharaId();
		var experience = main != null && main == chara.get().getId()
			? owner.getMainExp() : owner.getAltExp();

		var info = ctx.buffer(INFO_SIZE);
		info.writeInt(0); // status
		info.writeInt((int) chara.get().getId());
		BufferUtil.writeString(info, chara.get().getName(), StandardCharsets.ISO_8859_1,
			NAME_LENGTH);
		info.writeBytes(CharacterConnectController.INFO_PREFIX);
		info.writeInt(experience);
		// v4: the "login times / flag / friend ids / blocked ids" labels were inferred from the
		// 0x4101 layout, never observed — and after v2/v3 they are the only bytes of this packet
		// that have been zero in every round while the per-mode grids also stayed zero. So they
		// are fingerprinted too: logins 9001/9002, the 64 u32s as 8001–8032 and 8501–8532.
		// Login times: we do not record them. Zero rather than 9001/9002 — an invented epoch
		// renders as a real date, and "never" is the honest answer.
		info.writeInt(0).writeInt(0);
		info.writeByte(1); // the lone u8 — 1 rather than 0 in case it gates display
		// The friend and blocked lists are REAL ids, from chara_relation, the same source
		// 0x4101 uses. They used to be fingerprints (8001+i / 8501+i), which fed the client 64
		// character ids that do not exist.
		writeRelationIds(info, charaId, CharacterService.RELATION_FRIEND);
		writeRelationIds(info, charaId, CharacterService.RELATION_BLOCKED);

		// TEMPORARY fingerprint v5 of the 0x4103 tail, now on the byte-exact layout read from
		// the parser (0xd3e9ac, traced 2026-07-23): u32s carry 4001+, u16s 5101+, u8s distinct
		// small values, and each string field an ASCII marker, so every on-screen value or text
		// names its wire field. The comment slot carries the character's real comment.
		info.writeByte(42);            // u8 @301 → T+0x3329
		// The clan record — why Personal Data showed no clan. T+0x1AA0/0x1AA4/0x1AB5 are the same
		// {u32 id, name[16], u8 status} shape as the session clan record at session_ctx+0x1AA0 and
		// as 0x4122's clan block, and the 12 u16s after it are that block's privilege word and its
		// eleven unread siblings. The 0x4103 spec recorded these as unknown, noting "NOT the clan
		// field — clan stayed blank": true only because they had never carried a real clan.
		var clan = clanService.membershipOf(charaId);
		info.writeInt((int) clan.id());  // u32 → T+0x1AA0
		BufferUtil.writeString(info, clan.name(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
		info.writeByte(clan.state());    // u8 → T+0x1AB5
		for (var i = 0; i < 12; i++) {
			info.writeShort(0);        // 12×u16 → T+0x1AB6.. — the privilege word must stay 0
		}
		info.writeInt(0);              // u32 → T+0x1AD0 [UNKNOWN]
		for (var i = 0; i < 9; i++) {
			info.writeByte(61 + i);    // 9×u8 → T+0x1DE0..
		}
		info.writeInt(0);              // u32 → T+0x1DEC [UNKNOWN]
		for (var i = 0; i < 14; i++) {
			info.writeByte(71 + i);    // 14×u8 → T+0x1DF0..
		}
		for (var i = 0; i < 10; i++) {
			info.writeByte(91 + i);    // 5×u8 + 5×u8 → T+0x1DFE..
		}
		for (var i = 0; i < 5; i++) {
			info.writeInt(0);          // 5×u32 → T+0x1E08.. [UNKNOWN]
		}
		info.writeByte(44);            // u8 → T+0x1E1C
		info.writeInt(0);              // u32 → T+0x1E20 [UNKNOWN]
		BufferUtil.writeString(info, chara.get().getComment(), StandardCharsets.ISO_8859_1,
			COMMENT_LENGTH);           // the confirmed 128-byte comment → T+0x1E24
		info.writeByte(45);            // u8 → T+0x1EA5
		for (var i = 0; i < 9; i++) {
			info.writeByte(101 + i);   // 9×u8 → T+0x32B8..
		}
		for (var i = 0; i < 9; i++) {
			info.writeInt(0);          // 9×u32 → T+0x32C4.. — entry 7 is the HOST RATING
			                           // denominator and rendered as "/ 4027 votes"; we measure no
			                           // host rating, so 0 is the honest denominator
		}
		info.writeInt(0);              // u32 → obj+0x30, not T [UNKNOWN]

		// The instructor block, real data as of V25. It was fingerprinted ("FP-STR-B" in the name,
		// 4031 in the generation candidate), which told every character that they already had an
		// instructor called FP-STR-B — a lie the client may well act on, since the recognition
		// toggle a student is offered at graduation plausibly checks whether they have one.
		// A character who has never graduated now sends an empty name and zeros.
		var instructor = characterService.instructorOf(charaId).orElse(null);
		BufferUtil.writeString(info, instructor != null ? instructor.instructorName() : "",
			StandardCharsets.ISO_8859_1, NAME_LENGTH);
		// Wire 607, the "generation" candidate: it rendered nothing when it carried 4031, so
		// either it is not the generation or the line needs more than this field. Sending the real
		// value makes the next look at that screen a test rather than another fingerprint.
		info.writeInt(instructor != null ? instructor.generation() : 0);
		info.writeInt(0);              // [UNKNOWN]
		BufferUtil.writeString(info, "FP-STR-C", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		// [ELF] The clan emblem flag, not a spare byte. T+0x1AD8 is 6816 + 56, and the 0x4103
		// parser writes this u8 with `addi r4,r24,56` off `r24 = profile+6816` (0xD3F3FC), so it
		// lands in profile+6872 — the same slot 0x4122 fills for the local player. It sat here
		// carrying the fingerprint value 46 since the tail was mapped, which is why no one ever
		// saw anyone else's emblem: 0x905A94 tests this byte for exact equality with 3, and
		// anything else means "no emblem" and skips the 0x4b4a fetch entirely.
		//
		// The gate at 0x905A7C needs BOTH this byte == 3 and the membership state above in
		// {1, 2} — state 0 wraps to 255 under its unsigned compare and also skips. A character
		// with no clan sends state 99 and flag 0, and correctly fetches nothing.
		info.writeByte(clan.id() != 0
			&& clanService.emblemFlagOf(clan.id()) == ClanService.EMBLEM_ON_DISPLAY
			? ClanService.EMBLEM_ON_DISPLAY : 0);    // u8 → T+0x1AD8 = profile+6872
		info.writeInt(0)               // → T+0x32F0
			.writeInt(0)               // → T+0x32F4: the INSTRUCTOR SCORE denominator, rendered as
			                           // "/ 4034 votes" until now. Same reasoning as host rating.
			.writeInt(0);              // → T+0x32F8
		info.writeInt(0);              // trailing u32 → T+0x124 [UNKNOWN]
		ctx.write(new GamePacket(PERSONAL_STATS_INFO, info));

		// Both stats surfaces, both periods, all derived from round_report at query time.
		//
		// ORDER MATTERS AND IS NOT NEGOTIABLE. Page 0 must precede page 1 — the parser zeroes the
		// whole grid region (both pages) when it receives page 0, so a page-1-first burst loses
		// the weekly grid. And 0x4107 must be LAST: its parser unconditionally completes wait slot
		// 0x16 (0xd3e4b0), so anything sent after it arrives unexpected and anything missing
		// stalls the screen into FFFFFF60.
		//
		// Nothing here is a fingerprint any more. The client mints medals and titles itself from
		// these values, so an invented number awards an unearned medal; every slot we cannot
		// derive honestly is served as zero. See StatsService.
		writeMatrix(ctx, charaId, StatsService.Period.CUMULATIVE, PERIOD_CUMULATIVE);
		writeMatrix(ctx, charaId, StatsService.Period.WEEKLY, PERIOD_WEEKLY);

		var tail = ctx.buffer(TAIL_SIZE);
		tail.writeInt(0); // status
		writeScoreRecord(tail, statsService.personalScores(charaId, StatsService.Period.CUMULATIVE));
		writeScoreRecord(tail, statsService.personalScores(charaId, StatsService.Period.WEEKLY));
		ctx.write(new GamePacket(PERSONAL_STATS_TAIL, tail));
	}

	/**
	 * One {@code 0x4105} matrix: status, the page selector, then 8 mode rows of 18 u32 columns,
	 * mode-major.
	 * <p>
	 * The page selector MUST be 0 or 1 — the parser bails with {@code -0x47} on anything larger
	 * and silently discards the whole matrix, which is what the v1–v4 fingerprint rounds did by
	 * sending 7 and 8.
	 * <p>
	 * Column 3 (score) is the one signed column; everything else is an unsigned count. Values are
	 * clamped into u32 range because the wire has no room to say "more than this" — saturating is
	 * closer to the truth than wrapping, and it matches how the client's own counters saturate.
	 */
	private void writeMatrix(GameControllerContext ctx, long charaId, StatsService.Period period,
			int pageSelector) {
		var grid = statsService.modeGrid(charaId, period);
		var matrix = ctx.buffer(MATRIX_SIZE);
		matrix.writeInt(0); // status
		matrix.writeInt(pageSelector);
		for (var mode = 0; mode < StatsService.MODE_ROWS; mode++) {
			for (var column = 0; column < StatsService.STAT_COLUMNS; column++) {
				matrix.writeInt(column == SCORE_COLUMN
					? (int) Math.clamp(grid[mode][column], Integer.MIN_VALUE, Integer.MAX_VALUE)
					: (int) Math.clamp(grid[mode][column], 0, 0xFFFFFFFFL));
			}
		}
		ctx.write(new GamePacket(PERSONAL_STATS_MATRIX, matrix));
	}

	/** One 73-slot {@code 0x4107} record; the slot array is 1-based, so index 0 is skipped. */
	private void writeScoreRecord(ByteBuf tail, long[] slots) {
		for (var slot = 1; slot <= TAIL_RECORD_INTS; slot++) {
			tail.writeInt((int) Math.clamp(slots[slot], 0, 0xFFFFFFFFL));
		}
	}

	/** The character's real friend or blocked ids, zero-padded to the fixed 32-slot array. */
	private void writeRelationIds(ByteBuf info, long charaId, int relation) {
		var ids = characterService.relationIds(charaId, relation, RELATION_LIST_IDS);
		for (var id : ids) {
			info.writeInt(id.intValue());
		}
		for (var i = ids.size(); i < RELATION_LIST_IDS; i++) {
			info.writeInt(0);
		}
	}

	private void writeError(GameControllerContext ctx) {
		var info = ctx.buffer(Integer.BYTES);
		info.writeInt(STATUS_NOT_FOUND);
		ctx.write(new GamePacket(PERSONAL_STATS_INFO, info));
	}
}
