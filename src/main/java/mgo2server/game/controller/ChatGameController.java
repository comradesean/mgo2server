package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.service.GameService;
import mgo2server.game.ChannelRegistry;
import mgo2server.game.GameControllerContext;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * In-game chat: the message box in a game lobby.
 * <p>
 * The request {@code 0x4400} was decoded from four live captures on 2026-07-26 — see
 * {@code dev/docs/OBSERVED.md} "0x4400 — in-game chat" and
 * {@code dev/proto/blanks/inbound/mgo2_cmd_4400_c2s.ksy}. 129 bytes:
 * {@code {u8 kind, u8 channel_digit, NUL-terminated text padded to fill}}. The {@code /all} and
 * {@code /team} prefixes the player types are stripped client-side and never reach the wire.
 * <p>
 * <strong>The channel is the ASCII digit, not the leading byte.</strong> Digits {@code '0'} to
 * {@code '3'} occur, and {@code kind} is only a coarse public/team flag — {@code 0} for digits 0, 2
 * and 3, {@code 1} for digit 1 ([ELF 0xCA0A70, 0xCA0B30]). They therefore disagree above channel 1,
 * so neither may be derived from the other.
 * <p>
 * <strong>The client displays nothing until the server replies, and the server must fan the reply
 * out to every player including the sender.</strong> Two independent lines of evidence:
 * <ul>
 * <li>Observed live 2026-07-26: four messages sent while no handler existed, none of which appeared
 * in the sender's own chat window.</li>
 * <li>[ELF] The three display fields ({@code netctx+0x114C8} flag, {@code +0x114CC} speaker id,
 * {@code +0x114D0} text) have exactly one producer in the whole binary — the {@code 0x4401} parser
 * at {@code 0xD52C84}/{@code 0xD52C98}/{@code 0xD52C9C}. The {@code 0x4400} caller falls straight
 * into its epilogue at {@code 0xCA0A98} without touching them, so there is no local echo, and no
 * other inbound path writes chat text.</li>
 * </ul>
 * So {@code 0x4401} is the display path, not an acknowledgement, and answering only the sender
 * would leave every other player deaf.
 */
