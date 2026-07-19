package nomad.game.packet;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.AttributeKey;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class GamePacketDecoder extends ChannelInboundHandlerAdapter {
	private static class DecodeState {
		public final ByteBuf buffer;
		public int sequence;

		public DecodeState(ByteBuf buffer, int sequence) {
			this.buffer = buffer;
			this.sequence = sequence;
		}
	}

	private static final Logger logger = LogManager.getLogger();

	private static final AttributeKey<DecodeState> DECODE_STATE = AttributeKey.valueOf("decodeState");

	@Override
	public void channelActive(ChannelHandlerContext ctx) {
		var decodeStateAttribute = ctx.channel().attr(DECODE_STATE);

		if (decodeStateAttribute.get() != null) {
			logger.warn("GamePacketDecoder.channelActive(): Did not expect decodeState to be set.");
		}

		var buffer = ctx.alloc().buffer(GamePacketConstants.MAX_PACKET_SIZE, GamePacketConstants.MAX_PACKET_SIZE);
		decodeStateAttribute.set(new DecodeState(buffer, 1));

		ctx.fireChannelActive();
	}

	@Override
	public void channelInactive(ChannelHandlerContext ctx) {
		var decodeState = ctx.channel().attr(DECODE_STATE).get();
		if (decodeState != null) {
			decodeState.buffer.release();
		}

		ctx.fireChannelInactive();
	}

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		if (!(msg instanceof ByteBuf in)) {
			return;
		}

		var decodeState = ctx.channel().attr(DECODE_STATE).get();
		if (decodeState == null) {
			logger.error("GamePacketDecoder.channelRead(): decodeState is null.");
			return;
		}

		var buffer = decodeState.buffer;
		var expectedSequence = decodeState.sequence;

		logger.info("read");
		logger.info(ByteBufUtil.hexDump(in));

		while (in.isReadable()) {
			in.readBytes(buffer, Math.min(in.readableBytes(), buffer.writableBytes()));

			buffer.markReaderIndex();

			// Read command
			if (!buffer.isReadable(2)) {
				logger.info("Can't read command yet");
				buffer.resetReaderIndex();
				break;
			}

			var command = (int) buffer.readShort();
			logger.info("command=" + String.format("%04x", command));

			// Read payload length
			if (!buffer.isReadable(2)) {
				logger.info("Can't read payload length yet");
				buffer.resetReaderIndex();
				break;
			}

			var payloadLength = buffer.readShort();
			logger.info("payloadLength=" + payloadLength);

			// Read sequence
			if (!buffer.isReadable(4)) {
				logger.info("Can't read sequence yet");
				buffer.resetReaderIndex();
				break;
			}

			var sequence = buffer.readInt();
			logger.info("sequence=" + sequence);

			// Read checksum
			if (!buffer.isReadable(16)) {
				logger.info("Can't read checksum yet");
				buffer.resetReaderIndex();
				break;
			}

			var checksum = new byte[16];
			buffer.readBytes(checksum);
			logger.info("checksum=" + ByteBufUtil.hexDump(checksum));

			// Read payload
			if (!buffer.isReadable(payloadLength)) {
				logger.info("Can't read payload yet");
				buffer.resetReaderIndex();
				break;
			}

			var payload = new byte[payloadLength];
			buffer.readBytes(payload);
			logger.info("payload=" + ByteBufUtil.hexDump(payload));

			// Validate


			// Pass to next handler
			var packet = new GamePacket(command, Unpooled.wrappedBuffer(payload));
			ctx.fireChannelRead(packet);

			// Move readable bytes to start of buffer, if applicable
			logger.info("before, readerIndex=" + buffer.readerIndex() + ", readableBytes=" + buffer.readableBytes());
			logger.info(ByteBufUtil.hexDump(buffer));

			var readerIndex = buffer.readerIndex();
			var readableBytes = buffer.readableBytes();
			if (readableBytes > 0) {
				var length0 = Math.min(readerIndex, readableBytes);
				var length1 = readableBytes - length0;

				buffer.getBytes(readerIndex, buffer, 0, length0);

				if (length1 > 0) {
					buffer.getBytes(readerIndex + length0, buffer, length0, length1);
				}
			}

			buffer.readerIndex(0);
			buffer.writerIndex(readableBytes);

			logger.info("after, readerIndex=" + buffer.readerIndex() + ", readableBytes=" + buffer.readableBytes());
			logger.info(ByteBufUtil.hexDump(buffer));
		}
	}
}
