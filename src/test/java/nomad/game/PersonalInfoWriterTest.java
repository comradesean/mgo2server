package nomad.game;

import io.netty.buffer.Unpooled;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.model.EquippedSkills;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.*;

public class PersonalInfoWriterTest {
	private static Chara chara() {
		var chara = new Chara();
		chara.setId(42);
		chara.setName("Snake");
		chara.setComment("Kept you waiting, huh?");
		chara.setRank(7);
		return chara;
	}

	private static EquippedSkills skills() {
		var skills = new EquippedSkills();
		skills.setSkill1(1);
		skills.setSkill2(2);
		skills.setSkill3(3);
		skills.setSkill4(4);
		skills.setLevel1(5);
		skills.setLevel2(6);
		skills.setLevel3(7);
		skills.setLevel4(8);
		return skills;
	}

	private static io.netty.buffer.ByteBuf write() {
		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara(), new CharaAppearance(), skills());
		return buffer;
	}

	@Test
	public void payloadIsExactlySizedForTheClient() {
		assertThat(write().readableBytes()).isEqualTo(0xf5);
	}

	/** Clans are not modelled, so every character reports as unaffiliated. */
	@Test
	public void reportsNoClan() {
		var buffer = write();

		assertThat(buffer.getInt(0)).isZero();

		var name = new byte[16];
		buffer.getBytes(4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", "")).isEmpty();

		// Emblem flag is 3 only when a clan has one.
		assertThat(buffer.getByte(240)).isZero();
	}

	@Test
	public void writesEquippedSkillsAndLevels() {
		var buffer = write();

		assertThat(buffer.getByte(76)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(79)).isEqualTo((byte) 4);
		assertThat(buffer.getByte(81)).isEqualTo((byte) 5);
		assertThat(buffer.getByte(84)).isEqualTo((byte) 8);
	}

	@Test
	public void writesCommentAndRank() {
		var buffer = write();

		var comment = new byte[128];
		buffer.getBytes(111, comment);
		assertThat(new String(comment, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Kept you waiting, huh?");

		assertThat(buffer.getByte(239)).isEqualTo((byte) 7);
	}

	/** A character with no comment must still fill the fixed-width field. */
	@Test
	public void handlesNullComment() {
		var chara = chara();
		chara.setComment(null);

		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara, new CharaAppearance(), skills());

		assertThat(buffer.readableBytes()).isEqualTo(PersonalInfoWriter.PAYLOAD_SIZE);
	}

	@Test
	public void writesAppearanceIndices() {
		var appearance = new CharaAppearance();
		appearance.setGender(1);
		appearance.setFace(2);
		appearance.setAccessory2Color(9);

		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara(), appearance, skills());

		assertThat(buffer.getByte(49)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(50)).isEqualTo((byte) 2);
		assertThat(buffer.getByte(75)).isEqualTo((byte) 9);
	}
}
