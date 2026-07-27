package mgo2server.game.controller;

import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.BufferUtil;
import mgo2server.game.GameControllerContext;
import mgo2server.game.packet.GamePacket;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The mailbox, which the client reads as soon as it joins a game lobby.
 * <p>
 * Like the character name check, this is not optional: the client waits for the reply and fails
 * with <em>Unable to connect to lobby (092E:FFFFFF60)</em> if none arrives.
 * <p>
 * Mail is implemented as of 2026-07-26: send ({@code 0x4800}), list ({@code 0x4820}), open
 * ({@code 0x4840}) and delete ({@code 0x4880}), stored in the {@code mail} table. Read and
 * deleted state are per-side, because one row is a single delivery seen from both ends and the
 * wire has no field for either — see {@code V22__mail_deleted.sql} and {@code V23__mail_sender_read.sql}.
 * <p>
 * The request carries the mailbox to read: {@code 0x0f} for mail and {@code 0x10} for clan
 * applications. Clan applications stay empty until clans exist. That selector does <b>not</b>
 * choose a tab — every tab asks with {@code 0x0f}, and the inbox/sent split is driven by the
 * category byte on each {@code 0x4822} entry.
 */
public class MessageGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	private final CharacterService characterService;

	private final ClanService clanService;

	public MessageGameController(CharacterService characterService, ClanService clanService) {
		this.characterService = characterService;
		this.clanService = clanService;
	}

	public static final int GET_MESSAGES = 0x4820;

	public static final int GET_MESSAGES_START = 0x4821;

	public static final int GET_MESSAGES_DATA = 0x4822;

	public static final int GET_MESSAGES_END = 0x4823;

	public static final int DELETE_MESSAGE = 0x4880;

	public static final int DELETE_MESSAGE_RESULT = 0x4881;

	public static final int READ_MESSAGE = 0x4840;

	public static final int READ_MESSAGE_RESULT = 0x4841;

	/**
	 * The {@code 0x4841} body block: 708 bytes, the same width as the body field of the
	 * {@code 0x4800} that produced the letter. The parser at {@code 0xD5360C} reads it as ONE
	 * opaque block ({@code 0xD5D018} r5=708 at {@code 0xD5363C}) and stores it whole — it draws no
	 * internal fields, and the consumers of that object were not traced. So the block's layout is
	 * [UNKNOWN]: we send the body text NUL-padded, on the reasoning that the send side's 708-byte
	 * field is capture-confirmed to be the body text and a round trip of the same width is the
	 * likeliest shape. If the screen renders garbage, this is the assumption to attack first.
	 * <p>
	 * A short reply is the dangerous failure here: the block reader bound-checks against the
	 * 1023-byte receive buffer rather than the payload length, so sending fewer than 708 bytes
	 * copies stale buffer into the mail object and reports success.
	 */
	private static final int READ_BODY_LENGTH = 708;

	public static final int SEND_MESSAGE = 0x4800;

	public static final int SEND_MESSAGE_RESULT = 0x4801;

	/**
	 * The {@code 0x4801} flags byte. <b>Bit 0 must be set.</b>
	 * <p>
	 * The parser at {@code 0xD53DB0} tests only bit 0 ({@code clrldi. r9,r0,63} at
	 * {@code 0xD53E90}). Set, it completes the slot-{@code 0x55} request with our status
	 * ({@code 0xD32E08(0x55,2)} then {@code 0xD32E70(0x55,status)}). <b>Clear, it calls
	 * {@code 0xD53B6C}, which re-sends the entire letter as a 969-byte {@code 0x4860} and returns
	 * the slot to state 1</b> — so a zero here does not release the client, it starts a second
	 * request we also do not answer, and the player sees the same hang.
	 * <p>
	 * PROTOCOL.md transcribes Nomad's {@code flags = 0}. That is correct <em>for Nomad</em>, which
	 * also answers {@code 0x4860} with a no-op {@code 0x4861}; the pair works, either half alone
	 * does not. Sending 1 completes the transaction in one packet instead of two.
	 */
	private static final int SEND_RESULT_FLAGS = 0x01;

	/** Wire offset of the eight recipient-name slots: one leading count byte. */
	private static final int SEND_RECIPIENTS_OFFSET = 1;

	/** Character-name width, as everywhere else in this protocol. */
	private static final int NAME_LENGTH = 16;

	/** Recipient slots in a 0x4800: eight fixed 16-byte names, only the first count populated. */
	private static final int SEND_MAX_RECIPIENTS = 8;

	/** Wire widths of the 0x4800 subject and body blocks. */
	private static final int SUBJECT_LENGTH = 128;

	private static final int BODY_LENGTH = 708;

	/** 0x4822 entry: {u8 mailbox, u8 index, u8, char[128] name, char[128] comment, u32, u8 x3}. */
	private static final int ENTRY_SIZE = 3 + 128 + 128 + Integer.BYTES + 3;

	/**
	 * <b>One entry per 0x4822 packet.</b> Three would fit in the 1023-byte payload, but the parser
	 * at {@code 0xD53714} has no loop — no {@code 0xD5CEB0} cursor test, no back-edge — so it
	 * reads exactly one record and discards the rest of the payload.
	 */
	private static final int ENTRIES_PER_PACKET = 1;

	/**
	 * Entries the client can hold <b>per category</b>: the record arena is four categories x 16
	 * elements of 280 bytes at {@code arena+0x1E268}, and {@code 0xD34858} silently drops any
	 * entry once that category's counter reaches 16. Not operator policy — exceeding it loses
	 * mail with no error.
	 */
	private static final int MAILBOX_MAX = 16;

	/**
	 * The 0x4822 byte at wire 0x02. Nomad sends the constant 1 and its meaning is [UNKNOWN]; we
	 * send 1 for want of anything evidenced. Unlike the 0x4582 gate at wire 0x14, no filter on
	 * this byte was found, so it is not known to matter.
	 */
	private static final int ENTRY_UNKNOWN_02 = 1;

	/**
	 * The 0x4822 <em>category</em> byte at wire 0x00 — the entry's first field, which the parser
	 * at {@code 0xD53714} sign-extends and passes to {@code 0xD347E4} along with the record, so it
	 * <b>routes the entry to a list</b> rather than describing it.
	 * <p>
	 * <b>Valid values are 0, 1, 2 and 3</b> — four separate 16-element arrays — plus 4, which the
	 * router treats as a flat 64-entry view aliasing category 0. {@code 0xD347E4} does
	 * <b>not</b> range-check the index ({@code extsb r3,r11} at {@code 0xD34844}; the only guard
	 * is {@code count < cap}), so an out-of-range value writes into somebody else's heap.
	 * <p>
	 * <b>This was a live bug, not a theory.</b> We first sent the 0x4820 request's selector
	 * ({@code 0x0f}) here. That indexes the record arena at
	 * {@code arena+0x1E268 + 15*4480 = arena+0x2E8E8} — 26 816 bytes past the end of a
	 * 0x28028-byte allocation — and reads its "count" from a byte inside category 0's first
	 * record. The entry never displayed and the GM tab vanished from the mailbox screen, which is
	 * consistent with a 275-byte write into unrelated heap.
	 * <p>
	 * Which tab each of 0/1/3 draws is <b>still unproven</b> — the labels live in the language
	 * resource, not the binary. Category 1 is Sent, observed live 2026-07-26 (our entry appeared
	 * there and the client's 0x4840 echoed category 1 back). Category 2 has no UI reference at
	 * all and may be unreachable in this build. The environment overrides
	 * {@code MGO2SERVER_MAIL_CATEGORY_INBOX} / {@code MGO2SERVER_MAIL_CATEGORY_SENT} stay until
	 * the remaining tabs are identified — the one-shot experiment is four entries, categories
	 * 0/1/2/3, each with a distinct subject, then read the tabs.
	 */
	private static final int CATEGORY_INBOX =
		category("MGO2SERVER_MAIL_CATEGORY_INBOX", 0);

	private static final int CATEGORY_SENT =
		category("MGO2SERVER_MAIL_CATEGORY_SENT", 1);

	/**
	 * The tab a system letter goes to — the Announcements tab the original's GameMaster mail
	 * arrives in.
	 * <p>
	 * A guess, and flagged as one: 0 and 1 are Inbox and Sent, leaving 2 and 3, and neither has
	 * been identified. The graduation announcement went out as category 0 and duly appeared in the
	 * Inbox (live, 2026-07-26), which at least confirms the category byte decides the tab. If 3 is
	 * wrong, {@code MGO2SERVER_MAIL_CATEGORY_ANNOUNCEMENT=2} tries the other candidate in one
	 * restart, and whichever lands settles the remaining tab labels for good.
	 */
	private static final int CATEGORY_ANNOUNCEMENT =
		category("MGO2SERVER_MAIL_CATEGORY_ANNOUNCEMENT", 3);

	private static int category(String variable, int fallback) {
		var configured = System.getenv(variable);
		if (configured == null || configured.isBlank()) {
			return fallback;
		}
		try {
			return Integer.decode(configured.trim()) & 0xff;
		} catch (NumberFormatException e) {
			logger.warn("{}=\"{}\" is not a number; using {}.", variable, configured, fallback);
			return fallback;
		}
	}

	/** Mailbox selectors, named after the reference servers. */
	private static final int MAIL = 0x0f;

	private static final int CLAN_APPLICATIONS = 0x10;

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_MESSAGES, this::getMessages);
		handlers.put(SEND_MESSAGE, this::sendMessage);
		handlers.put(READ_MESSAGE, this::readMessage);
		handlers.put(DELETE_MESSAGE, this::deleteMessage);
	}

	/**
	 * Send mail ({@code 0x4800}, 967 bytes): {@code u8 recipientCount}, eight 16-byte recipient
	 * names, a 128-byte subject, a 708-byte body, and two trailing bytes whose meaning is unknown.
	 * All three text fields are capture-confirmed (2026-07-26) — see
	 * {@code dev/proto/blanks/inbound/mgo2_cmd_4800_c2s.ksy}.
	 * <p>
	 * One send fans out to a row per recipient. A name nobody owns is skipped and logged: the
	 * client lets the player type recipients freely, so an unknown name is an ordinary outcome.
	 * <b>We still report success</b> — the {@code 0x4801} error list exists for exactly this case,
	 * but the codes it carries are [UNKNOWN], and inventing one risks a worse failure than
	 * silently dropping the letter. Populating it is the follow-up.
	 * <p>
	 * The reply is five bytes: {@code u32 status}, {@code u8 flags}. The error list that follows
	 * is read <em>only when status is nonzero</em> ({@code beq} at {@code 0xD53DD8}), so success
	 * genuinely ends the packet. See {@link #SEND_RESULT_FLAGS} for why the flags byte is 1.
	 * <p>
	 * The whole mailbox family shares request slot {@code 0x55}, so only one mailbox command can
	 * be outstanding and replies must stay in order.
	 */
	private void sendMessage(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(SEND_MESSAGE_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var charaId = account.getCurrentCharaId();
		var senderName = characterService.get(charaId).map(chara -> chara.getName()).orElse("");
		var subjectOffset = SEND_RECIPIENTS_OFFSET + SEND_MAX_RECIPIENTS * NAME_LENGTH;
		var bodyOffset = subjectOffset + SUBJECT_LENGTH;

		if (payload.readableBytes() < bodyOffset + BODY_LENGTH) {
			logger.warn("Send mail: short payload, {} bytes, expected {}.",
				payload.readableBytes(), bodyOffset + BODY_LENGTH);
			ctx.write(SEND_MESSAGE_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var count = Math.min(payload.getByte(0) & 0xff, SEND_MAX_RECIPIENTS);
		var subject = readString(payload, subjectOffset, SUBJECT_LENGTH);
		var body = readString(payload, bodyOffset, BODY_LENGTH);

		var delivered = 0;
		var blocked = 0;
		for (var slot = 0; slot < count; slot++) {
			var recipient = readString(payload, SEND_RECIPIENTS_OFFSET + slot * NAME_LENGTH,
				NAME_LENGTH);
			if (recipient.isEmpty()) {
				continue;
			}
			// A player who blocked you cannot be mailed by you. The client knows this state — "The
			// receiver has blocked incoming mail" (lobby 23809) — but the block lives here, so the
			// check has to be here too.
			var target = characterService.findByName(recipient).orElse(null);
			if (target != null && characterService.hasBlocked(target, charaId)) {
				logger.info("Send mail: \"{}\" has blocked character {}; letter dropped.",
					recipient, charaId);
				blocked++;
			} else if (characterService.sendMail(charaId, senderName, recipient, subject, body)) {
				delivered++;
			} else {
				logger.info("Send mail: no character named \"{}\"; letter dropped.", recipient);
			}
		}
		logger.info("Send mail from \"{}\": {} of {} recipient(s) delivered{}, subject \"{}\".",
			senderName, delivered, count,
			blocked == 0 ? "" : " (" + blocked + " blocked)", subject);

		var buffer = ctx.buffer(Integer.BYTES + 1);
		buffer.writeInt(GameError.NONE.result()).writeByte(SEND_RESULT_FLAGS);
		ctx.write(new GamePacket(SEND_MESSAGE_RESULT, buffer));
	}

	/**
	 * The mailbox list ({@code 0x4820}): a {@code 0x4821} result, {@code 0x4822} packets of up to
	 * {@value #ENTRIES_PER_PACKET} entries, then a {@code 0x4823} result. Both the start and the
	 * end carry a <em>result code</em>, not a count — the client counts the entry records itself.
	 * <p>
	 * <b>Received and sent mail both go out in this one reply.</b> The client asks with the same
	 * selector byte ({@code 0x0f}) whichever tab is open — observed live 2026-07-26 — so the tabs
	 * cannot be a per-request choice. The split must be client-side, driven by each entry's
	 * category byte (see {@link #CATEGORY_INBOX}). Sending both lists at once follows from that;
	 * if the trace shows the tabs are separate requests after all, this becomes two branches.
	 * <p>
	 * Clan applications ({@code 0x10}) share this command and stay empty until clans exist.
	 * <p>
	 * The entry carries no body — only a name, a 128-byte comment and a timestamp. The 708-byte
	 * body travels separately in the {@code 0x4841} reply to an open. We put the subject in the
	 * comment slot, which is [INFERRED] from width alone.
	 */
	private void getMessages(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(GET_MESSAGES_START, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var mailbox = payload.readableBytes() > 0 ? payload.readByte() & 0xff : MAIL;
		if (mailbox != MAIL && mailbox != CLAN_APPLICATIONS) {
			logger.warn("Get messages: unknown mailbox 0x{}.", Integer.toHexString(mailbox));
		}

		var charaId = account.getCurrentCharaId();
		var received = mailbox == MAIL && charaId != null
			? characterService.mailbox(charaId, MAILBOX_MAX)
			: java.util.List.<CharacterService.Mail>of();
		var sent = mailbox == MAIL && charaId != null
			? characterService.sentMail(charaId, MAILBOX_MAX)
			: java.util.List.<CharacterService.Mail>of();

		var entries = new java.util.ArrayList<Entry>(received.size() + sent.size());
		// A letter with no sender character is from the system — the graduation announcement — and
		// belongs in Announcements rather than the Inbox.
		received.forEach(letter -> entries.add(
			new Entry(letter.systemSender() ? CATEGORY_ANNOUNCEMENT : CATEGORY_INBOX, letter)));
		sent.forEach(letter -> entries.add(new Entry(CATEGORY_SENT, letter)));

		ctx.write(GET_MESSAGES_START, GameError.NONE);

		// Mailbox 0x10 is the clan's pending applications, and it is where a leader approves them:
		// an application is a MESSAGE, not a roster row, which is why nothing ever appeared under
		// Check Roster however the records were arranged. The sender name is the applicant, and the
		// leader acts on the entry with 0x4b30 (accept) or 0x4b32 (decline).
		if (mailbox == CLAN_APPLICATIONS && charaId != null) {
			var membership = clanService.membershipOf(charaId);
			var applications = membership.state() == ClanService.STATE_LEADER
				? clanService.applicationsFor(membership.id())
				: java.util.List.<ClanService.Applicant>of();
			if (!applications.isEmpty()) {
				var buffer = ctx.buffer(applications.size() * ENTRY_SIZE);
				for (var i = 0; i < applications.size(); i++) {
					var applicant = applications.get(i);
					buffer.writeByte(0);
					buffer.writeByte(i);
					buffer.writeByte(ENTRY_UNKNOWN_02);
					BufferUtil.writeString(buffer, applicant.name(), StandardCharsets.ISO_8859_1,
						SUBJECT_LENGTH);
					BufferUtil.writeString(buffer, "", StandardCharsets.ISO_8859_1, SUBJECT_LENGTH);
					buffer.writeInt((int) applicant.appliedAt());
					buffer.writeZero(2);
					buffer.writeByte(0);
				}
				ctx.write(new GamePacket(GET_MESSAGES_DATA, buffer));
				logger.info("Clan {}: {} pending application(s) listed for character {}.",
					membership.id(), applications.size(), charaId);
			}
		}

		for (var offset = 0; offset < entries.size(); offset += ENTRIES_PER_PACKET) {
			var batch = entries.subList(offset,
				Math.min(offset + ENTRIES_PER_PACKET, entries.size()));
			var buffer = ctx.buffer(batch.size() * ENTRY_SIZE);
			for (var entry : batch) {
				var letter = entry.letter();
				buffer.writeByte(entry.category());
				buffer.writeByte(letter.index());
				buffer.writeByte(ENTRY_UNKNOWN_02);
				BufferUtil.writeString(buffer, letter.counterparty(), StandardCharsets.ISO_8859_1,
					SUBJECT_LENGTH);
				BufferUtil.writeString(buffer, letter.subject(), StandardCharsets.ISO_8859_1,
					SUBJECT_LENGTH);
				buffer.writeInt((int) letter.sentAt().getEpochSecond());
				buffer.writeZero(2);
				buffer.writeByte(letter.read() ? 1 : 0);
			}
			ctx.write(new GamePacket(GET_MESSAGES_DATA, buffer));
		}

		ctx.write(GET_MESSAGES_END, GameError.NONE);
		logger.debug("Mailbox 0x{}: {} received (category {}), {} sent (category {}).",
			Integer.toHexString(mailbox), received.size(), CATEGORY_INBOX, sent.size(),
			CATEGORY_SENT);
	}

	/** One outgoing list entry: a stored letter plus the category byte that routes it. */
	private record Entry(int category, CharacterService.Mail letter) {
	}

	/**
	 * Open a letter ({@code 0x4840}, 2 bytes): {@code {s1 category, u1 index}}, answered with the
	 * 712-byte {@code 0x4841} — {@code u32 result} then the 708-byte body.
	 * <p>
	 * Both request fields are capture-confirmed (2026-07-26): a client opening the only letter in
	 * its Sent tab sent {@code 01 00}, i.e. the category byte <em>we</em> put on that entry's
	 * {@code 0x4822} plus its index within that list. The client echoes our own routing value
	 * back, so category and index round-trip — which is also what makes selecting the letter here
	 * possible at all.
	 * <p>
	 * A category we did not send, or an index past the end, answers result 0 with a zeroed body
	 * rather than an error: the {@code 0x4841} error codes are [UNKNOWN], and an invented one
	 * risks a worse failure than an empty letter.
	 */
	private void readMessage(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(READ_MESSAGE_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var category = payload.readableBytes() >= 1 ? payload.getByte(0) : 0;
		var index = payload.readableBytes() >= 2 ? payload.getByte(1) & 0xff : 0;
		var charaId = account.getCurrentCharaId();

		var sent = category == CATEGORY_SENT;
		var list = sent
			? characterService.sentMail(charaId, MAILBOX_MAX)
			: characterService.mailbox(charaId, MAILBOX_MAX);
		var letter = index < list.size() ? list.get(index) : null;

		if (letter == null) {
			logger.warn("Read mail: category {} index {} is not in this character's list of {}; "
				+ "answering with an empty body.", category, index, list.size());
		} else {
			// Opening is the only "mark as read" signal the protocol has — there is no command
			// for it. The client sets its own copy's read byte at 0x8E2CD8, but 0x4821 zeroes the
			// category counters and the list is rebuilt from our entries, so an unrecorded read
			// comes back as new at next login. Per-side: see markMailRead.
			characterService.markMailRead(charaId, letter.id(), sent);
			logger.debug("Read mail: category {} index {}, from/to \"{}\", subject \"{}\"; "
				+ "marked read for the {} side.", category, index, letter.counterparty(),
				letter.subject(), sent ? "sender" : "recipient");
		}

		var buffer = ctx.buffer(Integer.BYTES + READ_BODY_LENGTH);
		buffer.writeInt(GameError.NONE.result());
		BufferUtil.writeString(buffer, letter == null ? "" : letter.body(),
			StandardCharsets.ISO_8859_1, READ_BODY_LENGTH);
		ctx.write(new GamePacket(READ_MESSAGE_RESULT, buffer));
	}

	/**
	 * Delete a letter ({@code 0x4880}, 2 bytes): the same {@code {s1 category, u1 index}} pair as
	 * {@link #readMessage} — capture-confirmed 2026-07-26, a client deleting the second letter of
	 * its Sent tab sent {@code 01 01}. The reply {@code 0x4881} is a bare {@code u32} result
	 * ({@code 0xD52EF4}).
	 * <p>
	 * The letter leaves the asking end's list only. One row is a single delivery seen from both
	 * ends, so a recipient deleting must not empty the sender's Sent tab; each end has its own
	 * flag and the row goes once neither can see it. The wire has no deletion field at all — the
	 * 266-byte {@code 0x4822} entry is fully accounted for without one — so a letter is "deleted"
	 * purely by our not sending it next time the list is built.
	 * <p>
	 * An index the character does not own is answered with success and no change, for the same
	 * reason as {@link #readMessage}: the failure codes are [UNKNOWN].
	 */
	private void deleteMessage(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(DELETE_MESSAGE_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var category = payload.readableBytes() >= 1 ? payload.getByte(0) : 0;
		var index = payload.readableBytes() >= 2 ? payload.getByte(1) & 0xff : 0;
		var charaId = account.getCurrentCharaId();
		var sent = category == CATEGORY_SENT;

		var list = sent
			? characterService.sentMail(charaId, MAILBOX_MAX)
			: characterService.mailbox(charaId, MAILBOX_MAX);

		if (index < list.size()) {
			var letter = list.get(index);
			characterService.deleteMail(charaId, letter.id(), sent);
			logger.info("Delete mail: category {} index {}, subject \"{}\" removed from the {} list.",
				category, index, letter.subject(), sent ? "sent" : "received");
		} else {
			logger.warn("Delete mail: category {} index {} is not in this character's list of {}; "
				+ "nothing removed.", category, index, list.size());
		}

		ctx.write(DELETE_MESSAGE_RESULT, GameError.NONE);
	}

	/** Reads a NUL-terminated ISO-8859-1 string out of a fixed-width wire field. */
	private static String readString(io.netty.buffer.ByteBuf payload, int offset, int max) {
		var raw = payload.toString(offset, max, StandardCharsets.ISO_8859_1);
		var end = raw.indexOf(0);
		return (end < 0 ? raw : raw.substring(0, end)).trim();
	}
}
