package nomad.common.crypto;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;

/**
 * Transport-level crypto for the game protocol.
 * <p>
 * Every packet on the wire is XORed with a fixed key. On top of that, the header carries an
 * HMAC-MD5 over the first eight header bytes plus the payload, and a handful of commands
 * additionally Blowfish-encrypt their payload.
 * <p>
 * None of this is a security boundary — the keys ship inside the game disc and are reproduced
 * here so the server can talk to an unmodified client. Treat it as an encoding, not protection.
 */
public final class GameCrypto {
	/** Applied to the whole packet, header included. */
	public static final int XOR_KEY = 0x5a7085af;

	public static final int CHECKSUM_LENGTH = 16;

	/** Bytes of the header covered by the checksum: command, payload length and sequence. */
	public static final int CHECKSUM_HEADER_LENGTH = 8;

	private static final String HMAC_MD5 = "HmacMD5";

	private static final byte[] HMAC_KEY = {
		(byte) 0x5A, (byte) 0x37, (byte) 0x2F, (byte) 0x62, (byte) 0x69, (byte) 0x4A, (byte) 0x34, (byte) 0x36,
		(byte) 0x54, (byte) 0x7A, (byte) 0x47, (byte) 0x46, (byte) 0x2D, (byte) 0x38, (byte) 0x79, (byte) 0x78,
	};

	private static final SecretKeySpec HMAC_KEY_SPEC = new SecretKeySpec(HMAC_KEY, HMAC_MD5);

	/**
	 * Commands whose payload the client encrypts on the way in.
	 * <p>
	 * Taken from the reference servers, not from the binary — the client decides per call site
	 * rather than from a table, so there is nothing to read off. Only `0x3003`, `0x4700` and
	 * `0x4990` are handled here, and of those only `0x3003` is <em>confirmed</em>: its payload
	 * decrypts to a correct account id, which a wrong list or key could not produce.
	 */
	private static final int[] DECRYPT_COMMANDS = { 0x3003, 0x4310, 0x4320, 0x43c0, 0x4700, 0x4990 };

	/**
	 * Commands whose payload the server encrypts on the way out.
	 * <p>
	 * <b>Entirely unverified.</b> Nothing in this server sends `0x4305`, so this cipher has never
	 * encrypted a byte the client has seen, and whether the client expects it encrypted is unknown
	 * — the id appears as a code immediate in the binary but never near the crypto path. Inherited
	 * from the reference servers. If `0x4305` is ever implemented, confirm this before trusting it.
	 */
	private static final int[] ENCRYPT_COMMANDS = { 0x4305 };

	private static final Blowfish PACKET = Blowfish.loadResource("crypto/packet.key");

	private GameCrypto() {
	}

	/** Cipher for packet payloads. */
	public static Blowfish packet() {
		return PACKET;
	}

	public static boolean isPayloadEncryptedInbound(int command) {
		return contains(DECRYPT_COMMANDS, command);
	}

	public static boolean isPayloadEncryptedOutbound(int command) {
		return contains(ENCRYPT_COMMANDS, command);
	}

	private static boolean contains(int[] commands, int command) {
		for (var candidate : commands) {
			if (candidate == command) {
				return true;
			}
		}
		return false;
	}

	/** HMAC-MD5 over the first eight header bytes followed by the payload. */
	public static byte[] checksum(byte[] header, byte[] payload) {
		try {
			var mac = Mac.getInstance(HMAC_MD5);
			mac.init(HMAC_KEY_SPEC);
			mac.update(header, 0, CHECKSUM_HEADER_LENGTH);
			if (payload.length > 0) {
				mac.update(payload);
			}
			return mac.doFinal();
		} catch (GeneralSecurityException e) {
			// HmacMD5 is required of every Java platform, so this cannot happen in practice.
			throw new IllegalStateException("HmacMD5 unavailable", e);
		}
	}

	/** Constant-time comparison, so checksum checking cannot be turned into an oracle. */
	public static boolean checksumMatches(byte[] expected, byte[] actual) {
		return MessageDigest.isEqual(expected, actual);
	}

	/** Bytes of padding needed to reach a whole number of cipher blocks. */
	public static int paddingFor(int length) {
		var remainder = length % Blowfish.BLOCK_SIZE;
		return remainder == 0 ? 0 : Blowfish.BLOCK_SIZE - remainder;
	}
}
