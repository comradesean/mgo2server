package mgo2server.game;

import io.netty.channel.Channel;

import java.util.Map;
import java.util.function.Consumer;

public interface IGameController {
	void register(Map<Integer, Consumer<GameControllerContext>> handlers);

	/**
	 * Called for every inbound packet, before it is dispatched, whether or not this controller
	 * handles that command and whether or not any controller does.
	 * <p>
	 * Exists so a controller that has to reach a client <em>other</em> than the one currently asking
	 * can learn which channel belongs to which character. Every other write in this server goes back
	 * down the requesting channel, where {@link GameControllerContext} is enough; in-game chat is
	 * the exception, because the client renders a chat line only from a packet the server pushes
	 * (see {@code ChatGameController}). The default does nothing.
	 */
	default void onPacket(GameConnection connection, Channel channel) {
	}

	/**
	 * Called when a connection drops, whether the client sent an explicit command or the socket just
	 * closed. Controllers holding per-connection resources (a hosted game, a game membership) tear
	 * them down here so a crash or network drop leaves no ghost. The default does nothing.
	 */
	default void onDisconnect(GameConnection connection) {
	}
}
