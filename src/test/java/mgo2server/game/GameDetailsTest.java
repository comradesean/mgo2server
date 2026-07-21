package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.Game;
import mgo2server.common.service.GameService;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Pins the {@code 0x4313} payload against the client's parser at {@code 0xD44388} /
 * {@code 0xD4364C}. Every offset asserted here is a read the binary performs at that position;
 * a drift is a real parse failure, not a cosmetic one — the client errors or waits forever.
 */
public class GameDetailsTest {
	private static Game game() {
		var game = new Game();
		game.setId(3);
		game.setName("rawr");
		game.setComment("gg");
		game.setRule(2);
		game.setMap(5);
		game.setMaxPlayers(16);
		game.setStance(1);
		game.setBriefingTime(90);
		game.setIdleKick(300);
		game.setTeamKillKick(3);
		game.setHostScore(42);
		game.setHostVotes(7);
		return game;
	}

	private static List<GameService.GamePlayer> players() {
		return List.of(new GameService.GamePlayer(2, "SolidHost", 500),
			new GameService.GamePlayer(9, "Joiner", 120));
	}

	private static io.netty.buffer.ByteBuf written() {
		var buffer = Unpooled.buffer();
		GameDetails.write(buffer, game(), 4, 310, players());
		return buffer;
	}

	@Test
	public void fixedPartIsExactly372Bytes() {
		var buffer = Unpooled.buffer();
		GameDetails.write(buffer, game(), 0, 0, List.of());

		assertThat(buffer.readableBytes()).isEqualTo(GameDetails.FIXED_SIZE);
	}

	@Test
	public void eachPlayerAdds28Bytes() {
		assertThat(written().readableBytes())
			.isEqualTo(GameDetails.FIXED_SIZE + 2 * GameDetails.PLAYER_SIZE);
	}

	/** The parser reads result then id and bails on a nonzero result. */
	@Test
	public void startsWithZeroResultThenGameId() {
		var buffer = written();

		assertThat(buffer.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(buffer.getInt(4)).isEqualTo(3);
	}

	@Test
	public void nameAndCommentAreFixedLengthStrings() {
		var buffer = written();

		var name = new byte[16];
		buffer.getBytes(8, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("rawr");

		var comment = new byte[128];
		buffer.getBytes(24, comment);
		assertThat(new String(comment, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("gg");
	}

	/** Two zero bytes, the lobby subtype, then average experience, host score and votes. */
	@Test
	public void headerScalarsSitAtTheParsersOffsets() {
		var buffer = written();

		assertThat(buffer.getByte(152)).isZero();
		assertThat(buffer.getByte(153)).isZero();
		assertThat(buffer.getByte(154)).isEqualTo((byte) 4);
		assertThat(buffer.getInt(155)).isEqualTo(310);
		assertThat(buffer.getInt(159)).isEqualTo(42);
		assertThat(buffer.getInt(163)).isEqualTo(7);
		assertThat(buffer.getByte(167)).isEqualTo((byte) 1);
	}

	/** Round 0 carries the stored rule and map; the other 15 rotation slots stay empty. */
	@Test
	public void rotationCarriesRuleAndMapInRoundZero() {
		var buffer = written();

		assertThat(buffer.getByte(168)).isEqualTo((byte) 2);
		assertThat(buffer.getByte(169)).isEqualTo((byte) 5);
		for (var i = 170; i < 168 + GameDetails.ROUNDS * 3; i++) {
			assertThat(buffer.getByte(i)).as("rotation byte %d", i).isZero();
		}
	}

	@Test
	public void capacityCountAndBriefingFollowTheWeaponRestrictions() {
		var buffer = written();

		assertThat(buffer.getByte(234)).isEqualTo((byte) 16);
		assertThat(buffer.getByte(235)).isEqualTo((byte) 2);
		assertThat(buffer.getInt(236)).isEqualTo(90);
		assertThat(buffer.getByte(262)).isEqualTo((byte) 1); // stance
	}

	/**
	 * Two u32 slots carry constants taken verbatim from echo ({@code 0x16}, {@code 0x2e});
	 * regression guards, not correctness checks — their meaning is unknown.
	 */
	@Test
	public void reproducesEchosUnknownConstants() {
		var buffer = written();

		assertThat(buffer.getInt(264)).isEqualTo(0x16);
		assertThat(buffer.getInt(352)).isEqualTo(0x2e);
	}

	@Test
	public void kicksAndBitfieldsSitBeforeTheTail() {
		var game = game();
		game.setFriendlyFire(true);
		game.setVoiceChat(true);
		var buffer = Unpooled.buffer();
		GameDetails.write(buffer, game, 0, 0, List.of());

		assertThat(buffer.getByte(345)).isEqualTo((byte) GameListEntry.commonA(game));
		assertThat(buffer.getByte(346)).isEqualTo((byte) GameListEntry.commonB(game));
		assertThat(buffer.getShort(348)).isEqualTo((short) 300);
		assertThat(buffer.getShort(350)).isEqualTo((short) 3);
	}

	@Test
	public void nonStatSetsBitOneOfTheExtraFlags() {
		var game = game();
		game.setNonStat(true);
		var buffer = Unpooled.buffer();
		GameDetails.write(buffer, game, 0, 0, List.of());

		assertThat(buffer.getByte(367)).isEqualTo((byte) 0b10);
	}

	/** Player entries: chara id, 16-byte name, ping, experience — host first. */
	@Test
	public void writesPlayerEntriesAfterTheFixedPart() {
		var buffer = written();
		var base = GameDetails.FIXED_SIZE;

		assertThat(buffer.getInt(base)).isEqualTo(2);
		var name = new byte[16];
		buffer.getBytes(base + 4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("SolidHost");
		assertThat(buffer.getInt(base + 20)).isZero(); // ping is not tracked
		assertThat(buffer.getInt(base + 24)).isEqualTo(500);

		assertThat(buffer.getInt(base + GameDetails.PLAYER_SIZE)).isEqualTo(9);
	}

	/** 18 entries is the parser's cap; the full payload must stay under the 1023-byte limit. */
	@Test
	public void fullGameStaysWithinOnePacket() {
		assertThat(GameDetails.FIXED_SIZE + GameDetails.MAX_PLAYERS * GameDetails.PLAYER_SIZE)
			.isLessThanOrEqualTo(1023);
	}
}
