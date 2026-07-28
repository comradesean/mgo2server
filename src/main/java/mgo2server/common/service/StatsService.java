package mgo2server.common.service;

import org.jdbi.v3.core.Jdbi;

/**
 * The two aggregate surfaces of the personal-stats screen: the {@code 0x4105} per-mode matrix and
 * the {@code 0x4107} personal-score records.
 * <p>
 * Everything derives from {@code round_report} at query time — one immutable row per player per
 * round — in the same spirit as {@link RankingService} and the met-players history. There is no
 * accumulator table and there should not be one: the storage principle is pinned in BACKLOG
 * ("Match/encounter history"), and a {@code chara_stats} accumulator was built and dropped as
 * write-only before this existed.
 *
 * <h2>Honest zeros</h2>
 * Anything we cannot derive honestly is served as <b>zero</b>, which is inert, rather than as a
 * plausible guess. The fingerprint values this screen used to carry ({@code 1000 + slot}) are gone.
 * <p>
 * <b>Note what this is NOT about.</b> Medals and titles were long believed to be minted
 * client-side from these very values, which made a wrong stat award an unearned medal. That was
 * wrong (corrected 2026-07-28): both are gated by bitfields the server sends in {@code 0x4103} —
 * wire 615 for medals, wire 563 for titles — and nothing on this screen influences them. Honest
 * zeros here are still right, for the ordinary reason that a made-up statistic is a lie; they are
 * just not load-bearing for awards. See GATES.md §5a.
 *
 * <h2>Where a naive sum would be wrong</h2>
 * Three of these are subtle enough to have caused real errors already:
 * <ul>
 *   <li><b>Slots 1, 2, 3 are not sums and are not served.</b> They come from struct-B b00/b01/b02,
 *       which are <em>deltas of a per-stage record</em> (store-if-greater, zeroed on stage
 *       rotation). Summing them inflates without bound — two separate 5-kill streaks in different
 *       stages sum to 10 when the career best is 5. Reconstructing the record needs stage
 *       boundaries, and {@code round_report} does not store them. Zero until it does.</li>
 *   <li><b>Slot 25 is a {@code max}, and that is exact.</b> b24 is the one struct-B slot that is
 *       not a delta at all — the client stores an absolute per-stage snapshot straight through
 *       (ELF, {@code 0x27DA5C}). So the career value is the largest snapshot ever reported.</li>
 *   <li><b>Slot 5 is struct A, not struct B.</b> Times Stunned is {@code counter_0x0f}
 *       (knockouts received); struct-B b04 is self-stuns only, and the two agree only in rounds
 *       where every stun was self-inflicted.</li>
 * </ul>
 *
 * <h2>Known imprecision, deliberately not corrected</h2>
 * {@code sum(score)} telescopes correctly across a game because each report is a delta of the same
 * store — <em>except</em> where that store clamped at 0, which permanently loses the clamped
 * points. {@link RankingService} already sums it the same way. Inventing a correction would mean
 * modelling a clamp we cannot observe.
 */
public class StatsService {

	/** Mode rows in the {@code 0x4105} grid; the wire always carries 8. */
	public static final int MODE_ROWS = 8;

	/** Stat columns per mode row. */
	public static final int STAT_COLUMNS = 18;

	/** Slots per {@code 0x4107} record, 1-based on the wire. */
	public static final int SCORE_SLOTS = 73;

	/** Struct B is 58 s16 counters; slot {@code n} of 0x4107 maps to B index {@code n - 1}. */
	private static final int STRUCT_B_SLOTS = 58;

	/**
	 * Monday 00:00 UTC. {@code date_trunc('week', …)} is ISO and therefore Monday-based, and UTC is
	 * pinned in the expression rather than inherited from the database session — which is what makes
	 * the boundary actually UTC rather than however the server happens to be configured.
	 */
	private static final String WEEK_START =
		"date_trunc('week', current_timestamp at time zone 'UTC') at time zone 'UTC'";

	/**
	 * The two periods the screen toggles between. {@code 0x4105} carries this as its page selector
	 * and {@code 0x4107} as its record index; both must be sent, cumulative first.
	 * <p>
	 * <b>Weekly is a calendar week starting Monday 00:00 UTC</b> — {@code date_trunc('week', …)},
	 * which is ISO and therefore Monday-based. The reset cadence is <em>operator policy</em>, not
	 * protocol: the client renders whatever it is handed and the docs record the cadence as
	 * undecided in three places. Monday was chosen for symmetry with the ranking board's
	 * {@code date_trunc('month', …)}, so both period concepts use calendar boundaries and the same
	 * index serves both.
	 */
	public enum Period {
		CUMULATIVE(""),
		WEEKLY("and r.reported_at >= " + WEEK_START);

