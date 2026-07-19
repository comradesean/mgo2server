package nomad.common.crypto;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Recovers the session token the client presents when it checks in.
 * <p>
 * The client sends 16 bytes, of which only the first eight carry the token. Those are XORed with
 * a fixed mask and then run through the <em>encrypt</em> direction of the auth key schedule —
 * which is what recovers the plaintext here, however backwards that reads. The original
 * implementation carried the note "definitely not the right way to do this"; the transform is
 * reproduced faithfully because the client's behaviour is what it is.
 */
public final class SessionIds {
	public static final int LENGTH = 8;

	/** Full length of the session field in the packet, of which only the first 8 bytes matter. */
	public static final int FIELD_LENGTH = 16;

	private static final byte[] MASK = {
		(byte) 0x35, (byte) 0xd5, (byte) 0xc3, (byte) 0x8e, (byte) 0xd0, (byte) 0x11, (byte) 0x0e, (byte) 0xa8,
	};

	/**
	 * A sentinel the original server special-cased, mapping it to a fixed token. Retained so
	 * existing SaveMGO tooling that relies on it keeps working.
	 */
	private static final byte[] SPECIAL = {
		(byte) 0xE7, (byte) 0xBA, (byte) 0xB4, (byte) 0x26, (byte) 0xFE, (byte) 0x3F, (byte) 0x40, (byte) 0x73,
		(byte) 0xDB, (byte) 0x94, (byte) 0x36, (byte) 0xDF, (byte) 0x6D, (byte) 0xDB, (byte) 0xD3, (byte) 0x9C,
	};

	private static final String SPECIAL_TOKEN = "cafebabe";

	private SessionIds() {
	}

	/** Decodes the session field of a check-session packet into its token. */
	public static String decode(byte[] field) {
		if (field.length < LENGTH) {
			throw new IllegalArgumentException(
				"Session field must be at least %d bytes, got %d".formatted(LENGTH, field.length));
		}

		if (field.length == FIELD_LENGTH && Arrays.equals(field, SPECIAL)) {
			return SPECIAL_TOKEN;
		}

		var token = Arrays.copyOf(field, LENGTH);
		for (var i = 0; i < LENGTH; i++) {
			token[i] ^= MASK[i];
		}
		GameCrypto.auth().encrypt(token);

		return new String(token, StandardCharsets.ISO_8859_1);
	}

	/**
	 * Inverse of {@link #decode}, producing the session field a client would send for a token.
	 * <p>
	 * The server never needs this — it only ever decodes — but tests and tooling need to be able
	 * to construct a valid check-session packet, and the inverse belongs next to the transform it
	 * undoes.
	 */
	public static byte[] encode(String token) {
		var bytes = token.getBytes(StandardCharsets.ISO_8859_1);
		if (bytes.length != LENGTH) {
			throw new IllegalArgumentException(
				"Session token must be %d characters, got %d".formatted(LENGTH, bytes.length));
		}

		GameCrypto.auth().decrypt(bytes);
		for (var i = 0; i < LENGTH; i++) {
			bytes[i] ^= MASK[i];
		}

		return Arrays.copyOf(bytes, FIELD_LENGTH);
	}
}
