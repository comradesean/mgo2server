package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.GearSet;
import mgo2server.common.model.SkillSet;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The four loadout responses of the connect burst.
 * <p>
 * Gear (0x4124) and skills (0x4125) are catalogues rather than per-character state: the original
 * advertises every item and skill as owned, with no persistence behind either. That is reproduced
 * here — progression does not exist yet, and inventing a partial one would be worse than granting
 * everything, which is at least a state the client renders coherently.
 * <p>
 * Skill sets (0x4140) and gear sets (0x4142) <em>are</em> per-character, three of each.
 */
public final class LoadoutWriter {
	/** Item ids the original advertises. Their meaning lives in the game's own tables. */
	private static final int[] GEAR_ITEMS = {
		0x04, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x16, 0x1C, 0x1D,
		0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2E, 0x2F,
		0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x44, 0x45,
		0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x56, 0x57,
		0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x61, 0x62, 0x63, 0x64, 0x66, 0x67, 0x68,
		0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x80,
		0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
		0xA0, 0xA1, 0xA2, 0xB0, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4,
	};

	/** All colour variants unlocked. */
	private static final int ALL_COLOURS = 0xffffffff;

	private static final int GEAR_TERMINATOR_LENGTH = 32;

	public static final int SKILL_COUNT = 25;

	/**
	 * Most skills are advertised at this experience; a few sit lower.
	 * <p>
	 * These are not arbitrary magnitudes: the client derives a skill's <b>level</b> from this word
	 * as {@code min(exp >> 13, 3)} — literally the top three bits — at {@code 0x6FC580}, reading a
	 * u16 out of the record the {@code 0x4129} parser wrote ({@code 0x6FCE70}). So
	 * {@code 0x6000} advertises <b>level 3</b> and {@code 0x2000} advertises <b>level 1</b>, and
	 * the only reachable levels are 0, 1, 2 and 3 at 0 / 8192 / 16384 / 24576. In-match code gates
	 * on the result: {@code 0x6FCE90}'s caller compares the level against a per-entry requirement
	 * byte. A finer EXP-to-level ladder exists at {@code 0x6FCBF8} (thresholds 0, 1, 16, 23, 31,
	 * 35, 38, 45, 47, 51, 63, 70, 73 for levels 1–13) and is used elsewhere.
	 */
	private static final int SKILL_EXPERIENCE = 0x6000;

	private static final int SKILL_EXPERIENCE_LOW = 0x2000;

	/**
	 * Skills advertised at the lower value, i.e. handed out at level 1 rather than level 3.
	 * <p>
	 * Inherited from a reference server, which makes it tier 4 — no capture or ELF reading says the
	 * original did this, and nothing here explains why these three. Worth suspicion: <b>17 is the
	 * skill the training/graduation checks read</b> ({@code 0x8972F4} tests its record, and the
	 * in-match instructor code reads a skill level through {@code 0x6FC580}), so if a level
	 * requirement is what gates graduation, this list is what fails it. Override with
	 * {@code MGO2SERVER_SKILL_EXP=17:24576} to test that without a rebuild.
	 */
	private static final int[] LOW_EXPERIENCE_SKILLS = { 17, 20, 22 };

	/**
	 * Per-skill experience overrides, {@code skill:exp} pairs separated by commas, e.g.
	 * {@code MGO2SERVER_SKILL_EXP=17:24576,20:24576}. Malformed entries are ignored individually
	 * rather than discarding the whole setting, so a typo costs one skill and not the catalogue.
	 */
	private static final Map<Integer, Integer> SKILL_EXPERIENCE_OVERRIDES =
		parseSkillExperience(System.getenv("MGO2SERVER_SKILL_EXP"));

	static Map<Integer, Integer> parseSkillExperience(String configured) {
		var overrides = new HashMap<Integer, Integer>();
		if (configured == null || configured.isBlank()) {
			return overrides;
		}

		for (var pair : configured.split(",")) {
			var fields = pair.split(":");
			if (fields.length != 2) {
				continue;
			}
			try {
				overrides.put(Integer.parseInt(fields[0].trim()), Integer.parseInt(fields[1].trim()));
			}
			catch (NumberFormatException malformed) {
				// Ignored on purpose; see the field comment.
			}
		}

		return overrides;
	}

	private static final int SET_NAME_LENGTH = 63;

	public static final int SKILL_SET_SIZE = 0x4d;

	public static final int GEAR_SET_SIZE = 0x57;

	private LoadoutWriter() {
	}

	public static int gearPayloadSize() {
		return Integer.BYTES + GEAR_ITEMS.length * 5 + GEAR_TERMINATOR_LENGTH;
	}

	public static int skillsPayloadSize() {
		return Integer.BYTES + SKILL_COUNT * 4;
	}

	/** Every gear item, in every colour. */
	public static void writeGear(ByteBuf buffer) {
		buffer.writeInt(GEAR_ITEMS.length);

		for (var item : GEAR_ITEMS) {
			buffer.writeByte(item).writeInt(ALL_COLOURS);
		}

		// Terminator is all bits set, like the colour masks.
		for (var i = 0; i < GEAR_TERMINATOR_LENGTH; i++) {
			buffer.writeByte(0xff);
		}
	}

	/**
	 * The experience the catalogue advertises for a skill — also what the post-game results card
	 * ({@code 0x4129}) repeats, so the two screens agree while skill progression does not exist.
	 */
	public static int advertisedSkillExperience(int skill) {
		var override = SKILL_EXPERIENCE_OVERRIDES.get(skill);
		if (override != null) {
			return override;
		}
		return isLowExperience(skill) ? SKILL_EXPERIENCE_LOW : SKILL_EXPERIENCE;
	}

	private static boolean isLowExperience(int skill) {
		for (var low : LOW_EXPERIENCE_SKILLS) {
			if (low == skill) {
				return true;
			}
		}
		return false;
	}

	/** Every skill, at the experience the original advertises. */
	public static void writeSkills(ByteBuf buffer) {
		buffer.writeInt(SKILL_COUNT);

		for (var skill = 1; skill <= SKILL_COUNT; skill++) {
			buffer.writeByte(skill)
				.writeShort(isLowExperience(skill) ? SKILL_EXPERIENCE_LOW : SKILL_EXPERIENCE)
				.writeZero(1);
		}
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
