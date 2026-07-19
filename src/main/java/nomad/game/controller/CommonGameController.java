package nomad.game.controller;

import nomad.game.GameControllerContext;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * Commands every lobby answers, whatever its type.
 * <p>
 * The original handles these ahead of the per-lobby dispatch, so a gate, an account lobby and a
 * game lobby all respond identically. Without them a client that has finished with a lobby waits
 * for a close that never comes.
 */
public class CommonGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/** The client is done with this lobby and expects the connection to close. */
	public static final int DISCONNECT = 0x0003;

	/** Keepalive; echoed straight back. */
	public static final int PING = 0x0005;

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(DISCONNECT, this::disconnect);
		handlers.put(PING, this::ping);
	}

	private void disconnect(GameControllerContext ctx) {
		logger.debug("Client requested disconnect.");
		ctx.close();
	}

	private void ping(GameControllerContext ctx) {
		ctx.write(new GamePacket(PING));
	}
}
