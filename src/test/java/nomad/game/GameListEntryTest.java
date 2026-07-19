package nomad.game;

import io.netty.buffer.Unpooled;
import nomad.common.model.Game;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.*;

/**
 * The game list packs most of a host's settings into two bitfield bytes. A wrong bit shows up in
 * the browser as an unrelated option appearing set, which is easy to miss and hard to trace, so
 * each flag is pinned individually.
 */
public class GameListEntryTest {
	private static Game game() {
		var game = new Game();
		game.setId(7);
		game.setName("Outer Heaven");
		game.setMaxPlayers(16);
		return game;
	}

	@Test
	public void entryIsExactlyFiftyFiveBytes() {
		var buffer = Unpooled.buffer(GameListEntry.SIZE);
		GameListEntry.write(buffer, game(), 0, 0, false, false);

		assertThat(buffer.readableBytes()).isEqualTo(0x37);
	}

	@Test
	public void writesIdAndName() {
		var buffer = Unpooled.buffer(GameListEntry.SIZE);
		GameListEntry.write(buffer, game(), 0, 0, false, false);

		assertThat(buffer.getInt(0)).isEqualTo(7);

		var name = new byte[16];
		buffer.getBytes(4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Outer Heaven");
	}

	// ---------- hostOptions ----------

	@Test
	public void hostOptionsIsEmptyByDefault() {
		assertThat(GameListEntry.hostOptions(game())).isZero();
	}

	@Test
	public void hostOptionsFlagsPassword() {
		var game = game();
		game.setPassword("secret");

		assertThat(GameListEntry.hostOptions(game)).isEqualTo(0b1);
	}

	/** An empty password string is no password, not a password of length zero. */
	@Test
	public void hostOptionsTreatsEmptyPasswordAsNone() {
		var game = game();
		game.setPassword("");

		assertThat(GameListEntry.hostOptions(game)).isZero();
	}

	@Test
	public void hostOptionsFlagsDedicated() {
		var game = game();
		game.setDedicated(true);

		assertThat(GameListEntry.hostOptions(game)).isEqualTo(0b10);
	}

	// ---------- commonA ----------

	/** One bit is always set by the original; its meaning is undocumented. */
	@Test
	public void commonAAlwaysSetsItsConstantBit() {
		assertThat(GameListEntry.commonA(game())).isEqualTo(0b100);
	}

	@Test
	public void commonAPacksItsFlags() {
		var game = game();
		game.setIdleKick(30);
		game.setFriendlyFire(true);
		game.setGhosts(true);
		game.setAutoAim(true);
		game.setUniquesEnabled(true);

		assertThat(GameListEntry.commonA(game)).isEqualTo(0b10111101);
	}

	/** Idle kick is a duration, and only its presence reaches the browser. */
	@Test
	public void commonAFlagsIdleKickOnlyWhenPositive() {
		var game = game();
		game.setIdleKick(0);
		assertThat(GameListEntry.commonA(game) & 0b1).isZero();

		game.setIdleKick(1);
		assertThat(GameListEntry.commonA(game) & 0b1).isEqualTo(0b1);
	}

	// ---------- commonB ----------

	@Test
	public void commonBIsEmptyByDefault() {
		assertThat(GameListEntry.commonB(game())).isZero();
	}

	@Test
	public void commonBPacksItsFlags() {
		var game = game();
		game.setTeamsSwitch(true);
		game.setAutoAssign(true);
		game.setSilentMode(true);
		game.setEnemyNametags(true);
		game.setLevelLimitEnabled(true);
		game.setVoiceChat(true);
		game.setTeamKillKick(3);

		assertThat(GameListEntry.commonB(game)).isEqualTo(0b11011111);
	}

	@Test
	public void commonBFlagsTeamKillKickOnlyWhenPositive() {
		var game = game();
		game.setTeamKillKick(0);
		assertThat(GameListEntry.commonB(game) & 0b10000000).isZero();

		game.setTeamKillKick(1);
		assertThat(GameListEntry.commonB(game) & 0b10000000).isEqualTo(0b10000000);
	}

	/** The two bitfields must not overlap; each flag belongs to exactly one byte. */
	@Test
	public void commonAAndCommonBAreIndependent() {
		var game = game();
		game.setFriendlyFire(true);

		assertThat(GameListEntry.commonA(game) & 0b1000).isEqualTo(0b1000);
		assertThat(GameListEntry.commonB(game)).isZero();

		var other = game();
		other.setVoiceChat(true);

		assertThat(GameListEntry.commonB(other) & 0b1000000).isEqualTo(0b1000000);
		assertThat(GameListEntry.commonA(other)).isEqualTo(0b100);
	}

	// ---------- friendBlock ----------

	@Test
	public void friendBlockPacksBothFlags() {
		assertThat(GameListEntry.friendBlock(false, false)).isZero();
		assertThat(GameListEntry.friendBlock(true, false)).isEqualTo(0b1);
		assertThat(GameListEntry.friendBlock(false, true)).isEqualTo(0b10);
		assertThat(GameListEntry.friendBlock(true, true)).isEqualTo(0b11);
	}

	// ---------- field offsets ----------

	@Test
	public void writesCountsAndScoresAtTheExpectedOffsets() {
		var game = game();
		game.setPing(42);
		game.setLevelLimitBase(150);
		game.setLevelLimitTolerance(7);
		game.setHostScore(1000);
		game.setHostVotes(9);
		game.setStance(2);
		game.setRule(3);
		game.setMap(4);

		var buffer = Unpooled.buffer(GameListEntry.SIZE);
		GameListEntry.write(buffer, game, 5, 250, true, false);

		assertThat(buffer.getByte(22)).isEqualTo((byte) 3);    // rule
		assertThat(buffer.getByte(23)).isEqualTo((byte) 4);    // map
		assertThat(buffer.getByte(25)).isEqualTo((byte) 16);   // maxPlayers
		assertThat(buffer.getByte(26)).isEqualTo((byte) 2);    // stance
		assertThat(buffer.getByte(29)).isEqualTo((byte) 5);    // players present
		assertThat(buffer.getInt(30)).isEqualTo(42);           // ping
		assertThat(buffer.getByte(34)).isEqualTo((byte) 0b1);  // friendBlock
		assertThat(buffer.getByte(35)).isEqualTo((byte) 7);    // level limit tolerance
		assertThat(buffer.getInt(36)).isEqualTo(150);          // level limit base
		assertThat(buffer.getInt(40)).isEqualTo(250);          // average experience
		assertThat(buffer.getInt(44)).isEqualTo(1000);         // host score
		assertThat(buffer.getInt(48)).isEqualTo(9);            // host votes
	}
}
