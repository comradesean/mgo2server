package mgo2server.game.controller;

import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * The {@code 0x4400} chat decoder, checked against real client bytes.
 * <p>
 * The four request payloads below are tier 2: captured from {@code BLUS30109} on RPCS3 on
 * 2026-07-26, logged verbatim by {@code GameServerHandler} when no handler existed yet. Each one is
 * paired with what the player typed, which is what makes them worth asserting on — they pin the
 * channel encoding and prove the {@code /all} and {@code /team} prefixes never reach the wire.
 * <p>
 * The reply assertions are tier 1: the {@code 0x4401} layout comes from the parser at
 * {@code 0xD52BA8} and its consumer at {@code 0xC9FEF0}, which resolves the {@code u32} against the
 * roster and strips {@code 0x30} off the string's first byte. They still are not evidence that a
 * client renders the line — only a client can settle that — but they are no longer guesses.
 */
public class ChatGameControllerTest {
	/** Padding to the 129-byte request length, so the fixtures can be written as their heads. */
	private static byte[] request(String hexHead) {
		var full = new byte[129];
		var head = ByteBufUtil.decodeHexDump(hexHead);
		System.arraycopy(head, 0, full, 0, head.length);
		return full;
	}

	// The four captures, hex exactly as logged, trailing zero padding elided by request().
	private static final String ALL_HI = "003068 6900".replace(" ", "");

	private static final String ALL_HELLO = "0030 68656c6c6f 00".replace(" ", "");

	private static final String TEAM_TEAM = "0131 7465616d 00".replace(" ", "");

	private static final String ALL_ALL = "0030 616c6c 00".replace(" ", "");

	@Test
	public void decodesAllChat() {
		// Typed: "hi"
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request(ALL_HI)));

		assertThat(message).isNotNull();
		assertThat(message.channel()).isZero();
		assertThat(message.digit()).isEqualTo('0');
		assertThat(message.text()).isEqualTo("hi");
	}

	@Test
	public void decodesLongerAllChat() {
		// Typed: "hello"
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request(ALL_HELLO)));

		assertThat(message.channel()).isZero();
		assertThat(message.text()).isEqualTo("hello");
	}

	@Test
	public void decodesTeamChat() {
		// Typed: "/team team".
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request(TEAM_TEAM)));

		assertThat(message.channel()).isEqualTo(1);
		assertThat(message.digit()).isEqualTo('1');
	}

	@Test
	public void takesTheChannelFromTheDigitNotTheKindByte() {
		// kind is a coarse public/team flag: 0 for channel digits 0, 2 and 3, 1 for digit 1
		// [ELF 0xCA0A70, 0xCA0B30]. Our four captures only reached channels 0 and 1, where the two
		// agree — so this synthetic case is the one that pins which byte we actually read. Not a
		// capture: constructed from the ELF's channel table.
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request("0032" + "78")));

		assertThat(message.channel()).isEqualTo(2);
		assertThat(message.digit()).isEqualTo('2');
		assertThat(message.text()).isEqualTo("x");
	}

	@Test
	public void relaysTheDigitRatherThanRegeneratingIt() {
		// The reply must echo the sender's digit. Regenerating it from kind would collapse channels
		// 2 and 3 onto 0 and silently misroute them.
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request("0033" + "78")));
		var out = Unpooled.buffer(ChatGameController.replySize(message));

		ChatGameController.writeReply(out, 4, message);

		assertThat(ByteBufUtil.hexDump(out)).isEqualTo("00000004" + "33" + "78" + "00");
	}

	@Test
	public void stripsTheChannelPrefixFromTheText() {
		// Typed: "/all all" and "/team team". The client parses its own command word and sends only
		// the body, so the text is the bare word — a server looking for a leading "/all" would find
		// nothing. This is the finding most likely to be re-broken by someone "helpfully" parsing
		// prefixes, hence its own test.
		assertThat(ChatGameController.parse(Unpooled.wrappedBuffer(request(ALL_ALL))).text())
			.isEqualTo("all");
		assertThat(ChatGameController.parse(Unpooled.wrappedBuffer(request(TEAM_TEAM))).text())
			.isEqualTo("team");
	}

	@Test
	public void ignoresATruncatedRequest() {
		// The builder at 0xD52CEC always emits 129 bytes, so a short payload is not something the
		// real client produces; it must not throw.
		assertThat(ChatGameController.parse(Unpooled.wrappedBuffer(new byte[] { 0, '0' }))).isNull();
	}

	@Test
	public void replyCarriesTheSpeakerThenTheRelayedBlob() {
		// [ELF-proven] The u32 is the speaker's character id — the consumer at 0xC9FFD8 matches it
		// against all 24 roster slots to attribute the line. The string is the request's blob
		// unchanged, digit included (mandatory: 0xC9FF94 does digit - 0x30), terminated rather than
		// padded because the client's reader (0xD5CE34) stops on the delimiter and consumes it.
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request(ALL_HELLO)));
		var out = Unpooled.buffer(ChatGameController.replySize(message));

		ChatGameController.writeReply(out, 7, message);

		assertThat(ByteBufUtil.hexDump(out)).isEqualTo("00000007" + "30" + "68656c6c6f" + "00");
		assertThat(out.readableBytes()).isEqualTo(ChatGameController.replySize(message));
	}

	@Test
	public void replyIsTerminatedNotPaddedToWidth() {
		// The destination buffer in the client is 129 bytes, but the field is delimiter-terminated:
		// a fixed-width 128-byte write would only work by accident. Guard against someone reaching
		// for BufferUtil.writeString here.
		var message = ChatGameController.parse(Unpooled.wrappedBuffer(request(ALL_HI)));
		var out = Unpooled.buffer(ChatGameController.replySize(message));

		ChatGameController.writeReply(out, 1, message);

		assertThat(out.readableBytes()).isEqualTo(4 + 1 + 2 + 1);
	}
}
