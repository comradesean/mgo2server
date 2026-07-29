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

	/** In echo's extra-time flags byte, bit 1 marks a non-stat game. */
	private static final int EXTRA_NON_STAT = 0b10;

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
			List<GameService.GamePlayer> players, boolean viewerIsHost) {
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
			// THE HOST-RATING GATE, not a constant. [ELF] Struct +964; the 0x4313 parser writes it
			// at 0xD44588. A nonzero there is what lets the end-of-game screen open the star picker
			// and therefore send 0x43C4 — the 1-to-5 host rating. It must be 0 for your own game,
			// which is how the client stops you rating yourself.
			//
			// NECESSARY BUT NOT SUFFICIENT, corrected 2026-07-29. 0x4321 wire 0x28 writes the SAME
			// slot (0xD441FC) and lands after any pre-join 0x4313, so the join reply overwrites
			// this. Setting it here alone can never enable rating — see GameJoin, which is where
			// the bug actually was. A live capture had this byte = 1 and produced no prompt.
			.writeByte(viewerIsHost ? 0 : 1);

		// The rotation: 16 triples of (rule, map, flags). Only a single rule and map are stored
		// until the 0x4310 settings blob is persisted, so round 0 carries them and the rest stay
		// empty. (Echo splits this same region as 15 triples plus 5 zero bytes; the parser at
		// 0xD4364C says 16 triples then two separate bytes, and the parser wins.)
		buffer.writeByte(game.getRule())
			.writeByte(game.getMap())
			.writeByte(game.getFlags())
			.writeZero((ROUNDS - 1) * 3)
			.writeZero(2); // two u8s after the rotation; echo zeroes them, meaning unknown

		// EVERYTHING HERE NOW COMES FROM TYPED COLUMNS. These five regions used to be copied
		// verbatim out of the stored 0x4310 blob, which meant the browser could only show a host's
		// real settings for as long as we kept bytes we could not describe. They are columns now,
		// and the blob is on its way out — see BACKLOG, "The host-settings blob must go".

		// Weapon restrictions: one bit per item, 1 = locked, bit 0 of byte 0 the master enable.
		// The per-weapon map IS established — 19 bits confirmed weapon-by-weapon against the live
		// client (PROTOCOL.md, "Weapon restrictions") — so this is not an unknown. It stays a
		// 16-byte field because it is a bitmask the client owns, and because the remaining bits are
		// reference-transcribed and unverifiable on this build; expanding it would harden those
		// guesses into schema.
		writeOrZero(buffer, game.getWeaponRestrictions(), 16);
		buffer.writeByte(game.getMaxPlayers())
			.writeByte(players.size())
			.writeInt(game.getBriefingTime())
			.writeZero(22) // u32,u32,u16,u16,u32,u32,u16 in the parser; echo zeroes all of it
			.writeByte(game.getStance())
			.writeByte(game.getLevelLimitTolerance())
			// [ELF 2026-07-29] Struct +848 — the LEVEL-LIMIT BASE, the same value 0x4302 already
			// sends from the same column. Identified by the client's own hosted-game builder
			// mapping struct+848 onto the browser entry's level-limit slot, one of twelve
			// concordant fields in that mapping. Was a hardcoded 0x16 (22) inherited from a
			// reference — a plausible-looking level, which is why it never looked wrong.
			.writeInt(game.getLevelLimitBase());
		writeTimers(buffer, game.getRuleTimers());
		buffer.writeByte(game.getUniqueRed())
			.writeByte(game.getUniqueBlue());
		buffer.writeZero(7)
			.writeByte(GameListEntry.commonA(game))
			.writeByte(GameListEntry.commonB(game))
			.writeZero(1)
			.writeShort(game.getIdleKick())
			.writeShort(game.getTeamKillKick())
			// [ELF 2026-07-29] Struct +936 — the host's PING, the same column 0x4302 sends. No
			// client writer exists for it on any settings base and 0x4305 skips it, exactly like
			// player_count: a live-session field, not a saved setting. Was a hardcoded 0x2e (46),
			// which reads as a believable latency and so survived unquestioned.
			.writeInt(game.getPing());
		buffer.writeByte(game.isCaptureExtraTime() ? 1 : 0)
			.writeByte(game.getSneakingSnakeKills());
		// The first eight bytes of the block the client writes raw and never reads back. Our own
		// label for them is "per-rule byte-sized timers" for the post-launch modes, which is tier 4
		// and unverified — they are replayed rather than interpreted.
		writeOrZero(buffer, game.getUnreadTail(), 8);
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

	/** Writes the first {@code count} bytes of a stored field, zero-filling what is missing. */
	private static void writeOrZero(ByteBuf buffer, byte[] value, int count) {
		if (value != null) {
			buffer.writeBytes(value, 0, Math.min(value.length, count));
			buffer.writeZero(Math.max(0, count - value.length));
			return;
		}
		buffer.writeZero(count);
	}

	/** The seventeen per-rule timers as u32, or zeros for a game whose settings never arrived. */
	private static void writeTimers(ByteBuf buffer, int[] timers) {
		for (var slot = 0; slot < 17; slot++) {
			buffer.writeInt(timers != null && slot < timers.length ? timers[slot] : 0);
		}
	}

}
