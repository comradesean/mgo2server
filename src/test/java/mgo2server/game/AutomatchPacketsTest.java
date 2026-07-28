package mgo2server.game;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The {@code 0x43e4} search panel, byte by byte — {@code AUTOMATCH.md} §3.
 *
 * <p>Every assertion here is <b>protocol</b>, read from the binary: the 36 bytes are the parser's
 * fixed read at {@code 0xD5BDCC}, the nibble order is {@code 0x93C6EC}/{@code 0x93C6F4}, the 23
 * columns are the draw loop's bound at {@code 0x93C790}, and the ceiling of 15 is the bar clamp at
 * {@code 0x93C754}–{@code 0x93C784}. None of it is our choice.
 *
 * <p>This is worth testing this closely because <b>the failure mode is silent</b>. {@code 0x43e4}
 * goes through the fire-and-forget event path {@code 0xD33CD8}, not the request-completion path, so
 * no value it can carry stalls the client, raises an error or changes control flow — a wrong byte
 * draws a wrong graph on somebody's television and nothing anywhere says so. The clamp cases are the
 * sharp end: two columns share a byte, so a count that overflows its nibble does not merely render
 * itself wrong, it <b>corrupts the neighbouring column</b>.
 */
public class AutomatchPacketsTest {

	/** Offsets from {@code AUTOMATCH.md} §3's layout table, named so the field-order test reads. */
	private static final int ARRAY_A = 0x00;

	private static final int BAND = 0x10;

	private static final int PLAYERS_NEEDED = 0x11;

	private static final int EVENT_ARG = 0x12;

	private static final int ARRAY_B = 0x13;

	private static final int TAIL = 0x23;

	private static ByteBuf panel(int[] matching, int[] inGame, int band, int playersNeeded) {
		var buffer = Unpooled.buffer(AutomatchPackets.SEARCH_PANEL_SIZE);
		AutomatchPackets.writeSearchPanel(buffer, matching, inGame, band, playersNeeded);
		return buffer;
	}

	/** {@code getUnsignedByte} returns a short, which makes every literal below need a cast. */
	private static int at(ByteBuf buffer, int index) {
		return buffer.getUnsignedByte(index);
	}

	private static int[] columns() {
		return new int[AutomatchPackets.COLUMNS];
	}

	private static int[] allOf(int value) {
		var columns = columns();
		Arrays.fill(columns, value);
		return columns;
	}

	/**
	 * A count per column that never repeats between neighbours and is never zero.
	 * <p>
	 * Twenty-three columns cannot all differ when the ceiling is 15, so the property actually
	 * available is the one that matters for packing: the two columns sharing a byte always differ, so
	 * a swapped nibble order is visible. Zero is excluded so a column that was never written at all
	 * fails rather than passing by accident.
	 */
	private static int[] ramp() {
		var columns = columns();
		for (var column = 0; column < columns.length; column++) {
			columns[column] = 1 + column % AutomatchPackets.MAX_COLUMN;
		}
		return columns;
	}

	/**
	 * The size is not a convention we chose — the parser at {@code 0xD5BDCC} reads a fixed 36 bytes,
	 * so one byte short leaves it reading the next packet's header as array B.
	 */
	@Test
	public void theSearchPanelIsExactlyThirtySixBytes() {
		assertThat(AutomatchPackets.SEARCH_PANEL_SIZE).isEqualTo(36);
		assertThat(panel(columns(), columns(), 0, 0).readableBytes()).isEqualTo(36);

		// Saturating every field cannot change the length either; the clamps write, they do not skip.
		assertThat(panel(allOf(99), allOf(99), 99, 999).readableBytes()).isEqualTo(36);
	}

