package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.EquippedSkills;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.*;

public class PersonalInfoWriterTest {

	/**
	 * No worn title. The byte at wire {@code 0xef} is the animal-rank index the in-game scorecard
	 * draws, 1-based, with 0 meaning none — these tests pin the layout, not the value.
	 */
	private static final int NO_TITLE = 0;

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
		PersonalInfoWriter.write(buffer, chara(), new CharaAppearance(), skills(), PersonalInfoWriter.NO_SAVED_INSTRUCTOR,
			mgo2server.common.service.ClanService.Membership.NONE, false, NO_TITLE, skill -> 0);
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
	public void writesCommentAndWornTitle() {
		var buffer = write();

		var comment = new byte[128];
		buffer.getBytes(111, comment);
		assertThat(new String(comment, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Kept you waiting, huh?");

		// Byte 239 is wire 0xef. It carried chara.rank until 2026-07-28, which was dead — always 0,
		// written by nothing — so the in-game scorecard's animal-rank badge never appeared while
		// Personal Stats showed the title correctly. The two read different blocks: 0x4103 fills a
		// scratch record, this fills the LOCAL character record at charBlock+0x1EA5, and only the
		// local one is published to peers as record slot+1 key 358.
		//
		// 1-based, 0 for none, and the client's sprite table has 22 entries — see PersonalInfoWriter.
		assertThat(buffer.getByte(239)).as("wire 0xef, the worn title").isEqualTo((byte) 0);

		var withTitle = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(withTitle, chara(), new CharaAppearance(), skills(),
			PersonalInfoWriter.NO_SAVED_INSTRUCTOR,
			mgo2server.common.service.ClanService.Membership.NONE, false, 7, skill -> 0);
		assertThat(withTitle.getByte(239)).as("a worn title reaches the wire").isEqualTo((byte) 7);
	}

	/** A character with no comment must still fill the fixed-width field. */
	@Test
	public void handlesNullComment() {
		var chara = chara();
		chara.setComment(null);

		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara, new CharaAppearance(), skills(), PersonalInfoWriter.NO_SAVED_INSTRUCTOR,
			mgo2server.common.service.ClanService.Membership.NONE, false, NO_TITLE, skill -> 0);

		assertThat(buffer.readableBytes()).isEqualTo(PersonalInfoWriter.PAYLOAD_SIZE);
	}

	@Test
	public void writesAppearanceIndices() {
		var appearance = new CharaAppearance();
		appearance.setGender(1);
		appearance.setFace(2);
		appearance.setAccessory2Color(9);

		var buffer = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara(), appearance, skills(), PersonalInfoWriter.NO_SAVED_INSTRUCTOR,
			mgo2server.common.service.ClanService.Membership.NONE, false, NO_TITLE, skill -> 0);

		assertThat(buffer.getByte(49)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(50)).isEqualTo((byte) 2);
		assertThat(buffer.getByte(75)).isEqualTo((byte) 9);
	}

	/**
	 * The emblem flag at wire 0xf0. [ELF] 3 is the client's own constant, stored to
	 * {@code profile+6872} by the upload path at {@code 0xAD4724} and tested by exact equality at
	 * {@code 0x8F9954} and {@code 0x905A94} — so any non-3 value reads as "no emblem", and 0 is the
	 * one the client itself writes on the -1214 path.
	 */
	@Test
	public void announcesTheClanEmblemOnlyWhenThereIsOne() {
		var withEmblem = Unpooled.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(withEmblem, chara(), new CharaAppearance(), skills(),
			PersonalInfoWriter.NO_SAVED_INSTRUCTOR,
			mgo2server.common.service.ClanService.Membership.NONE, true, NO_TITLE, skill -> 0);

		assertThat(withEmblem.getByte(0xf0)).isEqualTo((byte) PersonalInfoWriter.EMBLEM_ON_DISPLAY);
		assertThat(write().getByte(0xf0)).isEqualTo((byte) 0);
	}
}
