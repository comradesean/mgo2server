package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.service.AccountService;
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
 * experience, login times, friend/blocked ids); the rest of its grid, the 8×18 stat matrix in
 * {@code 0x4105} and the two 292-byte records in {@code 0x4107} are sent as zeros until a live
 * capture of the original data maps them. The totals are what the parsers consume
 * ({@code 0xd3e9ac}/{@code 0xd3e53c}/{@code 0xd3db1c}) and must not change.
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

	/** The 8×18 u32 matrix in {@code 0x4105}. */
	private static final int MATRIX_CELLS = 144;

	/** Each {@code 0x4107} record is 292 bytes = 73 u32s. */
	private static final int TAIL_RECORD_INTS = 73;

	/** "Training Mode Time", seconds. 1-based wire slot; CONFIRMED in {@code mgo2_cmd_4107.ksy}. */
	private static final int TRAINING_MODE_SECONDS_SLOT = 46;

	/** "Combat Training Time (Instructor)", seconds. */
	private static final int INSTRUCTOR_SECONDS_SLOT = 47;

	/** "Combat Training Time (Student)", seconds. */
	private static final int STUDENT_SECONDS_SLOT = 48;

	private static final int NAME_LENGTH = 16;

	/** The 128-byte comment field at wire offset 413, confirmed live via fingerprint v3. */
	private static final int COMMENT_LENGTH = 128;

	/** The status the error path compares; any nonzero value surfaces as an error. */
	private static final int STATUS_NOT_FOUND = 1;

	private final CharacterService characterService;

	private final AccountService accountService;

	public PersonalStatsController(CharacterService characterService,
			AccountService accountService) {
		this.characterService = characterService;
		this.accountService = accountService;
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
		info.writeInt(9001).writeInt(9002);
		info.writeByte(1); // the lone u8 — 1 rather than 0 in case it gates display
		for (var i = 0; i < 32; i++) {
			info.writeInt(8001 + i);
		}
		for (var i = 0; i < 32; i++) {
			info.writeInt(8501 + i);
		}

		// TEMPORARY fingerprint v5 of the 0x4103 tail, now on the byte-exact layout read from
		// the parser (0xd3e9ac, traced 2026-07-23): u32s carry 4001+, u16s 5101+, u8s distinct
		// small values, and each string field an ASCII marker, so every on-screen value or text
		// names its wire field. The comment slot carries the character's real comment.
		info.writeByte(42);            // u8 @301 → T+0x3329
		info.writeInt(4001);           // u32 → T+0x1AA0
		BufferUtil.writeString(info, "FP-STR-A", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		info.writeByte(43);            // u8 → T+0x1AB5
		for (var i = 0; i < 12; i++) {
			info.writeShort(5101 + i); // 12×u16 → T+0x1AB6..
		}
		info.writeInt(4002);           // u32 → T+0x1AD0
		for (var i = 0; i < 9; i++) {
			info.writeByte(61 + i);    // 9×u8 → T+0x1DE0..
		}
		info.writeInt(4003);           // u32 → T+0x1DEC
		for (var i = 0; i < 14; i++) {
			info.writeByte(71 + i);    // 14×u8 → T+0x1DF0..
		}
		for (var i = 0; i < 10; i++) {
			info.writeByte(91 + i);    // 5×u8 + 5×u8 → T+0x1DFE..
		}
		for (var i = 0; i < 5; i++) {
			info.writeInt(4011 + i);   // 5×u32 → T+0x1E08..
		}
		info.writeByte(44);            // u8 → T+0x1E1C
		info.writeInt(4016);           // u32 → T+0x1E20
		BufferUtil.writeString(info, chara.get().getComment(), StandardCharsets.ISO_8859_1,
			COMMENT_LENGTH);           // the confirmed 128-byte comment → T+0x1E24
		info.writeByte(45);            // u8 → T+0x1EA5
		for (var i = 0; i < 9; i++) {
			info.writeByte(101 + i);   // 9×u8 → T+0x32B8..
		}
		for (var i = 0; i < 9; i++) {
			info.writeInt(4021 + i);   // 9×u32 → T+0x32C4.. (the UI reads T+0x32D0 = 4024)
		}
		info.writeInt(4030);           // u32 → obj+0x30, not T
		BufferUtil.writeString(info, "FP-STR-B", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		info.writeInt(4031).writeInt(4032);
		BufferUtil.writeString(info, "FP-STR-C", StandardCharsets.ISO_8859_1, NAME_LENGTH);
		info.writeByte(46);            // u8 → T+0x1AD8
		info.writeInt(4033).writeInt(4034).writeInt(4035); // → T+0x32F0/F4/F8
		info.writeInt(4036);           // trailing u32 → T+0x124
		ctx.write(new GamePacket(PERSONAL_STATS_INFO, info));

		// TEMPORARY fingerprint payload, 2026-07-23: the matrix and tail semantics are unmapped,
		// so every u32 carries its own wire position as its value — whatever number a stat shows
		// on screen names the slot it came from. Matrix cells are 1–144 in wire order (the parser
		// reads 18 groups of 8, so value v sits in group (v-1)/8, index (v-1)%8); the two tail
		// records are 1001–1073 and 2001–2073. Replace with real data as slots get labelled.
		var matrix = ctx.buffer(MATRIX_SIZE);
		matrix.writeInt(0); // status
		// The second u32 is a PAGE SELECTOR and must be 0 or 1 (parser bails on anything
		// greater — which is what v1's 7 and v2–v4's 8 did, silently skipping the matrix).
		// Wire order is 8 modes × 18 stats, mode-major.
		matrix.writeInt(0);
		// v8: is the ALL row client-computed (like the Total page) or shown from the wire?
		// Columns 0/1/4/5 are deliberately too small to be sums: ALL = 3/4/5/6 means the wire
		// value renders directly; ALL = 15/26/37/48 means the client sums the displayed rows.
		var deathmatch = new int[] {
			3, 4, 5, 3004, 5, 6, 10, 20, 30, 40, 7, 6, 8, 52300, 3015, 52500, 3017, 3018,
		};
		for (var cell = 0; cell < MATRIX_CELLS; cell++) {
			var mode = cell / 18;
			var column = cell % 18;
			matrix.writeInt(mode == 0 ? deathmatch[column] : 3001 + cell);
		}
		ctx.write(new GamePacket(PERSONAL_STATS_MATRIX, matrix));

		// v9: a second matrix on page 1 (6001–6144), to confirm the live-discovered
		// cumulative/weekly toggle maps to the page selector.
		var weekly = ctx.buffer(MATRIX_SIZE);
		weekly.writeInt(0);
		weekly.writeInt(1);
		for (var cell = 0; cell < MATRIX_CELLS; cell++) {
			weekly.writeInt(6001 + cell);
		}
		ctx.write(new GamePacket(PERSONAL_STATS_MATRIX, weekly));

		// Real values where we have them, fingerprints everywhere else. The three training slots
		// are CONFIRMED labels (mgo2_cmd_4107.ksy) and we hold the data: round_report stores the
		// host's own measurement of each player's presence, which is what these totals are.
		// Record 1 is lifetime and record 2 weekly; we have no period model, so weekly repeats the
		// lifetime total rather than inventing a reset cadence.
		var training = characterService.trainingSeconds(charaId);

		var tail = ctx.buffer(TAIL_SIZE);
		tail.writeInt(0); // status
		for (var record = 0; record < 2; record++) {
			for (var i = 1; i <= TAIL_RECORD_INTS; i++) {
				tail.writeInt(switch (i) {
					case TRAINING_MODE_SECONDS_SLOT -> (int) training.trainingMode();
					case INSTRUCTOR_SECONDS_SLOT -> (int) training.instructor();
					case STUDENT_SECONDS_SLOT -> (int) training.student();
					default -> (record + 1) * 1000 + i;
				});
			}
		}
		ctx.write(new GamePacket(PERSONAL_STATS_TAIL, tail));
	}

	private void writeError(GameControllerContext ctx) {
		var info = ctx.buffer(Integer.BYTES);
		info.writeInt(STATUS_NOT_FOUND);
		ctx.write(new GamePacket(PERSONAL_STATS_INFO, info));
	}
}