	/**
	 * Column {@code 2j} in the <b>low</b> nibble of byte {@code j}, {@code 2j+1} in the high one.
	 * <p>
	 * Getting this backwards is not a subtle error — it transposes every pair of adjacent columns on
	 * the histogram — but nothing detects it, so it has to be pinned here.
	 */
	@Test
	public void columnsPackTwoPerByteLowNibbleFirst() {
		var expected = ramp();
		var buffer = panel(expected, columns(), 0, 0);

		for (var column = 0; column < AutomatchPackets.COLUMNS; column++) {
			var index = column / 2;
			var even = column % 2 == 0;
			var nibble = even ? at(buffer, index) & 0x0F : at(buffer, index) >> 4 & 0x0F;

			assertThat(nibble)
				.as("column %d, the %s nibble of byte %d", column, even ? "low" : "high", index)
				.isEqualTo(expected[column]);
		}
	}

	/**
	 * Column 22, the last one, and the only place the packing runs out mid-byte.
	 * <p>
	 * 23 is odd, so column 22 is even and lands in the low nibble of byte 11 with nothing above it.
	 * The high nibble there must stay zero: the client sums {@code A[i] + B[i]} per column and would
	 * happily draw a bar for a column 23 that does not exist if anything ever wrote it.
	 */
	@Test
	public void theLastColumnIsTheLowNibbleOfByteElevenAndNothingIsAboveIt() {
		var counts = columns();
		counts[AutomatchPackets.COLUMNS - 1] = AutomatchPackets.MAX_COLUMN;

		var buffer = panel(counts, columns(), 0, 0);

		assertThat(at(buffer, 11)).isEqualTo(0x0F);
		assertThat(at(buffer, 10)).as("column 22 must not have landed a byte early").isZero();
		assertThat(at(buffer, 12)).as("nor a byte late").isZero();
	}

	/**
	 * Bytes 12–15 of each array carry nothing — 23 columns fit in 12 bytes — but they are part of the
	 * fixed 36 and every field after them is read at a fixed offset, so they must be present and
	 * quiet. {@code AUTOMATCH.md} §11 lists them as written-but-never-read.
	 */
	@Test
	public void theLastFourBytesOfEachArrayAreZero() {
		// Both arrays saturated, so anything that could spill into the tail would have.
		var buffer = panel(allOf(AutomatchPackets.MAX_COLUMN), allOf(AutomatchPackets.MAX_COLUMN),
			AutomatchPackets.MAX_LEVEL, 0xFF);

		for (var offset = 12; offset < AutomatchPackets.ARRAY_BYTES; offset++) {
			assertThat(at(buffer, ARRAY_A + offset)).as("array A byte %d", offset).isZero();
			assertThat(at(buffer, ARRAY_B + offset)).as("array B byte %d", offset).isZero();
		}
	}

	/**
	 * <b>The important one.</b> A count above 15 must saturate inside its own nibble.
	 * <p>
	 * 99 is {@code 0x63}. Written without a clamp into the low nibble it puts a 6 into the high
	 * nibble as well, so an over-full column at level {@code n} silently invents population at level
	 * {@code n+1}. That is a wrong graph with no wrong value anywhere the eye can find it, which is
	 * why the ceiling is asserted from both sides of the byte.
	 */
	@Test
	public void aCountAboveFifteenSaturatesWithoutTouchingItsNeighbour() {
		var low = columns();
		low[0] = 99;
		assertThat(at(panel(low, columns(), 0, 0), 0))
			.as("column 0 saturated, column 1 still empty")
			.isEqualTo(0x0F);

		var high = columns();
		high[3] = 99;
		assertThat(at(panel(high, columns(), 0, 0), 1))
			.as("column 3 saturated, column 2 still empty")
			.isEqualTo(0xF0);

		// Every column over the ceiling at once: eleven full bytes and the half-byte of column 22.
		var all = panel(allOf(99), columns(), 0, 0);
		for (var index = 0; index < 11; index++) {
			assertThat(at(all, index)).as("byte %d", index).isEqualTo(0xFF);
		}
		assertThat(at(all, 11)).isEqualTo(0x0F);
	}

