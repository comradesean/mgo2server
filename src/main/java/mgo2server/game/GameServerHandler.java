package mgo2server.game;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandler;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.ReferenceCountUtil;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Dispatches decoded packets to the controller registered for their command.
 * <p>
 * Sharable, and deliberately so: one instance serves every channel. The handler map is built in
 * the constructor and only read afterwards, so there is no per-connection state here — that lives
 * in {@link GameConnection} and in the codecs.
 */
@ChannelHandler.Sharable
public class GameServerHandler extends ChannelInboundHandlerAdapter {
	private static final Logger logger = LogManager.getLogger();

	private final Map<Integer, Consumer<GameControllerContext>> handlers = new HashMap<>();

	public GameServerHandler(List<IGameController> controllers) {
		for (var controller : controllers) {
			var map = new HashMap<Integer, Consumer<GameControllerContext>>();
			controller.register(map);
			handlers.putAll(map);
		}
	}

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		if (msg instanceof GamePacket packet) {
			var command = (int) packet.getCommand();
			var handler = handlers.get(command);
			if (handler == null) {
				// Silently dropping these makes a stalled client impossible to diagnose: the
				// connection looks healthy and simply stops.
				logger.warn("No handler for command {}; ignoring.", String.format("%04x", command));
			}
			if (handler != null) {
				var allocations = new ArrayList<ByteBuf>();
				try {
					var gameControllerContext = new GameControllerContext(ctx, packet, allocations);
					handler.accept(gameControllerContext);
				} catch (Exception e) {
					logger.error(e);
					for (var allocation : allocations) {
						allocation.release();
					}
				}
				ctx.flush();
			}
		} else {
			ReferenceCountUtil.release(msg);
		}
	}

	@Override
	public void channelActive(ChannelHandlerContext ctx) {
		// Connections are logged as well as packets. A client that connects and sends nothing is
		// otherwise completely invisible here, which is exactly the case worth seeing.
		logger.info("Connected: {}", ctx.channel().remoteAddress());
		ctx.fireChannelActive();
	}

	@Override
	public void channelInactive(ChannelHandlerContext ctx) {
		logger.info("Disconnected: {}", ctx.channel().remoteAddress());
		ctx.fireChannelInactive();
	}

	@Override
	public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
		logger.error(cause);
	}
}
