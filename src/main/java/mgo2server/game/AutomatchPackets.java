package mgo2server.game;

import io.netty.buffer.ByteBuf;

/**
 * Writers for the automatch pushes — the server→client half of the feature.
 *
 * <p>All of these are <b>unsolicited</b>: they carry no result field, nothing waits on them, and
 * they only reach a client that has already been answered {@code 0x43e1} with result 0, because that
 * is what registers its push channel ({@code 0x93CF04}). Layouts are in
 * {@code dev/docs/AUTOMATCH.md} §3.
 */
public final class AutomatchPackets {

	/** The search panel. Event 42. */
	public static final int SEARCH_PANEL = 0x43e4;

	/** The match announcement: host character id plus the settings block. Event 44. */
	public static final int MATCH_FOUND = 0x43f1;

	/** The game id, which releases the joiners. Event 45. */
	public static final int MATCH_GAME = 0x43f2;

	/** Host failed to create. Event 46 ⇒ error 4945. */
	public static final int MATCH_FAILED = 0x43f3;

	/** Automatching closed under a searcher. Event 47 ⇒ error 4929. */
	public static final int AUTOMATCH_CLOSED = 0x43f4;

	/** {@code 0x43e4} is a fixed 36 bytes: two 16-byte arrays and four scalars. */
	public static final int SEARCH_PANEL_SIZE = 36;

	/**
	 * Columns in the level histogram, one per level 0–22 inclusive.
	 * <p>
	 * Confirmed four independent ways: the draw loop's bound at {@code 0x93C790}, and four 23-entry
	 * sprite-name hash tables at {@code 0xE14BA0 + 128/220/312/404}.
	 */
	public static final int COLUMNS = 23;

	/**
	 * Bytes each histogram array occupies on the wire. Only {@code ceil(23/2) = 12} carry data; the
	 * client never reads the last four, but they are part of the fixed 36 and must be present or
	 * every field after them is parsed from the wrong offset.
	 */
	public static final int ARRAY_BYTES = 16;

	/**
	 * The largest value a column can show. The bar is {@code (A[i] + B[i]) * 64} pixels clamped to
	 * 960 ({@code 0x93C754}–{@code 0x93C784}), so 15 is both the nibble ceiling and the draw ceiling.
	 */
	public static final int MAX_COLUMN = 15;

	/** The band and the centre column are both clamped to this by the client ({@code 0x93C348}). */
	public static final int MAX_LEVEL = 22;

	private AutomatchPackets() {
	}

	/**
	 * The search panel: a population histogram by player level, plus the search band and the number
	 * of players still needed.
	 *
	 * <p><b>This can never stall the client.</b> It goes through the fire-and-forget event path
	 * ({@code 0xD33CD8}) rather than the request-status completion path that {@code 0x43e1} and
	 * {@code 0x43e3} use, so nothing waits on it, no value it can carry changes control flow, and an
	 * all-zero payload simply renders a flat graph. That makes it the safest possible place to find
	 * out whether pushing works at all.
	 *
	 * @param matching per-level counts for one series, indexed by level 0–22
	 * @param inGame per-level counts for the other series
	 * @param band the level half-width the search spans; the client lights columns
	 *     {@code [myLevel - band, myLevel + band]} around a centre it computes itself
	 * @param playersNeeded printed through disc string 917 when nonzero; zero selects the
	 *     placeholder string 48, so zero reads as "no figure" rather than "zero more players"
	 */
	public static void writeSearchPanel(ByteBuf buffer, int[] matching, int[] inGame, int band,
			int playersNeeded) {
		writeColumns(buffer, matching);
		buffer.writeByte(Math.min(Math.max(band, 0), MAX_LEVEL));
		buffer.writeByte(Math.min(Math.max(playersNeeded, 0), 0xFF));
		// The event-42 argument. The only handler registered for that event overwrites the register
		// holding it before reading it (0x93D760), so its value cannot matter.
		buffer.writeByte(0);
		writeColumns(buffer, inGame);
		// Stored at the status block's +4 and never read anywhere in the binary.
		buffer.writeByte(0);
	}

	/**
	 * Packs 23 column counts into 16 bytes, two per byte.
	 *
	 * <p>Byte {@code j} holds column {@code 2j} in the <b>low</b> nibble and {@code 2j+1} in the
	 * high nibble ({@code 0x93C6EC}, {@code 0x93C6F4}). Column 22 is even, so it lands in the low
	 * nibble of byte 11 and the high nibble there is unused, as are bytes 12–15.
	 */
	private static void writeColumns(ByteBuf buffer, int[] columns) {
		var packed = new byte[ARRAY_BYTES];
		for (var column = 0; column < COLUMNS; column++) {
			var value = Math.min(Math.max(columns[column], 0), MAX_COLUMN);
			var index = column / 2;
			packed[index] |= (byte) (column % 2 == 0 ? value : value << 4);
		}
		buffer.writeBytes(packed);
	}
}
