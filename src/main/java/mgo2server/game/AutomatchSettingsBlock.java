package mgo2server.game;

import io.netty.buffer.ByteBuf;

/**
 * The 204-byte settings block carried inside {@code 0x43f1}.
 *
 * <h2>This is not a message, it is the host's settings</h2>
 * The block lands at {@code +752} of a 968-byte struct that the elected host then hands straight to
 * the create-game task, and that task's {@code 0x4310} builder ({@code 0xD446C8}) reads <b>nothing
 * else</b> and validates nothing numeric. So every field here becomes the created game, and a zero
 * here is a zero in the match — zero players, zero briefing, zero round time. See
 * {@code dev/docs/AUTOMATCH.md} §3.
 *
 * <p>The shortcut that follows, and what this class implements: <b>serve the same 204 bytes you
 * would serve in a {@code 0x4313}</b>. It is the same structure at the same offsets, parsed by the
 * same reader ({@code 0xD4364C}), which is why the source can be an ordinary stored
 * {@code 0x4310} blob.
 *
 * <h2>Where the values come from — and the open question</h2>
 * We build the block from the <b>elected host's own saved host settings</b>, overriding only the
 * rotation so the match runs the rule the group searched for.
 *
 * <p><b>That is operator policy standing in for something we could not recover, not fidelity.</b>
 * The disc argues the original server owned these rules: automatching sits in the same family as
 * Tournament and Survival, and one of its four server notices reads <em>"Automatching rules have
 * been updated"</em> (string 499) — which is not a thing you announce if each match simply inherits
 * whatever the assigned host last configured. A search of community sources for the real rule set
 * found nothing; see {@code AUTOMATCH.md}. Using the host's settings gets a playable match with sane
 * timers rather than invented ones, and it is a single call to swap when the real values surface.
 */
public final class AutomatchSettingsBlock {

	/** The block's fixed size. */
	public static final int SIZE = 204;

	/** Rotation entries. Sixteen, matching the {@code 0x4310} writer's own loop bound. */
	public static final int ROTATION_ENTRIES = 16;

	// Block offsets. The rotation is three parallel arrays here, but three interleaved values per
	// entry on the 0x4310 wire — the one place the two layouts genuinely disagree.
	private static final int RULES = 0;

	private static final int MAPS = 16;

	private static final int FLAGS = 32;

	/**
	 * Where round 0's {@code [rule, map, flags]} triple starts in a stored {@code 0x4310} blob.
	 * Mirrors {@code HostGameController.ROTATION_OFFSET}; repeated rather than shared so this class
	 * does not depend on a controller.
	 */
	private static final int BLOB_ROTATION = 163;

	/**
	 * Field-for-field map from a {@code 0x4310} blob to this block: {@code {blobOffset, blockOffset,
	 * length}}.
	 *
	 * <p>Derived from the {@code 0x4310} builder's own put sequence, which is how the two layouts
	 * were reconciled: `163 + 182 = 345`, the known payload size, with **22 block bytes that
	 * {@code 0x4310} never carries** (blocks 67, 76–79, 82–83, 88–91, 170–176, 184–187). Those stay
	 * zero here, and must stay zero in our {@code 0x4313} too — on the host they reach the live game
	 * object from us, and on joiners only from that reply, so an inconsistency makes host and clients
	 * disagree about the same match.
	 */
	private static final int[][] FIELDS = {
		{0xD3, 48, 1},      // unidentified
		{0xD4, 49, 1},      // unidentified
		{0xD5, 50, 16},     // weapon restrictions
		{0xE5, 66, 1},      // max players
		{0xE6, 68, 4},      // briefing time
		{0xEA, 72, 4},      // unidentified u32
		{0xEE, 80, 2},      // unidentified u16
		{0xF0, 84, 4},      // unidentified u32
		{0xF4, 92, 2},      // unidentified u16
		{0xF6, 94, 1},      // stance
		{0xF7, 95, 1},      // level limit tolerance
		{0xF8, 96, 4},      // level limit base
		{0xFC, 100, 68},    // the seventeen timer/count u32s
		{0x140, 168, 2},    // unique characters, red and blue
		{0x142, 177, 2},    // commonA, commonB
		{0x144, 179, 1},    // unidentified
		{0x145, 180, 2},    // idle kick, u16
		{0x147, 182, 2},    // team-kill kick, u16
		{0x149, 188, 1},    // capture extra time
		{0x14A, 189, 1},    // sneaking: Snake's side
		{0x14B, 190, 14},   // byte timers and extra-time flags
	};

