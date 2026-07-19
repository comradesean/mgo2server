package nomad.game.packet;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.ByteToMessageDecoder;
import io.netty.handler.codec.CorruptedFrameException;
import nomad.common.crypto.GameCrypto;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Arrays;
import java.util.List;
import java.util.function.IntPredicate;

/**
 * Decodes the game wire format into {@link GamePacket}s.
 * <p>
 * Stateful (it tracks the expected sequence) and therefore not sharable: give every channel its
 * own instance. Reassembly is left to {@link ByteToMessageDecoder}, which already handles
 * fragmented and coalesced reads correctly.
 */
public class GamePacketDecoder extends ByteToMessageDecoder {
	private static final Logger logger = LogManager.getLogger();

	/** Whether a given command's payload arrives Blowfish-encrypted. */
	private final IntPredicate payloadEncrypted;

	private int expectedSequence = 1;

	public GamePacketDecoder(IntPredicate payloadEncrypted) {
		this.payloadEncrypted = payloadEncrypted;
	}

	/** Decodes what a client sends to the server. */
	public static GamePacketDecoder forServer() {
		return new GamePacketDecoder(GameCrypto::isPayloadEncryptedInbound);
	}

	/** Decodes what the server sends back, for use by test and tool clients. */
	public static GamePacketDecoder forClient() {
		return new GamePacketDecoder(GameCrypto::isPayloadEncryptedOutbound);
	}

	@Override
	protected void decode(ChannelHandlerContext ctx, ByteBuf in, List<Object> out) {
		if (in.readableBytes() < GamePacketCodec.HEADER_LENGTH) {
			return;
		}

		// Command and length are needed to size the frame, but the buffer is still XORed, so
		// undo the key over just those four bytes. The key repeats every four bytes, which is
		// why the top half applies at offset 0 and the bottom half at offset 2.
		var index = in.readerIndex();
		var command = (in.getShort(index + GamePacketCodec.OFFSET_COMMAND)
			^ (GameCrypto.XOR_KEY >>> 16)) & 0xffff;
		var declaredLength = (in.getShort(index + GamePacketCodec.OFFSET_PAYLOAD_LENGTH)
			^ GameCrypto.XOR_KEY) & 0xffff;

		var encrypted = payloadEncrypted.test(command);
		var padding = GamePacketCodec.paddingFor(declaredLength, encrypted);
		var bodyLength = declaredLength + padding;

		if (bodyLength > GamePacketCodec.MAX_PAYLOAD_LENGTH + 1) {
			throw new CorruptedFrameException(
				"Payload length %d exceeds maximum for command %04x".formatted(bodyLength, command));
		}

		var frameLength = GamePacketCodec.HEADER_LENGTH + bodyLength;
		if (in.readableBytes() < frameLength) {
			return;
		}

		var frame = new byte[frameLength];
		in.readBytes(frame);
		GamePacketCodec.xor(frame);

		var body = Arrays.copyOfRange(frame, GamePacketCodec.HEADER_LENGTH, frameLength);

		// The checksum covers only the declared length, not any padding beyond it.
		var covered = declaredLength <= body.length ? Arrays.copyOf(body, declaredLength) : body;
		var expectedChecksum = GameCrypto.checksum(frame, covered);
		var actualChecksum = Arrays.copyOfRange(frame, GamePacketCodec.OFFSET_CHECKSUM,
			GamePacketCodec.OFFSET_CHECKSUM + GameCrypto.CHECKSUM_LENGTH);

		if (!GameCrypto.checksumMatches(expectedChecksum, actualChecksum)) {
			throw new CorruptedFrameException("Bad checksum for command %04x".formatted(command));
		}

		var sequence = ((frame[GamePacketCodec.OFFSET_SEQUENCE] & 0xff) << 24)
			| ((frame[GamePacketCodec.OFFSET_SEQUENCE + 1] & 0xff) << 16)
			| ((frame[GamePacketCodec.OFFSET_SEQUENCE + 2] & 0xff) << 8)
			| (frame[GamePacketCodec.OFFSET_SEQUENCE + 3] & 0xff);

		if (sequence != expectedSequence) {
			throw new CorruptedFrameException(
				"Out of sequence for command %04x: got %d, expected %d"
					.formatted(command, sequence, expectedSequence));
		}
		expectedSequence++;

		if (encrypted && body.length > 0) {
			GameCrypto.packet().decrypt(body);
			// Drop the cipher padding so handlers see only the declared payload.
			body = Arrays.copyOf(body, declaredLength);
		}

		if (logger.isDebugEnabled()) {
			logger.debug("In  - command {} - {} bytes", String.format("%04x", command), body.length);
			if (body.length > 0) {
				logger.debug(ByteBufUtil.hexDump(body));
			}
		}

		out.add(new GamePacket(command, Unpooled.wrappedBuffer(body)));
	}
}
