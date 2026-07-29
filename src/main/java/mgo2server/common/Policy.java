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
	boolean zeroUnreadFields
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
			flag(env, "MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS")
		);
	}

	/**
	 * <b>An experiment switch, not a feature.</b> Zeroes the four inherited constants that an
	 * exhaustive ELF sweep found have <b>no reader in this client build</b>:
	 * <ul>
	 * <li>automatch settings block {@code +72} (captured {@code 0x02000000}) and {@code +179}
	 * (captured {@code 0x20});</li>
	 * <li>{@code 0x4101}'s four u16 — their only readers are four getters nothing calls;</li>
	 * <li>{@code 0x4120}'s trailer bytes 8..31.</li>
	 * </ul>
	 *
	 * <p><b>Deliberately excluded</b>, because they are NOT unread: {@code 0x4120} trailer bytes 0-7,
	 * where two nibbles reach a consumer, and the {@code 0x3049} trailer, whose index-3 bit 0 unlocks
	 * 32 of the 91 loadout items.
	 *
	 * <p>Off by default. The point is to test the sweeps against a real client rather than to change
	 * what we ship — and the sweeps have a stated limit: a reader that stashed the struct pointer in
	 * memory and reloaded it into an untracked register would have been missed.
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