		private final String window;

		Period(String window) {
			this.window = window;
		}

		String window() {
			return window;
		}
	}

	/**
	 * One mode row's aggregate. Columns 0/1/4/5 are <b>minuends</b>: the client renders
	 * {@code OTHER = column − headshots − lockon}, clamped at 0, and never shows the column
	 * itself. Sending the plain total is therefore correct and needs no arithmetic — OTHER comes
	 * out as "the ones that were neither a headshot nor a lock-on".
	 */
	private record ModeRow(int rule, long kills, long deaths, long lockonKills, long score,
			long stuns, long stunsReceived, long headshots, long headshotDeaths,
			long hsStuns, long hsStunsReceived, long lockonStuns, long lockonDeaths,
			long lockonStunsReceived, long rounds, long wins, long seconds) {
	}

	private static final String MODE_GRID = """
			select r.rule as rule,
				coalesce(sum(r.kills), 0) as kills,
				coalesce(sum(r.deaths), 0) as deaths,
				coalesce(sum(r.lockon_kills), 0) as lockon_kills,
				coalesce(sum(r.score), 0) as score,
				coalesce(sum(r.stuns), 0) as stuns,
				coalesce(sum(r.counter_0x0f), 0) as stuns_received,
				coalesce(sum(r.headshots), 0) as headshots,
				coalesce(sum(r.headshot_deaths), 0) as headshot_deaths,
				coalesce(sum(r.counter_0x15), 0) as hs_stuns,
				coalesce(sum(r.counter_0x17), 0) as hs_stuns_received,
				coalesce(sum(r.lockon_stuns_dealt), 0) as lockon_stuns,
				coalesce(sum(r.lockon_deaths), 0) as lockon_deaths,
				coalesce(sum(r.lockon_stuns_received), 0) as lockon_stuns_received,
				count(*) as rounds,
				coalesce(sum(r.team_win), 0) as wins,
				coalesce(sum(r.seconds_in_game), 0) as seconds
			from round_report r
			where r.chara_id = :chara and r.rule between 0 and :lastMode %s
			group by r.rule
			""";

	/**
	 * Struct-B totals, one row per slot. {@code unnest … with ordinality} is far clearer than 58
	 * array subscripts and lets the slot number fall out as the ordinality — B index {@code n − 1}
	 * is 0x4107 slot {@code n}, and Postgres arrays are 1-based, so {@code idx} <em>is</em> the
	 * slot number.
	 */
	private static final String STRUCT_B_TOTALS = """
			select s.idx as idx, coalesce(sum(s.val), 0) as total
			from round_report r,
				lateral unnest(r.detail_counters) with ordinality as s(val, idx)
			where r.chara_id = :chara %s
			group by s.idx
			""";

	/**
	 * The struct-A and max-family values the slot table needs, in one pass.
	 * <p>
	 * {@code times_stunned} is struct A, not struct B (see the class note). {@code best_survivals}
	 * is a {@code max} because b24 is an absolute snapshot — summing it would be meaningless.
	 */
	private static final String SCORE_EXTRAS = """
			select coalesce(sum(r.counter_0x0f), 0) as times_stunned,
				coalesce(max(r.detail_counters[25]), 0) as best_survivals
			from round_report r
			where r.chara_id = :chara %s
			""";

	/**
	 * The Sneaking trio (slots 63 Victories as Snake, 67 Snake Kills, 72 Time as Snake). These sit
	 * beyond struct B's 58 slots so they cannot be B-fed directly; they are derived from the
	 * reports in which this character <em>was</em> the Snake.
	 * <p>
	 * The role test is <b>b56 {@code rounds_as_snake}</b> ({@code detail_counters[57]}), not
	 * {@code flag_0x04}. The flag is recomputed live at send time and reads 0 on a teardown report
	 * even for the Snake; b56 is an accumulated counter and survives. Over completed rounds the two
	 * agree exactly, and only b56 is right when they do not.
	 */
	private static final String SNAKE_TOTALS = """
			select coalesce(sum(r.detail_counters[50]), 0) as victories,
				coalesce(sum(r.kills), 0) as kills,
				coalesce(sum(r.seconds_in_game), 0) as seconds
			from round_report r
			where r.chara_id = :chara and r.detail_counters[57] != 0 %s
			""";

