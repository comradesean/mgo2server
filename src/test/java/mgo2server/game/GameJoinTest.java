package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.ConnectionInfo;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.*;

/**
 * Pins the {@code 0x4321} success payload against the client's reply parser at {@code 0xD440DC}:
 * result, then public IP + port, private IP + port, and a trailing byte. Offsets asserted here
 * are reads the binary performs; a drift sends the joiner to the wrong peer address.
 */
public class GameJoinTest {
	private static ConnectionInfo host() {
		var info = new ConnectionInfo();
		info.setCharaId(2);
		info.setPublicIp("47.205.42.160");
		info.setPublicPort(5730);
		info.setPrivateIp("192.168.1.100");
		info.setPrivatePort(5731);
		return info;
	}

	private static io.netty.buffer.ByteBuf written() {
		var buffer = Unpooled.buffer();
		GameJoin.write(buffer, host(), 2, 5, true);
		return buffer;
	}

	/**
	 * Wire 0x28 is the host-rating gate, and it must be set for a joiner.
	 * <p>
	 * [ELF] the 0x4321 parser stores this byte to {@code details+964} ({@code 0xD441FC}) — the slot
	 * the end-of-game star picker is gated on. We hardcoded 0 here on the strength of "echo writes
	 * 0", which switched host rating off on every join. It also overwrites whatever {@code 0x4313}
	 * wire 0x0a7 set, because the join reply lands afterwards, so setting the flag there alone
	 * could never have worked.
	 */
	@Test
	public void theHostRatingGateIsSetForAJoiner() {
		assertThat(written().getUnsignedByte(0x28))
			.as("wire 0x28 permits the star picker; zero means no rating prompt ever appears")
			.isEqualTo((short) 1);
	}

	/** And clear when the player must not rate, which is how self-rating stays impossible. */
	@Test
	public void theHostRatingGateIsClearWhenRatingIsNotPermitted() {
		var buffer = Unpooled.buffer();
		GameJoin.write(buffer, host(), 2, 5, false);

		assertThat(buffer.getUnsignedByte(0x28)).isEqualTo((short) 0);
	}

	@Test
	public void successPayloadIs43Bytes() {
		assertThat(written().readableBytes()).isEqualTo(GameJoin.SIZE);
		assertThat(GameJoin.SIZE).isEqualTo(0x2b);
	}

	@Test
	public void startsWithZeroResult() {
		assertThat(written().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	@Test
	public void writesPublicEndpointThenPrivate() {
		var buffer = written();

		var publicIp = new byte[16];
		buffer.getBytes(4, publicIp);
		assertThat(new String(publicIp, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("47.205.42.160");
		assertThat(buffer.getUnsignedShort(20)).isEqualTo(5730);

		var privateIp = new byte[16];
		buffer.getBytes(22, privateIp);
		assertThat(new String(privateIp, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("192.168.1.100");
		assertThat(buffer.getUnsignedShort(38)).isEqualTo(5731);
	}

	/**
	 * The three trailing bytes: the host-rating gate at 40 (0x28), then rule and map.
	 * <p>
	 * This test used to assert byte 40 was ZERO, and named it "theZero" — pinning the bug in place.
	 * The byte is the rating gate ({@code 0xD441FC} stores it to {@code details+964}), so a zero
	 * here disables host rating for the joiner. Rule and map are read by no instruction in this
	 * client; they are kept because they cost nothing and the reference sends them.
	 */
	@Test
	public void trailingBytesCarryTheRatingGateThenRuleAndMap() {
		var buffer = written();

		assertThat(buffer.getByte(40)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(41)).isEqualTo((byte) 2);
		assertThat(buffer.getByte(42)).isEqualTo((byte) 5);
	}
}
