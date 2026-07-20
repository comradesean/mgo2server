package mgo2server.game;

import io.netty.channel.ChannelInitializer;
import io.netty.channel.socket.SocketChannel;
import mgo2server.game.packet.GamePacketDecoder;
import mgo2server.game.packet.GamePacketEncoder;

public class GameServerChannelInitializer extends ChannelInitializer<SocketChannel> {
	private final GameServerHandler serverHandler;

	public GameServerChannelInitializer(GameServerHandler serverHandler) {
		this.serverHandler = serverHandler;
	}

	@Override
	public void initChannel(SocketChannel ch) {
		var pipeline = ch.pipeline();
		// The codecs carry per-connection sequence counters, so each channel needs its own
		// instances. Only the handler, which is stateless, is shared.
		pipeline.addLast(GamePacketEncoder.forServer());
		pipeline.addLast(GamePacketDecoder.forServer());
		pipeline.addLast(serverHandler);
	}
}
