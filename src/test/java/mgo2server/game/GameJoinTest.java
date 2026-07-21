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
		GameJoin.write(buffer, host(), 2, 5);
		return buffer;
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

	/** The parser reads one byte at offset 40; echo's rule and map follow, read by no instruction. */
	@Test
	public void trailingBytesCarryTheZeroThenRuleAndMap() {
		var buffer = written();

		assertThat(buffer.getByte(40)).isZero();
		assertThat(buffer.getByte(41)).isEqualTo((byte) 2);
		assertThat(buffer.getByte(42)).isEqualTo((byte) 5);
	}
}
