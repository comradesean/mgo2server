package nomad.game;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.ReferenceCountUtil;
import nomad.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

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
	public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
		logger.error(cause);
	}
}
