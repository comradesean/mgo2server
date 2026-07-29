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
	 * @param canRateHost whether this player may rate the host — see the field at wire {@code 0x28}
	 */
	public static void write(ByteBuf buffer, ConnectionInfo host, int currentRule, int currentMap,
			boolean canRateHost) {
		buffer.writeInt(GameError.NONE.result());
		BufferUtil.writeString(buffer, host.getPublicIp(), StandardCharsets.ISO_8859_1, IP_LENGTH);
		buffer.writeShort(host.getPublicPort());
		BufferUtil.writeString(buffer, host.getPrivateIp(), StandardCharsets.ISO_8859_1, IP_LENGTH);
		buffer.writeShort(host.getPrivatePort());

		// THE HOST-RATING GATE. [ELF 2026-07-29] This byte is not spare, and it is not "unknown":
		// the 0x4321 parser at 0xD441DC reads it and 0xD441FC stores it to details+964 — the very
		// slot the star picker is gated on. The end-of-game screen SNAPSHOTS that byte when it is
		// constructed (six sites, e.g. 0x9D7F34, into screen+344), and 0x9DCA34 skips opening the
		// picker when the snapshot is zero. No picker, no 0x43C4, no rating.
		//
		// We sent a hardcoded zero here, on the strength of "echo writes 0" — so every join
		// silently switched host rating off, and it stayed off because this reply lands AFTER the
		// 0x4313 that also writes details+964. Setting the flag in 0x4313 alone could never have
		// worked. It explains the single rating this server has ever recorded: that one needed a
		// details refresh to arrive after the join and before the results screen was built.
		//
		// A seventh inherited constant, and the same shape as the other six: transcribed
		// faithfully, wrong for this client, and invisible because nothing tested it.
		buffer.writeByte(canRateHost ? 1 : 0)
			.writeByte(currentRule)
			.writeByte(currentMap);
	}
}
