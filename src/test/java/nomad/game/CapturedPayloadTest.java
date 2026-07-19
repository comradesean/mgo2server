package nomad.game;

import io.netty.buffer.Unpooled;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.model.EquippedSkills;
import nomad.common.model.Game;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Objects;

import static org.assertj.core.api.Assertions.*;

/**
 * Checks the payload writers against reference payloads shipped in Nomad's repository.
 * <p>
 * The other writer tests assert that the implementation matches my reading of the original Java
 * source, which is circular: a misread offset would be reproduced identically in the code and in
 * the test. These fixtures are not circular in that way, because nothing in Nomad generates them —
 * the code only ever reads them, via {@code Util.readFile}, to serve canned responses to a client.
 * They are therefore independent of the code being ported from.
 * <p>
 * Their ultimate origin is <em>not</em> documented anywhere in that repository. They may be traces
 * preserved from the retail servers, or they may have been constructed by hand; the repo says
 * nothing either way, and the files were committed in 2017, years after MGO2 shut down. What can
 * be observed is that several ship in differing {@code -working} and {@code .bak} variants, which
 * suggests they were iterated until a client accepted them — but that is inference, not evidence.
 * <p>
 * So: treat these as strong corroboration that the layouts and undocumented constants match a
 * second, independent artefact, and not as proof of correctness against the retail protocol. Only
 * a real client can supply that.
 * <p>
 * Only the parts that do not depend on character data are compared — sizes, fixed blocks and the
 * constants whose meaning is unknown. Everything else legitimately differs.
 */
public class CapturedPayloadTest {
	private static byte[] capture(String name) {
		try (var stream = CapturedPayloadTest.class.getClassLoader()
				.getResourceAsStream("captures/" + name)) {
			Objects.requireNonNull(stream, () -> "Missing capture: " + name);
			return stream.readAllBytes();
		} catch (IOException e) {
			throw new UncheckedIOException(e);
		}
	}

	// ---------- 0x4122 personal info ----------

	private static byte[] personalInfo() {
		var chara = new Chara();
		chara.setId(1);
		chara.setName("Test");
		chara.setComment("");

		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara, new CharaAppearance(), new EquippedSkills());

		var bytes = new byte[buffer.readableBytes()];
		buffer.getBytes(0, bytes);
		return bytes;
	}

	@Test
	public void personalInfoMatchesCapturedLength() {
		assertThat(personalInfo()).hasSameSizeAs(capture("4122-personal-info.bin"));
	}

	/** The undocumented 25-byte block after the clan name. */
	@Test
	public void personalInfoPrefixMatchesCapture() {
		var captured = capture("4122-personal-info.bin");
		var mine = personalInfo();

		assertThat(java.util.Arrays.copyOfRange(mine, 20, 45))
			.isEqualTo(java.util.Arrays.copyOfRange(captured, 20, 45));
	}

	/** The four skill-experience values, which the original sends as a constant. */
	@Test
	public void personalInfoSkillExperienceMatchesCapture() {
		var captured = capture("4122-personal-info.bin");
		var mine = personalInfo();

		assertThat(java.util.Arrays.copyOfRange(mine, 86, 107))
			.isEqualTo(java.util.Arrays.copyOfRange(captured, 86, 107));
	}

	/** The undocumented four-byte tail. */
	@Test
	public void personalInfoSuffixMatchesCapture() {
		var captured = capture("4122-personal-info.bin");
		var mine = personalInfo();

		assertThat(java.util.Arrays.copyOfRange(mine, 241, 245))
			.isEqualTo(java.util.Arrays.copyOfRange(captured, 241, 245));
	}

	/**
	 * The fixture is from a character in a clan with an emblem, which is the case this build
	 * cannot yet produce. Documents the known divergence so it is not mistaken for a bug.
	 */
	@Test
	public void personalInfoClanFieldsDivergeBecauseClansAreNotModelled() {
		var captured = capture("4122-personal-info.bin");
		var mine = personalInfo();

		assertThat(captured[240]).as("captured character's clan has an emblem").isEqualTo((byte) 3);
		assertThat(mine[240]).as("no clans modelled yet, so never an emblem").isZero();
	}

	// ---------- 0x4302 game list entry ----------

	private static byte[] gameListEntry() {
		var game = new Game();
		game.setId(1);
		game.setName("SaveMGO");
		game.setMaxPlayers(16);

		var buffer = Unpooled.buffer(GameListEntry.SIZE);
		GameListEntry.write(buffer, game, 1, 0, false, false);

		var bytes = new byte[buffer.readableBytes()];
		buffer.getBytes(0, bytes);
		return bytes;
	}

	@Test
	public void gameListEntryMatchesCapturedLength() {
		assertThat(gameListEntry()).hasSameSizeAs(capture("4302-game-list-entry.bin"));
	}

	/** The constant at offset 21, whose meaning is undocumented. */
	@Test
	public void gameListEntryUnknownConstantMatchesCapture() {
		assertThat(gameListEntry()[21]).isEqualTo(capture("4302-game-list-entry.bin")[21]);
	}

	/** The two padding bytes and the trailing constant at the end of the entry. */
	@Test
	public void gameListEntryTailMatchesCapture() {
		var captured = capture("4302-game-list-entry.bin");
		var mine = gameListEntry();

		assertThat(java.util.Arrays.copyOfRange(mine, 52, 55))
			.isEqualTo(java.util.Arrays.copyOfRange(captured, 52, 55));
	}

	/** The bit the original always sets in commonA is set in real traffic too. */
	@Test
	public void gameListEntryAlwaysSetBitIsPresentInCapture() {
		var captured = capture("4302-game-list-entry.bin");

		assertThat(captured[27] & 0b100).as("commonA constant bit").isEqualTo(0b100);
		assertThat(gameListEntry()[27] & 0b100).isEqualTo(0b100);
	}

	/** The name field occupies the same 16 bytes in both. */
	@Test
	public void gameListEntryNameIsAtTheSameOffset() {
		var captured = capture("4302-game-list-entry.bin");
		var mine = gameListEntry();

		var capturedName = new String(java.util.Arrays.copyOfRange(captured, 4, 20),
			java.nio.charset.StandardCharsets.ISO_8859_1).replace("\0", "");
		var myName = new String(java.util.Arrays.copyOfRange(mine, 4, 20),
			java.nio.charset.StandardCharsets.ISO_8859_1).replace("\0", "");

		assertThat(myName).isEqualTo(capturedName).isEqualTo("SaveMGO");
	}
}
