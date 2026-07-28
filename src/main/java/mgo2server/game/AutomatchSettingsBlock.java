package mgo2server.game;

import io.netty.buffer.ByteBuf;

import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/**
 * The 204-byte settings block carried inside {@code 0x43f1}.
 *
 * <h2>This is not a message, it is the host's settings</h2>
 * The block lands at {@code +752} of a 968-byte struct that the elected host hands straight to the
 * create-game task, whose {@code 0x4310} builder ({@code 0xD446C8}) reads <b>nothing else</b> and
 * performs no numeric validation at all. Every field here becomes the created game, and a zero here
 * is a zero in the match — zero players, zero briefing, zero round time. See
 * {@code dev/docs/AUTOMATCH.md} §3.
 *
 * <h2>Where the numbers come from, and which are placeholders</h2>
 * Three tiers, and the code keeps them apart on purpose:
 *
 * <ol>
 * <li><b>Observed retail values</b> — {@link #AUTOMATCH_TIMERS}. Captured from recordings of real
 * Konami-era automatch games. Two rules only.</li>
 * <li><b>Client defaults</b> — {@link #DEFAULT_BLOCK}. Everything else. <b>These are
 * placeholders.</b> They are what a fresh character's own create-game screen offers, not what
 * automatching served.</li>
 * <li><b>Structure</b> — the field offsets and the rotation layout, read from the binary and
 * confirmed against stored captures. Not a placeholder; this part is known.</li>
 * </ol>
 *
 * <b>We know the placeholders are wrong.</b> Observed automatch ran TDM at 5/4/25 where the client
 * default is 3/4/15, and SNE at 7/4/3 where the default is 8/4/3. Neither could have come from a
 * host's saved settings or from the defaults, so the original server authored its own table — we
 * simply have only two rows of it. Every remaining rule is served a default because a known-wrong
 * fixed value beats an invented one, and because the difference is one line to fix per rule as soon
 * as a game of that rule is observed. DM, RES, CAP and BASE are the four still missing.
 */
public final class AutomatchSettingsBlock {

	/** The block's fixed size. */
	public static final int SIZE = 204;

	/** Rotation entries, matching the {@code 0x4310} writer's own loop bound. */
	public static final int ROTATION_ENTRIES = 16;

	private static final int RULES = 0;

	private static final int MAPS = 16;

	private static final int FLAGS = 32;

	/** The seventeen timer/count u32s. */
	private static final int TIMERS = 100;

	/**
	 * The SNAKE count for Sneaking: how many times Snake must be killed.
	 * <p>
	 * <b>Not in the timer array.</b> Sneaking shows three settings but has two slots there; this is
	 * the third. Our docs called this byte "sneaking Snake side" until 2026-07-28 — it reads 3 in
	 * every stored blob, which is the client's own default, and 3 is also what the observed automatch
	 * game ran.
	 */
	private static final int SNAKE = 189;

	/**
	 * Timer-array index of each rule's first slot, and how many slots it owns.
	 *
	 * <p><b>Confirmed, not inferred.</b> Two independent lines agree. The client scales exactly the
	 * eight <em>time</em> indices by 60 ({@code 0x8CA470}), giving a 2/2/2/3/2/2/2/2 shape; and four
	 * stored blobs from characters that had never edited a timer read {@code [0]=8 [1]=4} and
	 * {@code [6]=3 [7]=4 [8]=15}, matching the client's documented defaults for Sneaking (8/4) and
	 * Team Deathmatch (3/4/15) at exactly these indices.
	 */
	private static final Map<Integer, int[]> RULE_TIMERS = Map.of(
		0, new int[] {9, 2},    // Deathmatch      — time, tickets (no rounds slot)
		1, new int[] {6, 3},    // Team Deathmatch — time, rounds, tickets
		2, new int[] {4, 2},    // Rescue          — time, rounds
		3, new int[] {2, 2},    // Capture         — time, rounds
		4, new int[] {0, 2},    // Sneaking        — time, rounds (+ SNAKE, above)
		5, new int[] {11, 2},   // Base            — time, rounds
		6, new int[] {13, 2},   // Bomb            — time, rounds. Not served
		7, new int[] {15, 2});  // Team Sneaking   — time, rounds. Not served

	/**
	 * Values a real automatch game was observed to use, by rule id: the slots of
	 * {@link #RULE_TIMERS} in order.
	 *
	 * <p><b>Tier 2-3</b> — observed from recordings of the retail service, not read from our
	 * artifacts. Each entry replaces a client default that is known to be wrong.
	 */
	private static final Map<Integer, int[]> AUTOMATCH_TIMERS = Map.of(
		1, new int[] {5, 4, 25},   // TDM: 5 min, 4 rounds, 25 tickets (default is 3/4/15)
		4, new int[] {7, 4});      // SNE: 7 min, 4 rounds            (default is 8/4)

