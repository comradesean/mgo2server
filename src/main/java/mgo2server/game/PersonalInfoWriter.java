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

	/**
	 * Clan membership state, wire {@code 0x14} -> {@code profile+6837}. Not an unknown: the client
	 * writes this byte itself, and the constants are readable straight out of its handlers —
	 * {@code 0} affiliation pending ({@code 0xD58740}), {@code 1} member ({@code 0xD56B68}),
	 * {@code 2} leader ({@code 0xD56B84}), {@code 99} not in a clan ({@code 0xD56B44},
	 * {@code 0xD56C7C}, {@code 0xD56D68} — each `li r0,99; stb r0,6837`, and each zeroes the clan
	 * id alongside). Every reader tests membership as {@code state - 1 <= 1}, i.e. 1 or 2.
	 *
	 * <p>We had been sending {@code 01} — "this character is in a clan" — alongside a clan id of 0.
	 * Inert only because nearly every reader checks the id first. 99 is what the client itself
	 * writes for no clan, so it is the honest value.
	 */
	public static final int CLAN_STATE_NONE = 0x63;

	/**
	 * Wire {@code 0x15}: twelve u16s at {@code profile+6838}. Element 0 is the clan privilege mask
	 * (bit 0 tested at {@code 0x8F9944}, bit 8 at {@code 0xAB3480}, whole value OR'd into a UI flags
	 * word at {@code 0xAB0118} and passed as a mask to {@code 0xCFD0A0}). Elements 1-11 have no
	 * reader anywhere in the binary.
	 *
	 * <p>Zero throughout: no clan, so no privileges. What was here before — {@code 0x000C} and a
	 * scattering of {@code 0x0001} — was one captured character's clan record, transcribed as if it
	 * were a constant. Same mistake as the saved-instructor field below, in the same packet.
	 */
	private static final int CLAN_BLOCK_BYTES = 24;

	/**
	 * The last field of the payload: the character's <b>saved instructor</b> marker. Zero means
	 * "no instructor saved", which is what every character here has, since nothing yet writes one.
	 *
	 * <p>This was a fixed {@code 00 A7 00 0D} copied from another server byte for byte, and it cost
	 * a day. The client's parser reads it at {@code 0xD3D624} ({@code addi r4,r25,13048}, then the
	 * u32 reader {@code 0xD5CCD8}) straight into {@code profile+0x32F8} — <b>unguarded</b>, unlike
	 * the {@code 0x43c9} path, which stores only a nonzero value. From there the join-announcement
	 * packer at {@code 0x8842AC} puts it in the announcement, P2P message 36 carries it to peers,
	 * it lands in {@code G+0x1C0} (sole writer {@code 0x9D17C8}, sole reader {@code 0x9CD5D0}), and
	 * {@code 0xA359A4} skips the "Save current instructor, %s, as the instructor for your personal
	 * data?" prompt (stage {@code n002a} string 3099) whenever it is nonzero.
	 *
	 * <p>So every character we served announced "I already have an instructor" to every peer, and
	 * no student was ever offered the prompt — leaving only "Choose a rating" (string 3105).
	 *
	 * <p>Whatever {@code 0x00A7000D} meant, it was one captured character's saved instructor, not a
	 * constant.
	 */
	public static final int NO_SAVED_INSTRUCTOR = 0;

	private PersonalInfoWriter() {
	}

	/**
	 * @param savedInstructor the character id of the instructor this character has permanently
	 *     saved, or {@link #NO_SAVED_INSTRUCTOR} when they have none. Nonzero suppresses the
	 *     recognition prompt for them from that point on, which is what "cannot be erased once
	 *     saved" means from the server's side.
	 *     <p>
	 *     [INFERRED] That the field holds the instructor's <em>character id</em> is the working
	 *     hypothesis, not a proven encoding. What is proven: the value is stored verbatim at
	 *     {@code profile+0x32F8}, copied into the join announcement by {@code 0x8842AC}, and sent to
	 *     every peer as P2P message 36 — a peer-visible identity, which is what an "instructor" tag
	 *     on another player would need. The one captured value, {@code 0x00A7000D}, is consistent
	 *     with an id and inconsistent with a flag. If the tag renders wrongly, this is the line to
	 *     change; the field is otherwise inert to us.
	 */
	public static void write(ByteBuf buffer, Chara chara, CharaAppearance a, EquippedSkills skills,
			int savedInstructor) {
		var start = buffer.writerIndex();

		// No clan: id zero and an empty name.
		buffer.writeInt(0);
		BufferUtil.writeString(buffer, "", StandardCharsets.ISO_8859_1, CLAN_NAME_LENGTH);

		buffer.writeByte(CLAN_STATE_NONE).writeZero(CLAN_BLOCK_BYTES);
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

		buffer.writeInt(savedInstructor);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Personal info payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
