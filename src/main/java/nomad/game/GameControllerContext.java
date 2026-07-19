package nomad.game;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import nomad.game.packet.GamePacket;

import java.util.List;

public class GameControllerContext {
	private final ChannelHandlerContext channelHandlerContext;

	private final GamePacket packet;

	private final List<ByteBuf> allocations;

	public GameControllerContext(ChannelHandlerContext channelHandlerContext, GamePacket packet, List<ByteBuf> allocations) {
		this.channelHandlerContext = channelHandlerContext;
		this.packet = packet;
		this.allocations = allocations;
	}

	public GamePacket packet() {
		return packet;
	}

	public ByteBuf buffer(int initialCapacity) {
		var buffer = channelHandlerContext.alloc().buffer(initialCapacity);
		if (buffer != null) {
			allocations.add(buffer);
		}
		return buffer;
	}

	public void write(GamePacket packet) {
		channelHandlerContext.write(packet);
	}
}
