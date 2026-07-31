package mgo2server.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.common.model.News;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code 0x2008} — Online News.
 * <p>
 * The body is <b>delimiter-terminated, not a fixed field</b>: the client reads it with the
 * terminated-string primitive {@code 0xD5CE34} and then keeps parsing records out of whatever
 * remains in the packet. So trailing padding is not inert — it is more news items.
 * <p>
 * [OBSERVED 2026-07-27] This used to pad every body to 886 bytes to make the payload total 1023,
 * for a reason nobody recorded. Live, with two rows whose bodies were 19 and 134 characters, the
 * client showed <b>10 pages with real items on 1 and 8</b>: 866 and 751 bytes of leftover padding,
 * divided by the 138 bytes an empty record costs, is 6 and 5 phantom entries — 13 in all, capped
 * at the client's table limit of 10, with the second real item at position 8. Predicted to the
 * page before the fix.
 * <p>
 * The old test asserted all 1023 padded bytes as a literal, so it locked the bug in. These assert
 * the rule instead: one record per packet, nothing after the terminator.
 */
public class NewsGameControllerIT extends BaseGameClientServerIT {
	/** {@code u32 id}, {@code u8 important}, {@code u32 time}, {@code char[128] title}. */
private static final int TITLE_LENGTH = 128;

	private static final int FIXED_PART = 9 + TITLE_LENGTH;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GATE;
	}

	private List<GamePacket> fetchNews() {
		var packets = new ArrayList<GamePacket>();
		client.run(1, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(0x2008));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					packets.add(packet);
					if (packet.getCommand() == 0x200b) {
						ctx.close();
					}
				}
			}
		});
		return packets;
	}

	private News addNews(String title, String body) {
		var news = new News();
		news.setTime(Instant.ofEpochSecond(1213228801).atOffset(ZoneOffset.UTC));
		news.setImportant(true);
		news.setTitle(title);
		news.setBody(body);
		services.getNewsService().addNewsItem(news);
		return news;
	}

	/**
	 * The item whose title matches. Not simply the first {@code 0x200a} — these tests share a
	 * database and each adds a row, so the reply carries every item any of them created. Matched on
	 * title rather than id because {@code addNewsItem} does not write the generated id back.
	 */
	private static GamePacket itemFor(List<GamePacket> packets, String title) {
		return packets.stream()
			.filter(p -> p.getCommand() == 0x200a)
			.filter(p -> p.getPayload().slice(9, TITLE_LENGTH)
				.toString(StandardCharsets.ISO_8859_1).startsWith(title + "\0"))
			.findFirst()
			.orElseThrow(() -> new AssertionError("no news item titled " + title));
	}

	@Test
	public void servesAStartAnItemAndAnEnd() {
		addNews("Test", "Hello, world!");

		var packets = fetchNews();

		assertThat(packets.get(0).getCommand()).isEqualTo(0x2009);
		assertThat(packets.get(packets.size() - 1).getCommand()).isEqualTo(0x200b);
		assertThat(packets).anyMatch(p -> p.getCommand() == 0x200a);
	}

	@Test
	public void writesTheFieldsTheClientReads() {
		addNews("FieldsTest", "Hello, world!");

		var payload = itemFor(fetchNews(), "FieldsTest").getPayload();

		assertThat(payload.getInt(0)).isPositive();
		assertThat(payload.getByte(4)).isEqualTo((byte) 1);
		assertThat(payload.getInt(5)).isEqualTo(1213228801);
		assertThat(payload.slice(9, 10).toString(StandardCharsets.ISO_8859_1)).isEqualTo("FieldsTest");

		// The title IS a fixed 128-byte field, NUL-padded. The phantom-record arithmetic only works
		// out at six per item if it is: were the title terminated like the body, an empty record
		// would cost 11 bytes and the client would have shown about 89 pages rather than 7.
		assertThat(payload.getByte(9 + 10)).isZero();

		assertThat(payload.slice(FIXED_PART, 13).toString(StandardCharsets.ISO_8859_1))
			.isEqualTo("Hello, world!");
	}

	/**
	 * The regression. Anything after the body's terminator is parsed as another news item, so the
	 * payload has to end there.
	 */
	@Test
	public void endsAtTheBodyTerminatorWithNoPadding() {
		var body = "Hello, world!";
		addNews("NoPadding", body);

		var payload = itemFor(fetchNews(), "NoPadding").getPayload();

		assertThat(payload.readableBytes())
			.as("one record: 137 fixed, the body, one terminator, and nothing after it")
			.isEqualTo(FIXED_PART + body.length() + 1);
		assertThat(payload.getByte(payload.readableBytes() - 1))
			.as("the terminator is the last byte in the packet")
			.isZero();
	}

	/** An empty body is one byte — the terminator — not a packet full of zeros. */
	@Test
	public void anEmptyBodyStillTerminates() {
		addNews("EmptyBody", "");

		var payload = itemFor(fetchNews(), "EmptyBody").getPayload();

		assertThat(payload.readableBytes()).isEqualTo(FIXED_PART + 1);
		assertThat(payload.getByte(FIXED_PART)).isZero();
	}

	/** Each item gets its own packet; the client must never see two records in one. */
	@Test
	public void sendsOnePacketPerItem() {
		addNews("First", "one");
		addNews("Second", "two");

		var items = fetchNews().stream().filter(p -> p.getCommand() == 0x200a).toList();

		assertThat(items).hasSizeGreaterThanOrEqualTo(2);
		assertThat(items).allSatisfy(item -> assertThat(item.getPayload().readableBytes())
			.as("no item carries padding")
			.isLessThan(FIXED_PART + 886));
	}
}
