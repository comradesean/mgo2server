package mgo2server.common.crypto;

/**
 * The XOR obfuscation the client applies to a ranking HTTP response body before parsing it.
 * <p>
 * The Rankings screens do not use the lobby TCP protocol at all: they POST to
 * {@code rank/mgogetrank.html} / {@code rank/mgogetrank_clan.html} and parse the reply as a binary
 * blob. Before a single field is read, the whole body is run through this transform, so a server
 * that answers in cleartext produces garbage in every column with no error reported.
 * <p>
 * Traced in {@code MGO2.elf} (BLUS30109), function {@code 0xBC2D78}, and re-read instruction by
 * instruction here rather than taken on report. The eight key bytes are written inline as
 * immediates at {@code 0xBC2D80}-{@code 0xBC2DC8} — {@code li r0,-117} / {@code stb r0,0(r6)}
 * gives {@code key[0] = 0x8B}, and so on for all eight, in the scrambled store order the compiler
 * chose ({@code +3} first, then {@code +0}, {@code +1}, {@code +2}, {@code +4}…).
 * <p>
 * The keystream, from the loop at {@code 0xBC2DD4}-{@code 0xBC2E58}:
 * <pre>
 *   buf[0] ^= key[0];                       // peeled, 0xBC2DD4
 *   j = 0;
 *   for (i = 1; i &lt; len; i++) {
 *       m = i % 4;                          // 0xBC2E00, srawi/slwi/subf
 *       buf[i] ^= key[j + m];               // 0xBC2E28, lbzx r11,r6,r9
 *       if (m == 3) { j++; if (j == 5) j = 0; }   // 0xBC2E38-0xBC2E54
 *   }
 * </pre>
 * The peeled first byte is not a special case in effect: at {@code i = 0}, {@code m} and {@code j}
 * are both zero, so it takes {@code key[0]} exactly as the general rule would. That collapses to
 * the closed form used below — byte {@code i} is XORed with {@code key[((i / 4) % 5) + (i % 4)]},
 * which indexes the full 0..7 range and repeats with a period of 20 bytes.
 * <p>
 * The wrap test in the binary is written as branchless sign arithmetic
 * ({@code xori r9,r7,5} then {@code srawi}/{@code xor}/{@code subf}/{@code srawi}/{@code and}),
 * which is the idiom for {@code j = (j ^ 5) != 0 ? j : 0}, i.e. reset to zero on reaching five.
 * <p>
 * XOR is its own inverse, so the server scrambles with the same routine the client descrambles
 * with. [ELF] throughout; no capture of a real Konami ranking response exists to check it against.
 */
public final class RankingScramble {
	/**
	 * {@code 8B 75 2C 90 3A 5E 4D F1} — read out of the immediates at {@code 0xBC2D80} onward.
	 * Eight bytes, all of which the keystream reaches.
	 */
	private static final int[] KEY = {0x8B, 0x75, 0x2C, 0x90, 0x3A, 0x5E, 0x4D, 0xF1};

	/** Blocks of four bytes; the key offset advances every block and wraps after five. */
	private static final int BLOCK = 4;

	private static final int BLOCKS_PER_CYCLE = 5;

	private RankingScramble() {
	}

	/**
	 * Applies the transform in place and returns the same array, so it reads as a pipeline stage.
	 * Symmetric: applying it twice is the identity.
	 */
	public static byte[] apply(byte[] body) {
		for (var i = 0; i < body.length; i++) {
			body[i] ^= (byte) KEY[keyIndex(i)];
		}
		return body;
	}

	/**
	 * The key byte position for wire offset {@code i}. Kept separate so the keystream can be
	 * asserted against the ELF's loop directly, rather than only through a scrambled buffer.
	 */
	static int keyIndex(int i) {
		return (i / BLOCK) % BLOCKS_PER_CYCLE + i % BLOCK;
	}
}
