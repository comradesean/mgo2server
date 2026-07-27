package mgo2server.game;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.ByteBufUtil;
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

	private final List<IGameController> controllers;

	/**
	 * Which controller claimed each command, so a second claim can name both parties.
	 * <p>
	 * Registration used to be a plain {@code put} into a {@code HashMap} followed by
	 * {@code putAll}, which meant a command claimed twice was resolved by declaration order and
	 * nothing said so. {@code ClanGameController} claimed {@code 0x4b90} twice — as a "member
	 * action" and as clan search — and the second silently won for months. The wrong one winning
	 * would have been a stall; the right one winning was worse, because it left dead code that read
	 * the same bytes a different way and looked maintained.
	 * <p>
	 * A command has exactly one handler. Two is a bug in our wiring, not a runtime condition, so it
	 * fails at construction rather than being resolved by chance.
	 */
	private final Map<Integer, String> owners = new HashMap<>();

	public GameServerHandler(List<IGameController> controllers) {
		this.controllers = controllers;
		for (var controller : controllers) {
			var name = controller.getClass().getSimpleName();
			var map = new HashMap<Integer, Consumer<GameControllerContext>>();
			controller.register(map);

			for (var entry : map.entrySet()) {
				claim(entry.getKey(), name);
				handlers.put(entry.getKey(), entry.getValue());
			}
		}
	}

	private void claim(int command, String controller) {
		var previous = owners.put(command, controller);
		if (previous != null) {
			throw new IllegalStateException(String.format(
				"Command 0x%04x is registered twice, by %s and %s. One of them is dead code: a "
					+ "command has exactly one handler, and which one wins is declaration order.",
				command, previous, controller));
		}
	}

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		if (msg instanceof GamePacket packet) {
			var command = (int) packet.getCommand();

			// Before dispatch and regardless of whether anything handles this command: a controller
			// that pushes to other clients needs to see every connection, not just the ones that
			// talk to it. Failures here must not stop the packet being served.
			var connection = GameConnection.of(ctx.channel());
			for (var controller : controllers) {
				try {
					controller.onPacket(connection, ctx.channel());
				} catch (Exception e) {
					logger.error("onPacket failed in {}", controller.getClass().getSimpleName(), e);
				}
			}

			var handler = handlers.get(command);
			if (handler == null) {
				// Silently dropping these makes a stalled client impossible to diagnose: the
				// connection looks healthy and simply stops. The payload hex is the only record
				// of what the client asked for, so dump it here.
				logger.warn("No handler for command {}; ignoring. Payload: {}",
					String.format("%04x", command), ByteBufUtil.hexDump(packet.getPayload()));
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
		// A dropped socket sends no Quit Game, so tear down anything this connection was holding —
		// otherwise a crash or network drop leaves a ghost game or player behind. Failures here must
		// not stop the disconnect from propagating.
		var connection = GameConnection.of(ctx.channel());
		for (var controller : controllers) {
			try {
				controller.onDisconnect(connection);
			} catch (Exception e) {
				logger.error("Disconnect teardown failed in {}", controller.getClass().getSimpleName(), e);
			}
		}
		ctx.fireChannelInactive();
	}

	@Override
	public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
		logger.error(cause);
	}
}
