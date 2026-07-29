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
 * <li><b>Observed retail values</b> — {@link #AUTOMATCH_TIMERS} and {@link #AUTOMATCH_SNAKE}.
 * Captured from recordings of real Konami-era automatch games. Two rules only.</li>
 * <li><b>Client defaults</b> — {@link #DEFAULT_BLOCK}. Everything else. <b>These are
 * placeholders.</b> They are what a fresh character's own create-game screen offers, not what
 * automatching served.</li>
 * <li><b>Structure</b> — the field offsets and the rotation layout, read from the binary and
 * confirmed against stored captures. Not a placeholder; this part is known.</li>
 * </ol>
 *
 * <p>One field is neither: {@link #CURRENT_PLAYERS} at block 67 is <b>required to be nonzero</b> by
 * a client-side validator, so it is set deliberately rather than inherited. The other five bytes
 * {@code 0x4310} cannot carry (82, 88, 170, 172, 184) have <b>no reader anywhere in the client</b>
 * and stay zero — a full-width scan found no live consumer of any of them.</p>
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

	/**
	 * The rotation occupies the block's first 48 bytes as <b>16 interleaved
	 * {@code [rule, map, flags]} triples</b> — not three parallel arrays.
	 *
	 * <p>This cost an evening. The client's <em>in-memory</em> form is parallel: the shared reader
	 * {@code 0xD4364C} scatters the stream into {@code rules[16]} at +0, {@code maps[16]} at +16 and
	 * {@code flags[16]} at +32 ({@code 0xD43678}–{@code 0xD436E4}). But the read primitive is a
	 * strictly sequential byte stream, so the <b>wire</b> order is the call order — rule0, map0,
	 * flags0, rule1, map1, flags1, and so on. The {@code 0x4310} builder emits the same interleaved
	 * order at wire {@code 0xA3}, so the convention is symmetric.
	 *
	 * <p>Writing the parallel form onto the wire produced a rotation the client de-interleaved into
	 * nonsense: two requested modes came out as one entry with a map id of 1 — a stage that does not
	 * exist on the disc, whose five maps are {@code {2,3,4,7,12}} — and a second entry with map 0,
	 * which terminates every loop that walks the rotation. That is one mode in the "Rules:" popup and
	 * a black loading screen, both from the same mistake.
	 */
	private static final int ROTATION = 0;

	/** Bytes per rotation entry: rule, map, flags. */
	private static final int ENTRY = 3;

	/** The seventeen timer/count u32s. */
	private static final int TIMERS = 100;

	/**
	 * Current player count — and <b>zero is invalid</b>, which is the one thing in this block that is
	 * not a matter of taste.
	 * <p>
	 * The client validates its game object at {@code 0x883FB4} and fails if <em>any</em> of game id
	 * ({@code +0}), game name ({@code +4}), roster[0] character id ({@code +176}), roster[0] name
	 * ({@code +180}), {@code maps[0]} ({@code +768}) or this byte ({@code +819}) is zero. Failure
	 * raises message <b>2831, "Unable to acquire host information."</b>
	 * <p>
	 * The byte has <b>no writer anywhere in the client</b> — it is purely server-supplied — and our
	 * default block came from a captured {@code 0x4310}, which structurally cannot carry it. So it
	 * was going out as zero.
	 * <p>
	 * We send <b>1</b>: at the moment the elected host creates the game, the host is the only player
	 * in it. The joiners arrive afterwards through the ordinary join path, which maintains the real
	 * roster.
	 */
	private static final int CURRENT_PLAYERS = 67;

	/** The host, and only the host, is in the game when it is created. */
	private static final int PLAYERS_AT_CREATE = 1;

	/**
	 * The SNAKE count for Sneaking: how many times Snake must be killed.
	 * <p>
	 * <b>Not in the timer array.</b> Sneaking shows three settings but has two slots there; this is
	 * the third. Our docs called this byte "sneaking Snake side" until 2026-07-28 — it reads 3 in
	 * every stored blob, which is the client's own default, and 3 is also what the observed automatch
	 * game ran.
	 */
	private static final int SNAKE = 189;

	/** Sneaking Mission. The one rule whose third setting lives outside the timer array. */
	private static final int RULE_SNEAKING = 4;

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
	 * Sneaking's third observed value: SNAKE 3, the number of times Snake must be killed.
	 *
	 * <p>Written explicitly even though it is <b>identical to the client default</b> already sitting
	 * in {@link #DEFAULT_BLOCK}. The emitted bytes do not change; the provenance does. Left implicit,
	 * an observed figure would be indistinguishable from a placeholder, and regenerating the default
	 * block from a different capture would silently drop a value we actually confirmed. It lives here
	 * rather than in {@link #AUTOMATCH_TIMERS} because it is not in the timer array at all — see
	 * {@link #SNAKE}.
	 */
	private static final int AUTOMATCH_SNAKE = 3;

	/**
	 * The block, composed field by field.
	 *
	 * <p><b>This replaces a 204-byte captured hex constant</b> that was cloned and patched in four
	 * places, so roughly 150 bytes went out as one player's client defaults with no statement of what
	 * they were. Decoding that capture against the schemas
	 * ({@code dev/proto/outbound/mgo2_cmd_43f1_s2c.ksy} and {@code inbound/mgo2_cmd_4310_c2s.ksy},
	 * which describe the same struct) showed the alarming part was an illusion: <b>almost the entire
	 * block is zero</b>. Every non-zero byte in it is either a field the schemas name, or one of the
	 * two exceptions called out below.
	 *
	 * <p>The emitted bytes are unchanged — {@code AutomatchSettingsBlockTest} pins the output against
	 * the original capture. What changed is that nothing is inherited without saying so.
	 */
	private static byte[] template() {
		var block = new byte[SIZE];

		// The rotation (0..47) stays zero here; build() writes it. A zero map terminates every walk,
		// so an unwritten rotation is inert rather than wrong.

		// Weapon restrictions (50..65) are zero: no weapon is barred. [CONFIRMED in 0x4310] — a
		// bitfield, and all-zero is the permissive value rather than a placeholder.

		block[MAX_PLAYERS] = (byte) MAX_PLAYERS_VALUE;
		putU32(block, BRIEFING_TIME, BRIEFING_SECONDS);

		// Level limits: base 0 with tolerance at the level cap, i.e. no restriction. The gate at
		// 0x8BA560 admits a player when base - tolerance <= level <= base + tolerance, and these are
		// in LEVEL units, not experience.
		block[LEVEL_LIMIT_TOLERANCE] = (byte) LEVEL_CAP;

		for (var i = 0; i < DEFAULT_TIMERS.length; i++) {
			putU32(block, TIMERS + i * Integer.BYTES, DEFAULT_TIMERS[i]);
		}

		block[UNIQUE_BLUE] = 1;
		block[COMMON_A] = (byte) COMMON_A_VALUE;
		putU16(block, TEAM_KILL_KICK, TEAM_KILL_KICK_VALUE);
		block[SNAKE] = (byte) AUTOMATCH_SNAKE;

		// THE ONLY TWO BYTES WE STILL INHERIT WITHOUT UNDERSTANDING. Both are [UNKNOWN] in both
		// schemas, and both are non-zero in every capture, so zeroing them is a change we have no
		// evidence for. They are named and isolated here so the residue is two lines rather than
		// spread invisibly through a hex blob.
		if (!mgo2server.common.Policy.current().zeroUnreadFields()) {
			putU32(block, UNKNOWN_72, UNKNOWN_72_VALUE);
			block[UNKNOWN_179] = (byte) UNKNOWN_179_VALUE;
		}

		return block;
	}

	private static void putU16(byte[] block, int at, int value) {
		block[at] = (byte) (value >>> 8);
		block[at + 1] = (byte) value;
	}

	private static void putU32(byte[] block, int at, int value) {
		block[at] = (byte) (value >>> 24);
		block[at + 1] = (byte) (value >>> 16);
		block[at + 2] = (byte) (value >>> 8);
		block[at + 3] = (byte) value;
	}

	/** Block offsets the schemas name. See the two ksy files for each field's evidence tag. */
	private static final int MAX_PLAYERS = 66;

	private static final int BRIEFING_TIME = 68;

	private static final int LEVEL_LIMIT_TOLERANCE = 95;

	private static final int UNIQUE_BLUE = 169;

	private static final int COMMON_A = 177;

	private static final int TEAM_KILL_KICK = 182;

	/** 16 players, the game's own maximum. */
	private static final int MAX_PLAYERS_VALUE = 16;

	/** Briefing length. The client's default, and not a value we have reason to change. */
	private static final int BRIEFING_SECONDS = 2;

	/** Level 22, the top of the table — so the limit spans every level and restricts nobody. */
	private static final int LEVEL_CAP = 22;

	/** Common-settings toggle A. Capture-proven at this offset; the bits are not all identified. */
	private static final int COMMON_A_VALUE = 0x24;

	/** Team kills tolerated before a kick. */
	private static final int TEAM_KILL_KICK_VALUE = 3;

	/**
	 * The 17-slot timer array as the client itself defaults it, indexed by {@link #RULE_TIMERS}:
	 * SNE 8/4, CAP 4/4, RES 4/4, TDM 3/4/15, DM 5/30, BASE 5/4, BOMB 30/4, TSNE 10/4.
	 *
	 * <p>{@link #AUTOMATCH_TIMERS} overrides the rules a real automatch game was observed to run
	 * differently; the rest stay at these, which is the placeholder story and is why that map is the
	 * one place to edit.
	 */
	private static final int[] DEFAULT_TIMERS = {
		8, 4, 4, 4, 4, 4, 3, 4, 15, 5, 30, 5, 4, 30, 4, 10, 4};

	/** Block offset of the first still-unexplained field. [UNKNOWN] in both schemas. */
	private static final int UNKNOWN_72 = 72;

	/**
	 * <b>A genuine u32, and read by nothing</b> [ELF 2026-07-29].
	 * <p>
	 * The width is settled in both directions — the parser at {@code 0xD43784} uses the u32 reader
	 * {@code 0xd5ccd8} and the builder at {@code 0xD449C8} the u32 writer {@code 0xd5c9bc} — so this
	 * is the value 33554432, not a {@code 2} with three padding bytes. Identical on the wire either
	 * way, which is exactly why it needed checking.
	 * <p>
	 * <b>No reader and no writer exists anywhere in the binary.</b> An exhaustive scan for
	 * {@code ,824(rN)} found nothing in the MGO ranges, while every identified neighbour appears at
	 * its literal offset many times over. So the value is server-authored and merely echoed back,
	 * and the disc has no Common Settings label for it either.
	 * <p>
	 * Emitted as captured. Zeroing it is still a change with no evidence behind it — but the reason
	 * has upgraded from "no reader traced" to "no reader exists, and the client is not the author".
	 */
	private static final int UNKNOWN_72_VALUE = 0x02000000;

	/** Block offset of the second still-unexplained field. [UNKNOWN] in both schemas. */
	private static final int UNKNOWN_179 = 179;

	/**
	 * <b>The low byte of the settings flags word, and no flag lives in it</b> [ELF 2026-07-29].
	 * <p>
	 * It has its own u8 read ({@code 0xD43B10}), distinct from the raw-2 covering the two common
	 * toggles beside it. Those three bytes are the 32-bit flags word at struct {@code +928}, and
	 * <b>every one of the 117 bit-tests against that word lies in bits 8-23</b> — the two toggles.
	 * Nothing tests bits 0-7. Our {@code 0x20} sets bit 5, which no site consumes.
	 * <p>
	 * The only load of this byte is the accessor {@code 0x9072AC}, which is dead code: its sole
	 * appearance is an OPD descriptor, there is no call to it, and the image is {@code ET_EXEC} with
	 * no relocations so a runtime-patched reference is impossible.
	 * <p>
	 * Emitted as captured, for the same reason as {@link #UNKNOWN_72_VALUE}.
	 */
	private static final int UNKNOWN_179_VALUE = 0x20;

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

		var block = template();
		block[CURRENT_PLAYERS] = (byte) PLAYERS_AT_CREATE;

		// Wipe the captured rotation before writing ours: every loop that walks it stops at the first
		// zero map, so a leftover entry beyond ours would still be part of the cycle.
		java.util.Arrays.fill(block, ROTATION, ROTATION + ROTATION_ENTRIES * ENTRY, (byte) 0);

		var entry = 0;
		for (var rule : new LinkedHashSet<>(rules)) {
			var at = ROTATION + entry * ENTRY;
			block[at] = (byte) (int) rule;
			block[at + 1] = (byte) map;
			// The per-rule "rule option". Zero is the one value the disc's ruleopt_bit whitelist
			// permits for every rule.
			block[at + 2] = 0;
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
		if (rule == RULE_SNEAKING) {
			block[SNAKE] = (byte) AUTOMATCH_SNAKE;
		}
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
