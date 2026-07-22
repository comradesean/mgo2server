package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.Game;
import mgo2server.common.service.GameService;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * The game details reply ({@code 0x4313}): everything the details, join and player-list screens
 * show about one hosted game.
 * <p>
 * The layout below is read straight out of the client's parser — the reply dispatcher at
 * {@code 0xD38954} routes {@code 0x4313} to {@code 0xD44388}, whose read sequence (with the
 * settings sub-structure at {@code 0xD4364C}) fixes every field's size and order. Sizes and order
 * are therefore fact. Most field <em>names</em> come from echo's {@code GameDetailsPacket}, whose
 * writes align with this parser byte for byte; names are reference-derived and unverified except
 * where a wrong value has been seen to change a rendered screen.
 * <p>
 * The parser reads the fixed part unconditionally: a shorter payload is a parse error and the
 * client keeps waiting, so every unknown field must be present even if zero. Player entries are
 * read while payload remains, at most {@link #MAX_PLAYERS}; a truncated final entry is also a
 * parse error, never a shorter list.
 */
public final class GameDetails {
	/** Bytes before the player entries. The parser reads exactly this much unconditionally. */
	public static final int FIXED_SIZE = 372;

	/** Bytes per player entry: chara id, name, ping, experience. */
	public static final int PLAYER_SIZE = 28;

	/** The parser's player loop runs at most 18 times, matching the game list's 18-entry cap. */
	public static final int MAX_PLAYERS = 18;

	/** The round-rotation table is 16 (rule, map, flags) triples, interleaved on the wire. */
	public static final int ROUNDS = 16;

	private static final int NAME_LENGTH = 16;

	private static final int COMMENT_LENGTH = 128;

	/**
	 * Constants echo writes verbatim at two u32 slots; meaning unknown. Reproduced because echo
	 * demonstrably satisfied this client build, and flagged so nobody mistakes them for ours.
	 */
	private static final int UNKNOWN_INT_A = 0x16;

	private static final int UNKNOWN_INT_B = 0x2e;

	/** In echo's extra-time flags byte, bit 1 marks a non-stat game. */
	private static final int EXTRA_NON_STAT = 0b10;

	// Offsets into the raw 0x4310 host-settings blob for the blocks replayed here verbatim. Each
	// block is the same field order and byte encoding as the 0x4313 slot it fills.
	private static final int WEAPON_OFFSET = 0xD5;        // 16-byte weapon-restriction block

	private static final int RULE_TIMERS_OFFSET = 0xFC;   // 17 u32: per-mode time/rounds/tickets

	private static final int UNIQUES_OFFSET = 0x140;      // unique characters red/blue

	private static final int CAP_EXTRA_OFFSET = 0x149;    // capture extra time, sneaking-Snake side

	private static final int BYTE_TIMERS_OFFSET = 0x14B;  // SDM/INT/DM/SCAP/RACE byte-sized timers

	private GameDetails() {
	}

	/**
	 * Writes the full reply payload, result included.
	 *
	 * @param lobbySubtype the serving lobby's subtype, echoed one byte after two zero bytes
	 * @param averageExperience mean experience across the players currently in the game
	 * @param players host first — echo writes the host entry before everyone else
	 */
	public static void write(ByteBuf buffer, Game game, int lobbySubtype, int averageExperience,
			List<GameService.GamePlayer> players) {
		var start = buffer.writerIndex();

		buffer.writeInt(GameError.NONE.result())
			.writeInt((int) game.getId());
		BufferUtil.writeString(buffer, game.getName(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
		BufferUtil.writeString(buffer, game.getComment(), StandardCharsets.ISO_8859_1,
			COMMENT_LENGTH);

		buffer.writeZero(2)
			.writeByte(lobbySubtype)
			.writeInt(averageExperience)
			.writeInt(game.getHostScore())
			.writeInt(game.getHostVotes())
			.writeByte(1); // echo writes 1 verbatim; meaning unknown

		// The rotation: 16 triples of (rule, map, flags). Only a single rule and map are stored
		// until the 0x4310 settings blob is persisted, so round 0 carries them and the rest stay
		// empty. (Echo splits this same region as 15 triples plus 5 zero bytes; the parser at
		// 0xD4364C says 16 triples then two separate bytes, and the parser wins.)
		buffer.writeByte(game.getRule())
			.writeByte(game.getMap())
			.writeByte(game.getFlags())
			.writeZero((ROUNDS - 1) * 3)
			.writeZero(2); // two u8s after the rotation; echo zeroes them, meaning unknown

		// The per-mode timers/rounds/tickets and uniques are replayed verbatim from the stored
		// 0x4310 blob (same field order and encoding as here), so the browser shows the host's real
		// values instead of zeros. Everything else stays derived from the game columns.
		var blob = game.getHostSettings();

		// Weapon restrictions, replayed opaquely from the blob (1 bit per item, 1 = locked).
		// Byte-by-bit map in PROTOCOL.md, "Weapon restrictions": 19 bits capture-confirmed on
		// this build, the remainder expansion-era gear transcribed from Nomad and unverifiable.
		copyOrZero(buffer, blob, WEAPON_OFFSET, 16);
		buffer.writeByte(game.getMaxPlayers())
			.writeByte(players.size())
			.writeInt(game.getBriefingTime())
			.writeZero(22) // u32,u32,u16,u16,u32,u32,u16 in the parser; echo zeroes all of it
			.writeByte(game.getStance())
			.writeByte(game.getLevelLimitTolerance())
			.writeInt(UNKNOWN_INT_A);
		copyOrZero(buffer, blob, RULE_TIMERS_OFFSET, 17 * Integer.BYTES); // per-rule times/rounds/tickets
		copyOrZero(buffer, blob, UNIQUES_OFFSET, 2); // unique characters red/blue
		buffer.writeZero(7)
			.writeByte(GameListEntry.commonA(game))
			.writeByte(GameListEntry.commonB(game))
			.writeZero(1)
			.writeShort(game.getIdleKick())
			.writeShort(game.getTeamKillKick())
			.writeInt(UNKNOWN_INT_B);
		copyOrZero(buffer, blob, CAP_EXTRA_OFFSET, 2); // capture extra time, sneaking-Snake side
		copyOrZero(buffer, blob, BYTE_TIMERS_OFFSET, 8); // per-rule byte-sized timers
		buffer.writeZero(1)
			.writeByte(game.isNonStat() ? EXTRA_NON_STAT : 0)
			.writeZero(4);

		assert buffer.writerIndex() - start == FIXED_SIZE
			: "Game details fixed part must be " + FIXED_SIZE + " bytes";

		for (var player : players) {
			buffer.writeInt((int) player.charaId());
			BufferUtil.writeString(buffer, player.name(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
			buffer.writeInt(player.ping()); // host-reported via 0x4398; 0 until a report arrives
			buffer.writeInt(player.experience());
		}
	}

	/** Copies {@code count} bytes from the host-settings blob at {@code offset}, or zero-fills. */
	private static void copyOrZero(ByteBuf buffer, byte[] blob, int offset, int count) {
		if (blob != null && offset + count <= blob.length) {
			buffer.writeBytes(blob, offset, count);
		} else {
			buffer.writeZero(count);
		}
	}
}
