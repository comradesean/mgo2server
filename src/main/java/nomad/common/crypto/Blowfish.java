package nomad.common.crypto;

import io.netty.buffer.ByteBuf;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.util.Objects;

/**
 * The Blowfish variant MGO2 uses for packet payloads and session identifiers.
 * <p>
 * The game ships an already-expanded key schedule rather than a passphrase, so there is no key
 * setup here: {@link #load} reads the 4168-byte table directly (18 P-array entries followed by
 * four 256-entry S-boxes, all big-endian). Blocks are eight bytes and the two halves are swapped
 * on output, which is the standard Feistel final swap.
 * <p>
 * Instances are immutable and safe to share across channels.
 */
public final class Blowfish {
	/** 18 P-array entries plus 4 * 256 S-box entries, four bytes each. */
	public static final int KEY_LENGTH = (18 + 4 * 256) * 4;

	public static final int BLOCK_SIZE = 8;

	private static final int ROUNDS = 8;

	private final int[] p;

	private final int[][] s;

	private Blowfish(int[] p, int[][] s) {
		this.p = p;
		this.s = s;
	}

	/** Reads an expanded key schedule in the layout the game uses. */
	public static Blowfish load(byte[] key) {
		if (key.length != KEY_LENGTH) {
			throw new IllegalArgumentException(
				"Expected a %d byte key schedule, got %d".formatted(KEY_LENGTH, key.length));
		}

		var buffer = ByteBuffer.wrap(key);

		var p = new int[18];
		for (var i = 0; i < p.length; i++) {
			p[i] = buffer.getInt();
		}

		var s = new int[4][256];
		for (var box = 0; box < s.length; box++) {
			for (var i = 0; i < s[box].length; i++) {
				s[box][i] = buffer.getInt();
			}
		}

		return new Blowfish(p, s);
	}

	/** Loads a key schedule from the classpath, e.g. {@code crypto/packet.key}. */
	public static Blowfish loadResource(String resource) {
		try (var stream = Blowfish.class.getClassLoader().getResourceAsStream(resource)) {
			Objects.requireNonNull(stream, () -> "Missing crypto key resource: " + resource);
			return load(stream.readAllBytes());
		} catch (IOException e) {
			throw new UncheckedIOException("Failed to read crypto key resource: " + resource, e);
		}
	}

	private int f(int x) {
		return ((s[0][x >>> 24] + s[1][(x >>> 16) & 0xff]) ^ s[2][(x >>> 8) & 0xff]) + s[3][x & 0xff];
	}

	public void encrypt(byte[] data) {
		encrypt(data, 0, data.length);
	}

	public void encrypt(byte[] data, int offset, int length) {
		checkBlockAligned(length);
		var buffer = ByteBuffer.wrap(data, offset, length);

		for (var i = 0; i < length; i += BLOCK_SIZE) {
			var b = buffer.getInt(offset + i);
			var a = buffer.getInt(offset + i + 4);

			b ^= p[0];
			for (var j = ROUNDS - 1; j >= 0; j--) {
				a ^= p[15 - 2 * j];
				a ^= f(b);
				b ^= p[16 - 2 * j];
				b ^= f(a);
			}
			a ^= p[17];

			buffer.putInt(offset + i, a);
			buffer.putInt(offset + i + 4, b);
		}
	}

	public void decrypt(byte[] data) {
		decrypt(data, 0, data.length);
	}

	public void decrypt(byte[] data, int offset, int length) {
		checkBlockAligned(length);
		var buffer = ByteBuffer.wrap(data, offset, length);

		for (var i = 0; i < length; i += BLOCK_SIZE) {
			var b = buffer.getInt(offset + i);
			var a = buffer.getInt(offset + i + 4);

			b ^= p[17];
			for (var j = 0; j < ROUNDS; j++) {
				a ^= p[16 - 2 * j];
				a ^= f(b);
				b ^= p[15 - 2 * j];
				b ^= f(a);
			}
			a ^= p[0];

			buffer.putInt(offset + i, a);
			buffer.putInt(offset + i + 4, b);
		}
	}

	/** Encrypts the readable region of {@code buffer} in place. */
	public void encrypt(ByteBuf buffer) {
		transform(buffer, true);
	}

	/** Decrypts the readable region of {@code buffer} in place. */
	public void decrypt(ByteBuf buffer) {
		transform(buffer, false);
	}

	private void transform(ByteBuf buffer, boolean encrypt) {
		var length = buffer.readableBytes();
		checkBlockAligned(length);

		var bytes = new byte[length];
		buffer.getBytes(buffer.readerIndex(), bytes);

		if (encrypt) {
			encrypt(bytes);
		} else {
			decrypt(bytes);
		}

		buffer.setBytes(buffer.readerIndex(), bytes);
	}

	private static void checkBlockAligned(int length) {
		if (length % BLOCK_SIZE != 0) {
			throw new IllegalArgumentException(
				"Length must be a multiple of %d, got %d".formatted(BLOCK_SIZE, length));
		}
	}
}