	/**
	 * A settings block as a fresh character's client offers it, captured from a stored
	 * {@code 0x4310} on a character that had never edited its timers.
	 *
	 * <p><b>Placeholder for every field the observed table does not cover.</b> Three such captures
	 * were byte-identical across the whole timer array and differed only in rotation entry 0 and two
	 * unidentified bytes, so this is the client's default rather than one player's taste. The
	 * rotation in it is overwritten on every build.
	 *
	 * <p>Notable values it carries: max players 16 (block 66), briefing 2 (block 68), SNAKE 3
	 * (block 189), and the full default timer table.
	 */
	private static final byte[] DEFAULT_BLOCK = HexFormat.of().parseHex(
		"0400000000000000000000000000000007000000000000000000000000000000"
			+ "0000000000000000000000000000000000000000000000000000000000000000"
			+ "0000100000000002020000000000000000000000000000000000000000000016"
			+ "0000000000000008000000040000000400000004000000040000000400000003"
			+ "000000040000000f000000050000001e00000005000000040000001e00000004"
			+ "0000000a00000004000100000000000000240020000000030000000000030000"
			+ "000000000000000000000000");

	private AutomatchSettingsBlock() {
	}

	/**
	 * Builds the block for a match.
	 *
	 * <p>The rotation carries <b>one entry per distinct rule the group asked for</b>, contiguous from
	 * index 0. That shape is observed, not assumed: a real automatch session whose searchers had
	 * requested TDM, SNE and BASE ran a rotation of all three. The accompanying {@code 0x43f1}
	 * rotation index must be <b>0</b> — the client copies entry {@code idx} into entry 0 without
	 * clearing entry {@code idx} ({@code 0x93D3BC}), so any other index makes that rule play twice
	 * per cycle.
	 *
	 * <p>{@code flags} is left 0 for every entry. That byte is the per-rule "rule option", whitelisted
	 * by the disc's {@code ruleopt_bit} to {@code {0,2}} for most rules and {@code {0}} for Sneaking
	 * and Team Sneaking, so 0 is the one value legal everywhere.
	 *
	 * @param rules the distinct rules the group requested, in the order they should rotate. Must be
	 *     non-empty and no larger than {@link #ROTATION_ENTRIES}
	 * @param map the map to run. <b>Must be nonzero</b> — the client discards a rotation entry with a
	 *     zero map. The release-day pool is {@code {2,3,4,7,12}}
	 */
	public static byte[] build(Set<Integer> rules, int map) {
		if (rules.isEmpty()) {
			throw new IllegalArgumentException("An automatch rotation needs at least one rule.");
		}
		if (rules.size() > ROTATION_ENTRIES) {
			throw new IllegalArgumentException("At most " + ROTATION_ENTRIES + " rotation entries, got "
				+ rules.size());
		}
		if (map == 0) {
			throw new IllegalArgumentException("Automatch map must not be 0: the client discards a "
				+ "rotation entry with a zero map and silently falls back to entry 0.");
		}

		var block = DEFAULT_BLOCK.clone();

		// Wipe the captured rotation before writing ours: the client's own blob-save loop stops at the
		// first zero map, so a leftover entry beyond ours would still be part of the cycle.
		for (var entry = 0; entry < ROTATION_ENTRIES; entry++) {
			block[RULES + entry] = 0;
			block[MAPS + entry] = 0;
			block[FLAGS + entry] = 0;
		}

		var entry = 0;
		for (var rule : new LinkedHashSet<>(rules)) {
			block[RULES + entry] = (byte) (int) rule;
			block[MAPS + entry] = (byte) map;
			block[FLAGS + entry] = 0;
			applyObservedTimers(block, rule);
			entry++;
		}
		return block;
	}

	/**
	 * Replaces a rule's client defaults with the values a real automatch game was seen to use.
	 * Silently leaves the defaults in place for rules nobody has captured yet — which is the whole
	 * placeholder story, and why {@link #AUTOMATCH_TIMERS} is the file's one place to edit.
	 */
	private static void applyObservedTimers(byte[] block, int rule) {
		var observed = AUTOMATCH_TIMERS.get(rule);
		var slots = RULE_TIMERS.get(rule);
		if (observed == null || slots == null) {
			return;
		}
		for (var i = 0; i < observed.length && i < slots[1]; i++) {
			writeTimer(block, slots[0] + i, observed[i]);
		}
	}

	private static void writeTimer(byte[] block, int index, int value) {
		var at = TIMERS + index * 4;
		block[at] = (byte) (value >>> 24);
		block[at + 1] = (byte) (value >>> 16);
		block[at + 2] = (byte) (value >>> 8);
		block[at + 3] = (byte) value;
	}

	/** The SNAKE count this block carries, for tests and logging. */
	public static int snakeCount(byte[] block) {
		return block[SNAKE] & 0xFF;
	}

	/** Reads a timer slot, for tests and logging. */
	public static int timer(byte[] block, int index) {
		var at = TIMERS + index * 4;
		return ((block[at] & 0xFF) << 24) | ((block[at + 1] & 0xFF) << 16)
			| ((block[at + 2] & 0xFF) << 8) | (block[at + 3] & 0xFF);
	}

	/** Writes a block built by {@link #build}. */
	public static void write(ByteBuf buffer, byte[] block) {
		if (block.length != SIZE) {
			throw new IllegalArgumentException("Settings block must be exactly " + SIZE
				+ " bytes, got " + block.length);
		}
		buffer.writeBytes(block);
	}
}
