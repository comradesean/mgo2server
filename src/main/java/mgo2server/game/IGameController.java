package mgo2server.game;

import java.util.Map;
import java.util.function.Consumer;

public interface IGameController {
	void register(Map<Integer, Consumer<GameControllerContext>> handlers);

	/**
	 * Called when a connection drops, whether the client sent an explicit command or the socket just
	 * closed. Controllers holding per-connection resources (a hosted game, a game membership) tear
	 * them down here so a crash or network drop leaves no ghost. The default does nothing.
	 */
	default void onDisconnect(GameConnection connection) {
	}
}
