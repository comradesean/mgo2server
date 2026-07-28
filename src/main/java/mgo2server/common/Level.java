package mgo2server.common;

/**
 * Character level, derived from experience exactly as the client derives it.
 *
 * <h2>Where the numbers come from</h2>
 * <b>Not from {@code MGO2.elf}.</b> The client walks a 128-entry array in {@code .bss} at
 * {@code 0x1659D24} that is zero at load and filled at runtime by a GCX native ({@code 0x6F9370},
 * option letter {@code -r}) from a stage script. The table below is that script's argument list,
 * read from the disc — byte-identical in six stages ({@code lobby}, {@code n002a}, {@code n003a},
 * {@code n004a}, {@code n007a}, {@code n012a}), and the sole call site of that native in each.
 *
 * <p>The native was identified through the GCX registration table rather than by the shape of the
 * data: name hash {@code 0x00D3656D} at {@code 0x1031584}, OPD {@code 0x1014CF0} to
 * {@code 0x6F9370}. The same method reproduces the sibling {@code ComputeScore} native
 * ({@code 0x0035706D} to {@code 0x6FA1B8}) that {@code ADDRESSES.md} already records, which is what
 * validates the lookup.
 *
 * <h2>The algorithm, read from {@code 0x6F9260}</h2>
 * Count the thresholds at or below the experience. The comparison is a signed {@code ble}, so an
 * entry exactly equal to the experience <em>is</em> counted; the walk stops at the first entry
 * greater than the experience, at a zero entry, or after 128 — which is why the 106 unwritten
 * entries of the runtime array do not push everyone to level 128.
 *
 * <p><b>The level is the count itself, not one more than it.</b> That distinction is settled by
 * measurement, not reading: 499 experience displays as level 3 and 500 as level 4 on a live client,
 * and {@code T[3]} is 500.
 *
 * <h2>Verification</h2>
 * Reproduces all twelve recorded live readings: 11/22/33/44 → 0, 214 → 1, 428 → 3, 499 → 3,
 * 500 → 4, 1450 → 10, 1600 → 10, 49250 → 22, 50000 → 22.
 */
public final class Level {

	/**
	 * Experience needed for each level, ascending. Level <i>n</i> is reached at {@code THRESHOLDS[n-1]}.
	 * <p>
	 * Twenty-two entries, so the cap is level 22 at 4,600 experience — everything above that is still
	 * 22. That ceiling is why the automatch panel's gauge is 23 columns wide (levels 0 through 22),
	 * and why the client clamps its own centre column to that range at {@code 0x93C348}.
	 */
	private static final int[] THRESHOLDS = {
		125, 250, 375, 500, 650, 800, 950, 1100, 1275, 1450,
		1625, 1800, 2000, 2200, 2400, 2600, 2850, 3100, 3350, 3600, 4100, 4600,
	};

	/** The highest level the table defines, and the client's own display clamp. */
	public static final int MAX = THRESHOLDS.length;

	private Level() {
	}

	/**
	 * The level a character with this experience displays.
	 *
	 * @return 0 through {@link #MAX}. Zero is a real level, not an error: it is what everyone below
	 *     125 experience shows
	 */
	public static int of(long experience) {
		var level = 0;
		while (level < THRESHOLDS.length && THRESHOLDS[level] <= experience) {
			level++;
		}
		return level;
	}

	/**
	 * The experience needed to reach a level, or 0 for level 0.
	 * <p>
	 * Mirrors the client's own inverse at {@code 0x6F92B0}, which clamps to the last entry — that
	 * function has no callers in the binary, but it confirms the 1-based indexing convention.
	 */
	public static int experienceFor(int level) {
		if (level <= 0) {
			return 0;
		}
		return THRESHOLDS[Math.min(level, THRESHOLDS.length) - 1];
	}
}
