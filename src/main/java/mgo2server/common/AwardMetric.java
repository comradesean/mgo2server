package mgo2server.common;

/**
 * The statistics an award requirement may test.
 * <p>
 * This set is deliberately closed. {@code awards.json} picks a metric, an optional mode filter, a
 * comparison and a number — it cannot define a computation. That keeps the file safe to hand-edit
 * (a typo names itself at startup rather than silently evaluating to zero) and keeps the arithmetic
 * where it can be tested.
 * <p>
 * Every one is computed in {@code AwardService} from {@code round_report},
 * {@code round_weapon_tally}, {@code chara_training_time} or {@code chara.last_seen_at}. The mapping
 * from each to its wire source is in {@code dev/docs/AWARDS.md}.
 * <p>
 * <b>Ratios over an empty denominator evaluate to zero, not infinity.</b> A character with no
 * deaths has not earned an infinite kill/death ratio; they have not played. Requirements that would
 * otherwise be trivially satisfied by inactivity are guarded by pairing them with {@code ROUNDS} in
 * the file.
 */
public enum AwardMetric {

	/** {@code (kills + stuns) / (deaths + stuns received)} — the game's own "K+s/D+s". */
	KD_RATIO,

	/** {@code kills / deaths}, ignoring stuns. */
	SIMPLE_KD,

	/** {@code rounds won / rounds played}, 0..1 rather than a percentage. */
	WIN_RATE,

	/** Rounds played. The usual guard against a ratio computed from three rounds. */
	ROUNDS,

	/**
	 * The share of rounds a player left before the end: {@code 1 − mean(round_completed)}.
	 * Reads struct A {@code counter_0x1f}, which nothing had ever consumed.
	 */
	WITHDRAWAL_RATE,

	/** Bases conquered per Base round — struct-B b25 over rounds where the rule is Base. */
	BASES_PER_ROUND,

	/** {@code (headshot kills + headshot stuns) / (kills + stuns)}. */
	HEADSHOT_RATIO,

	/** Knife kills over total kills, from {@code round_weapon_tally} weapon id 1. */
	KNIFE_RATIO,

	/** Deaths per round. */
	DEATHS_PER_ROUND,

	/** Headshot deaths over total deaths. */
	HEADSHOT_DEATH_RATIO,

	/** Stuns dealt over stuns received. */
	STUN_RATIO,

	/** Stuns dealt per kill — high means a player who prefers not to kill. */
	STUNS_PER_KILL,

	/** Rolls per round, struct-B b12. */
	ROLLS_PER_ROUND,

	/** CQC attacks given per round, struct-B b10. */
	CQC_PER_ROUND,

	/** Cardboard box uses per round, struct-B b21. */
	BOX_PER_ROUND,

	/** Successful SOP scans per round, struct-B b19. */
	SCANS_PER_ROUND,

	/** Times caught in a trap per round, struct-B b18. */
	TRAPS_PER_ROUND,

	/** Seconds wearing ENVG over seconds played — struct-B b13 over {@code seconds_in_game}. */
	ENVG_TIME_RATIO,

	/** Rounds in the named modes over rounds in every mode. */
	MODE_ROUND_SHARE,

	/** Rounds in the named modes within the current calendar week. */
	WEEKLY_MODE_ROUNDS,

	/** Kills per round. */
	KILLS_PER_ROUND,

	/** Stuns dealt per round. */
	STUNS_PER_ROUND,

	/** Stuns received per round. */
	STUNS_RECEIVED_PER_ROUND,

	/**
	 * Whole days since this character was last seen logging in.
	 * <p>
	 * The one metric no gameplay row can express, because not playing writes nothing — which is why
	 * {@code chara.last_seen_at} exists. A character never seen since the column was added counts
	 * as zero days rather than infinity, so absence of data does not award a title.
	 */
	DAYS_SINCE_LOGIN,

	/** Career kills across every mode. Medals only. */
	TOTAL_KILLS,

	/** Career deaths across every mode. Medals only. */
	TOTAL_DEATHS,

	/** A raw {@code 0x4107} personal-score slot, named by the entry's {@code slot}. Medals only. */
	SLOT,
}
