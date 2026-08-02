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

	/**
	 * {@code 0x43f1}: 19 bytes of scalars then the 204-byte settings block.
	 * <p>
	 * Goes to the <b>whole group</b>, not just the elected host. Every recipient compares the leading
	 * id against its own ({@code 0xD5B7F4}); the one that matches goes to state 12 and creates the
	 * game, everyone else parks at state 18 and waits for {@link #MATCH_GAME}.
	 *
	 * @param hostCharaId the elected host's character id — the id we send at {@code 0x4101 + 0x00}
	 * @param lobbyId this lobby's id, which the four sibling parsers all fill from the lobby object
	 * @param lobbySubtype likewise. 2 here, and the same field as {@code 0x4310}'s byte at `0xA2`
	 * @param rule the rule at rotation entry 0 — see the byte's comment below
	 * @param settings exactly {@link AutomatchSettingsBlock#SIZE} bytes
	 */
	public static void writeMatchFound(ByteBuf buffer, long hostCharaId, long lobbyId,
			int lobbySubtype, int rule, byte[] settings) {
		buffer.writeInt((int) hostCharaId);
		buffer.writeInt((int) lobbyId);
		buffer.writeByte(lobbySubtype);
		// The RULE ID. Was hardcoded 0 with "meaning not established" until 2026-08-01, which meant
		// we announced Deathmatch regardless of what the group had actually been matched into.
		//
		// The three bytes before this one are not three unrelated fields: the five parsers that
		// fill the automatch object at session+0x11558 copy `lwz 604` / `lbz 608` / `lbz 609` off
		// one base register as a straight-line block, and that base is the team record from
		// 0xD491F8. So this byte is team+0x261, the sibling of the lobby id at +0x25C and the
		// subtype at +0x260 -- and team+0x261 is read as a rule at four sites, each doing
		// `lbz r3,609` then `rlwinm r3,r3,1,23,30` then strres(0x654515, 2*rule). Same enum as
		// 0x4310's rotation rule. lobbyId and lobbySubtype above are accepted on exactly this
		// evidence; this byte rides the same block.
		//
		// Note the doc calls the source "lobbyObj". It is the team record, not a lobby object.
		//
		// It is not a VISIBLE defect today: amObj+0x09's two readers both store to app+0x295,
		// whose onward copy at +0x2C9 is stored five times and loaded zero times, and the 0x49A0
		// sender explicitly re-zeroes +0x261 before building its packet. Nothing branches on it.
		// It is fixed anyway because it is a wrong value in a currently-served feature, the fix is
		// one byte, and 0x8C53FC is a hand-rolled struct copy -- anything that later reads
		// app+0x295 would inherit a bogus "Deathmatch".
		buffer.writeByte(rule);
		// Both zeroed by every sibling writer in the binary, so zero is the read value, not a guess.
		buffer.writeInt(0);
		buffer.writeInt(0);
		// The rotation index. ALWAYS 0: the client copies entry idx into entry 0 without clearing
		// entry idx (0x93D3BC), so any other value makes that rule play twice per cycle. We put the
		// elected rules at entry 0 upward ourselves instead.
		buffer.writeByte(0);
		AutomatchSettingsBlock.write(buffer, settings);
	}

	/** Bytes in {@code 0x43f1}: the scalars plus the block. */
	public static final int MATCH_FOUND_SIZE = 19 + AutomatchSettingsBlock.SIZE;

	/**
	 * {@code 0x43f2}: the game id, which releases the joiners.
	 * <p>
	 * Sent to the <b>whole group including the host</b>. The client's 4945 path proves the host's
	 * handler expects it, and the failure is asymmetric: a spurious push to a host who has already
	 * left the screen is dropped, while omitting it risks the host parking forever.
	 * <p>
	 * <b>One-shot.</b> Processing this unregisters the client's push channel ({@code 0x93DDA0}), so
	 * nothing can reach that client afterwards — {@link #MATCH_FAILED} is only useful before it.
	 */
	public static void writeMatchGame(ByteBuf buffer, long gameId) {
		buffer.writeInt((int) gameId);
	}

	/**
	 * {@code 0x43f3}: the elected host could not create the game.
	 * <p>
	 * Raises error 4945, <em>"The host was unable to create game for automatching"</em> — the
	 * sentence Konami shipped for exactly this. Its u32 is echoed into the dialog's detail code.
	 */
	public static void writeMatchFailed(ByteBuf buffer, int detail) {
		buffer.writeInt(detail);
	}

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
