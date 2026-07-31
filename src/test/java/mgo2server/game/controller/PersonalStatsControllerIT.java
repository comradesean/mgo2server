package mgo2server.game.controller;

import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.Level;
import mgo2server.common.service.StatsService;
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
					insert into account (username, password, session, slots)
					values ('player', 'x', :session, 3)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name, experience)"
					+ " values (:account, :name, 1234)")
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
					// The last row of matrix 0 is the player-details card's summary row, not a mode:
					// column 17 is its PLAY TIME and column 13 its LEVEL. Both are real values rather
					// than fabricated ones, so they are exempt from "played nothing produces
					// nothing" — a character with no rounds still has a level, and its play time is
					// legitimately zero. See cumulativeMatrixCarriesTheCardsPlayTimeAndLevel.
					if (page == 0 && mode == StatsService.MODE_ROWS - 1
						&& (column == 13 || column == 17)) {
						continue;
					}
					assertThat(cell(replies.get(1 + page), mode, column))
						.as("page %d mode %d column %d", page, mode, column)
						.isZero();
				}
			}
		}
		// And with no rounds at all the card's play time is genuinely zero.
		assertThat(cell(replies.get(1), StatsService.MODE_ROWS - 1, 17)).isZero();
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
	 * No <b>mode statistics</b> may be binned into rows 6 or 7. Row 6 has no page of its own but IS
	 * summed into every Total and the header time, so anything put there inflates totals with
	 * nothing on screen to explain it.
	 * <p>
	 * Narrowed 2026-07-29: row 7 is <b>not a hidden mode row</b> — the parser's eight wire blocks
	 * land in memory rows 0,1,2,3,4,5,7,11, so this one is row 11, the player-details card's summary
	 * row. Its columns 13 and 17 deliberately carry the card's LEVEL and PLAY TIME. The rule this
	 * test protects is unchanged: no per-mode figures there, and rule 6 and rule 7 reports stay out
	 * of the grid entirely.
	 */
	@Test
	public void theHiddenModeRowsCarryNoModeStatistics() {
		givenSelectedCharacter("Snake");
		givenReport(6, "kills, seconds_in_game", "9, 600");
		givenReport(7, "kills", "4");

		var matrix = statsBurst().get(1);

		for (var column = 0; column < 18; column++) {
			assertThat(cell(matrix, 6, column)).as("row 6 column %d", column).isZero();
			if (column == 13 || column == 17) {
				continue; // the card's LEVEL and PLAY TIME, asserted separately
			}
			assertThat(cell(matrix, 7, column)).as("row 7 column %d", column).isZero();
		}

		// The rule-6 and rule-7 reports above contributed 600 seconds, and none of it may appear:
		// the card's play time counts playable modes only.
		assertThat(cell(matrix, StatsService.MODE_ROWS - 1, 17))
			.as("rule 6/7 seconds must not reach the card's play time")
			.isZero();
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
						(chara_id, training_mode_seconds, instructor_seconds, student_seconds)
					values (:chara, 600, 300, 120)
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

	// --- Titles: the worn u8 at wire 541 and the 22-bit mask at wire 563 --------------------

	/** TORTOISE, "Often uses cardboard box" — the cheapest title in awards.json to earn. */
	private static final int TORTOISE_BIT = 19;

	/** CROCODILE, "High kill count" — rank 11, so it outranks TORTOISE's 33 on the name plate. */
	private static final int CROCODILE_BIT = 4;

	/** The worn title, u8 at wire 541. 1-based: bit 19 is served as 20, and 0 means none. */
	private static int wornTitle(GamePacket info) {
		return info.getPayload().getUnsignedByte(541);
	}

	/** The 22-bit unlock mask, u32 at wire 563 — rating-block entry 3. */
	private static int titleMask(GamePacket info) {
		return info.getPayload().getInt(563);
	}

	/**
	 * Runs the unlock pass. In the server it runs at round end and on lobby entry; these tests
	 * write {@code round_report} rows straight to the database and never send {@code CONNECT}, so
	 * nothing else is going to run it for them. Reading the stats screen deliberately does not,
	 * which is why it has to be said here.
	 */
	private void whenTitlesAreEvaluated() {
		services.getAwardService().evaluate(charaId);
	}

	/**
	 * Rounds that carry box uses in slot 22 (struct-B b21). The kills are not decoration: without
	 * them the fixture also clears CHICKEN ("Rarely participates in battle"), which would make the
	 * exact-mask assertions below untrue for a reason that has nothing to do with what they test.
	 */
	private void givenBoxRounds(int rounds, int boxUsesEach) {
		for (var i = 0; i < rounds; i++) {
			givenReport(0, "kills, detail_counters", "5, " + detail(22, boxUsesEach));
		}
	}

	/** The title counterpart of {@code aCharacterWithNoRoundsEarnsNoMedals}. */
	@Test
	public void aCharacterWithNoRoundsWearsNoTitle() {
		givenSelectedCharacter("Snake");

		// Every ratio clause is guarded by a rounds clause, so an empty character unlocks nothing.
		assertThat(services.getAwardService().evaluate(charaId)).isEmpty();

		var info = statsBurst().get(0);
		assertThat(titleMask(info)).as("wire 563, the 22-bit mask").isZero();
		assertThat(wornTitle(info)).as("wire 541, the worn title").isZero();
	}

	/**
	 * TORTOISE asks for {@code box_per_round >= 15} over at least 5 rounds, so five rounds of 80
	 * box uses is 400/5 = 80 and clears it by a wide margin. Nothing else in the file is cleared by
	 * this fixture, which is why the mask can be asserted exactly rather than bit by bit.
	 */
	@Test
	public void anEarnedTitleSetsExactlyItsOwnBit() {
		givenSelectedCharacter("Snake");
		givenBoxRounds(5, 80);

		whenTitlesAreEvaluated();

		var info = statsBurst().get(0);
		assertThat(titleMask(info)).isEqualTo(1 << TORTOISE_BIT);
		// 1-based on the wire: bit 19 is served as 20. Zero is "no title", not "title 0".
		assertThat(wornTitle(info)).isEqualTo(TORTOISE_BIT + 1);
	}

	/**
	 * The point of storing titles instead of deriving them, and the one property that must never
	 * regress. Medals are derived at query time because every medal source is a career sum or
	 * maximum and only grows. Title requirements are ratios, and a ratio falls — so a derived title
	 * would disappear the moment a player had a bad week. The unlock is a row, inserted once and
	 * never deleted.
	 */
	@Test
	public void anUnlockedTitleLatchesAfterItsRatioFallsBelowTheThreshold() {
		givenSelectedCharacter("Snake");
		givenBoxRounds(5, 80);
		whenTitlesAreEvaluated();

		assertThat(titleMask(statsBurst().get(0)) & (1 << TORTOISE_BIT))
			.as("earned at 80 box uses per round")
			.isNotZero();

		// 25 more rounds using the box not once. The requirement is genuinely no longer met, which
		// the two figures below assert directly rather than by assuming the arithmetic.
		givenBoxRounds(25, 0);
		whenTitlesAreEvaluated();

		var replies = statsBurst();
		assertThat(slot(replies.get(3), 0, 22)).as("career box uses").isEqualTo(400);
		assertThat(cell(replies.get(1), 0, 14)).as("rounds").isEqualTo(30);
		// 400 / 30 = 13.3, under the 15 the title asks for, and it is still worn.
		assertThat(titleMask(replies.get(0)) & (1 << TORTOISE_BIT)).isNotZero();
		assertThat(wornTitle(replies.get(0))).isEqualTo(TORTOISE_BIT + 1);
	}

	/**
	 * The player does not choose which title is worn — the client has no command for it — so the
	 * server picks the best unlocked one by the {@code rank} ordering in awards.json, lowest wins.
	 */
	@Test
	public void theWornTitleIsTheBestRankedOneUnlocked() {
		givenSelectedCharacter("Snake");
		// Five rounds that clear TORTOISE (box 80 per round) and CROCODILE (K+s/D+s of 50/5 = 10,
		// against the 1.50 it asks for) at once.
		for (var i = 0; i < 5; i++) {
			givenReport(0, "kills, deaths, detail_counters", "10, 1, " + detail(22, 80));
		}

		whenTitlesAreEvaluated();

		var info = statsBurst().get(0);
		assertThat(titleMask(info)).isEqualTo((1 << CROCODILE_BIT) | (1 << TORTOISE_BIT));
		// CROCODILE ranks 11 and TORTOISE 33, so CROCODILE is worn — and 1-based, so bit 4 is 5.
		assertThat(wornTitle(info)).isEqualTo(CROCODILE_BIT + 1);
	}

	/**
	 * A ratio over an empty denominator is ZERO, not infinity. A character with fifty kills and no
	 * deaths has not earned an unbeatable kill/death ratio, and the alternative reading is not a
	 * rounding difference: it would hand CROCODILE, EAGLE, JAWS and the FOXHOUND family to the
	 * first player to survive five rounds. Asserted as behaviour — no title — rather than by
	 * reaching for the divide.
	 */
	@Test
	public void aRatioWithNoDenominatorAwardsNothing() {
		givenSelectedCharacter("Snake");
		for (var i = 0; i < 5; i++) {
			givenReport(0, "kills", "10");
		}

		whenTitlesAreEvaluated();

		var info = statsBurst().get(0);
		assertThat(titleMask(info) & (1 << CROCODILE_BIT))
			.as("CROCODILE asks for K+s/D+s >= 1.50, and 50/0 is not a pass")
			.isZero();
		assertThat(titleMask(info)).isZero();
		assertThat(wornTitle(info)).isZero();
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

		// Byte-identical to what 0x4124 sends -- THE property that matters, because the two writers
		// fill one client table and whichever arrives last wins. 4 + 28x5 + 32 = 176 for the
		// the fixture's three items; it was 651 when creation granted the whole catalogue.
		//
		// The trailing 32 bytes are sixteen {u8 item_id, u8 bit_index} pairs, not a terminator.
		assertThat(payload.getInt(0)).isEqualTo(3);
		assertThat(payload.readableBytes()).isEqualTo(51);
	}
	/**
	 * The last row of matrix 0 carries the player-details card's PLAY TIME and LEVEL.
	 * <p>
	 * That row is <b>not a mode</b>. The parser computes
	 * {@code base = T + 312 + index*864 + row*72 + col*4} and skips memory rows 6, 8, 9 and 10, so
	 * the eight wire blocks land in memory rows 0,1,2,3,4,5,7,11 — the eighth being row 11. The
	 * card's PLAY TIME cell {@code T+0x494} is exactly {@code 312 + 11*72 + 17*4}, the final u32 of
	 * this payload; its LEVEL is column 13 of the same row.
	 * <p>
	 * Before this, More Details blanked the card: matrix index 0 memsets {@code T+0x138} for 3456
	 * bytes, which spans that cell, and {@code 0x4103} cannot restore it — that parser's
	 * destinations stop below the range and resume above it. The renderer clamps to 9999:59:59, so
	 * zero was the only value that could produce {@code 00:00:00}.
	 */
	@Test
	public void cumulativeMatrixCarriesTheCardsPlayTimeAndLevel() {
		givenSelectedCharacter("Snake");
		givenReport(0, "seconds_in_game", "600");
		givenReport(1, "seconds_in_game", "900");

		var replies = statsBurst();
		var cumulative = replies.get(1);
		assertThat(cumulative.getPayload().getInt(4)).as("matrix index 0 is sent first").isZero();

		var summaryRow = StatsService.MODE_ROWS - 1;
		assertThat(cell(cumulative, summaryRow, 17))
			.as("row 11 col 17 = T+0x494, the card's PLAY TIME, and the final u32 of the payload")
			.isEqualTo(1500);
		assertThat(cumulative.getPayload().getInt(580))
			.as("same cell addressed by absolute offset, pinning the geometry")
			.isEqualTo(1500);

		assertThat(cell(cumulative, summaryRow, 13))
			.as("row 11 col 13 = T+0x484, the card's LEVEL")
			.isEqualTo(Level.of(services.getCharacterService().experienceOf(charaId)));
	}

	/** The weekly matrix is left alone: the card reads matrix 0, and nothing reads matrix 1's row 11. */
	@Test
	public void weeklyMatrixSummaryRowIsNotFilled() {
		givenSelectedCharacter("Snake");
		givenReport(0, "seconds_in_game", "600");

		var weekly = statsBurst().get(2);

		assertThat(weekly.getPayload().getInt(4)).isEqualTo(1);
		assertThat(cell(weekly, StatsService.MODE_ROWS - 1, 17)).isZero();
	}

}