	/**
	 * Students this character has graduated, for slot 36.
	 * <p>
	 * Counted from {@code instructor_review}, which is append-only and timestamped, NOT from
	 * {@code chara_instructor}: that table holds one current-state row per student, so a student
	 * re-graduating under someone else would make this number go DOWN — and a career counter that
	 * decreases is wrong in a way a medal threshold would expose. This is the only slot outside
	 * {@code round_report} that can honestly answer the weekly period.
	 */
	private static final String SOLDIERS_TRAINED = """
			select count(distinct v.student_chara_id)
			from instructor_review v
			where v.instructor_chara_id = :chara and v.recognised %s
			""";

	/** Knife kills, and any future weapon line, come from the 0x43a2 tallies. */
	private static final String WEAPON_KILLS = """
			select coalesce(sum(t.kills), 0)
			from round_weapon_tally t
			where t.chara_id = :chara and t.weapon_id = :weapon %s
			""";

	// --- 0x4107 slot numbers (1-based on the wire, mgo2_cmd_4107.ksy) ------------------------

	private static final int SLOT_CONSECUTIVE_KILLS = 1;

	private static final int SLOT_CONSECUTIVE_DEATHS = 2;

	private static final int SLOT_CONSECUTIVE_HEADSHOTS = 3;

	private static final int SLOT_TIMES_STUNNED = 5;

	/** No wire source: the client never reports dedicated-host time. Permanently zero. */
	private static final int SLOT_DEDICATED_HOST_SECONDS = 15;

	private static final int SLOT_CONSECUTIVE_SURVIVALS_TDM = 25;

	/** Server-side accounting; nothing tracks students instructed yet. */
	private static final int SLOT_SOLDIERS_TRAINED = 36;

	private static final int SLOT_TRAINING_SECONDS = 46;

	private static final int SLOT_INSTRUCTOR_SECONDS = 47;

	private static final int SLOT_STUDENT_SECONDS = 48;

	private static final int SLOT_SNAKE_VICTORIES = 63;

	private static final int SLOT_KNIFE_KILLS = 64;

	private static final int SLOT_SNAKE_KILLS = 67;

	private static final int SLOT_SNAKE_SECONDS = 72;

	/** ST KNIFE, weapon id 1 in the ELF's master table (dev/docs/WEAPONS.md). */
	private static final int WEAPON_ID_KNIFE = 1;

	private final Jdbi jdbi;

	private final CharacterService characterService;

	public StatsService(Jdbi jdbi, CharacterService characterService) {
		this.jdbi = jdbi;
		this.characterService = characterService;
	}

	/**
	 * One medal tier: the id the client tests, where its bit lives in the 16-byte field, the count
	 * that earns it, and which statistic supplies that count.
	 */
	private record Medal(int id, int byteIndex, int bit, long threshold, Source source) {
	}

	/** Where a medal's count comes from. */
	private enum Source {
		/** A 1-based {@code 0x4107} slot. */
		SLOT,
		/** Career kills, summed over every mode. */
		TOTAL_KILLS,
		/** Career deaths, summed over every mode. */
		TOTAL_DEATHS,
	}

