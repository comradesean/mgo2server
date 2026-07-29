package mgo2server.common;

import java.time.Duration;
import java.util.function.UnaryOperator;

/**
 * Operator policy: the waiting periods this server imposes, and nothing the game imposes.
 * <p>
 * <b>None of these are protocol.</b> The client never sends, validates or knows about any of them;
 * it only renders whatever refusal we answer with. Every number here is a server-side choice, and
 * the community figure of 168 hours is a player report about the retail service, not a value read
 * out of {@code MGO2.elf}. Treat them as defaults to be argued about, not as facts.
 * <p>
 * Kept separate from {@link Config}, which is deployment wiring — ports, database, which lobby this
 * instance is. That gets threaded through constructors because it differs per container. These are
 * the same for every container in a deployment and are read statically, so a service can consult
 * one without every caller having to hand it one.
 * <p>
 * Overrides come from the environment, which in practice means the {@code server.env} file at the
 * repository root. Defaults live here: a missing or deleted {@code server.env} must leave the
 * server running on documented defaults rather than failing to start.
 */
public record Policy(
	Duration characterDeleteCooldown,
	Duration clanDisbandCooldown,
	Duration clanEmblemCooldown,
	Duration clanJoinCooldown,
	boolean zeroUnreadFields,
	boolean capturePackets
) {
	/** A week. What all three cooldowns default to. */
	public static final Duration DEFAULT_COOLDOWN = Duration.ofHours(168);

	private static final Policy CURRENT = fromEnv();

	public static Policy fromEnv() {
		return from(System::getenv);
	}

	/** The process-wide policy, read once at class initialisation. */
	public static Policy current() {
		return CURRENT;
	}

	/** Reads from an arbitrary lookup rather than the process environment, so it can be tested. */
	public static Policy from(UnaryOperator<String> env) {
		return new Policy(
			hours(env, "MGO2SERVER_CHARACTER_DELETE_COOLDOWN_HOURS", DEFAULT_COOLDOWN),
			hours(env, "MGO2SERVER_CLAN_DISBAND_COOLDOWN_HOURS", DEFAULT_COOLDOWN),
			hours(env, "MGO2SERVER_CLAN_EMBLEM_COOLDOWN_HOURS", DEFAULT_COOLDOWN),
			hours(env, "MGO2SERVER_CLAN_JOIN_COOLDOWN_HOURS", DEFAULT_COOLDOWN),
			flag(env, "MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS"),
			flag(env, "MGO2SERVER_CAPTURE_PACKETS")
		);
	}

	/**
	 * Archives raw protocol payloads to {@code dev_packet_audit} for offline decoding.
	 *
	 * <p>Dev tooling, and the cost is explicit: the table grows unbounded by design, because
	 * consecutive senders must not overwrite each other's evidence. Off means the server writes
	 * nothing there at all.
	 *
	 * <p>It pairs with the inert-field tripwire and does a different job. The tripwire is the
	 * <b>summary</b> — distinct values per watched field, where a second row is an alert. This is
	 * the <b>evidence</b> — whole payloads with timestamps, so a later question can be answered
	 * against real bytes instead of re-derived from a conclusion. The training-lobby correlation
	 * needed the evidence: it correlated a byte inside each payload against the lobby subtype in the
	 * same row, which the summary could not have answered.
	 */
	/**
	 * Zeroes the inherited constants an exhaustive ELF sweep found have <b>no reader</b> in this
	 * client build: automatch settings block {@code +72} (captured {@code 0x02000000}) and
	 * {@code +179} (captured {@code 0x20}), and {@code 0x4101}'s four u16, whose only readers are
	 * four getters nothing ever calls.
	 *
	 * <p><b>Kept for a specific future purpose:</b> these are candidate bits for a later game
	 * version. {@code +179} in particular is the low byte of the settings flags word whose bits 8-23
	 * are the ~16 Common Settings toggles — bits 0-7 are an unused byte with our bit 5 set, which is
	 * what a compiled-out feature tends to leave behind. If a later client is compared against this
	 * one, that is the first place to look, and this switch is how the theory gets tested.
	 *
	 * <p><b>Not included</b>, because they are read: {@code 0x4120}'s trailer bytes 0-7 (the filter
	 * and sort preferences, now sent as deliberate zeros) and the {@code 0x3049} trailer, whose
	 * index-3 bit 0 unlocks 32 of the 91 loadout items.
	 *
	 * <p>Off unless explicitly set. Absent, blank and non-boolean all mean off.
	 */
	private static boolean flag(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		return value != null && Boolean.parseBoolean(value.trim());
	}

	/**
	 * Hours, where {@code 0} means no waiting period at all — which is what a test deployment
	 * wants, and why these are configurable in the first place. Negative values are rejected rather
	 * than clamped: a negative cooldown is a typo, and silently treating it as zero would turn a
	 * misconfiguration into a permissive one.
	 */
	private static Duration hours(UnaryOperator<String> env, String name, Duration fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		long parsed;
		try {
			parsed = Long.parseLong(value.trim());
		} catch (NumberFormatException e) {
			throw new IllegalArgumentException(name + " must be a whole number of hours, got: " + value, e);
		}
		if (parsed < 0) {
			throw new IllegalArgumentException(name + " must not be negative, got: " + value);
		}
		return Duration.ofHours(parsed);
	}
}
