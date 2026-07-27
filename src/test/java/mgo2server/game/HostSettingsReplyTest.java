package mgo2server.game;

import io.netty.buffer.Unpooled;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Pins the populated {@code 0x4305} mapping against the layout transcribed from
 * GHzGangster/Nomad's {@code Hosts.getSettings()}. <b>Regression guard only</b>: the sole
 * authority for this layout is a reference server (tier 4), not the binary — the client's
 * {@code 0x4305} parser has not been located, so these assertions keep the transcription stable,
 * they do not prove it correct for {@code BLUS30109}.
 */
public class HostSettingsReplyTest {
	/** A blob long enough to carry every mapped field, with each byte marking its own offset. */
	private static byte[] blob() {
		var blob = new byte[0x156];
		for (var i = 0; i < blob.length; i++) {
			blob[i] = (byte) i;
		}
		return blob;
	}

	private static io.netty.buffer.ByteBuf written() {
		var buffer = Unpooled.buffer();
		HostSettingsReply.write(buffer, blob());
		return buffer;
	}

	@Test
	public void replyIsExactlyNomadsSize() {
		// 348 = 0x15C, where the parser's last read ends (0xD4548C; final opaque read 0x14E..0x15B).
		// Was 0x163 until 2026-07-26 — that was Nomad's struct length, not this client's packet.
		assertThat(written().readableBytes()).isEqualTo(0x15C);
	}

	@Test
	public void startsWithAZeroResultWord() {
		assertThat(written().getInt(0)).isZero();
	}

	/** Every source region lands at its re-based reply offset. */
	@Test
	public void remapsEachFieldFromItsRequestOffset() {
		var reply = written();

		assertThat(reply.getByte(0x004)).isEqualTo((byte) 0x00); // name <- 0x00
		assertThat(reply.getByte(0x014)).isEqualTo((byte) 0x10); // comment <- 0x10
		assertThat(reply.getByte(0x094)).isEqualTo((byte) 0x90); // password flag <- 0x90
		assertThat(reply.getByte(0x0A5)).isEqualTo((byte) 0xA1); // dedicated <- 0xA1
		assertThat(reply.getByte(0x0A6)).isEqualTo((byte) 0xA3); // rotation <- 0xA3 (skips 0xA2)
		assertThat(reply.getByte(0x0D8)).isEqualTo((byte) 0xD5); // weapon restrictions <- 0xD5
		assertThat(reply.getByte(0x0E8)).isEqualTo((byte) 0xE5); // max players <- 0xE5
		assertThat(reply.getByte(0x0E9)).isEqualTo((byte) 0xE6); // briefing time <- 0xE6
		assertThat(reply.getByte(0x0F9)).isEqualTo((byte) 0xF6); // stance <- 0xF6
		assertThat(reply.getByte(0x0FA)).isEqualTo((byte) 0xF7); // tolerance <- 0xF7
		assertThat(reply.getByte(0x0FB)).isEqualTo((byte) 0xF8); // level-limit base <- 0xF8
		assertThat(reply.getByte(0x0FF)).isEqualTo((byte) 0xFC); // timers <- 0xFC
		assertThat(reply.getByte(0x143)).isEqualTo((byte) 0x40); // uniques <- 0x140
		assertThat(reply.getByte(0x145)).isEqualTo((byte) 0x42); // commonA <- 0x142
		assertThat(reply.getByte(0x146)).isEqualTo((byte) 0x43); // commonB <- 0x143
		// Kick timers are u16 on both sides: request 0x145/0x147 -> reply 0x148/0x14a. The low
		// halves land where the old byte-wise mapping put them, so these two assertions are
		// unchanged; the high halves below are what the truncation used to zero.
		assertThat(reply.getByte(0x148)).isEqualTo((byte) 0x45); // idle kick high <- 0x145
		assertThat(reply.getByte(0x149)).isEqualTo((byte) 0x46); // idle kick low  <- 0x146
		assertThat(reply.getByte(0x14A)).isEqualTo((byte) 0x47); // team-kill high <- 0x147
		assertThat(reply.getByte(0x14B)).isEqualTo((byte) 0x48); // team-kill low  <- 0x148
		assertThat(reply.getByte(0x14C)).isEqualTo((byte) 0x49); // capture extra <- 0x149
		assertThat(reply.getByte(0x14D)).isEqualTo((byte) 0x4A); // Snake side <- 0x14A
		assertThat(reply.getByte(0x14E)).isEqualTo((byte) 0x4B); // byte timers <- 0x14B
		assertThat(reply.getByte(0x157)).isEqualTo((byte) 0x54); // extra-time flags <- 0x154
		assertThat(reply.getByte(0x158)).isEqualTo((byte) 0x55); // host options <- 0x155
	}

	/**
	 * The last byte of every multi-byte region, so a wrong copy length fails and not just a wrong
	 * offset — a region shortened by one would otherwise zero its tail silently.
	 */
	@Test
	public void copiesEachRegionToItsFullLength() {
		var reply = written();

		assertThat(reply.getByte(0x013)).isEqualTo((byte) 0x0F); // name[15]
		assertThat(reply.getByte(0x093)).isEqualTo((byte) 0x8F); // comment[127]
		assertThat(reply.getByte(0x0A4)).isEqualTo((byte) 0xA0); // password block end
		assertThat(reply.getByte(0x0D2)).isEqualTo((byte) 0xCF); // rotation entry 14, flags
		assertThat(reply.getByte(0x0E7)).isEqualTo((byte) 0xE4); // weapon restrictions [15]
		assertThat(reply.getByte(0x0EC)).isEqualTo((byte) 0xE9); // briefing time low byte
		assertThat(reply.getByte(0x0FE)).isEqualTo((byte) 0xFB); // level-limit base low byte
		assertThat(reply.getByte(0x142)).isEqualTo((byte) 0x3F); // timer 17 low byte
		assertThat(reply.getByte(0x144)).isEqualTo((byte) 0x41); // unique blue
		assertThat(reply.getByte(0x155)).isEqualTo((byte) 0x52); // race rounds
	}

	/** The two constants Nomad writes verbatim, and the gaps it leaves zero. */
	@Test
	public void writesNomadsConstantsAndZeroGaps() {
		var reply = written();

		assertThat(reply.getByte(0x0ED)).isEqualTo((byte) 0x02);
		assertThat(reply.getByte(0x147)).isEqualTo((byte) 0x20); // commonC constant, not echoed
		// Rotation entry 16 (wire 0x0D3..0x0D5) — copied since 2026-07-26. It used to be zero
		// because we sent only 15 triples, which silently dropped a full rotation's last round.
		assertThat(reply.getByte(0x0D5)).isEqualTo((byte) 0xD2);
		assertThat(reply.getByte(0x0D6)).isZero(); // padding starts here now
		assertThat(reply.getByte(0x0F0)).isZero(); // pre-stance padding
		assertThat(reply.getByte(0x156)).isZero();
		assertThat(reply.getByte(0x15B)).isZero(); // last byte the parser reads
	}

	@Test
	public void refusesBlobsTooShortToCarryEveryField() {
		assertThat(HostSettingsReply.canWrite(null)).isFalse();
		assertThat(HostSettingsReply.canWrite(new byte[0x155])).isFalse();
		assertThat(HostSettingsReply.canWrite(new byte[0x156])).isTrue();
	}
}
