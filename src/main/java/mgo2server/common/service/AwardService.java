package mgo2server.common.service;

import mgo2server.common.AwardMetric;
import mgo2server.common.AwardsConfig;
import org.jdbi.v3.core.Jdbi;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Unlocking titles, and serving the two title fields of {@code 0x4103}.
 *
 * <h2>Why titles are stored and medals are not</h2>
 * {@link StatsService#medalBits} derives the whole medal field at query time, because every medal
 * source is a career sum or maximum — it only grows, so a medal cannot un-earn itself.
 * <p>
 * Title requirements are <b>ratios</b>, and a ratio falls. A derived title would vanish the moment a
 * player had a bad week. Since titles latch, the unlock is a row in {@code chara_title}, inserted
 * once and never deleted — the database does the latching, so no code has to remember to.
 *
 * <h2>Which title is worn</h2>
 * The player does not choose. The client has no command for it — all 24 {@code 0x41xx} ids are
 * accounted for — and the requirements source says the highest rank you qualify for "is still listed
 * as your main as per the old override rule". So the worn title is simply the best one unlocked, by
 * the {@code rank} ordering in {@code awards.json}, and the server computes it exactly as it
 * computes the clan emblem flag.
 */
public class AwardService {

	/** Mode name in {@code awards.json} to the {@code rule} byte on a round report. */
	private static final Map<String, Integer> MODES = Map.of(
		"DM", 0, "TDM", 1, "RES", 2, "CAP", 3, "SNE", 4, "BASE", 5, "TSNE", 7);

	// 0x4105 grid columns, from mgo2_cmd_4105.ksy.
	private static final int KILLS = 0;

	private static final int DEATHS = 1;

	private static final int STUNS = 4;

	private static final int STUNS_RECEIVED = 5;

	private static final int HEADSHOT_KILLS = 6;

	private static final int HEADSHOT_DEATHS = 7;

	private static final int HEADSHOT_STUNS = 8;

	private static final int ROUNDS = 14;

	private static final int WINS = 16;

	private static final int SECONDS = 17;

	// 0x4107 slots (slot n is struct-B index n-1).
	private static final int SLOT_CQC_GIVEN = 11;

	private static final int SLOT_ROLLS = 13;

	private static final int SLOT_ENVG_SECONDS = 14;

	private static final int SLOT_TRAPS = 19;

	private static final int SLOT_SCANS = 20;

	private static final int SLOT_BOX_USES = 22;

	private static final int SLOT_BASES_CONQUERED = 26;

	private static final int WEAPON_ID_KNIFE = 1;

	private final Jdbi jdbi;

	private final StatsService statsService;

	public AwardService(Jdbi jdbi, StatsService statsService) {
		this.jdbi = jdbi;
		this.statsService = statsService;
	}

	/**
	 * Unlocks every title this character now qualifies for. Idempotent, and safe to call after every
	 * round: already-unlocked titles conflict and are ignored.
	 *
	 * @return the bits newly unlocked by this call, for logging — empty on the overwhelmingly
	 *     common no-change path
	 */
	public Set<Integer> evaluate(long charaId) {
		var metrics = metricsFor(charaId);
		var unlocked = new LinkedHashSet<Integer>();

		for (var title : AwardsConfig.current().titles()) {
			var qualifies = true;
			for (var clause : title.requires()) {
				if (!clause.test(metrics.value(clause.metric(), clause.modes()))) {
					qualifies = false;
					break;
				}
			}
			if (qualifies && unlock(charaId, title.bit())) {
				unlocked.add(title.bit());
			}
		}
		return unlocked;
	}

	/**
	 * The 22-bit mask for {@code 0x4103} wire 563.
	 * <p>
	 * The shift is written {@code 2 ^ title_bit} rather than the natural {@code 1 << title_bit}
	 * because Jdbi renders statements through StringTemplate, which reads a less-than sign as the
	 * start of an expression and fails to compile the statement — at runtime, not at build time,
	 * so it surfaces as every request to this screen timing out. {@code ^} is exponentiation in
	 * Postgres, not xor, so this is the same value. The same trap is documented in
	 * {@code CharacterService.create} and in V20's migration.
	 */
	public int titleMask(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("select coalesce(sum((2 ^ title_bit)::bigint), 0) from chara_title "
				+ "where chara_id = :chara")
			.bind("chara", charaId)
			.mapTo(Integer.class)
			.one());
	}

	/**
	 * The title worn on the name plate, for {@code 0x4103} wire 541 — <b>1-based</b>, 0 for none.
	 * The best unlocked title by {@code rank}, lowest wins.
	 */
	public int wornTitle(long charaId) {
		var mask = titleMask(charaId);
		return AwardsConfig.current().titles().stream()
			.filter(title -> (mask & (1 << title.bit())) != 0)
			.min(java.util.Comparator.comparingInt(AwardsConfig.Title::rank))
			.map(title -> title.bit() + 1)
			.orElse(0);
	}

	/**
	 * Records that this character has been seen, and re-evaluates first.
	 * <p>
	 * The order matters and is the whole reason this is one method rather than two calls at the call
	 * site. TSUCHINOKO's requirement is an <i>absence</i> of play, measured from the previous stamp —
	 * so the gap has to be tested while the previous stamp is still there. Stamping first would
	 * reduce every gap to zero and make the title unreachable, which is exactly the kind of bug that
	 * looks like a threshold being too strict.
	 *
	 * @return the bits newly unlocked, for logging
	 */
	public Set<Integer> seen(long charaId) {
		var unlocked = evaluate(charaId);
		jdbi.useHandle(handle -> handle
			.createUpdate("update chara set last_seen_at = now() where id = :chara")
			.bind("chara", charaId)
			.execute());
		return unlocked;
	}

	private boolean unlock(long charaId, int bit) {
		return jdbi.withHandle(handle -> handle
			.createUpdate("insert into chara_title (chara_id, title_bit) values (:chara, :bit) "
				+ "on conflict (chara_id, title_bit) do nothing")
			.bind("chara", charaId)
			.bind("bit", bit)
			.execute() > 0);
	}

	private Metrics metricsFor(long charaId) {
		var lifetime = statsService.modeGrid(charaId, StatsService.Period.CUMULATIVE);
		var weekly = statsService.modeGrid(charaId, StatsService.Period.WEEKLY);
		var slots = statsService.personalScores(charaId, StatsService.Period.CUMULATIVE);

		var knifeKills = jdbi.withHandle(handle -> handle
			.createQuery("select coalesce(sum(kills), 0) from round_weapon_tally "
				+ "where chara_id = :chara and weapon_id = :weapon")
			.bind("chara", charaId)
			.bind("weapon", WEAPON_ID_KNIFE)
			.mapTo(Long.class)
			.one());

		// counter_0x1f is round_completed. Nothing had read this column since V16.
		var completionRate = jdbi.withHandle(handle -> handle
			.createQuery("select coalesce(avg(counter_0x1f), 1) from round_report "
				+ "where chara_id = :chara")
			.bind("chara", charaId)
			.mapTo(Double.class)
			.one());

		var lastSeen = jdbi.withHandle(handle -> handle
			.createQuery("select last_seen_at from chara where id = :chara")
			.bind("chara", charaId)
			.mapTo(OffsetDateTime.class)
			.findOne());

		return new Metrics(lifetime, weekly, slots, knifeKills, completionRate, lastSeen);
	}

	/**
	 * A character's statistics, resolved once so a title with five clauses costs one pass rather
	 * than five queries.
	 */
	private record Metrics(long[][] lifetime, long[][] weekly, long[] slots, long knifeKills,
			double completionRate, Optional<OffsetDateTime> lastSeen) {

		double value(AwardMetric metric, Set<String> modes) {
			var rows = rowsFor(modes);
			return switch (metric) {
				case KD_RATIO -> ratio(sum(rows, KILLS) + sum(rows, STUNS),
					sum(rows, DEATHS) + sum(rows, STUNS_RECEIVED));
				case SIMPLE_KD -> ratio(sum(rows, KILLS), sum(rows, DEATHS));
				case WIN_RATE -> ratio(sum(rows, WINS), sum(rows, ROUNDS));
				case ROUNDS -> sum(rows, ROUNDS);
				case WITHDRAWAL_RATE -> 1.0 - completionRate;
				case BASES_PER_ROUND -> ratio(slots[SLOT_BASES_CONQUERED],
					lifetime[MODES.get("BASE")][ROUNDS]);
				case HEADSHOT_RATIO -> ratio(sum(rows, HEADSHOT_KILLS) + sum(rows, HEADSHOT_STUNS),
					sum(rows, KILLS) + sum(rows, STUNS));
				case KNIFE_RATIO -> ratio(knifeKills, sum(rows, KILLS));
				case DEATHS_PER_ROUND -> ratio(sum(rows, DEATHS), sum(rows, ROUNDS));
				case HEADSHOT_DEATH_RATIO -> ratio(sum(rows, HEADSHOT_DEATHS), sum(rows, DEATHS));
				case STUN_RATIO -> ratio(sum(rows, STUNS), sum(rows, STUNS_RECEIVED));
				case STUNS_PER_KILL -> ratio(sum(rows, STUNS), sum(rows, KILLS));
				case ROLLS_PER_ROUND -> perRound(SLOT_ROLLS, rows);
				case CQC_PER_ROUND -> perRound(SLOT_CQC_GIVEN, rows);
				case BOX_PER_ROUND -> perRound(SLOT_BOX_USES, rows);
				case SCANS_PER_ROUND -> perRound(SLOT_SCANS, rows);
				case TRAPS_PER_ROUND -> perRound(SLOT_TRAPS, rows);
				case ENVG_TIME_RATIO -> ratio(slots[SLOT_ENVG_SECONDS], sum(rows, SECONDS));
				case MODE_ROUND_SHARE -> ratio(sum(rows, ROUNDS), sum(allRows(), ROUNDS));
				case WEEKLY_MODE_ROUNDS -> sumWeekly(modes, ROUNDS);
				case KILLS_PER_ROUND -> ratio(sum(rows, KILLS), sum(rows, ROUNDS));
				case STUNS_PER_ROUND -> ratio(sum(rows, STUNS), sum(rows, ROUNDS));
				case STUNS_RECEIVED_PER_ROUND -> ratio(sum(rows, STUNS_RECEIVED), sum(rows, ROUNDS));
				case DAYS_SINCE_LOGIN -> lastSeen
					.map(seen -> (double) Duration.between(seen, OffsetDateTime.now()).toDays())
					.orElse(0.0);
				case TOTAL_KILLS -> sum(allRows(), KILLS);
				case TOTAL_DEATHS -> sum(allRows(), DEATHS);
				// Medals resolve SLOT themselves; a title clause has no slot to name.
				case SLOT -> 0;
			};
		}

		private long[][] rowsFor(Set<String> modes) {
			if (modes.isEmpty()) {
				return allRows();
			}
			return modes.stream()
				.map(MODES::get)
				.filter(java.util.Objects::nonNull)
				.map(rule -> lifetime[rule])
				.toArray(long[][]::new);
		}

		private long[][] allRows() {
			return lifetime;
		}

		private double sumWeekly(Set<String> modes, int column) {
			var total = 0L;
			for (var mode : modes) {
				var rule = MODES.get(mode);
				if (rule != null) {
					total += weekly[rule][column];
				}
			}
			return total;
		}

		private double perRound(int slot, long[][] rows) {
			return ratio(slots[slot], sum(rows, ROUNDS));
		}

		private static long sum(long[][] rows, int column) {
			var total = 0L;
			for (var row : rows) {
				total += row[column];
			}
			return total;
		}

		/**
		 * A ratio with no denominator is ZERO, not infinity. A character with no deaths has not
		 * earned an unbeatable kill/death ratio; they have not played, and treating an empty
		 * denominator as success would hand every title to anyone who never joined a round.
		 */
		private static double ratio(double numerator, double denominator) {
			return denominator == 0 ? 0 : numerator / denominator;
		}
	}
}
