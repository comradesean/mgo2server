package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.CharaSkill;
import mgo2server.common.service.CharacterService;
import mgo2server.common.model.GearSet;
import mgo2server.common.model.SkillSet;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

public class LoadoutWriterTest {
	private static List<CharacterService.OwnedGear> gear(int... ids) {
		return java.util.Arrays.stream(ids)
			.mapToObj(id -> new CharacterService.OwnedGear(id, 0xffffffffL))
			.toList();
	}

	@Test
	public void gearPayloadIsCountThenItemsThenTerminator() {
		var items = gear(0x04, 0x0B, 0x0C);
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize(items.size()));
		LoadoutWriter.writeGear(buffer, items);

		assertThat(buffer.readableBytes()).isEqualTo(LoadoutWriter.gearPayloadSize(items.size()));
		assertThat(buffer.getInt(0)).isEqualTo(items.size());
		// count, then five bytes per item, then the 32-byte trailer.
		assertThat(LoadoutWriter.gearPayloadSize(items.size())).isEqualTo(4 + items.size() * 5 + 32);
	}

	/** The colour mask is per item and comes from the row, not from a constant. */
	@Test
	public void gearWritesThePerItemColourMask() {
		var items = List.of(new CharacterService.OwnedGear(0x04, 0xffffffffL),
			new CharacterService.OwnedGear(0x0B, 0x00000003L));
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize(items.size()));
		LoadoutWriter.writeGear(buffer, items);

		assertThat(buffer.getByte(4)).isEqualTo((byte) 0x04);
		assertThat(buffer.getInt(5)).isEqualTo(0xffffffff);
		assertThat(buffer.getByte(9)).isEqualTo((byte) 0x0B);
		assertThat(buffer.getInt(10)).isEqualTo(3);
	}

	/**
	 * A duplicated item id is emitted twice, not collapsed. The catalogue holds 0x86 twice, and
	 * dropping one would take 0x4124 from its known-good 651 bytes to 646.
	 */
	@Test
	public void gearDoesNotDeduplicate() {
		var items = gear(0x85, 0x86, 0x86, 0x87);
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize(items.size()));
		LoadoutWriter.writeGear(buffer, items);

		assertThat(buffer.getInt(0)).isEqualTo(4);
		assertThat(buffer.getByte(9)).isEqualTo((byte) 0x86);
		assertThat(buffer.getByte(14)).isEqualTo((byte) 0x86);
	}

	/** A character that owns nothing sends a count of zero, not a full catalogue. */
	@Test
	public void gearCanBeEmpty() {
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize(0));
		LoadoutWriter.writeGear(buffer, List.of());

		assertThat(buffer.readableBytes()).isEqualTo(36);
		assertThat(buffer.getInt(0)).isZero();
	}

	@Test
	public void gearTerminatorIsAllBitsSet() {
		var items = gear(0x04);
		var size = LoadoutWriter.gearPayloadSize(items.size());
		var buffer = Unpooled.buffer(size);
		LoadoutWriter.writeGear(buffer, items);

		for (var i = size - 32; i < size; i++) {
			assertThat(buffer.getByte(i)).as("trailer byte %d", i).isEqualTo((byte) 0xff);
		}
	}

	/**
	 * The table is whatever the character owns — the writer no longer generates ids. Omitting an id
	 * is meaningful: the client memsets its array before applying records, so an absent id has no
	 * record rather than a zeroed one.
	 */
	@Test
	public void skillsPayloadCarriesExactlyTheRowsGiven() {
		var skills = List.of(skill(1, 0x6000, 0), skill(17, 0x2000, 1));

		var buffer = Unpooled.buffer(LoadoutWriter.skillsPayloadSize(skills.size()));
		LoadoutWriter.writeSkills(buffer, skills);

		assertThat(buffer.readableBytes()).isEqualTo(LoadoutWriter.skillsPayloadSize(2));
		assertThat(buffer.getInt(0)).isEqualTo(2);

		assertThat(buffer.getByte(4)).isEqualTo((byte) 1);
		assertThat(buffer.getShort(5)).isEqualTo((short) 0x6000);
		assertThat(buffer.getByte(7)).isEqualTo((byte) 0);

		assertThat(buffer.getByte(8)).isEqualTo((byte) 17);
		assertThat(buffer.getShort(9)).isEqualTo((short) 0x2000);
		assertThat(buffer.getByte(11)).as("flag is sent, not forced to zero").isEqualTo((byte) 1);
	}

	@Test
	public void skillsPayloadIsEmptyWhenNothingIsOwned() {
		var buffer = Unpooled.buffer(LoadoutWriter.skillsPayloadSize(0));
		LoadoutWriter.writeSkills(buffer, List.of());

		assertThat(buffer.readableBytes()).isEqualTo(Integer.BYTES);
		assertThat(buffer.getInt(0)).isEqualTo(0);
	}

	private static CharaSkill skill(int id, int experience, int flag) {
		var skill = new CharaSkill();
		skill.setSkillId(id);
		skill.setExperience(experience);
		skill.setFlag(flag);
		return skill;
	}

	@Test
	public void skillSetsAreFixedWidth() {
		var sets = List.of(new SkillSet(), new SkillSet(), new SkillSet());

		var buffer = Unpooled.buffer(sets.size() * LoadoutWriter.SKILL_SET_SIZE);
		LoadoutWriter.writeSkillSets(buffer, sets);

		assertThat(buffer.readableBytes()).isEqualTo(3 * 0x4d);
	}

	@Test
	public void gearSetsAreFixedWidth() {
		var sets = List.of(new GearSet(), new GearSet(), new GearSet());

		var buffer = Unpooled.buffer(sets.size() * LoadoutWriter.GEAR_SET_SIZE);
		LoadoutWriter.writeGearSets(buffer, sets);

		assertThat(buffer.readableBytes()).isEqualTo(3 * 0x57);
	}

	@Test
	public void skillSetCarriesItsValuesAndName() {
		var set = new SkillSet();
		set.setModes(5);
		set.setSkill1(1);
		set.setLevel1(2);
		set.setName("Assault");

		var buffer = Unpooled.buffer(LoadoutWriter.SKILL_SET_SIZE);
		LoadoutWriter.writeSkillSets(buffer, List.of(set));

		assertThat(buffer.getInt(0)).isEqualTo(5);
		assertThat(buffer.getByte(4)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(9)).isEqualTo((byte) 2);

		var name = new byte[63];
		buffer.getBytes(14, name);
		assertThat(new String(name, StandardCharsets.UTF_8).replace("\0", "")).isEqualTo("Assault");
	}

	/** Set names are UTF-8, so a multi-byte name must not be cut mid-character. */
	@Test
	public void setNameTruncatesOnACharacterBoundary() {
		var set = new SkillSet();
		// Each character is three bytes; 63 bytes holds exactly 21 of them.
		set.setName("あ".repeat(30));

		var buffer = Unpooled.buffer(LoadoutWriter.SKILL_SET_SIZE);
		LoadoutWriter.writeSkillSets(buffer, List.of(set));

		var name = new byte[63];
		buffer.getBytes(14, name);
		var decoded = new String(name, StandardCharsets.UTF_8).replace("\0", "");

		assertThat(decoded).isEqualTo("あ".repeat(21));
		assertThat(decoded).doesNotContain("�");
	}


	/**
	 * The level a skill renders at is {@code min(exp >> 13, 3)} client-side ({@code 0x6FC580}), so
	 * the experience values seeded by V20 are chosen for what they decode to, not as magnitudes.
	 */
	@Test
	public void seededExperienceValuesDecodeToTheIntendedLevels() {
		assertThat(0x6000 >> 13).isEqualTo(3);
		assertThat(0x2000 >> 13).isEqualTo(1);
		assertThat(0 >> 13).isEqualTo(0);
	}

}