	/**
	 * The medal table: 12 families of 3 tiers, from {@code 0xE139C0}.
	 * <p>
	 * <b>The threshold is the number the client PRINTS in the medal's own description</b>, not a
	 * condition it checks — it loads that word after the gate and sprintf's it in as a {@code %d}.
	 * Awarding at exactly that number is therefore the one choice that makes the screen tell the
	 * truth: a medal captioned "500 Mk.II destructions" is granted at 500 Mk.II destructions. Any
	 * other threshold would leave the client stating a requirement we did not apply. That reasoning
	 * is the whole justification, because the original server's rule is unobservable — see
	 * AWARDS.md, where this is recorded as operator policy.
	 * <p>
	 * The 13th family in the table, ids 80/81/82 "%d targets captured", is deliberately absent:
	 * the client's accessor ({@code 0xD5C2A8}) has no arm for those ids, so no bit can ever draw
	 * them. It also has arms for ids that {@code 0xE139C0} never mentions (93, 110, 120-162), which
	 * this screen never queries.
	 * <p>
	 * {@code byteIndex}/{@code bit} are into the 16 bytes at {@code 0x4103} wire 615. Bits 3 and 7
	 * of every byte are unused, as are bytes 13-15.
	 */
	private static final Medal[] MEDALS = {
		// %d consecutive kills — 0x4107 slot 1, served as 0 until stage boundaries exist.
		new Medal(1, 0, 0, 5, Source.SLOT), new Medal(2, 0, 1, 10, Source.SLOT),
		new Medal(3, 0, 2, 25, Source.SLOT),
		// %d consecutive headshots — slot 3, likewise 0 for now.
		new Medal(10, 0, 4, 3, Source.SLOT), new Medal(11, 0, 5, 10, Source.SLOT),
		new Medal(12, 0, 6, 30, Source.SLOT),
		// %d consecutive deaths — slot 2, likewise 0 for now.
		new Medal(20, 1, 0, 5, Source.SLOT), new Medal(21, 1, 1, 10, Source.SLOT),
		new Medal(22, 1, 2, 25, Source.SLOT),
		// %d total kills
		new Medal(30, 1, 4, 500, Source.TOTAL_KILLS),
		new Medal(31, 1, 5, 2000, Source.TOTAL_KILLS),
		new Medal(32, 1, 6, 10000, Source.TOTAL_KILLS),
		// %d total deaths
		new Medal(40, 2, 0, 500, Source.TOTAL_DEATHS),
		new Medal(41, 2, 1, 2000, Source.TOTAL_DEATHS),
		new Medal(42, 2, 2, 10000, Source.TOTAL_DEATHS),
		// %d consecutive survivals in TDM — slot 25, a max over b24 snapshots, so exact.
		new Medal(50, 3, 0, 2, Source.SLOT), new Medal(51, 3, 1, 4, Source.SLOT),
		new Medal(52, 3, 2, 6, Source.SLOT),
		// %d times spotted Snake first — slot 56.
		new Medal(60, 4, 0, 50, Source.SLOT), new Medal(61, 4, 1, 100, Source.SLOT),
		new Medal(62, 4, 2, 500, Source.SLOT),
		// %d Mk.II destructions — slot 53. Needs 12+ players in Sneaking (GATES.md).
		new Medal(63, 4, 4, 50, Source.SLOT), new Medal(64, 4, 5, 100, Source.SLOT),
		new Medal(65, 4, 6, 500, Source.SLOT),
		// %d hold ups performed as Snake — slot 51.
		new Medal(66, 9, 0, 50, Source.SLOT), new Medal(67, 9, 1, 100, Source.SLOT),
		new Medal(68, 9, 2, 500, Source.SLOT),
		// %d SOP destabilizer uses — slot 27.
		new Medal(70, 5, 0, 50, Source.SLOT), new Medal(71, 5, 1, 100, Source.SLOT),
		new Medal(72, 5, 2, 200, Source.SLOT),
		// %d matches without a scratch — slot 31.
		new Medal(90, 7, 0, 50, Source.SLOT), new Medal(91, 7, 1, 100, Source.SLOT),
		new Medal(92, 7, 2, 500, Source.SLOT),
		// %d people finished training — slot 36.
		new Medal(100, 8, 0, 10, Source.SLOT), new Medal(101, 8, 1, 100, Source.SLOT),
		new Medal(102, 8, 2, 300, Source.SLOT),
	};

	/** The 0x4107 slot each SLOT-sourced medal family reads, keyed by the family's lowest id. */
	private static final java.util.Map<Integer, Integer> MEDAL_SLOTS = java.util.Map.of(
		1, 1,      // consecutive kills
		10, 3,     // consecutive headshots
		20, 2,     // consecutive deaths
		50, 25,    // consecutive survivals in TDM
		60, 56,    // times spotted Snake first
		63, 53,    // Mk.II destructions
		66, 51,    // hold ups performed as Snake
		70, 27,    // SOP destabilizer uses
		90, 31,    // matches without a scratch
		100, 36);  // people finished training

	/** The medal bitfield for {@code 0x4103} wire 615: 16 bytes, medal-id-keyed. */
	public static final int MEDAL_FIELD_BYTES = 16;

