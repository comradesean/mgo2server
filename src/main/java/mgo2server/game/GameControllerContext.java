package mgo2server.game;

import io.netty.buffer.ByteBuf;
import io.netty.channel.Channel;
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
	 * This request's channel, for a handler that needs to keep hold of it past the reply.
	 * <p>
	 * Only for <em>storing</em>. Writing a reply still goes through {@link #write}, and a push to a
	 * different client must allocate from that client's own channel — the encoders are per-channel
	 * and carry sequence counters, so neither a buffer nor a context may be shared across channels.
	 */
	public Channel channel() {
		return channelHandlerContext.channel();
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
