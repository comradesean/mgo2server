package nomad.game;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.ChannelOption;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import nomad.game.packet.GamePacketDecoder;
import nomad.game.packet.GamePacketEncoder;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public class GameServer {
	private static final Logger logger = LogManager.getLogger();

	private final CompletableFuture<Void> stopFuture = new CompletableFuture<>();

	private final List<IGameController> controllers;

	private EventLoopGroup bossGroup;

	private EventLoopGroup workerGroup;

	public GameServer(List<IGameController> controllers) {
		this.controllers = controllers;
	}

	public CompletableFuture<Void> start() {
		bossGroup = new MultiThreadIoEventLoopGroup(NioIoHandler.newFactory());
		workerGroup = new MultiThreadIoEventLoopGroup(NioIoHandler.newFactory());

		var b = new ServerBootstrap();

		b.group(bossGroup, workerGroup);

		b.channel(NioServerSocketChannel.class);

		var packetDecoder = new GamePacketDecoder();
		var packetEncoder = new GamePacketEncoder();
		var serverHandler = new GameServerHandler(controllers);
		b.childHandler(new GameServerChannelInitializer(packetDecoder, serverHandler, packetEncoder));

		b.option(ChannelOption.SO_BACKLOG, 128);

		b.childOption(ChannelOption.SO_KEEPALIVE, true);

		var future = new CompletableFuture<Void>();
		b.bind(5730).addListener(e -> future.complete(null));
		return future;
	}

	public CompletableFuture<Void> stop() {
		return stop(2L, 15L, TimeUnit.SECONDS);
	}

	public CompletableFuture<Void> stop(long quietPeriod, long timeout, TimeUnit unit) {
		var futures = new ArrayList<CompletableFuture<Void>>();

		if (workerGroup != null) {
			var future = new CompletableFuture<Void>();
			workerGroup.shutdownGracefully(quietPeriod, timeout, unit).addListener(e -> future.complete(null));
			futures.add(future);
		}

		if (bossGroup != null) {
			var future = new CompletableFuture<Void>();
			bossGroup.shutdownGracefully(quietPeriod, timeout, unit).addListener(e -> future.complete(null));
			futures.add(future);
		}

		return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]));
	}

	public void run() {
		Runtime.getRuntime().addShutdownHook(new Thread(this::stop));

		start().join();

		stopFuture.join();
	}

	public static void main(String[] args) {
		GameServerFactory.createGameServer().run();
	}
}
