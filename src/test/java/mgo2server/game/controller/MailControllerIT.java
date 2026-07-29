package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The mailbox family: send ({@code 0x4800}), list ({@code 0x4820}), open ({@code 0x4840}) and
 * delete ({@code 0x4880}).
 * <p>
 * Every size and constant asserted here is read from the client's own parsers, and several are
 * load-bearing in ways that fail <em>silently</em> — which is why they are pinned:
 * <ul>
 * <li>{@code 0x4801}'s flags byte must have bit 0 set. Clear, the client does not error: it
 *     re-sends the whole letter as a 969-byte {@code 0x4860} and keeps waiting.</li>
 * <li>{@code 0x4822} carries <b>one</b> entry per packet — its parser has no loop, so a packet
 *     with three entries delivers one and drops two.</li>
 * <li>{@code 0x4822}'s leading byte is a routing index the client uses <b>unchecked</b>; the
 *     value must stay in 0..3. Sending the {@code 0x4820} selector (0x0F) there wrote 280 bytes
 *     past the end of a client heap allocation.</li>
 * <li>{@code 0x4841} must carry the full 708-byte body block: a short reply is copied out of
 *     stale receive buffer and reported as success.</li>
 * </ul>
 * Read and deleted state are per-side, because one row is a single delivery seen from both ends
 * and the wire has no field for either.
 */