	/** The shortest blob that carries every mapped field. */
	public static final int MIN_BLOB = 0x14B + 14;

	private AutomatchSettingsBlock() {
	}

	/** Whether a stored blob is long enough to build a block from. */
	public static boolean canBuild(byte[] blob) {
		return blob != null && blob.length >= MIN_BLOB;
	}

	/**
	 * Builds the block from a stored {@code 0x4310} blob, with the elected rule and map forced into
	 * <b>rotation entry 0</b>.
	 *
	 * <p>Entry 0 specifically, and the accompanying {@code 0x43f1} rotation index must be 0, because
	 * of a client behaviour that is otherwise invisible: it copies entry {@code idx} into entry 0
	 * <em>without clearing entry {@code idx}</em> ({@code 0x93D3BC}–{@code 0x93D428}). Electing any
	 * other index therefore makes that rule play twice per cycle. Writing entry 0 ourselves sidesteps
	 * it entirely.
	 *
	 * <p>The remaining entries are truncated for the same family of reasons: the client's own
	 * blob-save loop stops at the first zero map ({@code 0x8CA254}), so a rotation must be contiguous
	 * from index 0, and an entry whose rule exceeds 10 triggers the fallback.
	 *
	 * @param blob the host's stored {@code 0x4310}, at least {@link #MIN_BLOB} bytes
	 * @param rule the rule the group searched for
	 * @param map the map to run it on. <b>Must be nonzero</b> — a zero map makes the client discard
	 *     the entry
	 */
	public static byte[] fromHostSettings(byte[] blob, int rule, int map) {
		if (!canBuild(blob)) {
			throw new IllegalArgumentException("0x4310 blob is " + (blob == null ? "absent"
				: blob.length + " bytes") + "; need at least " + MIN_BLOB);
		}
		if (map == 0) {
			throw new IllegalArgumentException("Automatch map must not be 0: the client discards a "
				+ "rotation entry with a zero map and silently falls back to entry 0.");
		}
		var block = new byte[SIZE];

		for (var field : FIELDS) {
			System.arraycopy(blob, field[0], block, field[1], field[2]);
		}

		// The rotation, de-interleaved: the wire carries 16 [rule, map, flags] triples, the block
		// carries three parallel arrays.
		for (var entry = 0; entry < ROTATION_ENTRIES; entry++) {
			var triple = BLOB_ROTATION + entry * 3;
			block[RULES + entry] = blob[triple];
			block[MAPS + entry] = blob[triple + 1];
			block[FLAGS + entry] = blob[triple + 2];
		}

		// The elected match goes in entry 0, and everything after it is dropped: a rotation the host
		// did not choose should not follow the one round automatching promised.
		block[RULES] = (byte) rule;
		block[MAPS] = (byte) map;
		for (var entry = 1; entry < ROTATION_ENTRIES; entry++) {
			block[RULES + entry] = 0;
			block[MAPS + entry] = 0;
			block[FLAGS + entry] = 0;
		}
		return block;
	}

	/** Writes a block built by {@link #fromHostSettings}. */
	public static void write(ByteBuf buffer, byte[] block) {
		if (block.length != SIZE) {
			throw new IllegalArgumentException("Settings block must be exactly " + SIZE
				+ " bytes, got " + block.length);
		}
		buffer.writeBytes(block);
	}
}
