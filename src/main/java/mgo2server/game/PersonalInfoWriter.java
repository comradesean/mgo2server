package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.EquippedSkills;

import java.nio.charset.StandardCharsets;
import java.time.Instant;

/**
 * Writes the 0x4122 personal-info payload: who a character is, how they look, and what they have
 * equipped.
 * <p>
 * Clan membership occupies the first twenty bytes. Clans are not modelled yet, so those are
 * written as "no clan" — which is a real state every character starts in, not a placeholder.
 */
public final class PersonalInfoWriter {
	public static final int PAYLOAD_SIZE = 0xf5;

	private static final int CLAN_NAME_LENGTH = 16;

	private static final int COMMENT_LENGTH = 128;

	/**
	 * Experience toward each equipped skill. The original sends a fixed value rather than
	 * tracking it, so this does the same until skill progression exists.
	 */
	private static final int SKILL_EXPERIENCE = 0x600000;

	/** Undocumented fixed blocks, reproduced from the original byte for byte. */
	private static final byte[] PREFIX = {
		(byte) 0x01, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x0C, (byte) 0x00, (byte) 0x01, (byte) 0x00,
		(byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00,
		(byte) 0x01, (byte) 0x00, (byte) 0x01, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00,
		(byte) 0x01,
	};

	private static final byte[] SUFFIX = { (byte) 0x00, (byte) 0xA7, (byte) 0x00, (byte) 0x0D };

	private PersonalInfoWriter() {
	}

	public static void write(ByteBuf buffer, Chara chara, CharaAppearance a, EquippedSkills skills) {
		var start = buffer.writerIndex();

		// No clan: id zero and an empty name.
		buffer.writeInt(0);
		BufferUtil.writeString(buffer, "", StandardCharsets.ISO_8859_1, CLAN_NAME_LENGTH);

		buffer.writeBytes(PREFIX);
		buffer.writeInt((int) Instant.now().getEpochSecond());

		buffer.writeByte(a.getGender()).writeByte(a.getFace()).writeByte(a.getUpper())
			.writeByte(a.getLower()).writeByte(a.getFacePaint()).writeByte(a.getUpperColor())
			.writeByte(a.getLowerColor()).writeByte(a.getVoice()).writeByte(a.getPitch())
			.writeZero(4)
			.writeByte(a.getHead()).writeByte(a.getChest()).writeByte(a.getHands())
			.writeByte(a.getWaist()).writeByte(a.getFeet()).writeByte(a.getAccessory1())
			.writeByte(a.getAccessory2()).writeByte(a.getHeadColor()).writeByte(a.getChestColor())
			.writeByte(a.getHandsColor()).writeByte(a.getWaistColor()).writeByte(a.getFeetColor())
			.writeByte(a.getAccessory1Color()).writeByte(a.getAccessory2Color());

		buffer.writeByte(skills.getSkill1()).writeByte(skills.getSkill2())
			.writeByte(skills.getSkill3()).writeByte(skills.getSkill4())
			.writeZero(1)
			.writeByte(skills.getLevel1()).writeByte(skills.getLevel2())
			.writeByte(skills.getLevel3()).writeByte(skills.getLevel4())
			.writeZero(1);

		buffer.writeInt(SKILL_EXPERIENCE).writeInt(SKILL_EXPERIENCE)
			.writeInt(SKILL_EXPERIENCE).writeInt(SKILL_EXPERIENCE)
			.writeZero(5);

		// The original sends the character id here; its purpose is not documented.
		buffer.writeInt((int) chara.getId());

		BufferUtil.writeString(buffer, chara.getComment() == null ? "" : chara.getComment(),
			StandardCharsets.ISO_8859_1, COMMENT_LENGTH);

		buffer.writeByte(chara.getRank());
		// Emblem flag: 3 when the character's clan has one. No clans yet, so never.
		buffer.writeByte(0);

		buffer.writeBytes(SUFFIX);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Personal info payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
