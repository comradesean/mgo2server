package mgo2server.common.crypto;

import mgo2server.common.ClientVersion;

import java.nio.charset.StandardCharsets;
import java.util.EnumMap;
import java.util.HexFormat;
import java.util.Map;

/**
 * Reproduces the value the client presents in the {@code 0x3003} check-session packet.
 * <p>
 * The client does not send the login token back. When it parses the login reply it keeps the token
 * as its sixteen ASCII characters, immediately runs them through a crypto service, and stores the
 * sixteen-byte result; that result is what the check-session packet carries. So the server never
 * has to invert anything — it applies the same transform to the token it issued and compares.
 * <p>
 * Traced in {@code MGO2.elf} (BLUS30109). The login parser calls the service at {@code 0xBB1800}
 * as {@code f(obj, out, in, 0x10, mode=6)} and copies the result to parse-object {@code +0x154}.
 * The service is a singleton whose pointer lives in the static global {@code 0xFFE6DC}; its vtable
 * is at {@code 0xfbbd00}, where {@code +0x8} is the cipher and {@code +0xC} the wrapper. The
 * wrapper checks the context size is {@code 0x40}, builds a context, then transforms:
 * <pre>
 *   context = 8-byte IV followed by a 56-byte key   (56 is Blowfish's maximum key length)
 *   C[i] = decrypt(P[i]) XOR P[i-1],  with P[-1] = IV
 * </pre>
 * Note the block is decrypted rather than encrypted, and the XOR is against the previous
 * <em>plaintext</em> block, not the previous ciphertext. That is neither ECB nor CBC, which is why
 * the transform resisted being guessed from captured pairs.
 * <p>
 * Mode 6's context is itself produced by running this same transform over a 64-byte blob with a
 * master context. The blob is zero in the image and is materialised at runtime, so it was read out
 * of a live client; the resulting key schedule is shipped as {@code crypto/session.key} and the IV
 * below. Verified against two independent captures from a real client — see {@code dev/docs/OBSERVED.md}.
 */
public final class SessionField {
	/** Characters of the login token the client keeps, and the size of the value it derives. */
	public static final int TOKEN_LENGTH = 16;

	public static final int FIELD_LENGTH = 16;

	/**
	 * One Blowfish schedule per client version, loaded eagerly.
	 * <p>
	 * <b>This class reads no environment.</b> It used to select a key from
	 * {@code MGO2SERVER_SESSION_KIT} on a {@code static final} field, which froze the choice at
	 * class load and meant {@code SessionFieldTest}'s capture-proven 1.0 vectors would fail if that
	 * variable were ever set in Maven's environment. The version now arrives as an argument, so both
	 * builds can be exercised in one JVM and the 1.0 vectors are pinned regardless of configuration.
	 * <p>
	 * Both are small (4,168 bytes each) and loading both is simpler than loading lazily.
	 */
	private static final Map<ClientVersion, Blowfish> CIPHERS = ciphers();

	private static Map<ClientVersion, Blowfish> ciphers() {
		var map = new EnumMap<ClientVersion, Blowfish>(ClientVersion.class);
		for (var version : ClientVersion.values()) {
			map.put(version, Blowfish.loadResource(version.sessionKeyResource()));
		}
		return map;
	}

	private SessionField() {
	}

	/**
	 * Derives the check-session field for a login token.
	 *
	 * @param version which build's key to use; the IV and schedule are two halves of one derived
	 *     context and are taken together from it
	 * @param token the sixteen characters handed to the client in the login reply
	 */
	public static byte[] of(ClientVersion version, String token) {
		var plain = token.getBytes(StandardCharsets.ISO_8859_1);
		if (plain.length != TOKEN_LENGTH) {
			throw new IllegalArgumentException(
				"Token must be %d characters, got %d".formatted(TOKEN_LENGTH, plain.length));
		}

		var cipher = CIPHERS.get(version);
		var out = new byte[FIELD_LENGTH];
		var previous = version.sessionIv();

		for (var offset = 0; offset < plain.length; offset += Blowfish.BLOCK_SIZE) {
			var block = new byte[Blowfish.BLOCK_SIZE];
			System.arraycopy(plain, offset, block, 0, Blowfish.BLOCK_SIZE);

			var transformed = block.clone();
			cipher.decrypt(transformed);
			for (var i = 0; i < Blowfish.BLOCK_SIZE; i++) {
				out[offset + i] = (byte) (transformed[i] ^ previous[i]);
			}

			// The chain carries the plaintext block forward, not the block just written.
			previous = block;
		}

		return out;
	}

	/**
	 * The same value as {@link #of(String)} in the form stored on the account, so a check-session
	 * packet can be matched with a plain lookup instead of a reverse transform.
	 */
	public static String stored(ClientVersion version, String token) {
		return HexFormat.of().formatHex(of(version, token));
	}

	/** Renders a field taken off the wire into the form {@link #stored} produces. */
	public static String stored(byte[] field) {
		return HexFormat.of().formatHex(field, 0, FIELD_LENGTH);
	}
}
