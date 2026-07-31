package mgo2server.common;

import mgo2server.common.AutomatchPolicy.Mode;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * These assert <b>operator policy</b>, not protocol. The client sends a rule filter and then waits;
 * whether anyone is listening, and at what hour, is entirely ours — see {@code AUTOMATCH.md} §1. So
 * nothing here is checkable against the binary and none of it is a correctness check against the
 * game.
 * <p>
 * What they are guarding is a feature whose failure mode is invisible. Answering {@code 0x43e1} with
 * result 0 registers the client's push channel and commits us to speaking again; a schedule that
 * says "open" when nobody is matching buys the player a twenty-minute stopwatch and no explanation.
 * A misparsed window is therefore not a cosmetic bug, and the midnight-wrapping case below is the
 * one an operator will reach for first.
 */
public class AutomatchPolicyTest {
	private static AutomatchPolicy of(Map<String, String> env) {
		return AutomatchPolicy.from(env::get);
	}

	/** Wall-clock 22:00 UTC on an arbitrary day; every window test below is read against it. */
	private static final Instant TEN_PM_UTC = Instant.parse("2026-07-27T22:00:00Z");

	private static boolean openAt(AutomatchPolicy policy, String utcTime) {
		return policy.openAt(Instant.parse("2026-07-27T" + utcTime + ":00Z").atZone(ZoneOffset.UTC));
	}

	/**
	 * Closed is the only defensible default. An operator who has not configured automatching gets
	 * the client's own "Automatching is currently not open" (4929), which is true, rather than an
	 * accepted search into a queue nobody is running.
	 */
	/**
	 * The player requirement decays from its starting value to its floor, one player per step.
	 *
	 * <p>A search holds out for a full game at first and settles for fewer the longer it waits, which
	 * is the same shape as the level band and the mode relaxation. It is also what the client's
	 * "Players Needed" figure counts down, so the number a player watches is the real requirement.
	 */
	@Test
	public void theePlayerRequirementDecaysToItsFloor() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "00:00-00:00",
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS", "2",
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS_START", "12",
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS_STEP_SECONDS", "30"));

