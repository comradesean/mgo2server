package nomad.game;

import io.netty.buffer.ByteBuf;
import nomad.common.BufferUtil;
import nomad.common.model.Game;

import java.nio.charset.StandardCharsets;

/**
 * One entry in a lobby's game list.
 * <p>
 * The client reads a fixed 55-byte record in which most of the host's settings are squeezed into
 * two bitfield bytes. The packing is pulled out here, away from the controller, because getting a
 * bit wrong shows up as an unrelated option appearing checked in the game browser rather than as
 * an obvious failure.
 */
public final class GameListEntry {
	/** Bytes per entry on the wire. */
	public static final int SIZE = 0x37;

	/** Entries per packet, bounded by the maximum payload size. */
	public static final int PER_PACKET = 18;

	private static final int NAME_LENGTH = 16;

	// hostOptions
	private static final int HOST_PASSWORD = 0b1;
	private static final int HOST_DEDICATED = 0b10;

	// commonA
	private static final int A_IDLE_KICK = 0b1;
	/** Always set by the original; meaning unknown. */
	private static final int A_ALWAYS = 0b100;
	private static final int A_FRIENDLY_FIRE = 0b1000;
	private static final int A_GHOSTS = 0b10000;
	private static final int A_AUTO_AIM = 0b100000;
	private static final int A_UNIQUES = 0b10000000;

	// commonB
	private static final int B_TEAMS_SWITCH = 0b1;
	private static final int B_AUTO_ASSIGN = 0b10;
	private static final int B_SILENT_MODE = 0b100;
	private static final int B_ENEMY_NAMETAGS = 0b1000;
	private static final int B_LEVEL_LIMIT = 0b10000;
	private static final int B_VOICE_CHAT = 0b1000000;
	private static final int B_TEAM_KILL_KICK = 0b10000000;

	// friendBlock
	private static final int F_HAS_FRIEND = 0b1;
	private static final int F_HAS_BLOCKED = 0b10;

	/** Constants the original writes verbatim; their meaning is not documented. */
	private static final int UNKNOWN_BYTE = 0x8;

	private static final int TRAILING_BYTE = 0x63;

	private GameListEntry() {
	}

	public static int hostOptions(Game game) {
		var flags = 0;
		if (game.getPassword() != null && !game.getPassword().isEmpty()) {
			flags |= HOST_PASSWORD;
		}
		if (game.isDedicated()) {
			flags |= HOST_DEDICATED;
		}
		return flags;
	}

	public static int commonA(Game game) {
		var flags = A_ALWAYS;
		if (game.getIdleKick() > 0) {
			flags |= A_IDLE_KICK;
		}
		if (game.isFriendlyFire()) {
			flags |= A_FRIENDLY_FIRE;
		}
		if (game.isGhosts()) {
			flags |= A_GHOSTS;
		}
		if (game.isAutoAim()) {
			flags |= A_AUTO_AIM;
		}
		if (game.isUniquesEnabled()) {
			flags |= A_UNIQUES;
		}
		return flags;
	}

	public static int commonB(Game game) {
		var flags = 0;
		if (game.isTeamsSwitch()) {
			flags |= B_TEAMS_SWITCH;
		}
		if (game.isAutoAssign()) {
			flags |= B_AUTO_ASSIGN;
		}
		if (game.isSilentMode()) {
			flags |= B_SILENT_MODE;
		}
		if (game.isEnemyNametags()) {
			flags |= B_ENEMY_NAMETAGS;
		}
		if (game.isLevelLimitEnabled()) {
			flags |= B_LEVEL_LIMIT;
		}
		if (game.isVoiceChat()) {
			flags |= B_VOICE_CHAT;
		}
		if (game.getTeamKillKick() > 0) {
			flags |= B_TEAM_KILL_KICK;
		}
		return flags;
	}

	public static int friendBlock(boolean hasFriend, boolean hasBlocked) {
		var flags = 0;
		if (hasFriend) {
			flags |= F_HAS_FRIEND;
		}
		if (hasBlocked) {
			flags |= F_HAS_BLOCKED;
		}
		return flags;
	}

	/**
	 * Writes one entry.
	 *
	 * @param averageExperience mean experience across the players currently in the game
	 */
	public static void write(ByteBuf buffer, Game game, int playerCount, int averageExperience,
			boolean hasFriend, boolean hasBlocked) {
		var start = buffer.writerIndex();

		buffer.writeInt((int) game.getId());
		BufferUtil.writeString(buffer, game.getName(), StandardCharsets.ISO_8859_1, NAME_LENGTH);

		buffer.writeByte(hostOptions(game))
			.writeByte(UNKNOWN_BYTE)
			.writeByte(game.getRule())
			.writeByte(game.getMap())
			.writeZero(1)
			.writeByte(game.getMaxPlayers())
			.writeByte(game.getStance())
			.writeByte(commonA(game))
			.writeByte(commonB(game))
			.writeByte(playerCount)
			.writeInt(game.getPing())
			.writeByte(friendBlock(hasFriend, hasBlocked))
			.writeByte(game.getLevelLimitTolerance())
			.writeInt(game.getLevelLimitBase())
			.writeInt(averageExperience)
			.writeInt(game.getHostScore())
			.writeInt(game.getHostVotes())
			.writeZero(2)
			.writeByte(TRAILING_BYTE);

		assert buffer.writerIndex() - start == SIZE
			: "Game list entry must be " + SIZE + " bytes";
	}
}