public class ChatGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	private final GameService gameService;

	/**
	 * Live channels on this server by character id.
	 * <p>
	 * This map used to live here, and the reasoning for its scope is now in
	 * {@link ChannelRegistry}. It moved out when a second subsystem — automatching — needed to reach
	 * a client that is not the one currently asking; the registry keeps itself current through the
	 * same two hooks this controller used, and is registered in {@code GameServerFactory}.
	 */
	private final ChannelRegistry channels;

	public ChatGameController(GameService gameService, ChannelRegistry channels) {
		this.gameService = gameService;
		this.channels = channels;
	}

	/** In-game chat send. */
	public static final int SEND_CHAT = 0x4400;

	/** The chat line to display. */
	public static final int SEND_CHAT_RESULT = 0x4401;

	/** Coarse public flag: the {@code kind} byte for channel digits 0, 2 and 3 [ELF 0xCA0A70]. */
	private static final int KIND_PUBLIC = 0;

	/** Coarse team flag: the {@code kind} byte for channel digit 1 [ELF 0xCA0B30]. */
	private static final int KIND_TEAM = 1;

	/**
	 * Highest channel digit the send path can produce [ELF 0xCA0A10-0xCA0B48]. Digit 3 diverts
	 * speaker resolution to a server-supplied table at {@code netctx+0xD928} rather than the game
	 * roster ([ELF 0xCA00CC]) — presumably clan or friends, [UNKNOWN] which.
	 */
	private static final int CHANNEL_MAX = 3;

	/**
	 * Total request payload, from the builder at {@code 0xD52CEC}: one {@code kind} byte plus a
	 * 128-byte blob copied verbatim.
	 */
	private static final int REQUEST_LENGTH = 1 + 128;

	/** Offset of the text inside the request: past the {@code kind} byte and the channel digit. */
	private static final int TEXT_OFFSET = 2;

	/**
	 * Longest message the wire can carry. The sender copies at most {@code 0x80} bytes of typed
	 * text into the blob one byte after the digit ([ELF 0xCA0A10-0xCA0A94]), and the receiving
	 * consumer takes {@code strncpy(dst, payload + 5, 0x7F)} ([ELF 0xC9FFEC]) — so 127 is what
	 * survives both ends. The client's own input-box limit is [UNKNOWN]; the longest message
	 * captured so far is five characters.
	 */
	private static final int TEXT_MAX = 127;

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(SEND_CHAT, this::sendChat);
	}

	/**
	 * Answers {@code 0x4400} with the line to display.
	 * <p>
	 * The reply is {@code {u32 speaker, NUL-terminated string}} — parser {@code 0xD52BA8}, which
	 * reads the u32, then the string through the delimiter-terminated primitive {@code 0xD5CE34}
	 * into a 129-byte buffer, stores {@code 0xFF} at {@code netctx+0x114C8}, the u32 at
	 * {@code +0x114CC} and the string at {@code +0x114D0}, then fires UI event {@code 0x30} carrying
	 * the u32. (Event {@code 0x30} is fired from this parser alone — {@code 0xD52CB0} — and carries
	 * no meaning beyond "a {@code 0x4401} arrived".)
	 * <p>
	 * Both halves are [ELF]-proven, not guessed:
	 * <ul>
	 * <li><strong>The u32 is the speaker's character id</strong> — the same value the server put at
	 * offset {@code 0x000} of that speaker's {@code 0x4101}. The consumer at {@code 0xC9FFD8} walks
	 * all 24 roster slots comparing it against {@code entry+0x60} to resolve who spoke; an
	 * unmatched id leaves the speaker slot at {@code 0xFF} and the line renders unattributed rather
	 * than being discarded. Read as plain big-endian binary, not ASCII decimal.</li>
	 * <li><strong>The leading channel digit is mandatory.</strong> {@code 0xC9FF94} does
	 * {@code digit - 0x30} into the display record's channel field and takes the text from byte 1
	 * ({@code 0xC9FFEC}). Omit the digit and the first character of every message is eaten and the
	 * channel comes out as garbage. Relay the digit the sender sent, not {@code kind} — they differ
	 * for channels 2 and 3.</li>
	 * </ul>
	 * Note the string is terminated on the wire and <em>not</em> padded to width — {@code 0xD5CE34}
	 * stops on the delimiter and consumes it — so {@code BufferUtil.writeString} is the wrong tool
	 * and the terminator is written by hand.
	 */
	private void sendChat(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			logger.warn("Chat from a connection with no character; dropping.");
			return;
		}
		var charaId = account.getCurrentCharaId();

		var message = parse(ctx.packet().getPayload());
		if (message == null) {
			return;
		}

		logger.debug("Chat from chara {} on channel {}: \"{}\"", charaId, message.channel(),
			message.text());

		var recipients = recipients(charaId);
		if (recipients.isEmpty()) {
			// Not in a game: answer the sender alone so their own line still renders. Chat outside a
			// game has not been exercised, so this is a fallback, not a modelled case.
			var reply = ctx.buffer(replySize(message));
			writeReply(reply, charaId, message);
			ctx.write(new GamePacket(SEND_CHAT_RESULT, reply));
			return;
		}

		var delivered = 0;
		for (var recipient : recipients) {
			// A roster row with no live channel on this server: the player is in the game but
			// connected elsewhere, or dropped without tearing down. Not an error.
			var channel = channels.channel(recipient).orElse(null);
			if (channel == null) {
				continue;
			}
			// Each recipient gets its own buffer written through its own pipeline: the encoders are
			// per-channel and carry sequence counters, so a buffer cannot be shared and the sender's
			// context must not be reused to reach another client.
			var reply = channel.alloc().buffer(replySize(message));
			writeReply(reply, charaId, message);
			channel.writeAndFlush(new GamePacket(SEND_CHAT_RESULT, reply));
			delivered++;
		}
		logger.debug("Chat from chara {} delivered to {} of {} players in the game.", charaId,
			delivered, recipients.size());
	}

	/**
	 * Everyone who should receive a message from this character: the players in the game the sender
	 * is in, <strong>including the sender</strong> — the client has no local echo, so omitting the
	 * sender means they never see their own line ([ELF 0xCA0A98], and observed live).
	 * <p>
	 * Empty if the sender is not in a game.
	 * <p>
	 * <strong>Not scoped by channel.</strong> Team chat (channel 1) ought to reach only the sender's
	 * team, and channel 3 resolves speakers against a separate server-supplied table
	 * ([ELF 0xCA00CC]) rather than the game roster, so it is probably clan or friends rather than a
	 * game at all. Neither can be honoured yet: {@code game_player.team} exists in the schema but
	 * nothing has ever written it, because {@code 0x4440} — the team/spectator change — is answered
	 * with a bare result and its byte discarded. Until that byte is persisted, every channel goes to
	 * the whole game. That is a known over-delivery, deliberately preferred to dropping the message,
	 * and it is why the channel is logged.
	 * <p>
	 * <strong>Do not "fix" this before checking whether it is broken.</strong> Live 2026-07-26, a
	 * channel-1 message was delivered to both clients and reportedly only the sender saw it — which
	 * would mean the client filters team chat by team membership itself and this over-delivery is
	 * invisible. The second player was never asked, so it is unconfirmed; one observation from a
	 * second client decides whether server-side scoping is needed at all. See OBSERVED.md.
	 */
	private List<Long> recipients(long senderCharaId) {
		var game = gameService.gameContaining(senderCharaId);
		if (game.isEmpty()) {
			return List.of();
		}
		return gameService.getPlayers(game.get().getId(), game.get().getHostCharaId()).stream()
			.map(GameService.GamePlayer::charaId)
			.toList();
	}

	/**
	 * One decoded chat send. {@code digit} is kept alongside {@code channel} because the wire byte is
	 * what must be relayed: the client derives the channel as {@code digit - '0'}
	 * ([ELF 0xC9FF94]), so preserving the byte as sent cannot drift from what the sender meant.
	 */
	public record ChatMessage(int channel, int digit, String text) {
	}

	/** Decodes a {@code 0x4400} payload, or null if it is too short to be one. */
	public static ChatMessage parse(ByteBuf payload) {
		if (payload.readableBytes() < REQUEST_LENGTH) {
			logger.warn("Chat payload is {} bytes, expected {}; dropping.",
				payload.readableBytes(), REQUEST_LENGTH);
			return null;
		}

		var kind = payload.getUnsignedByte(0);
		var digit = payload.getUnsignedByte(1);
		var text = readString(payload, TEXT_OFFSET, TEXT_MAX);

		// The digit is the real channel; kind is only a public/team flag and is 0 for channels 0, 2
		// and 3 alike [ELF 0xCA0A70, 0xCA0B30]. So the two legitimately disagree above channel 1 —
		// do not "correct" one from the other.
		var channel = digit - '0';
		if (channel < 0 || channel > CHANNEL_MAX) {
			logger.warn("Chat channel digit {} is outside 0-{}; relaying it unchanged.", digit,
				CHANNEL_MAX);
		} else if (kind != (channel == 1 ? KIND_TEAM : KIND_PUBLIC)) {
			logger.info("Chat kind {} does not match channel {} — the ELF says these pair as "
				+ "0/0, 1/1, 0/2, 0/3, so this is a new combination worth recording.", kind,
				channel);
		}

		return new ChatMessage(channel, digit, text);
	}

	/** Bytes {@link #writeReply} will produce for this message. */
	public static int replySize(ChatMessage message) {
		return Integer.BYTES + 1 + message.text().length() + 1;
	}

	/**
	 * Writes a {@code 0x4401}: the speaker, then the request's blob relayed unchanged — the digit,
	 * the text, and the terminator the client's reader consumes.
	 */
	public static void writeReply(ByteBuf out, long speakerCharaId, ChatMessage message) {
		out.writeInt((int) speakerCharaId);
		out.writeByte(message.digit());
		out.writeBytes(message.text().getBytes(StandardCharsets.ISO_8859_1));
		out.writeByte(0);
	}

	/** Reads a NUL-terminated ISO-8859-1 string out of a fixed-width wire field. */
	private static String readString(ByteBuf payload, int offset, int max) {
		var raw = payload.toString(offset, max, StandardCharsets.ISO_8859_1);
		var end = raw.indexOf(0);
		return end < 0 ? raw : raw.substring(0, end);
	}
}
