package nomad.game.controller;

import io.netty.buffer.ByteBuf;
import nomad.common.BufferUtil;
import nomad.common.service.NewsService;
import nomad.game.GameControllerContext;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Map;
import java.util.function.Consumer;

public class NewsGameController implements IGameController {
	private final NewsService newsService;

	public NewsGameController(NewsService newsService) {
		this.newsService = newsService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(0x2008, this::getNewsItems);
	}

	private void getNewsItems(GameControllerContext ctx) {
		var message = newsService.getNewsItems();
		System.out.println(message);

		var buffers = new ArrayList<ByteBuf>();
		for (var newsItem : message.getNewsItems()) {
			var buffer = ctx.buffer(1023);

			buffer.writeInt((int) newsItem.getId()).writeBoolean(newsItem.isImportant())
				.writeInt((int) newsItem.getTime().toEpochSecond());

			BufferUtil.writeString(buffer, newsItem.getTitle(), StandardCharsets.ISO_8859_1, 128);
			BufferUtil.writeString(buffer, newsItem.getBody(), StandardCharsets.ISO_8859_1, 886);

			buffers.add(buffer);
		}

		ctx.write(new GamePacket(0x2009, 0));
		for (var buffer : buffers) {
			ctx.write(new GamePacket(0x200a, buffer));
		}
		ctx.write(new GamePacket(0x200b, 0));
	}
}