public class MailControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	/** 0x4800: count, 8 x name[16], subject[128], body[708], two trailing bytes. */
	private static final int SEND_SIZE = 1 + 8 * 16 + 128 + 708 + 2;

	private static final int ENTRY_SIZE = 266;

	private static final int READ_REPLY_SIZE = Integer.BYTES + 708;

	private long charaId;

	private long friendId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private long givenCharacter(String name, boolean select) {
		var jdbi = TestDatabase.get().jdbi();
		var accountId = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values (:name, 'x', :session, 3)
					""")
				.bind("name", name)
				.bind("session", select ? SessionField.stored(TOKEN) : name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());

		var id = jdbi.withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId).bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());

		jdbi.useHandle(handle -> handle.createUpdate("""
				update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
				""").bind("chara", id).bind("id", accountId).execute());
		return id;
	}

	private void givenTwoCharacters() {
		charaId = givenCharacter("Snake", true);
		friendId = givenCharacter("Otacon", false);
	}

	/** Logs in, plays each request in turn, and collects every reply. */
	private List<GamePacket> exchange(GamePacket... requests) {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));

		var replies = java.util.Collections.synchronizedList(new ArrayList<GamePacket>());
		var sent = new int[] { 0 };

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				if (packet.getCommand() != AccountGameController.CHECK_SESSION_RESULT) {
					replies.add(packet);
				}
				// The list is a triple, so only advance once its terminator arrives.
				var terminal = packet.getCommand() != MessageGameController.GET_MESSAGES_START
					&& packet.getCommand() != MessageGameController.GET_MESSAGES_DATA;
				if (!terminal) {
					return;
				}
				if (sent[0] < requests.length) {
					ctx.writeAndFlush(requests[sent[0]++]);
				} else {
					ctx.close();
				}
			}
		});

		synchronized (replies) {
			return new ArrayList<>(replies);
		}
	}

	private static GamePacket sendMail(String recipient, String subject, String body) {
		var payload = Unpooled.buffer(SEND_SIZE, SEND_SIZE);
		payload.writeByte(1);
		payload.writeBytes(fixed(recipient, 16));
		payload.writeZero(7 * 16);
		payload.writeBytes(fixed(subject, 128));
		payload.writeBytes(fixed(body, 708));
		payload.writeZero(2);
		return new GamePacket(MessageGameController.SEND_MESSAGE, payload);
	}

	private static byte[] fixed(String text, int width) {
		var out = new byte[width];
		var raw = text.getBytes(StandardCharsets.ISO_8859_1);
		System.arraycopy(raw, 0, out, 0, Math.min(raw.length, width));
		return out;
	}

	private static GamePacket listMail() {
		var payload = Unpooled.buffer();
		payload.writeByte(0x0f);
		return new GamePacket(MessageGameController.GET_MESSAGES, payload);
	}

	private static GamePacket openMail(int category, int index) {
		var payload = Unpooled.buffer();
		payload.writeByte(category).writeByte(index);
		return new GamePacket(MessageGameController.READ_MESSAGE, payload);
	}

	private static GamePacket deleteMail(int category, int index) {
		var payload = Unpooled.buffer();
		payload.writeByte(category).writeByte(index);
		return new GamePacket(MessageGameController.DELETE_MESSAGE, payload);
	}

	private static String stringAt(ByteBuf buffer, int offset, int width) {
		var raw = buffer.toString(offset, width, StandardCharsets.ISO_8859_1);
		var end = raw.indexOf(0);
		return end < 0 ? raw : raw.substring(0, end);
	}

	private static List<GamePacket> entries(List<GamePacket> replies) {
		return replies.stream()
			.filter(packet -> packet.getCommand() == MessageGameController.GET_MESSAGES_DATA)
			.toList();
	}

	@Test
	public void sendReplyIsFiveBytesAndSetsTheFlagsBit() {
		givenTwoCharacters();

		var replies = exchange(sendMail("Otacon", "hi", "poop"));

		assertThat(replies).hasSize(1);
		var reply = replies.get(0);
		assertThat(reply.getCommand()).isEqualTo(MessageGameController.SEND_MESSAGE_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(5);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		// Bit 0 clear makes the client re-send the letter as 0x4860 instead of completing the
		// request — indistinguishable from no reply at all from the player's side.
		assertThat(reply.getPayload().getByte(4) & 0x01).isEqualTo(1);
	}

	@Test
	public void sentLetterReachesTheRecipientsInboxAndTheSendersSentList() {
		givenTwoCharacters();

		var stored = exchange(sendMail("Otacon", "subject", "body"));
		assertThat(stored).hasSize(1);

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("""
					select m.subject, m.body, m.sender_name, r.name as recipient
					from mail m join chara r on r.id = m.recipient_chara_id
					""")
				.map((rs, ctx) -> rs.getString("subject") + "|" + rs.getString("body") + "|"
					+ rs.getString("sender_name") + "|" + rs.getString("recipient"))
				.one());
		assertThat(row).isEqualTo("subject|body|Snake|Otacon");
	}

	@Test
	public void unknownRecipientIsDroppedButStillReportsSuccess() {
		givenTwoCharacters();

		var replies = exchange(sendMail("NoSuchPerson", "s", "b"));

		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		var count = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail").mapTo(Long.class).one());
		assertThat(count).isZero();
	}

	@Test
	public void listCarriesOneEntryPerPacketWithARoutableCategory() {
		givenTwoCharacters();

		var replies = exchange(sendMail("Snake", "first", "one"),
			sendMail("Snake", "second", "two"), listMail());

		var start = replies.stream()
			.filter(p -> p.getCommand() == MessageGameController.GET_MESSAGES_START).toList();
		assertThat(start).hasSize(1);
		assertThat(start.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		var data = entries(replies);
		// Two letters to self = two inbox entries plus two sent entries, ONE per packet: the
		// 0x4822 parser has no loop, so batching would silently drop all but the first.
		assertThat(data).hasSize(4);
		for (var packet : data) {
			assertThat(packet.getPayload().readableBytes()).isEqualTo(ENTRY_SIZE);
			// The leading byte indexes an array of four unchecked by the client.
			assertThat(packet.getPayload().getByte(0)).isBetween((byte) 0, (byte) 3);
		}

		var end = replies.stream()
			.filter(p -> p.getCommand() == MessageGameController.GET_MESSAGES_END).toList();
		assertThat(end).hasSize(1);
		assertThat(end.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	@Test
	public void entryCarriesCounterpartyAndSubjectWithDistinctIndices() {
		givenTwoCharacters();

		var replies = exchange(sendMail("Snake", "hello", "body"), listMail());
		var data = entries(replies);
		assertThat(data).hasSize(2); // one inbox, one sent — same row, both ends

		for (var packet : data) {
			var payload = packet.getPayload();
			assertThat(stringAt(payload, 3, 128)).isEqualTo("Snake");
			assertThat(stringAt(payload, 131, 128)).isEqualTo("hello");
			assertThat(payload.getUnsignedByte(1)).isZero(); // first in its own list
			assertThat(payload.getUnsignedByte(265)).isZero(); // 0 = unread
		}
	}

	@Test
	public void openingReturnsTheFullBodyBlockAndPersistsTheReadFlag() {
		givenTwoCharacters();

		var replies = exchange(sendMail("Snake", "s", "the body"), listMail(),
			openMail(0, 0), listMail());

		var read = replies.stream()
			.filter(p -> p.getCommand() == MessageGameController.READ_MESSAGE_RESULT).toList();
		assertThat(read).hasSize(1);
		// 712 bytes: a short reply is copied out of stale receive buffer and reported as success.
		assertThat(read.get(0).getPayload().readableBytes()).isEqualTo(READ_REPLY_SIZE);
		assertThat(read.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(stringAt(read.get(0).getPayload(), 4, 708)).isEqualTo("the body");

		// The client marks its own copy read on open, but 0x4821 zeroes the counters and the list
		// is rebuilt from our entries — so unless the server stores it, the letter comes back new.
		var inboxAfter = entries(replies).stream()
			.filter(p -> p.getPayload().getByte(0) == 0).toList();
		assertThat(inboxAfter).hasSize(2); // before and after the open
		assertThat(inboxAfter.get(0).getPayload().getUnsignedByte(265)).isZero();
		assertThat(inboxAfter.get(1).getPayload().getUnsignedByte(265)).isEqualTo((short) 1);
	}

	@Test
	public void deletingFromOneSideLeavesTheOtherSidesCopy() {
		givenTwoCharacters();

		// Snake mails Snake, so both the inbox and the sent list show the same row.
		var replies = exchange(sendMail("Snake", "s", "b"), deleteMail(0, 0), listMail());

		var ack = replies.stream()
			.filter(p -> p.getCommand() == MessageGameController.DELETE_MESSAGE_RESULT).toList();
		assertThat(ack).hasSize(1);
		assertThat(ack.get(0).getPayload().readableBytes()).isEqualTo(Integer.BYTES);

		// Gone from the inbox, still in Sent — the wire has no deletion field, so this is only
		// expressible in storage.
		var data = entries(replies);
		assertThat(data).hasSize(1);
		assertThat(data.get(0).getPayload().getByte(0)).isEqualTo((byte) 1);

		var remaining = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail where not sender_deleted")
				.mapTo(Long.class).one());
		assertThat(remaining).isEqualTo(1);
	}

	@Test
	public void deletingFromBothSidesRemovesTheRow() {
		givenTwoCharacters();

		exchange(sendMail("Snake", "s", "b"), deleteMail(0, 0), deleteMail(1, 0));

		var rows = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail").mapTo(Long.class).one());
		assertThat(rows).isZero();
	}

	/**
	 * Opening a letter that is not there is refused, and the refusal is FOUR bytes.
	 * <p>
	 * This test previously asserted a full-length success, on the "still answers" principle — the
	 * important thing being that the client is answered at all rather than left to stall. That
	 * principle stands and is still asserted; what changed is that answering <em>success</em> was
	 * the wrong way to honour it, and actively unsafe.
	 * <p>
	 * The parser reads the 708-byte body <b>only when the result is zero</b>, and its reader
	 * bound-checks against the 1023-byte packet buffer rather than the payload — so a success reply
	 * that is short copies stale buffer into the mail object and reports it as a letter. A nonzero
	 * result skips the read entirely, which is why the failure shape is a bare result word.
	 * <p>
	 * {@code -800} renders as "Unable to locate designated mail." [ELF sweep, chain {@code 0x8E9DEC},
	 * 4352/4352 verified.]
	 */
	@Test
	public void openingAnIndexTheCharacterDoesNotOwnIsRefused() {
		givenTwoCharacters();

		var replies = exchange(openMail(0, 7));

		assertThat(replies).as("answered at all — a silent drop stalls the client").hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(MessageGameController.READ_MESSAGE_RESULT);
		assertThat(replies.get(0).getPayload().readableBytes())
			.as("a failure is the bare result word; the body is only read on success")
			.isEqualTo(Integer.BYTES);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(-800);
	}

	/** Deleting a letter that is not there is refused too, rather than reported as deleted. */
	@Test
	public void deletingAnIndexTheCharacterDoesNotOwnIsRefused() {
		givenTwoCharacters();

		var replies = exchange(deleteMail(0, 7));

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand())
			.isEqualTo(MessageGameController.DELETE_MESSAGE_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(-800);
	}
}
