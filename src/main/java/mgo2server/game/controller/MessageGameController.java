package mgo2server.game.controller;

import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;
import java.util.function.Consumer;

/**
 * The mailbox, which the client reads as soon as it joins a game lobby.
 * <p>
 * Like the character name check, this is not optional: the client waits for the reply and fails
 * with <em>Unable to connect to lobby (092E:FFFFFF60)</em> if none arrives.
 * <p>
 * Messages themselves are not implemented. The list is returned empty, which is a real answer
 * rather than a stub — a player with no mail is the ordinary case, and the client renders it. The
 * request carries the mailbox to read: {@code 0x0f} for mail and {@code 0x10} for clan
 * applications, both of which are empty here until those features exist.
 */
public class MessageGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int GET_MESSAGES = 0x4820;

	public static final int GET_MESSAGES_START = 0x4821;

	public static final int GET_MESSAGES_DATA = 0x4822;

	public static final int GET_MESSAGES_END = 0x4823;

	/** Mailbox selectors, named after the reference servers. */
	private static final int MAIL = 0x0f;

	private static final int CLAN_APPLICATIONS = 0x10;

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_MESSAGES, this::getMessages);
	}

	private void getMessages(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(GET_MESSAGES_START, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var mailbox = payload.readableBytes() > 0 ? payload.readByte() & 0xff : MAIL;
		if (mailbox != MAIL && mailbox != CLAN_APPLICATIONS) {
			logger.warn("Get messages: unknown mailbox 0x{}.", Integer.toHexString(mailbox));
		}

		// Start then end, with no data packets in between: the mailbox is empty.
		ctx.write(GET_MESSAGES_START, GameError.NONE);
		ctx.write(GET_MESSAGES_END, GameError.NONE);
	}
}
