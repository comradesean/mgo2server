package mgo2server.game.packet;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.ByteBufUtil;
import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.MessageToByteEncoder;
import mgo2server.common.crypto.GameCrypto;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.function.IntPredicate;

/**
 * Encodes {@link GamePacket}s onto the wire.
 * <p>
 * Stateful (it tracks the outgoing sequence) and therefore not sharable: give every channel its
 * own instance. {@link MessageToByteEncoder} takes care of releasing the message.
 */
public class GamePacketEncoder extends MessageToByteEncoder<GamePacket> {
	private static final Logger logger = LogManager.getLogger();

	/** Whether a given command's payload must be Blowfish-encrypted before sending. */
	private final IntPredicate payloadEncrypted;

	private int sequence = 1;

	public GamePacketEncoder(IntPredicate payloadEncrypted) {
		this.payloadEncrypted = payloadEncrypted;
	}

	/** Encodes what the server sends to a client. */
	public static GamePacketEncoder forServer() {
		return new GamePacketEncoder(GameCrypto::isPayloadEncryptedOutbound);
	}

	/** Encodes what a client sends to the server, for use by test and tool clients. */
	public static GamePacketEncoder forClient() {
		return new GamePacketEncoder(GameCrypto::isPayloadEncryptedInbound);
	}

	@Override
	protected void encode(ChannelHandlerContext ctx, GamePacket packet, ByteBuf out) {
		var command = packet.getCommand();
		var payload = packet.getPayload();

		var body = new byte[payload.readableBytes()];
		payload.getBytes(payload.readerIndex(), body);

		if (logger.isDebugEnabled()) {
			logger.debug("Out - command {} - {} bytes", String.format("%04x", command), body.length);
			if (body.length > 0) {
				logger.debug(ByteBufUtil.hexDump(body));
			}
		}

		var frame = GamePacketCodec.frame(command, sequence++, body, payloadEncrypted.test(command));
		out.writeBytes(frame);
	}
}
