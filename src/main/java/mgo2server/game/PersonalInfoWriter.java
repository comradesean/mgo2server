package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.EquippedSkills;
import mgo2server.common.service.ClanService;

import java.nio.charset.StandardCharsets;
import java.time.Instant;

/**
 * Writes the 0x4122 personal-info payload: who a character is, how they look, and what they have
 * equipped.
 * <p>
 * Clan membership occupies the first twenty bytes, and carries the character's real clan — id,
 * name and state — so a clan survives a login. A character in none sends state 99, which is a real
 * state the client understands rather than a placeholder.
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
	 * writes for no clan, and it is now sent only when that is true: the state travels with the
	 * character's real membership, so a clan survives a login.
	 */
	public static final int CLAN_STATE_NONE = ClanService.STATE_NONE;

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

	/**
	 * Wire {@code 0xf0} -> {@code profile+6872}: the byte that says this character's clan has an
	 * emblem worth downloading.
	 *
	 * <p>[CONFIRMED] The value is <b>3</b> and it is the client's own constant, not an inherited
	 * guess. The emblem-upload commit path writes it itself — {@code 0xAD4724}
	 * ({@code stb r29,56(r11)} where {@code r11 = profile+6816}) — immediately before
	 * {@code memcpy}ing the 768-byte bitmap to {@code profile+6873}, so the flag physically
	 * precedes the image it describes. Only upload mode 3 reaches that store; modes 2 and 4 leave
	 * the byte alone.
	 *
	 * <p>It is <b>not</b> a boolean and not a bitfield. Every reader is an exact equality —
	 * {@code cmpwi cr7,r0,3} at {@code 0x8F9954} and {@code 0x905A94}, with no mask test and no
	 * comparison against 1 or 2 anywhere. So 1 and 2 behave exactly like 0.
	 *
	 * <p>What it gates is a <b>network fetch</b>, not merely rendering: at {@code 0x8F9914} the
	 * lobby-entry state machine advances only when the clan id is nonzero, membership is 1 or 2,
	 * and (privilege bit 0 is set <em>or</em> this byte is 3), then sends {@code 0x4b48} and blocks
	 * on {@code 0x4b49} for 6000 ticks. The clan-info screen does the same with {@code 0x4b4a} at
	 * {@code 0x905A7C}.
	 *
	 * <p>This was hardcoded to 0 with the note "emblems are not modelled, so never". They are
	 * modelled now, and 0 was not conservative — it meant a character in a clan with an emblem
	 * never fetched it at login and the clan-info screen silently skipped the fetch.
	 */
	public static final int EMBLEM_ON_DISPLAY = 3;

	private static final int NO_EMBLEM = 0;

	private PersonalInfoWriter() {
	}

	/**
	 * @param clan the character's clan record — id, name and membership state. {@link
	 *     ClanService.Membership#NONE} is the ordinary case and means state 99, id 0, empty name.
	 * @param clanHasEmblem whether that clan has an emblem on display. See {@link
	 *     #EMBLEM_ON_DISPLAY}: true makes the client fetch it with {@code 0x4b48} during connect
	 *     and block on the reply, so this must not be set for a clan we cannot serve an emblem for.
	 * @param savedInstructor the character id of the instructor this character has permanently
	 *     saved, or {@link #NO_SAVED_INSTRUCTOR} when they have none. Nonzero suppresses the
	 *     recognition prompt for them from that point on, which is what "cannot be erased once
	 *     saved" means from the server's side.
	 *     <p>
	 *     [CONFIRMED 2026-07-27] The field holds the instructor's <b>character id</b>, in our own id
	 *     namespace. Proven in a live team deathmatch: a student who had saved instructor id 1 saw
	 *     the instructor badge rendered next to <em>that</em> player's name and no one else's, so the
	 *     receiving client resolves the announced value against the players in the match. The route
	 *     is {@code profile+0x32F8} -> join announcement ({@code 0x8842AC}) -> P2P message 36, which
	 *     is why the badge appears in ordinary games and not only in training.
	 *     <p>
	 *     That also explains the captured {@code 0x00A7000D}: a retail character id, belonging to
	 *     whoever's session was recorded.
	 */
	public static void write(ByteBuf buffer, Chara chara, CharaAppearance a, EquippedSkills skills,
			int savedInstructor, ClanService.Membership clan, boolean clanHasEmblem) {
		var start = buffer.writerIndex();

		buffer.writeInt((int) clan.id());
		BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1, CLAN_NAME_LENGTH);

		// State, then the privilege/notification word and its eleven unread siblings. The word stays
		// zero — see ClanGameController.LEADER_PRIVILEGES for both experiments that proved it must.
		buffer.writeByte(clan.state()).writeZero(CLAN_BLOCK_BYTES);
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
		buffer.writeByte(clanHasEmblem ? EMBLEM_ON_DISPLAY : NO_EMBLEM);

		buffer.writeInt(savedInstructor);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Personal info payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
