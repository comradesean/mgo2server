package mgo2server.common;

import java.time.Duration;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.UnaryOperator;

/**
 * Operator policy for automatching: when it runs, how it matches, and how big a match has to be.
 *
 * <h2>None of this is protocol</h2>
 * The client sends a rule preference and then waits. Every other decision — whether the feature is
 * open at all, who is matched with whom, how many players a game needs before it forms — is ours.
 * The one thing the game does fix is the <em>vocabulary of refusal</em>: it ships a sentence for
 * "currently not open" and a separate one for "currently not available", which is why a schedule is
 * modelled here rather than a simple on/off. See {@code dev/docs/AUTOMATCH.md} §1.
 *
 * <h2>Why environment rather than a JSON resource</h2>
 * The obvious alternative was an {@code automatch.json} beside {@code awards.json}, since a schedule
 * is a table and {@link Policy} is scalars. Two facts about this deployment decide against it:
 * {@code awards.json} is on the classpath and baked into the shaded jar, so editing a window would
 * mean a <b>rebuild</b> where {@code server.env} needs only a restart; and its process-wide
 * {@code static CURRENT} cannot express "window open" in one test and "window closed" in the next
 * within a single JVM. So this follows {@link Policy}'s idiom — a record, a
 * {@link #from(UnaryOperator)} seam — but is <b>passed in from {@code GameServerFactory}</b> rather
 * than read from a static, because unlike a cooldown it differs between a test and a deployment.
 *
 * @param enabled whether to answer {@code 0x43e0} at all. When false every start is refused with
 *     {@code AUTOMATCH_NOT_OPEN}, which is honest: the alternative is the ~20-minute silent stall
 *     this feature replaced
 * @param windows when automatching is open. <b>Empty means never</b> — see {@link #DEFAULT_WINDOWS}
 * @param zone the zone {@code windows} are expressed in. Named explicitly because a window with no
 *     zone in a container that runs UTC is a bug you discover live, at the wrong hour
 * @param mode which of the two matching strategies to run
 * @param minPlayers how many searchers must accumulate before a game is formed
 * @param tick how often the matchmaker re-evaluates
 * @param slotInLobbies extra lobby ids whose games are candidates for slot-in, beyond this one
 */