	/**
	 * A negative count is a bug upstream rather than something the panel can express, and the way it
	 * would fail is the same corruption as the over-count: {@code -1} is {@code 0xFF}, which fills
	 * both nibbles and so writes the neighbouring column too.
	 */
	@Test
	public void negativeCountsClampToZero() {
		var counts = columns();
		counts[0] = -1;
		counts[1] = 3;

		assertThat(at(panel(counts, columns(), 0, 0), 0))
			.as("column 0 empty, column 1 intact")
			.isEqualTo(0x30);

		var all = panel(allOf(-7), columns(), 0, 0);
		for (var index = 0; index < AutomatchPackets.ARRAY_BYTES; index++) {
			assertThat(at(all, index)).as("byte %d", index).isZero();
		}
	}

	/**
	 * The band is a level half-width, and the client clamps it to 0–22 itself ({@code 0x93C348}) — so
	 * this is not about crashing it, it is about the wire carrying what we meant. The field is one
	 * byte, so an unclamped 300 would arrive as 44 and light a window we never intended.
	 */
	@Test
	public void theBandClampsToTheLevelRange() {
		assertThat(at(panel(columns(), columns(), -1, 0), BAND)).isZero();
		assertThat(at(panel(columns(), columns(), 0, 0), BAND)).isZero();
		assertThat(at(panel(columns(), columns(), 11, 0), BAND)).isEqualTo(11);
		assertThat(at(panel(columns(), columns(), AutomatchPackets.MAX_LEVEL, 0), BAND))
			.isEqualTo(AutomatchPackets.MAX_LEVEL);
		assertThat(at(panel(columns(), columns(), 23, 0), BAND)).isEqualTo(AutomatchPackets.MAX_LEVEL);
		assertThat(at(panel(columns(), columns(), 300, 0), BAND)).isEqualTo(AutomatchPackets.MAX_LEVEL);
	}

	/**
	 * Players-needed is a single unsigned byte printed through disc string 917. Negative is the case
	 * worth clamping: it would arrive as a large positive count rather than as nothing.
	 */
	@Test
	public void playersNeededClampsToAnUnsignedByte() {
		assertThat(at(panel(columns(), columns(), 0, -1), PLAYERS_NEEDED)).isZero();
		assertThat(at(panel(columns(), columns(), 0, 3), PLAYERS_NEEDED)).isEqualTo(3);
		assertThat(at(panel(columns(), columns(), 0, 255), PLAYERS_NEEDED)).isEqualTo(255);
		assertThat(at(panel(columns(), columns(), 0, 300), PLAYERS_NEEDED)).isEqualTo(255);
	}

	/**
	 * Every field at the offset {@code 0xD5BDCC} reads it from, with values chosen so a field written
	 * one byte out lands somewhere this test is asserting zero.
	 * <p>
	 * The two never-read bytes are pinned at zero deliberately. {@code +0x12} is the event-42
	 * argument, discarded by the only handler registered for that event ({@code 0x93D760} overwrites
	 * the register before reading it), and {@code +0x23} is stored at the status block's {@code +4}
	 * and read nowhere in the binary. Both are unknowns, and zero is the value that stays honest if
	 * one of them ever turns out to mean something.
	 */
	@Test
	public void everyFieldIsAtTheOffsetTheParserReads() {
		var matching = columns();
		matching[0] = 1;
		var inGame = columns();
		inGame[1] = 2;

		var buffer = panel(matching, inGame, 5, 7);

		assertThat(at(buffer, ARRAY_A)).as("array A begins at 0x00").isEqualTo(0x01);
		assertThat(at(buffer, BAND)).isEqualTo(5);
		assertThat(at(buffer, PLAYERS_NEEDED)).isEqualTo(7);
		assertThat(at(buffer, EVENT_ARG)).isZero();
		assertThat(at(buffer, ARRAY_B)).as("array B begins at 0x13").isEqualTo(0x20);
		assertThat(at(buffer, TAIL)).isZero();

		// The arrays are 16 bytes each and do not overlap: everything else either array touched must
		// still be empty, which is what catches an array written at the wrong base.
		for (var offset = 1; offset < AutomatchPackets.ARRAY_BYTES; offset++) {
			assertThat(at(buffer, ARRAY_A + offset)).as("array A byte %d", offset).isZero();
			assertThat(at(buffer, ARRAY_B + offset)).as("array B byte %d", offset).isZero();
		}
	}
}
