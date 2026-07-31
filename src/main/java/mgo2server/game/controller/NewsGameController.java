package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.service.NewsService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Map;
import java.util.function.Consumer;

public class NewsGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/** Protocol: a fixed field the client reads as exactly this many bytes. */
	private static final int TITLE_LENGTH = 128;

	private final NewsService newsService;

	public NewsGameController(NewsService newsService) {
		this.newsService = newsService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(0x2008, this::getNewsItems);
	}

	/** {@code u32 id}, {@code u8 important}, {@code u32 time}, {@code char[128] title}. */
	private static final int FIXED_PART = 4 + 1 + 4 + TITLE_LENGTH;

	/**
	 * Protocol: the client's table holds ten entries and it <b>aborts the whole reply with -71</b>
	 * on the eleventh ({@code cmpwi r3,9; bgt} at {@code 0xD366D0}). An eleventh news row would not
	 * be dropped, it would lose the entire news screen.
	 */
	private static final int MAX_ITEMS = 10;

	/**
	 * Protocol: the client's per-entry body buffer. Each table entry is 920 bytes with the body at
	 * offset 145, leaving 775 including the terminator.
	 * <p>
	 * <b>This is a client-side overrun, not a truncation.</b> The reader {@code 0xD5CE34} bounds
	 * only its source (`pos+i <= 1023`) and never its destination, so a body longer than this walks
	 * off the end of a 920-byte stack temporary in the client. Our column is {@code varchar(886)},
	 * which is wider than the client can hold — so the cap has to be enforced here.
	 */
	private static final int MAX_BODY = 774;

	private void getNewsItems(GameControllerContext ctx) {
		var message = newsService.getNewsItems();
		var items = message.getNewsItems();
		if (items.size() > MAX_ITEMS) {
			logger.warn("{} news items, but the client aborts above {} — serving the first {}.",
				items.size(), MAX_ITEMS, MAX_ITEMS);
			items = items.subList(0, MAX_ITEMS);
		}

		var buffers = new ArrayList<ByteBuf>();
		for (var newsItem : items) {
			var body = newsItem.getBody() == null ? "" : newsItem.getBody();
			if (body.length() > MAX_BODY) {
				logger.warn("News {} body is {} characters; truncating to {}.",
					newsItem.getId(), body.length(), MAX_BODY);
				body = body.substring(0, MAX_BODY);
			}
			var buffer = ctx.buffer(FIXED_PART + body.length() + 1);

			buffer.writeInt((int) newsItem.getId()).writeBoolean(newsItem.isImportant())
				.writeInt((int) newsItem.getTime().toEpochSecond());

			BufferUtil.writeString(buffer, newsItem.getTitle(), StandardCharsets.ISO_8859_1,
				TITLE_LENGTH);

			// The body is delimiter-terminated, NOT a fixed field: the client reads it with the
			// terminated-string primitive 0xD5CE34 (from 0xD366B0) and then KEEPS PARSING RECORDS
			// out of whatever is left in the packet.
			//
			// So the 886 bytes of NUL padding this used to write were not inert. They were parsed
			// as further news items. An empty record costs 138 bytes -- the 137-byte fixed part plus
			// a lone terminator -- so every item we sent manufactured about six phantom entries with
			// id 0, time 0 and an empty title, which the screen rendered as blank pages dated
			// 12-31-1969.
			//
			// [OBSERVED 2026-07-27] Predicted to the page before this fix. Two items with bodies of
			// 19 and 134 characters left 866 and 751 bytes of padding, giving 6 and 5 phantoms: 13
			// entries, capped at the client's limit of 10, with the second real item at position 8.
			// The client showed exactly 10 pages with real items on 1 and 8.
			//
			// The same arithmetic pins two things the docs had only assumed. The title really is a
			// fixed 128-byte field -- were it terminated too, a phantom would cost 11 bytes and there
			// would have been ~89 of them. And the terminator is exactly one byte, so it is the NUL
			// that writeString would have appended anyway.
			BufferUtil.writeString(buffer, body, StandardCharsets.ISO_8859_1, body.length());
			buffer.writeByte(0);

			buffers.add(buffer);
		}

		ctx.write(new GamePacket(0x2009, 0));
		for (var buffer : buffers) {
			ctx.write(new GamePacket(0x200a, buffer));
		}
		ctx.write(new GamePacket(0x200b, 0));
	}
}
