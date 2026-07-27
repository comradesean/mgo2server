package mgo2server.common.crypto;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Checks the ranking obfuscation against the client's own loop.
 * <p>
 * The oracle below is {@code MGO2.elf} {@code 0xBC2D78} transcribed statement for statement —
 * peeled first byte, {@code m = i % 4} key offset, and the {@code j} counter that advances every
 * fourth byte and resets at five. {@link RankingScramble} implements the closed form instead, so
 * the two agreeing is a real check of the algebra rather than a restatement of it.
 * <p>
 * Tier 1: the key bytes and the loop are read from the binary. No capture of a genuine Konami
 * ranking response exists, so nothing here is corroborated by tier 2.
 */
public class RankingScrambleTest {
	/** [ELF] the immediates stored at {@code 0xBC2D80}-{@code 0xBC2DC8}. */
	private static final int[] KEY = {0x8B, 0x75, 0x2C, 0x90, 0x3A, 0x5E, 0x4D, 0xF1};

	/** The ELF's loop, written the way the binary writes it. */
	private static byte[] reference(byte[] body) {
		var out = body.clone();
		if (out.length == 0) {
			return out;
		}

		out[0] ^= (byte) KEY[0];

		var j = 0;
		for (var i = 1; i < out.length; i++) {
			var m = i % 4;
			out[i] ^= (byte) KEY[j + m];
			if (m == 3) {
				j++;
				if (j == 5) {
					j = 0;
				}
			}
		}
		return out;
	}

	@Test
	public void matchesTheClientLoop() {
		var body = new byte[256];
		for (var i = 0; i < body.length; i++) {
			body[i] = (byte) (i * 7 + 3);
		}

		assertThat(RankingScramble.apply(body.clone())).isEqualTo(reference(body));
	}

	@Test
	public void keyIndexStaysInsideTheKey() {
		for (var i = 0; i < 1000; i++) {
			assertThat(RankingScramble.keyIndex(i)).isBetween(0, KEY.length - 1);
		}
	}

	/** The keystream repeats every five four-byte blocks, so the cycle is twenty bytes. */
	@Test
	public void keystreamCyclesEveryTwentyBytes() {
		for (var i = 0; i < 100; i++) {
			assertThat(RankingScramble.keyIndex(i)).isEqualTo(RankingScramble.keyIndex(i + 20));
		}
	}

	/** XOR is its own inverse: the server scrambles with what the client descrambles with. */
	@Test
	public void isSymmetric() {
		var body = "the quick brown fox jumps over the lazy dog".getBytes();

		assertThat(RankingScramble.apply(RankingScramble.apply(body.clone())))
			.isEqualTo(body);
	}

	/** The first byte takes key[0]: at i = 0 both the block index and the offset are zero. */
	@Test
	public void firstByteUsesTheFirstKeyByte() {
		assertThat(RankingScramble.keyIndex(0)).isZero();
		assertThat(RankingScramble.apply(new byte[]{0})).containsExactly((byte) 0x8B);
	}

	@Test
	public void handlesAnEmptyBody() {
		assertThat(RankingScramble.apply(new byte[0])).isEmpty();
	}
}
