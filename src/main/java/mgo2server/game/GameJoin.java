package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.ConnectionInfo;

import java.nio.charset.StandardCharsets;

/**
 * The join-game reply ({@code 0x4321}): the host's peer-to-peer endpoints, handed to the player
 * who asked to join so the two can connect directly.
 * <p>
 * The layout is read from the client's reply parser at {@code 0xD440DC}: a u32 result, then on
 * success a 16-byte IP, a u16 port, a 16-byte IP, a u16 port, and one trailing byte. That is the
 * host's public address:port followed by its private address:port. The parser reads exactly those
 * 41 bytes and stops — echo writes 43 (a further rule and map byte); the extra two are read by no
 * instruction here, but are reproduced because echo is known to satisfy this client and trailing
 * bytes are harmless.
 * <p>
 * On a nonzero result the parser skips the body, so a failure is a bare 4-byte result.
 */
public final class GameJoin {
	private static final int IP_LENGTH = 16;

	/**
	 * Bytes written on success: result(4) + publicIp(16) + publicPort(2) + privateIp(16) +
	 * privatePort(2) + three trailing bytes = 43 (echo's {@code 0x2b}). The parser reads the
	 * first 41; the last two are echo's rule/map, reproduced but unread by this client.
	 */
	public static final int SIZE = 4 + IP_LENGTH + 2 + IP_LENGTH + 2 + 3;

	private GameJoin() {
	}

	/**
	 * Writes the success reply from the host's registered endpoints.
	 *
	 * @param currentRule the game's active rule, echoed after the endpoints (echo does the same)
	 * @param currentMap the game's active map
	 */
	public static void write(ByteBuf buffer, ConnectionInfo host, int currentRule, int currentMap) {
		buffer.writeInt(GameError.NONE.result());
		BufferUtil.writeString(buffer, host.getPublicIp(), StandardCharsets.ISO_8859_1, IP_LENGTH);
		buffer.writeShort(host.getPublicPort());
		BufferUtil.writeString(buffer, host.getPrivateIp(), StandardCharsets.ISO_8859_1, IP_LENGTH);
		buffer.writeShort(host.getPrivatePort());

		// The parser reads one trailing byte; echo writes a rule and map byte here too. Only the
		// first is consumed by this client, but all three are written to mirror the known-good
		// server byte for byte.
		buffer.writeByte(0)
			.writeByte(currentRule)
			.writeByte(currentMap);
	}
}
