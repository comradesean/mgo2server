package nomad;

import io.netty.bootstrap.Bootstrap;
import io.netty.channel.*;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import nomad.game.packet.GamePacketDecoder;
import nomad.game.packet.GamePacketEncoder;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public class GameClient {
	private static final Logger logger = LogManager.getLogger();

	private MultiThreadIoEventLoopGroup workerGroup;

	public void run(long timeout, ChannelHandler clientHandler) {
		workerGroup = new MultiThreadIoEventLoopGroup(NioIoHandler.newFactory());

		var bootstrap = new Bootstrap();
		bootstrap.group(workerGroup);
		bootstrap.channel(NioSocketChannel.class);
		bootstrap.option(ChannelOption.SO_KEEPALIVE, true);

		var closeFuture = new CompletableFuture<Void>();
		var closeHandler = new ChannelOutboundHandlerAdapter() {
			@Override
			public void close(ChannelHandlerContext ctx, ChannelPromise promise) {
				closeFuture.complete(null);
			}
		};

		var packetEncoder = new GamePacketEncoder();
		var packetDecoder = new GamePacketDecoder();
		bootstrap.handler(new ChannelInitializer<SocketChannel>() {
			@Override
			public void initChannel(SocketChannel ch) {
				ch.pipeline().addLast(closeHandler).addLast(packetEncoder).addLast(packetDecoder).addLast(clientHandler);
			}
		});

		bootstrap.connect("localhost", 5730); // .addListener(e -> future.complete(null))

		closeFuture.orTimeout(timeout, TimeUnit.SECONDS).join();
	}

	public CompletableFuture<Void> disconnect() {
		return disconnect(2L, 15L, TimeUnit.SECONDS);
	}

	public CompletableFuture<Void> disconnect(long quietPeriod, long timeout, TimeUnit unit) {
		var future = new CompletableFuture<Void>();
		workerGroup.shutdownGracefully(quietPeriod, timeout, unit).addListener(e -> future.complete(null));
		return future;
	}
}
