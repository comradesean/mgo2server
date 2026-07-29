package mgo2server.common;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * These assert <b>operator policy</b>, not protocol. Nothing here is readable from the binary —
 * the client neither sends nor validates any of it — so these are regression guards on our own
 * defaults, not correctness checks against the game.
 */
public class PolicyTest {
	private static Policy of(Map<String, String> env) {
		return Policy.from(env::get);
	}

	/**
	 * The point of the file. They used to be written independently and the emblem one had drifted
	 * to an hour while its siblings were a week.
	 */
	@Test
	public void everyCooldownDefaultsToAWeek() {
		var policy = of(Map.of());

		assertThat(policy.characterDeleteCooldown()).isEqualTo(Duration.ofHours(168));
		assertThat(policy.clanDisbandCooldown()).isEqualTo(Duration.ofHours(168));
		assertThat(policy.clanEmblemCooldown()).isEqualTo(Duration.ofHours(168));
		assertThat(policy.clanJoinCooldown()).isEqualTo(Duration.ofHours(168));
	}

	@Test
	public void readsHoursFromTheEnvironment() {
		var policy = of(Map.of(
			"MGO2SERVER_CHARACTER_DELETE_COOLDOWN_HOURS", "24",
			"MGO2SERVER_CLAN_DISBAND_COOLDOWN_HOURS", " 1 ",
			"MGO2SERVER_CLAN_EMBLEM_COOLDOWN_HOURS", "720"));

		assertThat(policy.characterDeleteCooldown()).isEqualTo(Duration.ofHours(24));
		assertThat(policy.clanDisbandCooldown()).isEqualTo(Duration.ofHours(1));
		assertThat(policy.clanEmblemCooldown()).isEqualTo(Duration.ofHours(720));
	}

	/** Zero is a real setting — a test deployment wants no waiting at all — and not "unset". */
	@Test
	public void zeroDisablesTheWait() {
		assertThat(of(Map.of("MGO2SERVER_CLAN_EMBLEM_COOLDOWN_HOURS", "0")).clanEmblemCooldown())
			.isEqualTo(Duration.ZERO);
	}

	/**
	 * A blank value is what compose produces for an env_file line with nothing after the {@code =},
	 * which must mean "use the default" rather than "no cooldown". Getting this wrong would turn an
	 * empty line in server.env into a silently permissive server.
	 */
	@Test
	public void blankFallsBackToTheDefaultRatherThanZero() {
		assertThat(of(Map.of("MGO2SERVER_CHARACTER_DELETE_COOLDOWN_HOURS", "")).characterDeleteCooldown())
			.isEqualTo(Policy.DEFAULT_COOLDOWN);
	}

	/** A negative cooldown is a typo. Clamping it to zero would make a misconfiguration permissive. */
	@Test
	public void rejectsNegativeAndNonNumericValues() {
		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_CLAN_DISBAND_COOLDOWN_HOURS", "-1")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("must not be negative");

		assertThatThrownBy(() -> of(Map.of("MGO2SERVER_CLAN_DISBAND_COOLDOWN_HOURS", "a week")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("whole number of hours");
	}

	/** The version-bit experiment is off unless explicitly turned on. */
	@Test
	public void zeroUnreadFieldsIsOffUnlessAskedFor() {
		assertThat(of(Map.of()).zeroUnreadFields()).isFalse();
		assertThat(of(Map.of("MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS", "")).zeroUnreadFields())
			.isFalse();
		assertThat(of(Map.of("MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS", "no")).zeroUnreadFields())
			.isFalse();
		assertThat(of(Map.of("MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS", " TRUE ")).zeroUnreadFields())
			.as("trimmed and case-insensitive, so a stray space is not a silent no-op")
			.isTrue();
	}

}
