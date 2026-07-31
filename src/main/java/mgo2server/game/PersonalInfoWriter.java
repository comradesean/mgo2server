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
	 * The client's hard cap on skill experience, and its level-3 threshold — they are the same
	 * number.
	 *
	 * <p>[ELF] Level is {@code clamp(experience >> 13, 0, 3)}, computed by {@code 0x6FC580} with no
	 * table: 0 below 8192, then 8192 / 16384 / 24576 for levels 1, 2 and 3. The validator at
	 * {@code 0x93E418} zeroes any roster record whose experience exceeds {@code 24576}
	 * ({@code cmpwi cr7,r0,24576; ble+}), so this is a legal maximum and not merely a display
	 * ceiling.
	 *
	 * <p>This field used to send a fixed {@code 0x600000}, inherited and unexplained. That is
	 * <b>this same number shifted left eight bits</b> — {@code 0x6000 << 8} — i.e. 256x the client's
	 * own legal maximum. It has been harmless only by luck: the range check runs on the
	 * {@code 0x4129} roster, which we do not send, and {@code 0x600000 >> 13} clamps to 3 anyway.
	 * It would have become a real bug the moment the roster was implemented.
	 */
	public static final int MAX_SKILL_EXPERIENCE = 24576;

	/** [ELF] {@code 0x6FC580}: one level per 8192 experience, capped at 3. */
	private static final int EXPERIENCE_PER_LEVEL = 8192;

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
	 * The experience to report for an equipped skill: the character's real total, but never so low
	 * that it fails to support the level being reported in the same packet.
	 *
	 * <p><b>The floor is a guard, not a fudge, and it exists because the client deletes rather than
	 * corrects.</b> The loadout sanitiser at {@code 0x93E46C} walks the five equipped slots and, if
	 * a slot's level exceeds {@code experience >> 13}, clears the id, the level <em>and</em> the
	 * experience ({@code 0x93E51C stw r0,40(r9)}). So reporting an honest 0 against an equipped
	 * level 2 does not display "level 2 with no progress" — it makes the skill vanish from the
	 * character.
	 *
	 * <p>The floor exists because a character can have no {@code chara_skill} row for something it
	 * has equipped; without it, sending the raw stored value would silently strip that skill on the
	 * next login. It is a {@code max} rather than a replacement precisely so it can never lower a
	 * real total.
	 *
	 * <p><b>Progression now exists</b> ({@code 0x43a4}, 2026-07-29), so for any skill a player has
	 * actually used the stored value exceeds the floor on its own and this is inert. It stays for
	 * the rows that do not exist yet.
	 *
	 * <p>Shared with {@code 0x4131}, which echoed a fixed {@code 0x600000} until 2026-07-29 — both
	 * paths must report the same number or the skill screen disagrees with itself between the
	 * connect burst and a wardrobe change.
	 */
	public static int reportedExperience(int stored, int level) {
		var supportsLevel = Math.min(level, 3) * EXPERIENCE_PER_LEVEL;
		return Math.min(Math.max(Math.max(stored, 0), supportsLevel), MAX_SKILL_EXPERIENCE);
	}

	/**
	 * @param clan the character's clan record — id, name and membership state. {@link
	 *     ClanService.Membership#NONE} is the ordinary case and means state 99, id 0, empty name.
	 * @param skillExperience the character's stored experience for a given skill id, or 0 for one
	 *     they have no row for. See {@link #reportedExperience} for why the value sent is a floor
	 *     rather than the raw total.
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
			int savedInstructor, ClanService.Membership clan, boolean clanHasEmblem, int wornTitle,
			java.util.function.IntUnaryOperator skillExperience) {
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

		buffer.writeInt(reportedExperience(skillExperience.applyAsInt(skills.getSkill1()),
				skills.getLevel1()))
			.writeInt(reportedExperience(skillExperience.applyAsInt(skills.getSkill2()),
				skills.getLevel2()))
			.writeInt(reportedExperience(skillExperience.applyAsInt(skills.getSkill3()),
				skills.getLevel3()))
			.writeInt(reportedExperience(skillExperience.applyAsInt(skills.getSkill4()),
				skills.getLevel4()))
			.writeZero(5);

		// The original sends the character id here; its purpose is not documented.
		buffer.writeInt((int) chara.getId());

		BufferUtil.writeString(buffer, chara.getComment() == null ? "" : chara.getComment(),
			StandardCharsets.ISO_8859_1, COMMENT_LENGTH);

		// The WORN TITLE, 1-based, 0 for none — the animal-rank badge on the in-game scorecard, and
		// the same value 0x4103 wire 541 carries for the Personal Stats screen.
		//
		// This byte was `chara.getRank()` until 2026-07-28, and `chara.rank` is dead — always 0,
		// written by nothing — so the badge never appeared in a session while Personal Stats showed
		// it correctly. The two screens read different blocks: 0x4103 fills a scratch record, while
		// this fills the LOCAL character record at charBlock+0x1EA5, and only the local one is
		// published to peers.
		//
		// From there the client copies it into the P2P player-announce struct at +3 (0x8842A4) and
		// RecordSets it into its own per-slot blob (record slot+1, key 358, len 1, at 0x276374);
		// peers receive it at 0x2780E4. The scorecard's sprite reader 0x9BFA68 then resolves
		// title_32_01_alp..title_32_22_alp from it. Note the announce struct puts title, emblem flag
		// and clan id adjacent — which is why the badge sits immediately left of the emblem.
		//
		// Must stay within 1..22: the reader's match loop runs 21 iterations over a 22-entry table,
		// so 0 means "none" and anything larger falls through with no sprite drawn.
		buffer.writeByte(wornTitle);
		buffer.writeByte(clanHasEmblem ? EMBLEM_ON_DISPLAY : NO_EMBLEM);

		buffer.writeInt(savedInstructor);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Personal info payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
