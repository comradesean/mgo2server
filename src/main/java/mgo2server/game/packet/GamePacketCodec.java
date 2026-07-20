package mgo2server.game.packet;

import mgo2server.common.crypto.GameCrypto;

import java.nio.ByteBuffer;

/**
 * Wire format of a game packet.
 * <p>
 * A packet is a 24-byte header followed by the payload:
 * <pre>
 *   0x00  u16  command
 *   0x02  u16  payload length (excluding any cipher padding)
 *   0x04  u32  sequence, counting from 1 and incrementing per packet in each direction
 *   0x08  16   HMAC-MD5 over bytes 0x00..0x08 plus the payload
 *   0x18  ..   payload, Blowfish-encrypted and zero-padded for some commands
 * </pre>
 * The finished packet is then XORed end to end with a fixed key.
 * <p>
 * Framing lives here rather than in the encoder so tests can build byte-exact packets without
 * going through a channel.
 */
public final class GamePacketCodec {
	public static final int OFFSET_COMMAND = 0x00;

	public static final int OFFSET_PAYLOAD_LENGTH = 0x02;

	public static final int OFFSET_SEQUENCE = 0x04;

	public static final int OFFSET_CHECKSUM = 0x08;

	public static final int HEADER_LENGTH = 0x18;

	public static final int MAX_PAYLOAD_LENGTH = 0x3ff;

	public static final int MAX_PACKET_LENGTH = HEADER_LENGTH + MAX_PAYLOAD_LENGTH + 1;

	private GamePacketCodec() {
	}

	/**
	 * Builds a complete packet as it appears on the wire.
	 *
	 * @param encryptPayload whether this command's payload is Blowfish-encrypted, which also
	 *                       zero-pads it up to a block boundary
	 */
	public static byte[] frame(int command, int sequence, byte[] payload, boolean encryptPayload) {
		if (payload.length > MAX_PAYLOAD_LENGTH) {
			throw new IllegalArgumentException(
				"Payload of %d exceeds maximum %d".formatted(payload.length, MAX_PAYLOAD_LENGTH));
		}

		var body = payload;
		if (encryptPayload) {
			body = new byte[payload.length + GameCrypto.paddingFor(payload.length)];
			System.arraycopy(payload, 0, body, 0, payload.length);
			GameCrypto.packet().encrypt(body);
		}

		// The length written is the padded one, matching what the original server sends. A peer
		// that instead declares the unpadded length still decodes correctly, because the receiver
		// re-derives the padding from whatever length it is given.
		var packet = ByteBuffer.allocate(HEADER_LENGTH + body.length);
		packet.putShort(OFFSET_COMMAND, (short) command);
		packet.putShort(OFFSET_PAYLOAD_LENGTH, (short) body.length);
		packet.putInt(OFFSET_SEQUENCE, sequence);
		packet.position(HEADER_LENGTH);
		packet.put(body);

		var bytes = packet.array();

		var checksum = GameCrypto.checksum(bytes, body);
		System.arraycopy(checksum, 0, bytes, OFFSET_CHECKSUM, GameCrypto.CHECKSUM_LENGTH);

		xor(bytes);
		return bytes;
	}

	/** XORs a packet in place with the transport key. */
	public static void xor(byte[] packet) {
		for (var i = 0; i < packet.length; i++) {
			packet[i] ^= (byte) (GameCrypto.XOR_KEY >>> (24 - 8 * (i & 3)));
		}
	}

	/** Padding the receiver must expect for a payload of this declared length. */
	public static int paddingFor(int payloadLength, boolean encrypted) {
		return encrypted ? GameCrypto.paddingFor(payloadLength) : 0;
	}
}