public record AutomatchPolicy(
	boolean enabled,
	List<Window> windows,
	ZoneId zone,
	Mode mode,
	int minPlayers,
	Duration tick,
	Set<Long> slotInLobbies,
	int bandStart,
	Duration bandStep,
	int bandMax
) {

	/**
	 * Which matching strategies to run.
	 *
	 * <p>The disc implies both existed: the automatch screen ships three distinct search messages —
	 * "Searching for opponents… until the required number of players are found" (string 911),
	 * "Searching for joinable games in progress" (912) and "Searching for open games" (913). The
	 * first is forming; the other two are slotting in.
	 */
	public enum Mode {
		/**
		 * Try to slot a searcher into an existing game; if none fits, queue them and form one. The
		 * useful default on a small server, because forming needs several people at once and
		 * slotting in needs only one.
		 */
		BOTH,

		/**
		 * Only ever form new games from queued searchers. Every automatch game is then a purpose-made
		 * one and nobody is dropped into a match already in progress.
		 */
		FORM_ONLY,

		/**
		 * Only ever slot searchers into games that already exist; never form one.
		 * <p>
		 * <b>This is a no-op unless {@link #slotInLobbies} is set.</b> Candidate games are scoped to
		 * the automatching lobby by default, and that lobby can only contain games a previous cohort
		 * <em>formed</em> — its screen has no Create Game and no browser. So slot-in-only with the
		 * default scope waits forever on an empty set. {@link #validate} says so at startup rather
		 * than letting it look like a bug.
		 */
		SLOT_IN_ONLY;

		static Mode of(String value, String name) {
			for (var mode : values()) {
				if (mode.name().equalsIgnoreCase(value.trim())) {
					return mode;
				}
			}
			throw new IllegalArgumentException(name + " must be one of BOTH, FORM_ONLY or "
				+ "SLOT_IN_ONLY, got: " + value);
		}
	}

	/**
	 * One open period, as a wall-clock range in {@link #zone}.
	 *
	 * <p>A range whose end is not after its start <b>wraps past midnight</b> — {@code 22:00-02:00}
	 * is four hours, not a mistake. That is the one shape an operator will reach for that a naive
	 * {@code start <= now < end} gets silently wrong.
	 */
	public record Window(LocalTime start, LocalTime end) {

		public boolean contains(LocalTime time) {
			if (end.isAfter(start)) {
				return !time.isBefore(start) && time.isBefore(end);
			}
			// Wraps midnight: open from start to the end of the day, and again from midnight to end.
			return !time.isBefore(start) || time.isBefore(end);
		}

		@Override
		public String toString() {
			return start + "-" + end;
		}
	}

	/**
	 * No windows at all, which reads as <b>closed</b>.
	 * <p>
	 * Closed is the right default for something nobody has switched on. An operator who has not
	 * configured automatching gets the client's own "Automatching is currently not open", which is
	 * true, rather than an open queue nobody is in.
	 */
	public static final List<Window> DEFAULT_WINDOWS = List.of();

	/** Two players is the smallest thing that is a match rather than a lobby of one. */
	public static final int DEFAULT_MIN_PLAYERS = 2;

	/**
	 * How often the matchmaker re-evaluates.
	 * <p>
	 * Five seconds is comfortably inside the client's own budget — its request deadline is ~40 s and
	 * its search timeout ~20 minutes — while being slow enough that the panel push is not chatty.
	 */
	public static final Duration DEFAULT_TICK = Duration.ofSeconds(5);

	/** A search starts looking at its own level and one either side. */
	public static final int DEFAULT_BAND_START = 1;

	/**
	 * How long before a search widens by a level.
	 * <p>
	 * Thirty seconds reaches the full 22-level span in about eleven minutes, comfortably inside the
	 * client's own ~20-minute search timeout — so a patient player ends up matched with anyone rather
	 * than timing out inside a narrow band.
	 */
	public static final Duration DEFAULT_BAND_STEP = Duration.ofSeconds(30);

	/** Every level. The client clamps the gauge to 0..22, so this is "anyone". */
	public static final int DEFAULT_BAND_MAX = 22;

	/**
	 * How wide a searcher's level window is after waiting this long.
	 * <p>
	 * <b>Each searcher carries their own window, and two match when the windows touch.</b> That is
	 * symmetric — a player who has waited ten minutes reaches out to a newcomer rather than the pair
	 * having to satisfy one shared band — and it is exactly what the client draws, since it lights
	 * columns {@code [myLevel - band, myLevel + band]} around a centre it computes itself. So the
	 * number we send is the truth about that player's search, not a decoration.
	 */
	public int bandAfter(Duration waited) {
		var steps = bandStep.isZero() ? 0 : waited.toSeconds() / bandStep.toSeconds();
		return (int) Math.min(bandMax, bandStart + steps);
	}

	public static AutomatchPolicy from(UnaryOperator<String> env) {
		var policy = new AutomatchPolicy(
			bool(env, "MGO2SERVER_AUTOMATCH_ENABLED", false),
			windows(env, "MGO2SERVER_AUTOMATCH_WINDOWS"),
			zone(env, "MGO2SERVER_AUTOMATCH_TIMEZONE"),
			mode(env, "MGO2SERVER_AUTOMATCH_MODE"),
			positive(env, "MGO2SERVER_AUTOMATCH_MIN_PLAYERS", DEFAULT_MIN_PLAYERS),
			seconds(env, "MGO2SERVER_AUTOMATCH_TICK_SECONDS", DEFAULT_TICK),
			lobbyIds(env, "MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES"),
			level(env, "MGO2SERVER_AUTOMATCH_BAND_START", DEFAULT_BAND_START),
			seconds(env, "MGO2SERVER_AUTOMATCH_BAND_STEP_SECONDS", DEFAULT_BAND_STEP),
			level(env, "MGO2SERVER_AUTOMATCH_BAND_MAX", DEFAULT_BAND_MAX));
		policy.validate();
		return policy;
	}

	/**
	 * Whether automatching is open at the given instant.
	 * <p>
	 * Day of week is deliberately not modelled. Nothing in the game distinguishes days, and a
	 * weekday/weekend schedule can be had by running two deployments' worth of windows through the
	 * same list if it is ever wanted.
	 */
	public boolean openAt(ZonedDateTime when) {
		if (!enabled) {
			return false;
		}
		var local = when.withZoneSameInstant(zone).toLocalTime();
		return windows.stream().anyMatch(window -> window.contains(local));
	}

	/** Whether this mode ever forms a new game. */
	public boolean forms() {
		return mode != Mode.SLOT_IN_ONLY;
	}

	/** Whether this mode ever slots a searcher into a game that already exists. */
	public boolean slotsIn() {
		return mode != Mode.FORM_ONLY;
	}

	/**
	 * Rejects configurations that cannot do anything, loudly and at startup.
	 * <p>
	 * Follows {@link Policy}'s reasoning rather than a soft fallback: a server that will not start is
	 * a bug report, and one that accepts searches it can never satisfy is a support ticket that costs
	 * somebody twenty minutes of staring at a stopwatch.
	 */
	private void validate() {
		if (!enabled) {
			return;
		}
		if (windows.isEmpty()) {
			throw new IllegalArgumentException("MGO2SERVER_AUTOMATCH_ENABLED is set but "
				+ "MGO2SERVER_AUTOMATCH_WINDOWS is empty, so automatching would be open never. "
				+ "Give it a window such as 20:00-23:00, or leave it disabled.");
		}
		if (mode == Mode.SLOT_IN_ONLY && slotInLobbies.isEmpty()) {
			throw new IllegalArgumentException("MGO2SERVER_AUTOMATCH_MODE=SLOT_IN_ONLY needs "
				+ "MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES, because the automatching lobby only ever "
				+ "contains games automatching itself formed — and this mode never forms one. "
				+ "Name the lobby ids whose games searchers may join, or use BOTH.");
		}
	}

	private static List<Window> windows(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return DEFAULT_WINDOWS;
		}
		var windows = new ArrayList<Window>();
		for (var part : value.split(",")) {
			var range = part.trim();
			if (range.isEmpty()) {
				continue;
			}
			var dash = range.indexOf('-');
			if (dash < 0) {
				throw new IllegalArgumentException(name + " entry \"" + range + "\" is not a range; "
					+ "expected HH:MM-HH:MM, comma-separated.");
			}
			windows.add(new Window(time(range.substring(0, dash), range, name),
				time(range.substring(dash + 1), range, name)));
		}
		return List.copyOf(windows);
	}

	private static LocalTime time(String text, String range, String name) {
		try {
			return LocalTime.parse(text.trim());
		} catch (RuntimeException e) {
			throw new IllegalArgumentException(name + " entry \"" + range + "\" has a bad time \""
				+ text.trim() + "\"; expected HH:MM.", e);
		}
	}

	private static ZoneId zone(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return ZoneId.of("UTC");
		}
		try {
			return ZoneId.of(value.trim());
		} catch (RuntimeException e) {
			throw new IllegalArgumentException(name + " is not a known zone id, got: " + value
				+ ". Use a region name such as America/New_York, or leave it unset for UTC.", e);
		}
	}

	private static Mode mode(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		return value == null || value.isBlank() ? Mode.BOTH : Mode.of(value, name);
	}

	private static Set<Long> lobbyIds(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return Set.of();
		}
		var ids = new LinkedHashSet<Long>();
		for (var part : value.split(",")) {
			var id = part.trim();
			if (id.isEmpty()) {
				continue;
			}
			try {
				ids.add(Long.parseLong(id));
			} catch (NumberFormatException e) {
				throw new IllegalArgumentException(name + " must be comma-separated lobby ids, got: "
					+ value, e);
			}
		}
		return Set.copyOf(ids);
	}

	private static boolean bool(UnaryOperator<String> env, String name, boolean fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		var trimmed = value.trim();
		if (trimmed.equalsIgnoreCase("true") || trimmed.equals("1")) {
			return true;
		}
		if (trimmed.equalsIgnoreCase("false") || trimmed.equals("0")) {
			return false;
		}
		throw new IllegalArgumentException(name + " must be true or false, got: " + value);
	}

	/** A level count, 0..22 — the range the client's own gauge clamps to. */
	private static int level(UnaryOperator<String> env, String name, int fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		int parsed;
		try {
			parsed = Integer.parseInt(value.trim());
		} catch (NumberFormatException e) {
			throw new IllegalArgumentException(name + " must be a whole number of levels, got: "
				+ value, e);
		}
		if (parsed < 0 || parsed > DEFAULT_BAND_MAX) {
			throw new IllegalArgumentException(name + " must be 0.." + DEFAULT_BAND_MAX
				+ " levels, got: " + value);
		}
		return parsed;
	}

	private static int positive(UnaryOperator<String> env, String name, int fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		int parsed;
		try {
			parsed = Integer.parseInt(value.trim());
		} catch (NumberFormatException e) {
			throw new IllegalArgumentException(name + " must be a whole number, got: " + value, e);
		}
		if (parsed < 2) {
			throw new IllegalArgumentException(name + " must be at least 2 — a match of one player is "
				+ "not a match, got: " + value);
		}
		return parsed;
	}

	private static Duration seconds(UnaryOperator<String> env, String name, Duration fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		long parsed;
		try {
			parsed = Long.parseLong(value.trim());
		} catch (NumberFormatException e) {
			throw new IllegalArgumentException(name + " must be a whole number of seconds, got: "
				+ value, e);
		}
		if (parsed < 1) {
			throw new IllegalArgumentException(name + " must be at least 1 second, got: " + value);
		}
		return Duration.ofSeconds(parsed);
	}
}
