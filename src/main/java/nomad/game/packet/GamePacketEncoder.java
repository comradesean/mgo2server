package nomad.game.packet;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelOutboundHandlerAdapter;
import io.netty.channel.ChannelPromise;
import io.netty.util.AttributeKey;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class GamePacketEncoder extends ChannelOutboundHandlerAdapter {
	private static class EncodeState {
		public int sequence;

		public EncodeState(int sequence) {
			this.sequence = sequence;
		}
	}

	private static final Logger logger = LogManager.getLogger();

	private static final AttributeKey<EncodeState> ENCODE_STATE = AttributeKey.valueOf("encodeState");

	@Override
	public void write(ChannelHandlerContext ctx, Object msg, ChannelPromise promise) {
		if (msg instanceof GamePacket packet) {
			var encodeStateAttribute = ctx.channel().attr(ENCODE_STATE);
			var encodeState = encodeStateAttribute.get();
			if (encodeState == null) {
				encodeStateAttribute.set(encodeState = new EncodeState(1));
			}

			var payload = packet.getPayload();
			try {
				var buffer = ctx.alloc().buffer(24 + payload.readableBytes());
				buffer.writeShort(packet.getCommand());
				buffer.writeShort(payload.readableBytes());
				buffer.writeInt(encodeState.sequence++);
				buffer.writeZero(16);
				buffer.writeBytes(payload);
				ctx.write(buffer, promise);
			} finally {
				payload.release();
			}
		} else {
			ctx.write(msg, promise);
		}
	}

	@Override
	public void flush(ChannelHandlerContext ctx) {
		ctx.flush();
	}
}
