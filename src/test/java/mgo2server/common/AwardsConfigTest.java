package mgo2server.common;

import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Two different kinds of assertion live here, and they are not equally authoritative.
 * <p>
 * The <b>bit range</b> is protocol: {@code MAX_TITLE_BIT} is a real client limit, since the title
 * screen's popcount loop runs 23 iterations over a 22-entry table and bit 22 corrupts the
 * scrollbar. The <b>thresholds</b> in {@code awards.json} are operator policy — nothing in the game
 * states one — so nothing here asserts a particular number. What is asserted is that the file is
 * well formed, that a hand-edit which breaks it says so at startup instead of silently awarding
 * nothing, and that the comparison operators point the way they read.
 */
public class AwardsConfigTest {

	/**
	 * The shipped file is loaded once at class initialisation of {@link AwardsConfig}, so a broken
	 * one takes the whole server down at startup. That makes this test the earliest warning
	 * available for an edit to {@code awards.json}.
	 */
	@Test
	public void theShippedRequirementsParse() {
		var config = AwardsConfig.load(AwardsConfig.RESOURCE);

		assertThat(config.titles()).isNotEmpty();
		assertThat(config.medals()).isNotEmpty();
		assertThat(config).isEqualTo(AwardsConfig.current());
	}

	/**
	 * Bit 22 and above are not a matter of taste: the client reads past its own title table. The
	 * uniqueness half matters just as much — two titles sharing a bit means unlocking either lights
	 * both, and the loader is the only place that can notice.
	 */
	@Test
	public void everyShippedTitleBitIsInRangeAndUsedOnce() {
		var bits = AwardsConfig.current().titles().stream().map(AwardsConfig.Title::bit).toList();

		assertThat(bits).allSatisfy(bit -> assertThat(bit).isBetween(0, AwardsConfig.MAX_TITLE_BIT));
		assertThat(bits).doesNotHaveDuplicates();
	}

	/** A title with no clauses is unlocked by everyone, including a character with no rounds. */
	@Test
	public void everyShippedTitleHasAtLeastOneClause() {
		assertThat(AwardsConfig.current().titles())
			.allSatisfy(title -> assertThat(title.requires())
				.as("title %s", title.name())
				.isNotEmpty());
	}

	@Test
	public void eachOperatorSymbolMapsToItsComparison() {
		assertThat(AwardsConfig.Op.of(">=", "test")).isEqualTo(AwardsConfig.Op.AT_LEAST);
		assertThat(AwardsConfig.Op.of(">", "test")).isEqualTo(AwardsConfig.Op.GREATER);
		assertThat(AwardsConfig.Op.of("<=", "test")).isEqualTo(AwardsConfig.Op.AT_MOST);
		assertThat(AwardsConfig.Op.of("<", "test")).isEqualTo(AwardsConfig.Op.LESS);

		assertThatThrownBy(() -> AwardsConfig.Op.of("=>", "somewhere"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("=>")
			.hasMessageContaining("somewhere");
	}

	/**
	 * The direction matters more than it looks. Four of the shipped titles are <b>negative</b> —
	 * SLOTH, CHICKEN, WATER BEAR and FOXHOUND's withdrawal clause all read {@code <=} — so an
	 * inverted comparison would not fail loudly, it would quietly award "Rarely participates in
	 * battle" to the most active players on the server and withhold it from the inactive ones. The
	 * {@code <=} cases below are the ones worth having; the boundary is included because every
	 * shipped threshold is written to be inclusive.
	 */
	@Test
	public void clausesCompareInTheDirectionTheyRead() {
		var atLeast = clause(AwardsConfig.Op.AT_LEAST, 1.50);
		assertThat(atLeast.test(1.49)).isFalse();
		assertThat(atLeast.test(1.50)).isTrue();
		assertThat(atLeast.test(1.51)).isTrue();

		var greater = clause(AwardsConfig.Op.GREATER, 1.50);
		assertThat(greater.test(1.50)).isFalse();
		assertThat(greater.test(1.51)).isTrue();

		// SLOTH's "simple_kd <= 0.85": a poor ratio qualifies and a good one must not.
		var atMost = clause(AwardsConfig.Op.AT_MOST, 0.85);
		assertThat(atMost.test(0.50)).isTrue();
		assertThat(atMost.test(0.85)).isTrue();
		assertThat(atMost.test(1.50)).isFalse();

		var less = clause(AwardsConfig.Op.LESS, 0.85);
		assertThat(less.test(0.85)).isFalse();
		assertThat(less.test(0.84)).isTrue();
	}

	/**
	 * The metric set is closed on purpose, so {@code awards.json} cannot define a computation. The
	 * point of failing here is that a typo names itself rather than evaluating to zero and quietly
	 * making the title unearnable.
	 */
	@Test
	public void anUnknownMetricNamesItself() {
		assertThatThrownBy(() -> AwardsConfig.load("awards-unknown-metric.json"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("kd_ration")
			.hasMessageContaining("TYPO");
	}

	/**
	 * Protocol, not tidiness. The client's title screen counts 23 bits out of a 22-entry table, so
	 * bit 22 over-counts the owned total and corrupts the scrollbar — a failed startup is the
	 * cheaper outcome.
	 */
	@Test
	public void aTitleBitPastTheClientsTableIsRejected() {
		assertThatThrownBy(() -> AwardsConfig.load("awards-bit-out-of-range.json"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("0..21")
			.hasMessageContaining("22");
	}

	/** Two titles on one bit: unlocking either would light both, and nothing downstream can tell. */
	@Test
	public void twoTitlesCannotShareABit() {
		assertThatThrownBy(() -> AwardsConfig.load("awards-duplicate-bit.json"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("SECOND")
			.hasMessageContaining("bit 7");
	}

	@Test
	public void aTitleWithNoRequirementsIsRejected() {
		assertThatThrownBy(() -> AwardsConfig.load("awards-no-clauses.json"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("FREEBIE")
			.hasMessageContaining("no requirements");
	}

	/**
	 * A missing file must name the resource. Falling back to an empty configuration would start a
	 * server that awards nothing and reports nothing, which looks exactly like a working one.
	 */
	@Test
	public void aMissingResourceNamesTheResource() {
		assertThatThrownBy(() -> AwardsConfig.load("awards-does-not-exist.json"))
			.isInstanceOf(NullPointerException.class)
			.hasMessageContaining("awards-does-not-exist.json");
	}

	private static AwardsConfig.Clause clause(AwardsConfig.Op op, double value) {
		return new AwardsConfig.Clause(AwardMetric.SIMPLE_KD, Set.of(), op, value);
	}
}
