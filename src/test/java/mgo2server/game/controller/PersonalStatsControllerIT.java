package mgo2server.game.controller;

import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The personal-stats burst and the outfit commit.
 * <p>
 * Sizes assert what the client's parsers consume, traced from the binary: {@code 0x4103} is a
 * 648-byte grid opening with a status u32, {@code 0x4105} 584, {@code 0x4107} 588 (the packet
 * that releases the client's wait state, so it must arrive last), and {@code 0x4133} is
 * {@code 4 + 5·count + 32} bytes — 651 for a character owning the whole 123-row catalogue, which
 * is what it must be, since {@code 0x4133} refills the very table {@code 0x4124} filled at login.
 */
public class PersonalStatsControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private long accountId;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private void givenSelectedCharacter(String name) {
		accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, main_exp, alt_exp)
					values ('player', 'x', :session, 3, 1234, 99)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		grantStartingGear(charaId);

		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", charaId).execute();
			handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
				.bind("chara", charaId).bind("id", accountId).execute();
		});
	}

	private List<GamePacket> loginThen(GamePacket request, int untilCommand) {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));

		var replies = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(request);
					return;
				}
				replies.add(packet);
				if (packet.getCommand() == untilCommand) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	private static GamePacket statsRequest(long charaId) {
		var payload = Unpooled.buffer();
		payload.writeInt((int) charaId);
		return new GamePacket(PersonalStatsController.GET_PERSONAL_STATS, payload);
	}

	/**
	 * The burst is four packets: info, the cumulative matrix (page 0), the weekly matrix
	 * (page 1), and the terminal tail — pages capture-proven as the cumulative/weekly toggle.
	 */
	@Test
	public void answersWithTheFourPacketBurst() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(statsRequest(charaId), PersonalStatsController.PERSONAL_STATS_TAIL);

		assertThat(replies).hasSize(4);

		var info = replies.get(0);
		assertThat(info.getCommand()).isEqualTo(PersonalStatsController.PERSONAL_STATS_INFO);
		assertThat(info.getPayload().readableBytes()).isEqualTo(0x288);
		assertThat(info.getPayload().getInt(0)).isEqualTo(0); // status
		assertThat(info.getPayload().getInt(4)).isEqualTo((int) charaId);
		var name = new byte[5];
		info.getPayload().getBytes(8, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1)).isEqualTo("Snake");
		// Main character, so the account's main experience.
		assertThat(info.getPayload().getInt(0x20)).isEqualTo(1234);

		for (var page = 0; page <= 1; page++) {
			var matrix = replies.get(1 + page);
			assertThat(matrix.getCommand())
				.isEqualTo(PersonalStatsController.PERSONAL_STATS_MATRIX);
			assertThat(matrix.getPayload().readableBytes()).isEqualTo(0x248);
			assertThat(matrix.getPayload().getInt(0)).isEqualTo(0); // status
			// The page selector: anything above 1 makes the client discard the matrix.
			assertThat(matrix.getPayload().getInt(4)).isEqualTo(page);
		}

		assertThat(replies.get(3).getCommand())
			.isEqualTo(PersonalStatsController.PERSONAL_STATS_TAIL);
		assertThat(replies.get(3).getPayload().readableBytes()).isEqualTo(0x24C);
	}

	// --- Aggregation: 0x4105 and 0x4107 served from round_report ----------------------------

	/** Inserts one round report for the selected character. Columns default; name what matters. */
	private void givenReport(int rule, String columns, String values) {
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("insert into round_report (game_id, host_chara_id, chara_id, rule"
					+ (columns.isEmpty() ? "" : ", " + columns) + ") values (777, :chara, :chara, "
					+ rule + (values.isEmpty() ? "" : ", " + values) + ")")
				.bind("chara", charaId)
				.execute());
	}

	/** A 58-element struct-B literal with the named 1-based SLOTS set; slot n is B index n-1. */
	private static String detail(int... slotValuePairs) {
		var slots = new int[58];
		for (var i = 0; i < slotValuePairs.length; i += 2) {
			slots[slotValuePairs[i] - 1] = slotValuePairs[i + 1];
		}
		var literal = new StringBuilder("'{");
		for (var i = 0; i < slots.length; i++) {
			literal.append(i == 0 ? "" : ",").append(slots[i]);
		}
		return literal.append("}'").toString();
	}

	/** Matrix cell: status u32 + page u32, then 8 mode rows of 18 u32 columns, mode-major. */
	private static int cell(GamePacket matrix, int mode, int column) {
		return matrix.getPayload().getInt(8 + (mode * 18 + column) * 4);
	}

	/** Tail slot, 1-based, record 0 cumulative and record 1 weekly. */
	private static int slot(GamePacket tail, int record, int slotNumber) {
		return tail.getPayload().getInt(4 + (record * 73 + slotNumber - 1) * 4);
	}

	private List<GamePacket> statsBurst() {
		return loginThen(statsRequest(charaId), PersonalStatsController.PERSONAL_STATS_TAIL);
	}

	/**
	 * The anti-fingerprint guard, and the reason this whole change exists.
	 * <p>
	 * The client mints medals and titles itself from these values. The screen used to send
	 * {@code 1000 + slot} and {@code 3001 + cell}, which clears every threshold in the client's
	 * table — a fresh character was being handed the full medal set. A character who has played
	 * nothing must produce nothing.
	 */
	@Test
	public void aCharacterWithNoRoundsSendsAllZeros() {
		givenSelectedCharacter("Snake");

		var replies = statsBurst();

		for (var page = 0; page <= 1; page++) {
			for (var mode = 0; mode < 8; mode++) {
				for (var column = 0; column < 18; column++) {
					assertThat(cell(replies.get(1 + page), mode, column))
						.as("page %d mode %d column %d", page, mode, column)
						.isZero();
				}
			}
		}
		for (var record = 0; record <= 1; record++) {
			for (var slotNumber = 1; slotNumber <= 73; slotNumber++) {
				assertThat(slot(replies.get(3), record, slotNumber))
					.as("record %d slot %d", record, slotNumber)
					.isZero();
			}
		}
	}

	/** Each report lands in its own mode row and nowhere else. */
	@Test
	public void reportsLandInTheirOwnModeRow() {
		givenSelectedCharacter("Snake");
		givenReport(0, "kills", "5");
		givenReport(5, "kills", "3");

		var matrix = statsBurst().get(1);

		assertThat(cell(matrix, 0, 0)).isEqualTo(5);
		assertThat(cell(matrix, 5, 0)).isEqualTo(3);
		assertThat(cell(matrix, 1, 0)).isZero();
		assertThat(cell(matrix, 0, 14)).isEqualTo(1); // rounds
	}

	/**
	 * Rows 6 and 7 must be zero even when a report exists for them. Row 6 has no page of its own
	 * but IS summed into every Total and the header time, so anything binned there inflates totals
	 * with nothing on screen to explain it.
	 */
	@Test
	public void theHiddenModeRowsStayZero() {
		givenSelectedCharacter("Snake");
		givenReport(6, "kills, seconds_in_game", "9, 600");
		givenReport(7, "kills", "4");

		var matrix = statsBurst().get(1);

		for (var column = 0; column < 18; column++) {
			assertThat(cell(matrix, 6, column)).as("row 6 column %d", column).isZero();
			assertThat(cell(matrix, 7, column)).as("row 7 column %d", column).isZero();
		}
	}

	/**
	 * Columns 0/1/4/5 are minuends: the client renders {@code OTHER = column - headshots - lockon}
	 * and never shows the column itself. Sending the plain total is what makes OTHER come out as
	 * "the ones that were neither".
	 */
	@Test
	public void minuendColumnsCarryTheTotalSoTheClientCanSubtract() {
		givenSelectedCharacter("Snake");
		givenReport(0, "kills, headshots, lockon_kills", "10, 3, 2");

		var matrix = statsBurst().get(1);

		assertThat(cell(matrix, 0, 0)).isEqualTo(10); // the client will show OTHER = 10 - 3 - 2
		assertThat(cell(matrix, 0, 6)).isEqualTo(3);
		assertThat(cell(matrix, 0, 2)).isEqualTo(2);
	}

	/** The weekly page is a calendar week; older rounds count cumulatively and not weekly. */
	@Test
	public void theWeeklyPageExcludesRoundsFromBeforeThisWeek() {
		givenSelectedCharacter("Snake");
		givenReport(0, "kills, reported_at", "4, now()");
		givenReport(0, "kills, reported_at", "7, now() - interval '10 days'");

		var replies = statsBurst();

		assertThat(cell(replies.get(1), 0, 0)).isEqualTo(11); // cumulative: both
		assertThat(cell(replies.get(2), 0, 0)).isEqualTo(4);  // weekly: only the recent one
	}

	/**
	 * Slot 5 is struct A {@code counter_0x0f} (knockouts received), not struct-B b04, which counts
	 * self-stuns alone. The two agree only when every stun was self-inflicted.
	 */
	@Test
	public void timesStunnedComesFromStructANotTheSelfStunSlot() {
		givenSelectedCharacter("Snake");
		givenReport(0, "counter_0x0f, detail_counters", "3, " + detail(5, 7));

		var replies = statsBurst();

		assertThat(slot(replies.get(3), 0, 5)).isEqualTo(3);
		// Same underlying column feeds matrix minuend 5, so the two surfaces cannot disagree.
		assertThat(cell(replies.get(1), 0, 5)).isEqualTo(3);
	}

	/**
	 * b00/b01/b02 are deltas of a per-stage record, so summing them inflates without bound. Until
	 * stage boundaries are stored these slots are zero — and the falsifiable consequence is that
	 * the consecutive-kills medals must never appear.
	 */
	@Test
	public void theStreakRecordSlotsAreZeroedRatherThanSummed() {
		givenSelectedCharacter("Snake");
		givenReport(0, "detail_counters", detail(1, 5, 2, 4, 3, 6));
		givenReport(0, "detail_counters", detail(1, 5, 2, 4, 3, 6));

		var tail = statsBurst().get(3);

		assertThat(slot(tail, 0, 1)).isZero();
		assertThat(slot(tail, 0, 2)).isZero();
		assertThat(slot(tail, 0, 3)).isZero();
	}

	/** b24 is an absolute per-stage snapshot, so the career value is a max — never a sum. */
	@Test
	public void consecutiveSurvivalsIsAMaxNotASum() {
		givenSelectedCharacter("Snake");
		givenReport(1, "detail_counters", detail(25, 3));
		givenReport(1, "detail_counters", detail(25, 2));

		assertThat(slot(statsBurst().get(3), 0, 25)).isEqualTo(3);
	}

	/**
	 * The Snake trio keys on b56 {@code rounds_as_snake}, not {@code flag_0x04}: the flag is
	 * recomputed at send time and reads 0 on a teardown report even for the Snake.
	 */
	@Test
	public void theSnakeTrioCountsTeardownReportsViaB56() {
		givenSelectedCharacter("Snake");
		givenReport(4, "flag_0x04, kills, seconds_in_game, detail_counters",
			"0, 6, 300, " + detail(57, 1, 50, 1));

		var tail = statsBurst().get(3);

		assertThat(slot(tail, 0, 63)).isEqualTo(1);   // victories as Snake
		assertThat(slot(tail, 0, 67)).isEqualTo(6);   // kills as Snake
		assertThat(slot(tail, 0, 72)).isEqualTo(300); // seconds as Snake
	}

	/** Knife kills are beyond struct B's 58 slots; they come from the 0x43a2 weapon tallies. */
	@Test
	public void knifeKillsComeFromTheWeaponTallies() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("""
					insert into round_weapon_tally (game_id, chara_id, weapon_id, kills)
					values (777, :chara, 1, 4), (777, :chara, 2, 9)
					""")
			.bind("chara", charaId)
			.execute());

		assertThat(slot(statsBurst().get(3), 0, 64)).isEqualTo(4);
	}

	/**
	 * Training seconds have no period dimension, so the weekly record must carry zero rather than
	 * repeat the lifetime figure — claiming "you trained this week" from a running total is the
	 * same class of invention as the fingerprints.
	 */
	@Test
	public void theWeeklyRecordDoesNotRepeatLifetimeTrainingTime() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("""
					insert into chara_training_time
						(chara_id, training_mode_seconds, instructor_seconds, student_seconds,
						 total_seconds)
					values (:chara, 600, 300, 120, 1020)
					""")
			.bind("chara", charaId)
			.execute());

		var tail = statsBurst().get(3);

		assertThat(slot(tail, 0, 46)).isEqualTo(600);
		assertThat(slot(tail, 0, 47)).isEqualTo(300);
		assertThat(slot(tail, 0, 48)).isEqualTo(120);
		assertThat(slot(tail, 1, 46)).isZero();
		assertThat(slot(tail, 1, 47)).isZero();
		assertThat(slot(tail, 1, 48)).isZero();
	}

	// --- Medals: the 16-byte bitfield at 0x4103 wire 615 ------------------------------------

	/** The medal bitfield, 16 bytes at wire 615 of the 0x4103 payload. */
	private static byte[] medalField(GamePacket info) {
		var field = new byte[16];
		info.getPayload().getBytes(615, field);
		return field;
	}

	/**
	 * The regression this whole area exists for. We sent the literal string "FP-STR-C" into the
	 * medal bitfield; its byte 4 is 'T' = 0x54, whose bit 6 is medal id 65 — "500 Mk.II
	 * destructions" — and the whole word lit 17 medals on every character alive. A player with no
	 * rounds must earn nothing.
	 */
	@Test
	public void aCharacterWithNoRoundsEarnsNoMedals() {
		givenSelectedCharacter("Snake");

		var field = medalField(statsBurst().get(0));

		assertThat(field).containsOnly((byte) 0);
		// The specific bit that produced the reported phantom, named so a regression is obvious.
		assertThat(field[4] & (1 << 6)).as("medal id 65, 500 Mk.II destructions").isZero();
	}

	/**
	 * Thresholds are the numbers the client PRINTS in each medal's description, so awarding at
	 * exactly those numbers is what makes the screen truthful. 500 total kills earns tier 1
	 * (id 30, byte 1 bit 4) and nothing above it.
	 */
	@Test
	public void totalKillsEarnsExactlyTheTiersItReaches() {
		givenSelectedCharacter("Snake");
		givenReport(0, "kills", "499");

		var justUnder = medalField(statsBurst().get(0));
		assertThat(justUnder[1] & (1 << 4)).as("499 kills is not 500").isZero();

		givenReport(0, "kills", "1");

		var atThreshold = medalField(statsBurst().get(0));
		assertThat(atThreshold[1] & (1 << 4)).as("id 30, 500 total kills").isNotZero();
		assertThat(atThreshold[1] & (1 << 5)).as("id 31 needs 2000").isZero();
		assertThat(atThreshold[1] & (1 << 6)).as("id 32 needs 10000").isZero();
	}

	/**
	 * Consecutive TDM survivals is the one max-family medal we can serve: slot 25 comes from b24,
	 * an absolute per-stage snapshot, so the career value is a max and needs no stage boundary.
	 */
	@Test
	public void consecutiveSurvivalsEarnsItsMedalFromAMaxNotASum() {
		givenSelectedCharacter("Snake");
		givenReport(1, "detail_counters", detail(25, 2));
		givenReport(1, "detail_counters", detail(25, 2));

		// Two rounds of 2 is still a best of 2 — the 4-tier must not light from a sum.
		var field = medalField(statsBurst().get(0));
		assertThat(field[3] & (1 << 0)).as("id 50, 2 consecutive survivals").isNotZero();
		assertThat(field[3] & (1 << 1)).as("id 51 needs 4, and 2+2 is not 4").isZero();
	}

	/**
	 * The families whose source is served as zero must stay dark, and say so — these are the
	 * medals that will start working the day stage boundaries are stored.
	 */
	@Test
	public void theStreakMedalsStayDarkWhileTheirSlotsAreZeroed() {
		givenSelectedCharacter("Snake");
		givenReport(0, "detail_counters", detail(1, 99, 2, 99, 3, 99));

		var field = medalField(statsBurst().get(0));

		assertThat(field[0]).as("consecutive kills, headshots and deaths all read zeroed slots")
			.isZero();
	}

	/** A bad id gets 0x4103 alone with a nonzero status; the client error-completes on it. */
	@Test
	public void unknownCharacterGetsAnErrorStatus() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(statsRequest(9999), PersonalStatsController.PERSONAL_STATS_INFO);

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(4);
		assertThat(replies.get(0).getPayload().getInt(0)).isNotEqualTo(0);
	}

	/**
	 * The outfit commit must read the gear catalogue back, not an empty table.
	 * <p>
	 * This replaces {@code outfitCommitGetsTheEmptyReadback}, which guarded the bug. [ELF] The
	 * {@code 0x4133} parser zeroes the whole {@code 0x60c}-byte loadout table before applying
	 * entries, and it addresses that table with the same {@code addi r9,r9,9888} ({@code +0x26a0})
	 * the {@code 0x4124} parser uses — {@code 0xD3C85C}/{@code 0xD3C90C} against
	 * {@code 0xD3CF10}/{@code 0xD3CFC0}. So a count of 0 does not mean "unchanged", it means
	 * "forget every item you own": the character logged in with the full catalogue and left the
	 * outfit screen with nothing unlocked.
	 */
	@Test
	public void outfitCommitReadsTheGearCatalogueBack() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(new GamePacket(PersonalInfoController.COMMIT_OUTFIT),
			PersonalInfoController.COMMIT_OUTFIT_RESULT);

		assertThat(replies).hasSize(1);
		var payload = replies.get(0).getPayload();

		// Byte-identical to what 0x4124 sends: 4 + 123x5 + 32 = 651. The trailing 32 bytes are
		// sixteen {u8 item_id, u8 bit_index} pairs, not a terminator, and the size only balances
		// at sixteen.
		// A new character owns the whole catalogue, so this is the known-good 651 bytes -- and
		// byte-identical to the 0x4124 the same character got at login, which is the property that
		// matters: the two writers fill one table and must agree.
		assertThat(payload.getInt(0)).isEqualTo(123);
		assertThat(payload.readableBytes()).isEqualTo(651);
	}
}
