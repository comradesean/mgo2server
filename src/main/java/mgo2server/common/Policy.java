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
	Duration clanJoinCooldown
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
			hours(env, "MGO2SERVER_CLAN_JOIN_COOLDOWN_HOURS", DEFAULT_COOLDOWN)
		);
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
