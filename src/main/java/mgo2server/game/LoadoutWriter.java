package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.service.CharacterService;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.CharaSkill;
import mgo2server.common.model.GearSet;
import mgo2server.common.model.SkillSet;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * The four loadout responses of the connect burst.
 * <p>
 * All four are per-character. Gear (0x4124) and skills (0x4125) once were not — both were constant
 * catalogues advertising everything as owned — but skills gained a table in V20 and gear in V44,
 * and each writer now takes rows. Nothing is generated here.
 * <p>
 * That matters beyond tidiness. Gear is written by <em>two</em> packets: 0x4124 fills the client's
 * loadout table at login, and 0x4133 refills it after the outfit screen zeroes it. While the
 * catalogue was a constant, one writer used it and the other sent an empty table, so opening the
 * outfit screen erased every item the character owned. Both now read
 * {@link mgo2server.common.service.CharacterService#ownedGear}, which is what keeps them honest.
 * <p>
 * Skill sets (0x4140) and gear sets (0x4142) are the saved loadout slots, three of each.
 */
public final class LoadoutWriter {
	private static final int GEAR_TERMINATOR_LENGTH = 32;

	private static final int SET_NAME_LENGTH = 63;

	/** One skill record on the wire: u8 id, u16 experience, u8 flag. */
	public static final int SKILL_RECORD_SIZE = 4;

	public static final int SKILL_SET_SIZE = 0x4d;

	public static final int GEAR_SET_SIZE = 0x57;

	private LoadoutWriter() {
	}

	/** {@code 4 + 5*items + 32}. At the full catalogue of 123 this is the known-good 651. */
	public static int gearPayloadSize(int items) {
		return Integer.BYTES + items * 5 + GEAR_TERMINATOR_LENGTH;
	}



	/**
	 * The gear a character owns, as both {@code 0x4124} and {@code 0x4133} carry it.
	 * <p>
	 * Takes rows rather than generating a fixed catalogue, for the same reason
	 * {@link #writeSkills} does: an omitted item is not "owned with no colours", it is absent, and
	 * absence is the only way the wire can say "does not have this". The catalogue itself lives in
	 * {@code gear_item} as of V44 — including the duplicated {@code 0x86}, which is why this emits
	 * one record per row given to it and never deduplicates.
	 */
	public static void writeGear(ByteBuf buffer, List<CharacterService.OwnedGear> items) {
		writeGear(buffer, items, List.of());
	}

	/**
	 * The gear payload with the character's colour reward unlocks filled in.
	 *
	 * @param highlights up to {@link #HIGHLIGHT_SLOTS} unlocks; extras are ignored rather than truncating
	 *     the payload, because the slot count is fixed by the wire and not by us
	 */
	public static void writeGear(ByteBuf buffer, List<CharacterService.OwnedGear> items,
			List<CharacterService.GearColourHighlight> highlights) {
		buffer.writeInt(items.size());

		for (var item : items) {
			buffer.writeByte(item.itemId()).writeInt((int) item.colours());
		}

		// [ELF] Not a terminator, despite the name it carried: these 32 bytes are sixteen
		// {u8 item_id, u8 bit_index} colour-unlock pairs, read by both the 0x4124 parser and the
		// 0x4133 one into the same table. Sixteen, not fifteen — the bound at 0xD3C8D4 is tested
		// before the increment at 0xD3C8DC — and 4 + 615 + 32 = 651 only balances at sixteen.
		//
		// THESE GRANT NOTHING. Corrected 2026-07-30: [ELF 0xD3CFBC-0xD3CFE4] the parser ORs a pair
		// into record+16 ONLY IF that bit is already set in the colour mask at record+12, so a pair
		// can only ever produce a subset of what the record already carried. +16 is read at
		// 0x92740C and 0x927744 on a highlight path, not an availability one.
		//
		// Availability lives elsewhere and is genuinely server-controlled: item ownership is
		// record+8 (tested at 0x927350 — an item absent from this packet is never listed in the
		// wardrobe) and per-colour is record+12 (0x925538, 0x92772C).
		//
		// Database-driven since V67 so the slots are usable at all; V68 renamed the table once it
		// was clear they highlight rather than unlock. Every pair was 0xff before that, which is
		// skipped only because item id 255 exceeds the parser's 128-entry bound.
		//
		// Unused slots keep the 0xff filler, which is the part of the old behaviour that was
		// right: it is provably ignored. A character with no rows is byte-identical to before.
		//
		// Both packets must select the SAME sixteen or the client's table depends on which
		// arrived last, which is why the query orders by unlocked_at rather than returning
		// whatever the planner produces.
		for (var slot = 0; slot < HIGHLIGHT_SLOTS; slot++) {
			if (slot < highlights.size()) {
				buffer.writeByte(highlights.get(slot).itemId())
					.writeByte(highlights.get(slot).bitIndex());
			} else {
				buffer.writeByte(0xff).writeByte(0xff);
			}
		}
	}

	/** Sixteen {@code {item, bit}} pairs — a hard wire limit, not a policy choice. */
	public static final int HIGHLIGHT_SLOTS = GEAR_TERMINATOR_LENGTH / 2;

	/**
	 * The skill table, from what the character actually owns.
	 * <p>
	 * Ids the list omits are not "level 0" to the client — they are absent: its parser memsets the
	 * whole 128-entry array before applying these records, so an omitted id has no record at all.
	 * That is what makes ownership expressible, and it is why this takes rows rather than
	 * generating a fixed 1..25 the way it did before V20.
	 */
	public static void writeSkills(ByteBuf buffer, List<CharaSkill> skills) {
		buffer.writeInt(skills.size());

		for (var skill : skills) {
			buffer.writeByte(skill.getSkillId())
				.writeShort(skill.getExperience())
				.writeByte(skill.getFlag());
		}
	}

	/** Four bytes per record after the count word. */
	public static int skillsPayloadSize(int skills) {
		return Integer.BYTES + skills * SKILL_RECORD_SIZE;
	}

	public static void writeSkillSets(ByteBuf buffer, List<SkillSet> sets) {
		for (var set : sets) {
			buffer.writeInt(set.getModes())
				.writeByte(set.getSkill1()).writeByte(set.getSkill2())
				.writeByte(set.getSkill3()).writeByte(set.getSkill4())
				.writeZero(1)
				.writeByte(set.getLevel1()).writeByte(set.getLevel2())
				.writeByte(set.getLevel3()).writeByte(set.getLevel4())
				.writeZero(1);
			// Set names are UTF-8 here, unlike most strings in the protocol.
			BufferUtil.writeString(buffer, set.getName(), StandardCharsets.UTF_8, SET_NAME_LENGTH);
		}
	}

	public static void writeGearSets(ByteBuf buffer, List<GearSet> sets) {
		for (var set : sets) {
			buffer.writeInt(set.getStages())
				.writeByte(set.getFace()).writeByte(set.getHead()).writeByte(set.getUpper())
				.writeByte(set.getLower()).writeByte(set.getChest()).writeByte(set.getWaist())
				.writeByte(set.getHands()).writeByte(set.getFeet())
				.writeByte(set.getAccessory1()).writeByte(set.getAccessory2())
				.writeByte(set.getHeadColor()).writeByte(set.getUpperColor())
				.writeByte(set.getLowerColor()).writeByte(set.getChestColor())
				.writeByte(set.getWaistColor()).writeByte(set.getHandsColor())
				.writeByte(set.getFeetColor())
				.writeByte(set.getAccessory1Color()).writeByte(set.getAccessory2Color())
				.writeByte(set.getFacePaint());
			BufferUtil.writeString(buffer, set.getName(), StandardCharsets.UTF_8, SET_NAME_LENGTH);
		}
	}
}