		assertThat(policy.requiredPlayersAfter(Duration.ZERO)).isEqualTo(12);
		assertThat(policy.requiredPlayersAfter(Duration.ofSeconds(29))).isEqualTo(12);
		assertThat(policy.requiredPlayersAfter(Duration.ofSeconds(30))).isEqualTo(11);
		assertThat(policy.requiredPlayersAfter(Duration.ofMinutes(5))).isEqualTo(2);
		assertThat(policy.requiredPlayersAfter(Duration.ofHours(1)))
			.as("it must never fall below the floor")
			.isEqualTo(2);
	}

	@Test
	public void defaultsToDisabledAndOpenAtNoInstant() {
		var policy = of(Map.of());

		assertThat(policy.enabled()).isFalse();
		assertThat(policy.windows()).isEmpty();
		assertThat(policy.zone()).isEqualTo(ZoneId.of("UTC"));
		assertThat(policy.mode()).isEqualTo(Mode.BOTH);
		assertThat(policy.minPlayers()).isEqualTo(AutomatchPolicy.DEFAULT_MIN_PLAYERS);
		assertThat(policy.tick()).isEqualTo(AutomatchPolicy.DEFAULT_TICK);
		assertThat(policy.slotInLobbies()).isEmpty();

		// Not "closed right now" — closed at every instant there is.
		assertThat(openAt(policy, "00:00")).isFalse();
		assertThat(openAt(policy, "12:00")).isFalse();
		assertThat(openAt(policy, "23:59")).isFalse();
	}

	/** Several windows in one day, comma-separated, each parsed independently. */
	@Test
	public void parsesACommaSeparatedList() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "12:00-13:00, 20:00-23:00"));

		assertThat(policy.windows()).containsExactly(
			new AutomatchPolicy.Window(LocalTime.of(12, 0), LocalTime.of(13, 0)),
			new AutomatchPolicy.Window(LocalTime.of(20, 0), LocalTime.of(23, 0)));
		assertThat(openAt(policy, "12:30")).isTrue();
		assertThat(openAt(policy, "17:00")).isFalse();
		assertThat(openAt(policy, "22:00")).isTrue();
	}

	/**
	 * The case a naive {@code start <= now < end} gets silently wrong, and the shape an operator
	 * reaches for first — a peak-hours window on a small server runs into the small hours. It has to
	 * be four hours of open, not a whole day minus four.
	 */
	@Test
	public void aWindowMayWrapPastMidnight() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "22:00-02:00"));

		assertThat(openAt(policy, "23:00")).isTrue();
		assertThat(openAt(policy, "01:00")).isTrue();
		assertThat(openAt(policy, "12:00")).isFalse();
		assertThat(openAt(policy, "21:59")).isFalse();
		assertThat(openAt(policy, "02:00")).isFalse();
	}

	/**
	 * Half-open, as a range of times should be: two adjacent windows must not both claim the instant
	 * they meet at, or a schedule of {@code 20:00-22:00,22:00-00:00} would double-count it.
	 */
	@Test
	public void startIsInclusiveAndEndIsExclusive() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00"));

		assertThat(openAt(policy, "19:59")).isFalse();
		assertThat(openAt(policy, "20:00")).isTrue();
		assertThat(openAt(policy, "22:59")).isTrue();
		assertThat(openAt(policy, "23:00")).isFalse();
	}

	/**
	 * The reason the zone is named in its own variable rather than inherited from the JVM: the
	 * container runs UTC, and an operator writing "20:00" means their evening. The same instant has
	 * to fall inside the window in one zone and outside it in another, or the setting is decoration.
	 */
	@Test
	public void theZoneDecidesWhichWallClockIsRead() {
		var utc = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00",
			"MGO2SERVER_AUTOMATCH_TIMEZONE", "UTC"));
		var newYork = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00",
			"MGO2SERVER_AUTOMATCH_TIMEZONE", "America/New_York"));

		// 22:00 UTC is 18:00 in New York, whichever side of a DST change the date falls on.
		var when = TEN_PM_UTC.atZone(ZoneOffset.UTC);
		assertThat(utc.openAt(when)).isTrue();
		assertThat(newYork.openAt(when)).isFalse();
	}

	/** The zone of the {@code ZonedDateTime} handed in is irrelevant; only the instant is read. */
	@Test
	public void openAtReadsTheInstantNotTheCallersZone() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00"));

		assertThat(policy.openAt(TEN_PM_UTC.atZone(ZoneOffset.UTC))).isTrue();
		assertThat(policy.openAt(TEN_PM_UTC.atZone(ZoneId.of("Asia/Tokyo")))).isTrue();
		assertThat(policy.openAt(TEN_PM_UTC.atZone(ZoneId.of("America/New_York")))).isTrue();
	}

	/**
	 * Env files are written by hand and shells do not care about case. Rejecting {@code both} would
	 * be a startup failure over nothing.
	 */
	@Test
	public void everyModeParsesRegardlessOfCase() {
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "both")).mode()).isEqualTo(Mode.BOTH);
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "BOTH")).mode()).isEqualTo(Mode.BOTH);
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "Form_Only")).mode())
			.isEqualTo(Mode.FORM_ONLY);
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_MODE", " slot_in_only ")).mode())
			.isEqualTo(Mode.SLOT_IN_ONLY);
		// Unset is BOTH: slot in where possible, form where not, which is the useful shape on a
		// server too small to fill a game from the queue alone.
		assertThat(of(Map.of()).mode()).isEqualTo(Mode.BOTH);
	}

	/** An unknown mode has to name the alternatives, or the operator is guessing at a restart. */
	@Test
	public void rejectsAnUnknownMode() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "slotin")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("BOTH, FORM_ONLY or SLOT_IN_ONLY")
			.hasMessageContaining("slotin");
	}

	/**
	 * The two questions the matchmaker asks the mode, answered for all three values. Both are true
	 * for BOTH, and exactly one is false for each of the others — a mode that answered false to both
	 * would be a queue that never resolves.
	 */
	@Test
	public void formsAndSlotsInPartitionTheModes() {
		var both = of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "BOTH"));
		assertThat(both.forms()).isTrue();
		assertThat(both.slotsIn()).isTrue();

		var formOnly = of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "FORM_ONLY"));
		assertThat(formOnly.forms()).isTrue();
		assertThat(formOnly.slotsIn()).isFalse();

		var slotInOnly = of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "SLOT_IN_ONLY"));
		assertThat(slotInOnly.forms()).isFalse();
		assertThat(slotInOnly.slotsIn()).isTrue();
	}

	/**
	 * Enabled with no windows is open never, which is indistinguishable from disabled at the wire and
	 * completely distinguishable in intent. Starting anyway would leave an operator watching a
	 * "currently not open" dialog on a server they believe they switched on.
	 */
	@Test
	public void rejectsEnabledWithNoWindows() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_ENABLED", "true")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("open never");
	}

	/**
	 * Slot-in is parked as a future project, so the mode that does nothing else must refuse to start.
	 * <p>
	 * The tick only runs its passes when {@code forms()} is true and no slot-in pass exists, so
	 * accepting this mode would produce a server that queues searchers and never matches anyone, with
	 * nothing in the log to explain it. Refusing at startup is the loud version of the same fact —
	 * and unlike the earlier "you also need SLOT_IN_LOBBIES" rule, no configuration rescues it.
	 */
	@Test
	public void refusesSlotInOnlyBecauseItIsNotImplemented() {
		assertThatThrownBy(() -> of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00",
			"MGO2SERVER_AUTOMATCH_MODE", "SLOT_IN_ONLY")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("not implemented");

		// Naming lobbies does not rescue it — the pass itself is missing, not its input.
		assertThatThrownBy(() -> of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00",
			"MGO2SERVER_AUTOMATCH_MODE", "SLOT_IN_ONLY",
			"MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES", "2, 3")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("not implemented");

		// The setting still parses, so reviving slot-in needs no config work.
		var parsed = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "true",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-23:00",
			"MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES", "2, 3"));
		assertThat(parsed.slotInLobbies()).containsExactlyInAnyOrder(2L, 3L);
	}

	/**
	 * The validation only fires for a server that is actually going to answer. A half-written config
	 * left behind {@code ENABLED=false} must not stop the process from starting, or every other lobby
	 * goes down with it.
	 */
	@Test
	public void aDisabledPolicyIsNeverValidated() {
		var policy = of(Map.of("MGO2SERVER_AUTOMATCH_MODE", "SLOT_IN_ONLY"));

		assertThat(policy.enabled()).isFalse();
		assertThat(openAt(policy, "22:00")).isFalse();
	}

	/**
	 * Every one of these is a typo that would otherwise become a schedule nobody notices is wrong.
	 * A window is silently ignorable in a way a cooldown is not — nothing renders it, and the only
	 * symptom is a dialog at the wrong hour — so each has to name what it could not read.
	 */
	@Test
	public void rejectsMalformedWindows() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_WINDOWS", "20:00 to 23:00")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("is not a range");

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_WINDOWS", "8pm-11pm")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("bad time");

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_WINDOWS", "20:00-25:00")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("bad time");
	}

	/** A zone id typo would otherwise silently fall back to the container's UTC. */
	@Test
	public void rejectsAnUnknownZone() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_TIMEZONE", "America/New York")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("not a known zone id");
	}

	/** One player is not a match, and a tick of zero is a busy loop. Both are typos, not settings. */
	@Test
	public void rejectsDegenerateNumbers() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_MIN_PLAYERS", "1")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("at least 2");

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_TICK_SECONDS", "0")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("at least 1 second");

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES", "2, training")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("comma-separated lobby ids");
	}

	/**
	 * Same reasoning as {@code PolicyTest.blankFallsBackToTheDefaultRatherThanZero}: a compose
	 * env_file line with nothing after the {@code =} arrives as an empty string, and must mean "use
	 * the default" rather than an unparseable value that stops the server.
	 */
	@Test
	public void blankValuesFallBackToTheDefaults() {
		var policy = of(Map.of(
			"MGO2SERVER_AUTOMATCH_ENABLED", "",
			"MGO2SERVER_AUTOMATCH_WINDOWS", "",
			"MGO2SERVER_AUTOMATCH_TIMEZONE", "",
			"MGO2SERVER_AUTOMATCH_MODE", "",
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS", "",
			"MGO2SERVER_AUTOMATCH_TICK_SECONDS", "",
			"MGO2SERVER_AUTOMATCH_SLOT_IN_LOBBIES", ""));

		assertThat(policy.enabled()).isFalse();
		assertThat(policy.windows()).isEmpty();
		assertThat(policy.zone()).isEqualTo(ZoneId.of("UTC"));
		assertThat(policy.mode()).isEqualTo(Mode.BOTH);
		assertThat(policy.minPlayers()).isEqualTo(2);
		assertThat(policy.tick()).isEqualTo(Duration.ofSeconds(5));
		assertThat(policy.slotInLobbies()).isEmpty();
	}

	/** {@code 1} and {@code 0} are what an operator writes for a flag as often as the words. */
	@Test
	public void enabledAcceptsBothSpellings() {
		var windows = "MGO2SERVER_AUTOMATCH_WINDOWS";
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_ENABLED", "1", windows, "20:00-23:00")).enabled())
			.isTrue();
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_ENABLED", "TRUE", windows, "20:00-23:00")).enabled())
			.isTrue();
		assertThat(of(Map.of("MGO2SERVER_AUTOMATCH_ENABLED", "0")).enabled()).isFalse();

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_AUTOMATCH_ENABLED", "yes")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("must be true or false");
	}
}