	/**
	 * Which medals a character has earned, as the 16-byte field the client gates on.
	 * <p>
	 * Derived from career statistics at query time, with no stored award state — every source is a
	 * career sum or a career maximum, so it only ever grows and a medal cannot un-earn itself. That
	 * is what "medals latch" means here, and it needs no table to express.
	 * <p>
	 * Several families can never light on this build, for reasons documented rather than
	 * mysterious: the three consecutive-* families read slots 1-3, which are served as zero until
	 * stage boundaries are stored; Mk.II destructions need a 12-player Sneaking round. They are
	 * still in the table so that they start working the day their source does.
	 */
	public byte[] medalBits(long charaId) {
		var slots = personalScores(charaId, Period.CUMULATIVE);
		var grid = modeGrid(charaId, Period.CUMULATIVE);
		var totalKills = 0L;
		var totalDeaths = 0L;
		for (var mode = 0; mode < MODE_ROWS; mode++) {
			totalKills += grid[mode][0];
			totalDeaths += grid[mode][1];
		}

		var field = new byte[MEDAL_FIELD_BYTES];
		for (var medal : MEDALS) {
			var earned = switch (medal.source()) {
				case TOTAL_KILLS -> totalKills;
				case TOTAL_DEATHS -> totalDeaths;
				case SLOT -> slots[MEDAL_SLOTS.get(familyOf(medal.id()))];
			};
			if (earned >= medal.threshold()) {
				field[medal.byteIndex()] |= (byte) (1 << medal.bit());
			}
		}
		return field;
	}

	/** A family is keyed by its lowest id: 1/2/3 -> 1, 63/64/65 -> 63, 100/101/102 -> 100. */
	private static int familyOf(int medalId) {
		return MEDAL_SLOTS.containsKey(medalId) ? medalId : familyOf(medalId - 1);
	}

	/**
	 * The {@code 0x4105} grid for one character and period: 8 mode rows of 18 u32 columns.
	 * <p>
	 * <b>Rows 6 and 7 are always zero.</b> Row 6 has no page of its own but IS summed into every
	 * Total and into the header play time, so anything placed there inflates totals with nothing
	 * on screen to explain it; row 7 is excluded from all sums. Rules 6+ are out of scope for the
	 * release-day target anyway (CLAUDE.md, "Target version"), so a report carrying one is dropped
	 * rather than folded into a visible row.
	 */
	public long[][] modeGrid(long charaId, Period period) {
		var grid = new long[MODE_ROWS][STAT_COLUMNS];
		var rows = jdbi.withHandle(handle -> handle
			.createQuery(MODE_GRID.formatted(period.window()))
			.bind("chara", charaId)
			.bind("lastMode", CharacterService.PLAYABLE_MODES - 1)
			.map((rs, ctx) -> new ModeRow(
				rs.getInt("rule"), rs.getLong("kills"), rs.getLong("deaths"),
				rs.getLong("lockon_kills"), rs.getLong("score"), rs.getLong("stuns"),
				rs.getLong("stuns_received"), rs.getLong("headshots"),
				rs.getLong("headshot_deaths"), rs.getLong("hs_stuns"),
				rs.getLong("hs_stuns_received"), rs.getLong("lockon_stuns"),
				rs.getLong("lockon_deaths"), rs.getLong("lockon_stuns_received"),
				rs.getLong("rounds"), rs.getLong("wins"), rs.getLong("seconds")))
			.list());

		for (var row : rows) {
			// Rules 6+ have no visible row. Dropping them keeps the Total honest, because the
			// client sums rows 0..6 and row 6 is invisible.
			if (row.rule() < 0 || row.rule() > CharacterService.PLAYABLE_MODES - 1) {
				continue;
			}
			var cells = grid[row.rule()];
			cells[0] = row.kills();               // minuend: OTHER = this − hs − lockon
			cells[1] = row.deaths();              // minuend
			cells[2] = row.lockonKills();
			cells[3] = row.score();               // signed on the wire
			cells[4] = row.stuns();               // minuend
			cells[5] = row.stunsReceived();       // minuend
			cells[6] = row.headshots();
			cells[7] = row.headshotDeaths();
			cells[8] = row.hsStuns();
			cells[9] = row.hsStunsReceived();
			cells[10] = row.lockonStuns();
			cells[11] = row.lockonDeaths();
			cells[12] = row.lockonStunsReceived();
			// 13 and 15 render nowhere on any page and have never been identified; zero.
			cells[14] = row.rounds();
			cells[16] = row.wins();
			cells[17] = row.seconds();
		}
		return grid;
	}

