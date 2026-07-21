package mgo2server.game;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import mgo2server.game.packet.GamePacket;

import java.net.InetSocketAddress;
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

	/** Per-connection state, including the authenticated account. */
	public GameConnection connection() {
		return GameConnection.of(channelHandlerContext.channel());
	}

	/**
	 * The client's own address as seen from this side of the socket. The peer-to-peer public
	 * address is read from here rather than trusted from the payload, matching the reference
	 * servers — a client cannot lie about where its packets actually come from.
	 */
	public String remoteIp() {
		var address = channelHandlerContext.channel().remoteAddress();
		if (address instanceof InetSocketAddress socketAddress) {
			return socketAddress.getAddress().getHostAddress();
		}
		return null;
	}

	/** Writes a bare result packet, masking the code as the client expects. */
	public void write(int command, GameError error) {
		write(new GamePacket(command, error.result()));
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

	/** Closes the connection once anything already written has been flushed. */
	public void close() {
		channelHandlerContext.flush();
		channelHandlerContext.close();
	}
}
