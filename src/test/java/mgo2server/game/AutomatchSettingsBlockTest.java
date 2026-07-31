package mgo2server.game;

import org.junit.jupiter.api.Test;

import java.util.HexFormat;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pins the composed settings block against the capture it replaced.
 *
 * <p>{@link AutomatchSettingsBlock} used to hold a 204-byte hex constant — a real {@code 0x4310}
 * from a fresh character — which it cloned and patched in four places. Roughly 150 bytes therefore
 * went out as one player's client defaults with nothing saying what they were. The block is now
 * composed field by field from the map in {@code dev/proto/outbound/mgo2_cmd_43f1_s2c.ksy} and
 * {@code dev/proto/inbound/mgo2_cmd_4310_c2s.ksy}.
 *
 * <p><b>The point of this test is that nothing on the wire changed.</b> The capture is kept here as
 * a fixture and the composed output is compared against it byte for byte, so the refactor is
 * provably a change of provenance rather than of behaviour. It also means that if someone later
 * edits a named field, this test fails and makes them say so deliberately.
 */
public class AutomatchSettingsBlockTest {

	/**
	 * The original constant, verbatim. Three captures from characters that had never edited a timer
	 * were byte-identical across the whole timer array and differed only in rotation entry 0, which
	 * is why this is the client's default rather than one player's taste.
	 */
	private static final byte[] CAPTURED = HexFormat.of().parseHex(
		"0407000000000000000000000000000000000000000000000000000000000000"
			+ "0000000000000000000000000000000000000000000000000000000000000000"
			+ "0000100000000002020000000000000000000000000000000000000000000016"
			+ "0000000000000008000000040000000400000004000000040000000400000003"
			+ "000000040000000f000000050000001e00000005000000040000001e00000004"
			+ "0000000a00000004000100000000000000240020000000030000000000030000"
			+ "000000000000000000000000");

	/**
	 * Everything outside the rotation and the four patched fields matches the capture exactly.
	 *
	 * <p>Compared with the rotation excluded because {@code build} deliberately overwrites it, and
	 * with the four fields the builder owns excluded because changing them is the whole purpose of
	 * the class: current players, and — for the rules requested here — the observed TDM timers and
	 * the SNAKE count.
	 */
	@Test
	public void composedBlockMatchesTheCaptureItReplaced() {
		// Rescue only (rule 2): still has no entry in AUTOMATCH_TIMERS, so no timer is overridden
		// and the comparison covers the entire timer array. This was Deathmatch until 2026-07-30,
		// when DM's observed values arrived and rule 0 stopped being an untouched case.
		var built = AutomatchSettingsBlock.build(Set.of(2), 2);

		assertThat(built).hasSize(AutomatchSettingsBlock.SIZE);

		for (var offset = 48; offset < AutomatchSettingsBlock.SIZE; offset++) {
			if (offset == 67) {
				// Current players — the one field the builder must change. The capture carries 0,
				// which the client's own validator at 0x883FB4 rejects.
				continue;
			}
			assertThat(built[offset])
				.as("block offset %d must match the captured client default", offset)
				.isEqualTo(CAPTURED[offset]);
		}
	}

	/** The two fields we still inherit without understanding are emitted exactly as captured. */
	@Test
	public void theTwoUnexplainedFieldsAreUnchanged() {
		var built = AutomatchSettingsBlock.build(Set.of(0), 2);

		assertThat(new byte[] {built[72], built[73], built[74], built[75]})
			.as("+72 is [UNKNOWN] in both schemas and non-zero in every capture")
			.containsExactly(CAPTURED[72], CAPTURED[73], CAPTURED[74], CAPTURED[75]);
		assertThat(built[179])
			.as("+179 is [UNKNOWN] in both schemas and 0x20 in every capture")
			.isEqualTo(CAPTURED[179]);
	}

	/**
	 * Current players must be nonzero: the client's create-game validator at {@code 0x883FB4}
	 * rejects a zero, and the captured block carries one because a stored {@code 0x4310} cannot
	 * structurally hold this field.
	 */
	@Test
	public void currentPlayersIsOneRatherThanTheCapturedZero() {
		var built = AutomatchSettingsBlock.build(Set.of(0), 2);

		assertThat(CAPTURED[67]).as("the capture really does carry zero here").isZero();
		assertThat(built[67]).isEqualTo((byte) 1);
	}

	/**
	 * Deathmatch's observed automatch values, and the rounds slot it does not have.
	 * <p>
	 * Reported live as <b>1 round, 50 tickets, 10 minutes</b>. DM owns only indices 9 and 10 —
	 * time and tickets — because it is the one rule with no rounds slot in the 2/2/2/3/2/2/2/2
	 * layout. A rule fixed at one round is exactly the rule that needs no slot for it, so the
	 * report corroborates the index mapping rather than contradicting it.
	 */
	@Test
	public void deathmatchServesItsObservedTimersAndHasNoRoundsSlot() {
		var built = AutomatchSettingsBlock.build(Set.of(0), 2);

		assertThat(readU32(built, 100 + 9 * 4)).as("DM time, 10 min").isEqualTo(10);
		assertThat(readU32(built, 100 + 10 * 4)).as("DM tickets").isEqualTo(50);

		assertThat(readU32(CAPTURED, 100 + 9 * 4)).as("the client default really is 5").isEqualTo(5);
		assertThat(readU32(CAPTURED, 100 + 10 * 4)).as("and 30 tickets").isEqualTo(30);

		// Index 11 is BASE's time. If DM ever grew a third value it would land here and silently
		// corrupt another rule, so the boundary is asserted rather than assumed.
		assertThat(readU32(built, 100 + 11 * 4))
			.as("DM must not spill into BASE's slot")
			.isEqualTo(readU32(CAPTURED, 100 + 11 * 4));
	}

	/**
	 * The observed automatch timers override the client defaults, which is the one place the block
	 * is deliberately not the capture.
	 */
	@Test
	public void observedTimersReplaceTheClientDefaultsForTeamDeathmatch() {
		var built = AutomatchSettingsBlock.build(Set.of(1), 2);

		// TDM owns timer slots 6, 7 and 8: time, rounds, tickets. Observed 5/4/25 against the
		// client's default 3/4/15.
		assertThat(readU32(built, 100 + 6 * 4)).isEqualTo(5);
		assertThat(readU32(built, 100 + 7 * 4)).isEqualTo(4);
		assertThat(readU32(built, 100 + 8 * 4)).isEqualTo(25);

		assertThat(readU32(CAPTURED, 100 + 6 * 4)).as("the default really is 3").isEqualTo(3);
		assertThat(readU32(CAPTURED, 100 + 8 * 4)).as("the default really is 15").isEqualTo(15);
	}

	private static int readU32(byte[] block, int at) {
		return ((block[at] & 0xff) << 24) | ((block[at + 1] & 0xff) << 16)
			| ((block[at + 2] & 0xff) << 8) | (block[at + 3] & 0xff);
	}
}
