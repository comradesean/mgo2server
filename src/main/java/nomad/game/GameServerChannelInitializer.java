package nomad.game;

import io.netty.channel.ChannelInitializer;
import io.netty.channel.socket.SocketChannel;
import nomad.game.packet.GamePacketDecoder;
import nomad.game.packet.GamePacketEncoder;

public class GameServerChannelInitializer extends ChannelInitializer<SocketChannel> {
	private final GamePacketDecoder packetDecoder;

	private final GameServerHandler serverHandler;

	private final GamePacketEncoder packetEncoder;

	public GameServerChannelInitializer(GamePacketDecoder packetDecoder, GameServerHandler serverHandler, GamePacketEncoder packetEncoder) {
		this.packetDecoder = packetDecoder;
		this.serverHandler = serverHandler;
		this.packetEncoder = packetEncoder;
	}

	@Override
	public void initChannel(SocketChannel ch) {
		var pipeline = ch.pipeline();
		pipeline.addLast(packetEncoder);
		pipeline.addLast(packetDecoder);
		pipeline.addLast(serverHandler);
	}
}
