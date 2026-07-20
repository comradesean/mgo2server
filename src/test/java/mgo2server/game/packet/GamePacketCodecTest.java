package mgo2server.game.packet;

import mgo2server.common.crypto.GameCrypto;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.*;

/**
 * Framing unit tests. These need no server, so they run under Surefire without Docker.
 */
public class GamePacketCodecTest {
	private static final int ECHO = 0x0001;

	/** 0x3003 is the session check, whose payload the client encrypts. */
	private static final int CHECK_SESSION = 0x3003;

	private static byte[] payload(int length) {
		var payload = new byte[length];
		for (var i = 0; i < length; i++) {
			payload[i] = (byte) (i * 7 + 1);
		}
		return payload;
	}

	private static byte[] header(byte[] frame) {
		var copy = frame.clone();
		GamePacketCodec.xor(copy);
		return Arrays.copyOf(copy, GamePacketCodec.HEADER_LENGTH);
	}

	@Test
	public void xorIsItsOwnInverse() {
		var original = payload(37);
		var data = original.clone();

		GamePacketCodec.xor(data);
		assertThat(data).isNotEqualTo(original);

		GamePacketCodec.xor(data);
		assertThat(data).isEqualTo(original);
	}

	@Test
	public void payloadIsObscuredOnTheWire() {
		var payload = payload(8);
		var frame = GamePacketCodec.frame(ECHO, 1, payload, false);

		assertThat(Arrays.copyOfRange(frame, GamePacketCodec.HEADER_LENGTH, frame.length))
			.isNotEqualTo(payload);

		GamePacketCodec.xor(frame);
		assertThat(Arrays.copyOfRange(frame, GamePacketCodec.HEADER_LENGTH, frame.length))
			.isEqualTo(payload);
	}

	@Test
	public void writesCommandLengthAndSequenceIntoHeader() {
		var frame = GamePacketCodec.frame(ECHO, 42, payload(16), false);
		var header = header(frame);

		var command = ((header[0] & 0xff) << 8) | (header[1] & 0xff);
		var length = ((header[2] & 0xff) << 8) | (header[3] & 0xff);
		var sequence = ((header[4] & 0xff) << 24) | ((header[5] & 0xff) << 16)
			| ((header[6] & 0xff) << 8) | (header[7] & 0xff);

		assertThat(command).isEqualTo(ECHO);
		assertThat(length).isEqualTo(16);
		assertThat(sequence).isEqualTo(42);
	}

	@Test
	public void unencryptedFrameIsHeaderPlusPayload() {
		var frame = GamePacketCodec.frame(ECHO, 1, payload(37), false);
		assertThat(frame).hasSize(GamePacketCodec.HEADER_LENGTH + 37);
	}

	/** Encrypted payloads are zero-padded up to a whole number of cipher blocks. */
	@Test
	public void encryptedFrameIsPaddedToBlockSize() {
		var frame = GamePacketCodec.frame(CHECK_SESSION, 1, payload(20), true);

		assertThat(frame).hasSize(GamePacketCodec.HEADER_LENGTH + 24);

		var header = header(frame);
		var declaredLength = ((header[2] & 0xff) << 8) | (header[3] & 0xff);
		assertThat(declaredLength).isEqualTo(24);
	}

	@Test
	public void encryptedPayloadRoundTrips() {
		var payload = payload(20);
		var frame = GamePacketCodec.frame(CHECK_SESSION, 1, payload, true);

		GamePacketCodec.xor(frame);
		var body = Arrays.copyOfRange(frame, GamePacketCodec.HEADER_LENGTH, frame.length);

		assertThat(Arrays.copyOf(body, payload.length)).isNotEqualTo(payload);

		GameCrypto.packet().decrypt(body);
		assertThat(Arrays.copyOf(body, payload.length)).isEqualTo(payload);
	}

	@Test
	public void checksumCoversHeaderAndPayload() {
		var frame = GamePacketCodec.frame(ECHO, 1, payload(16), false);
		GamePacketCodec.xor(frame);

		var body = Arrays.copyOfRange(frame, GamePacketCodec.HEADER_LENGTH, frame.length);
		var expected = GameCrypto.checksum(frame, body);
		var actual = Arrays.copyOfRange(frame, GamePacketCodec.OFFSET_CHECKSUM,
			GamePacketCodec.OFFSET_CHECKSUM + GameCrypto.CHECKSUM_LENGTH);

		assertThat(actual).isEqualTo(expected);
	}

	@Test
	public void changingPayloadChangesChecksum() {
		var a = GamePacketCodec.frame(ECHO, 1, payload(16), false);
		var b = GamePacketCodec.frame(ECHO, 1, payload(17), false);

		assertThat(Arrays.copyOfRange(a, GamePacketCodec.OFFSET_CHECKSUM, GamePacketCodec.HEADER_LENGTH))
			.isNotEqualTo(Arrays.copyOfRange(b, GamePacketCodec.OFFSET_CHECKSUM, GamePacketCodec.HEADER_LENGTH));
	}

	@Test
	public void rejectsOversizedPayload() {
		var tooBig = new byte[GamePacketCodec.MAX_PAYLOAD_LENGTH + 1];
		assertThatThrownBy(() -> GamePacketCodec.frame(ECHO, 1, tooBig, false))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("exceeds maximum");
	}

	@Test
	public void knowsWhichCommandsAreEncrypted() {
		assertThat(GameCrypto.isPayloadEncryptedInbound(CHECK_SESSION)).isTrue();
		assertThat(GameCrypto.isPayloadEncryptedInbound(ECHO)).isFalse();

		assertThat(GameCrypto.isPayloadEncryptedOutbound(0x4305)).isTrue();
		assertThat(GameCrypto.isPayloadEncryptedOutbound(CHECK_SESSION)).isFalse();
	}
}
