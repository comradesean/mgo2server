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

	/** Per-character login token, keyed by chara id — {@code account.session} is unique, so two
	 * characters cannot share {@link #TOKEN} verbatim. Populated by {@link #givenCharacter}, read
	 * by {@link #exchange(long, GamePacket...)}. */
	private final java.util.Map<Long, String> tokens = new java.util.HashMap<>();

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	/** A sixteen-character token distinct per name, padded/truncated from {@link #TOKEN}. */
	private static String tokenFor(String name) {
		return (name + TOKEN).substring(0, SessionField.TOKEN_LENGTH);
	}

	/** Gives the character a real stored session, so {@link #exchange(long, GamePacket...)} can
	 * log in as it. */
	private long givenCharacter(String name) {
		var jdbi = TestDatabase.get().jdbi();
		var token = tokenFor(name);
		var accountId = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values (:name, 'x', :session, 3)
					""")
				.bind("name", name)
				.bind("session", SessionField.stored(token))
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());

		var id = jdbi.withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId).bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());

		jdbi.useHandle(handle -> handle.createUpdate("""
				update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
				""").bind("chara", id).bind("id", accountId).execute());
		tokens.put(id, token);
		return id;
	}

	private void givenTwoCharacters() {
		charaId = givenCharacter("Snake");
		friendId = givenCharacter("Otacon");
	}

	/** Logs in as the test's default character, plays each request in turn, collects every reply. */
	private List<GamePacket> exchange(GamePacket... requests) {
		return exchange(charaId, requests);
	}

	/** Logs in as {@code asCharaId}, plays each request in turn, and collects every reply. */
	private List<GamePacket> exchange(long asCharaId, GamePacket... requests) {
		var login = Unpooled.buffer();
		login.writeInt((int) asCharaId);
		login.writeBytes(SessionField.of(tokens.get(asCharaId)));

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

	/**
	 * A letter To -> GM is stored, not silently dropped.
	 * <p>
	 * A GM letter carries NO recipient — count 0, all eight name slots zero — and marks itself with
	 * a single byte at wire {@code 0x3C5}, immediately after the body. [ELF] the client writes 3
	 * there at {@code 0x8EEAA8}, reached only when bit 18 of the compose screen's flags is set —
	 * the same bit that greys out the recipient-list row, confirmed live. (Bit 18, not 17:
	 * {@code rldicl. r9,r0,46,63} tests bit 64-46.)
	 * <p>
	 * Before 2026-07-29 this fell through the recipient loop as "0 of 0 delivered" and was answered
	 * SUCCESS, so the player was told it sent and nothing was stored anywhere.
	 */
	@Test
	public void aLetterToTheGameMasterIsStored() {
		givenTwoCharacters();

		var payload = Unpooled.buffer(SEND_SIZE, SEND_SIZE);
		payload.writeByte(0);                 // no recipients
		payload.writeZero(8 * 16);            // all name slots empty
		payload.writeBytes(fixed("HELP", 128));
		payload.writeBytes(fixed("AN ALLIGATOR GOT ME", 708));
		payload.writeByte(3).writeByte(0);    // wire 0x3C5 = 3, Game Master

		var replies = exchange(new GamePacket(MessageGameController.SEND_MESSAGE, payload));

		assertThat(replies.get(0).getPayload().readableBytes())
			.as("the ordinary 5-byte success shape")
			.isEqualTo(5);
		assertThat(replies.get(0).getPayload().getByte(4) & 0x01).isEqualTo(1);

		var stored = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select subject, body, sender_chara_id from gm_mail")
				.mapToMap().one());
		assertThat(stored.get("subject")).isEqualTo("HELP");
		assertThat(stored.get("body")).isEqualTo("AN ALLIGATOR GOT ME");
		assertThat(((Number) stored.get("sender_chara_id")).longValue()).isEqualTo(charaId);
	}

	/** An ordinary letter is not mistaken for one: the destination byte is zero. */
	@Test
	public void anOrdinaryLetterDoesNotBecomeGameMasterMail() {
		givenTwoCharacters();

		exchange(sendMail("Otacon", "hi", "poop"));

		var count = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from gm_mail").mapTo(Integer.class).one());
		assertThat(count).isZero();
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

	/**
	 * A letter to a name nobody owns is refused, and the recipient is named in the failure list.
	 * <p>
	 * This test previously asserted the opposite — its name was
	 * {@code unknownRecipientIsDroppedButStillReportsSuccess} — so the bug was pinned as intended
	 * behaviour. Nothing was stored and the player was told the letter sent.
	 * <p>
	 * The per-recipient failure list already existed for blocked recipients; unknown ones simply
	 * were not added to it. They carry {@code -802} rather than the blocked code, because saying
	 * "that player has blocked you" about a name that does not exist is a specific lie, which is
	 * worse than a vague truth.
	 */
	@Test
	public void unknownRecipientIsRefusedAndNamed() {
		givenTwoCharacters();

		var replies = exchange(sendMail("NoSuchPerson", "s", "b"));
		var payload = replies.get(0).getPayload();

		assertThat(payload.getInt(0))
			.as("a nonzero result is what makes the client read the failure list")
			.isNotEqualTo(GameError.NONE.result());
		assertThat(payload.getInt(5)).as("one failed recipient").isEqualTo(1);

		var name = new byte[16];
		payload.getBytes(9, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("NoSuchPerson");

		var count = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail").mapTo(Long.class).one());
		assertThat(count).as("still nothing stored — that part was always right").isZero();
	}

	@Test
	public void listCarriesOneEntryPerPacketWithARoutableCategory() {
		givenTwoCharacters();

		// Snake mails Otacon twice: two entries in Snake's Sent list, two in Otacon's Inbox — real
		// recipients rather than self-mail, since the server now refuses mailing yourself.
		exchange(sendMail("Otacon", "first", "one"), sendMail("Otacon", "second", "two"));
		var sentReplies = exchange(listMail());
		var inboxReplies = exchange(friendId, listMail());

		var start = sentReplies.stream()
			.filter(p -> p.getCommand() == MessageGameController.GET_MESSAGES_START).toList();
		assertThat(start).hasSize(1);
		assertThat(start.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		// Two letters = two Sent entries plus two Inbox entries, ONE per packet: the 0x4822 parser
		// has no loop, so batching would silently drop all but the first.
		var sentData = entries(sentReplies);
		var inboxData = entries(inboxReplies);
		assertThat(sentData).hasSize(2);
		assertThat(inboxData).hasSize(2);
		for (var packet : java.util.stream.Stream.concat(sentData.stream(), inboxData.stream())
				.toList()) {
			assertThat(packet.getPayload().readableBytes()).isEqualTo(ENTRY_SIZE);
			// The leading byte indexes an array of four unchecked by the client.
			assertThat(packet.getPayload().getByte(0)).isBetween((byte) 0, (byte) 3);
		}

		var end = sentReplies.stream()
			.filter(p -> p.getCommand() == MessageGameController.GET_MESSAGES_END).toList();
		assertThat(end).hasSize(1);
		assertThat(end.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	@Test
	public void entryCarriesCounterpartyAndSubjectWithDistinctIndices() {
		givenTwoCharacters();

		exchange(sendMail("Otacon", "hello", "body"));

		var sentData = entries(exchange(listMail()));
		assertThat(sentData).hasSize(1);
		var sentPayload = sentData.get(0).getPayload();
		assertThat(stringAt(sentPayload, 3, 128)).isEqualTo("Otacon"); // counterparty: recipient
		assertThat(stringAt(sentPayload, 131, 128)).isEqualTo("hello");
		assertThat(sentPayload.getUnsignedByte(1)).isZero(); // first in its own list
		assertThat(sentPayload.getUnsignedByte(265)).isZero(); // 0 = unread

		var inboxData = entries(exchange(friendId, listMail()));
		assertThat(inboxData).hasSize(1);
		var inboxPayload = inboxData.get(0).getPayload();
		assertThat(stringAt(inboxPayload, 3, 128)).isEqualTo("Snake"); // counterparty: sender
		assertThat(stringAt(inboxPayload, 131, 128)).isEqualTo("hello");
		assertThat(inboxPayload.getUnsignedByte(1)).isZero();
		assertThat(inboxPayload.getUnsignedByte(265)).isZero();
	}

	@Test
	public void openingReturnsTheFullBodyBlockAndPersistsTheReadFlag() {
		givenTwoCharacters();

		exchange(sendMail("Otacon", "s", "the body"));

		// Opened from Otacon's side — the recipient, category 0 (inbox) — which is what "opening a
		// letter" actually means; self-mail used to blur inbox and sent into the same row.
		var replies = exchange(friendId, listMail(), openMail(0, 0), listMail());

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

		exchange(sendMail("Otacon", "s", "b"));

		// Otacon (the recipient) deletes their inbox copy.
		var ack = exchange(friendId, deleteMail(0, 0)).stream()
			.filter(p -> p.getCommand() == MessageGameController.DELETE_MESSAGE_RESULT).toList();
		assertThat(ack).hasSize(1);
		assertThat(ack.get(0).getPayload().readableBytes()).isEqualTo(Integer.BYTES);

		// Gone from Otacon's inbox...
		assertThat(entries(exchange(friendId, listMail()))).isEmpty();
		// ...but Snake's Sent copy is untouched — the wire has no deletion field, so this is only
		// expressible in storage and in what each side's own list shows.
		var sentData = entries(exchange(listMail()));
		assertThat(sentData).hasSize(1);
		assertThat(sentData.get(0).getPayload().getByte(0)).isEqualTo((byte) 1);

		var remaining = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail where not sender_deleted")
				.mapTo(Long.class).one());
		assertThat(remaining).isEqualTo(1);
	}

	@Test
	public void deletingFromBothSidesRemovesTheRow() {
		givenTwoCharacters();

		exchange(sendMail("Otacon", "s", "b"));
		exchange(friendId, deleteMail(0, 0));  // Otacon deletes the inbox copy
		exchange(deleteMail(1, 0));            // Snake deletes the sent copy

		var rows = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail").mapTo(Long.class).one());
		assertThat(rows).isZero();
	}

	/**
	 * Mailing yourself is refused as operator policy — confirmed live 2026-08-01 — and dropped into
	 * the same {@code RECIPIENT_UNKNOWN} bucket as an invalid name, since the recipient is invalid
	 * without being unknown and inventing a specific code would claim evidence that does not exist.
	 */
	@Test
	public void mailingYourselfIsRefused() {
		givenTwoCharacters();

		var replies = exchange(sendMail("Snake", "s", "b"));
		var payload = replies.get(0).getPayload();
		assertThat(payload.getInt(0))
			.as("a nonzero result is what makes the client read the failure list")
			.isNotEqualTo(GameError.NONE.result());
		assertThat(payload.getInt(5)).as("one failed recipient").isEqualTo(1);

		var count = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail").mapTo(Long.class).one());
		assertThat(count).as("nothing stored").isZero();
	}

	/**
	 * The client's own list screen never shows more than {@code MAILBOX_MAX} (16) letters, so a 17th
	 * accepted delivery would store a letter nobody could ever read or delete. Confirmed live
	 * 2026-08-01 that a full mailbox really does refuse with a distinct sentence ({@code -802},
	 * "Receiver's mailbox is full") rather than silently succeeding or overflowing the list.
	 */
	@Test
	public void mailboxFullRefusesA17thLetter() {
		givenTwoCharacters();

		for (var i = 0; i < 16; i++) {
			exchange(sendMail("Otacon", "s" + i, "b"));
		}
		var replies = exchange(sendMail("Otacon", "one too many", "b"));
		var payload = replies.get(0).getPayload();
		assertThat(payload.getInt(0))
			.as("a nonzero result is what makes the client read the failure list")
			.isNotEqualTo(GameError.NONE.result());
		assertThat(payload.getInt(5)).as("one failed recipient").isEqualTo(1);

		var count = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from mail where recipient_chara_id = :chara")
				.bind("chara", friendId)
				.mapTo(Long.class).one());
		assertThat(count).as("still capped at 16 — the 17th never landed").isEqualTo(16);
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