	/**
	 * The {@code 0x4107} personal-score record for one character and period, 1-based: index 0 of
	 * the returned array is unused so slot numbers read directly.
	 * <p>
	 * Most slots are a plain sum of the matching struct-B delta. The exceptions are the ones the
	 * class note lists, plus the slots whose source is not a round report at all — training times
	 * come from presence accumulation, and Knife Kills from the weapon tallies.
	 */
	public long[] personalScores(long charaId, Period period) {
		var slots = new long[SCORE_SLOTS + 1];
		var window = period.window();

		jdbi.useHandle(handle -> {
			handle.createQuery(STRUCT_B_TOTALS.formatted(window))
				.bind("chara", charaId)
				.map((rs, ctx) -> new long[] { rs.getInt("idx"), rs.getLong("total") })
				.list()
				.forEach(pair -> {
					var slot = (int) pair[0];
					if (slot >= 1 && slot <= STRUCT_B_SLOTS) {
						slots[slot] = pair[1];
					}
				});

			handle.createQuery(SCORE_EXTRAS.formatted(window))
				.bind("chara", charaId)
				.map((rs, ctx) -> new long[] {
					rs.getLong("times_stunned"), rs.getLong("best_survivals"),
				})
				.findOne()
				.ifPresent(extras -> {
					slots[SLOT_TIMES_STUNNED] = extras[0];
					slots[SLOT_CONSECUTIVE_SURVIVALS_TDM] = extras[1];
				});

			handle.createQuery(SNAKE_TOTALS.formatted(window))
				.bind("chara", charaId)
				.map((rs, ctx) -> new long[] {
					rs.getLong("victories"), rs.getLong("kills"), rs.getLong("seconds"),
				})
				.findOne()
				.ifPresent(snake -> {
					slots[SLOT_SNAKE_VICTORIES] = snake[0];
					slots[SLOT_SNAKE_KILLS] = snake[1];
					slots[SLOT_SNAKE_SECONDS] = snake[2];
				});

			slots[SLOT_KNIFE_KILLS] = handle
				.createQuery(WEAPON_KILLS.formatted(windowOn(period, "t.reported_at")))
				.bind("chara", charaId)
				.bind("weapon", WEAPON_ID_KNIFE)
				.mapTo(Long.class)
				.one();

			slots[SLOT_SOLDIERS_TRAINED] = handle
				.createQuery(SOLDIERS_TRAINED.formatted(windowOn(period, "v.reviewed_at")))
				.bind("chara", charaId)
				.mapTo(Long.class)
				.one();
		});

		// The max-family: deltas of a per-stage record, unusable without stage boundaries.
		slots[SLOT_CONSECUTIVE_KILLS] = 0;
		slots[SLOT_CONSECUTIVE_DEATHS] = 0;
		slots[SLOT_CONSECUTIVE_HEADSHOTS] = 0;

		// Proven to have no wire source at all — the client never reports it.
		slots[SLOT_DEDICATED_HOST_SECONDS] = 0;



		// Training times are presence-accumulated, not round-reported: the host only reports when
		// a player leaves early, so a host who quits first reports nobody and a whole session is
		// lost. These are per-character totals with no period model of their own, so both records
		// carry the same value.
		// ...and they have NO period dimension, so the weekly record must carry zero rather than
		// repeat the lifetime figure. chara_training_time is a running total with no per-session
		// history; "you trained six hours this week" would be an invention of exactly the kind
		// this class exists to remove. Windowing it properly needs per-session presence rows.
		if (period == Period.CUMULATIVE) {
			var training = characterService.trainingSeconds(charaId);
			slots[SLOT_TRAINING_SECONDS] = training.trainingMode();
			slots[SLOT_INSTRUCTOR_SECONDS] = training.instructor();
			slots[SLOT_STUDENT_SECONDS] = training.student();
		}

		return slots;
	}

	/**
	 * The same week boundary against a different table's timestamp column.
	 * <p>
	 * UTC is pinned in the expression rather than inherited from the database session, which is
	 * what makes "Monday 00:00 UTC" true rather than dependent on however the server happens to be
	 * configured. (The ranking board's month predicate has the same latent dependency and is
	 * deliberately left alone here — changing it would move a shipped boundary.)
	 */
	private static String windowOn(Period period, String column) {
		return period == Period.WEEKLY ? "and " + column + " >= " + WEEK_START : "";
	}

}
