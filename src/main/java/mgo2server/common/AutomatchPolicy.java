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
	int bandMax,
	Duration modeRelax,
	int minPlayersStart,
	Duration minPlayersStep
) {

	/**
	 * Which matching strategies to run.
	 *
	 * <p><b>Automatching forms a brand-new game. That is the whole architecture, and slot-in is not
	 * part of it</b> — operator judgement, 2026-08-02, and this enum previously implied the
	 * opposite.
	 *
	 * <p>The claim it used to make was that "the disc implies both existed", resting on three search
	 * messages: 911 <em>"Searching for opponents… until the required number of players are
	 * found"</em> against 912 <em>"Searching for joinable games in progress"</em> and 913
	 * <em>"Searching for open games"</em>. <b>That inference does not carry.</b> The strings prove
	 * the client can <em>display</em> three search states; they say nothing about which the server
	 * ever entered. That is the project's standing distinction between what shipped on the disc and
	 * what Konami had switched on — and here it is sharper than usual, because the automatch screen
	 * is driven entirely by server pushes, so every message it can render is a message the client
	 * needs a string for whether or not the state occurs.
	 *
	 * <p>What points the other way is structural rather than textual, and it is the reason the
	 * default is now {@link #FORM_ONLY}:
	 * <ul>
	 *   <li>the automatching lobby has <b>no Create Game and no browser</b>, so the only games in it
	 *       are ones automatch itself formed — there is nothing to slot into that automatch did not
	 *       build;</li>
	 *   <li>reaching into other lobbies to find candidates is a policy invention with nothing behind
	 *       it, and would drop searchers into games whose hosts never agreed to receive them;</li>
	 *   <li>the one observed automatch session <b>formed</b>, assembling its rotation from the union
	 *       of what its searchers had asked for — a game built for that group.</li>
	 * </ul>
	 *
	 * <p>There is also no post-match lobby screen to see such a game in: automatch goes from the
	 * search straight into the formed game.
	 *
	 * <p>Slot-in stays in this enum as a <b>future</b> possibility rather than being deleted, because
	 * a later MGO2 version may well have added it and the strings would then be its evidence. It is
	 * not how this server behaves and not what v1 targets.
	 */
	public enum Mode {
		/**
		 * Form a game from the queue, and — <b>if slot-in is ever built</b> — try an existing game
		 * first.
		 * <p>
		 * <b>Today this behaves exactly like {@link #FORM_ONLY}</b>, because the slot-in pass is not
		 * implemented, and it is <b>no longer the default</b> (changed 2026-08-02): the default is
		 * {@link #FORM_ONLY}, which states the architecture rather than a plan we no longer hold.
		 * Selecting {@code BOTH} today is therefore indistinguishable from {@code FORM_ONLY} and is
		 * kept only so an existing deployment's {@code server.env} does not fail to start.
		 */
		BOTH,

		/**
		 * Only ever form new games from queued searchers. Every automatch game is then a purpose-made
		 * one and nobody is dropped into a match already in progress.
		 *
		 * <p><b>The default since 2026-08-02, and believed to be how the original worked.</b> See the
		 * enum's own documentation for why the three disc strings do not argue otherwise.
		 */
		FORM_ONLY,

		/**
		 * Only ever slot searchers into games that already exist; never form one.
		 *
		 * <p><b>NOT IMPLEMENTED — parked as a future project, and the server refuses to start with
		 * it.</b> Selecting it would leave the matchmaker completely inert, which is a worse failure
		 * than refusing.
		 *
		 * <h2>Why it is parked rather than missing</h2>
		 * The evidence for slot-in was always the weaker half of the feature. It rests on three disc
		 * strings that imply joining a game already running — 912 <em>"Searching for joinable games in
		 * progress"</em> and 913 <em>"Searching for open games"</em>, against 911 <em>"Searching for
		 * opponents… until the required number of players are found"</em>, which is forming.
		 *
		 * <p>Against that, the only <b>observed</b> automatch behaviour we have is forming: a real
		 * session assembled its rotation from the union of what its searchers had requested, which is
		 * a game built for that group rather than one they were dropped into. The operator's reading,
		 * and the one this server follows, is that forming is how the original worked.
		 *
		 * <p>It is also the harder half to justify on this deployment: the automatching lobby only
		 * ever contains games automatching itself formed — its screen has no Create Game and no
		 * browser — so slot-in is dormant unless it reaches into other lobbies, and pulling searchers
		 * into Free Battle games is a policy invention with nothing behind it.
		 *
		 * <p>If it is ever built: the client path is believed to be {@code 0x43f2} alone with an
		 * existing game's id and no preceding {@code 0x43f1}, which is a <em>reading</em> of the state
		 * machine and not an observation. Confirm that before relying on it.
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

	/**
	 * The floor the requirement decays to. Two players is the smallest thing that is a match rather
	 * than a lobby of one.
	 */
	public static final int DEFAULT_MIN_PLAYERS = 2;

	/**
	 * How many players a search holds out for when it starts.
	 * <p>
	 * Twelve, because a full game is better than a fast one — a search that immediately settles for
	 * two produces a duel when eight people were a minute away. The requirement decays from here, so
	 * nobody is held out forever; it only biases early matches toward being worth playing.
	 * <p>
	 * <b>Operator policy.</b> Nothing establishes what the original held out for, only that its panel
	 * has a "Players Needed" figure at all — which implies a target above the two it could settle for.
	 */
	public static final int DEFAULT_MIN_PLAYERS_START = 12;

	/**
	 * How long before the requirement drops by one player.
	 * <p>
	 * Thirty seconds walks 12 down to 2 in five minutes, well inside the client's own ~20-minute
	 * search timeout, so a lone pair still matches without waiting it out.
	 */
	public static final Duration DEFAULT_MIN_PLAYERS_STEP = Duration.ofSeconds(30);

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
	 * How long a searcher insists on their own requested mode before taking anything.
	 * <p>
	 * Ninety seconds: long enough that a populated server groups people who want the same thing,
	 * short enough that a quiet one still matches. Like the band, this is <b>operator policy</b> —
	 * nothing establishes what the original did, only that a rotation can carry several modes at
	 * once, which is what makes mixing them possible at all.
	 */
	public static final Duration DEFAULT_MODE_RELAX = Duration.ofSeconds(90);

	/**
	 * Whether a searcher who has waited this long will accept a mode they did not ask for.
	 * <p>
	 * The same shape as {@link #bandAfter}: strict at first, relaxing with that searcher's own wait,
	 * so a patient player reaches out rather than the pair having to satisfy one shared rule.
	 */
	public boolean acceptsAnyModeAfter(Duration waited) {
		return waited.compareTo(modeRelax) >= 0;
	}

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

	/**
	 * How many players a search that has waited this long still insists on.
	 *
	 * <p>Decays from {@link #minPlayersStart} to {@link #minPlayers}, one player per
	 * {@link #minPlayersStep}. Same shape as the level band and the mode relaxation: strict at first,
	 * relaxing with that searcher's own wait.
	 *
	 * <p>This is the number behind the client's "Players Needed" figure, so what a player sees
	 * counting down is the requirement genuinely falling, not a display trick.
	 */
	public int requiredPlayersAfter(Duration waited) {
		if (minPlayersStep.isZero()) {
			return minPlayers;
		}
		var steps = waited.toSeconds() / minPlayersStep.toSeconds();
		return (int) Math.max(minPlayers, minPlayersStart - steps);
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
			level(env, "MGO2SERVER_AUTOMATCH_BAND_MAX", DEFAULT_BAND_MAX),
			seconds(env, "MGO2SERVER_AUTOMATCH_MODE_RELAX_SECONDS", DEFAULT_MODE_RELAX),
			positive(env, "MGO2SERVER_AUTOMATCH_MIN_PLAYERS_START", DEFAULT_MIN_PLAYERS_START),
			seconds(env, "MGO2SERVER_AUTOMATCH_MIN_PLAYERS_STEP_SECONDS", DEFAULT_MIN_PLAYERS_STEP));
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
		if (mode == Mode.SLOT_IN_ONLY) {
			throw new IllegalArgumentException("MGO2SERVER_AUTOMATCH_MODE=SLOT_IN_ONLY is not "
				+ "implemented — slot-in is parked as a future project, so this mode would leave the "
				+ "matchmaker inert rather than doing anything. Use BOTH or FORM_ONLY, which both "
				+ "form a game from the queue. See AutomatchPolicy.Mode.SLOT_IN_ONLY for why.");
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
		// FORM_ONLY, not BOTH. A behaviour no-op today -- slot-in is unimplemented, so the two are
		// identical -- but the default should state the architecture rather than a plan we no longer
		// hold. See Mode's documentation.
		return value == null || value.isBlank() ? Mode.FORM_ONLY : Mode.of(value, name);
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
