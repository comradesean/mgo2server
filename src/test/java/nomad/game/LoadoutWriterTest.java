package nomad.game;

import io.netty.buffer.Unpooled;
import nomad.common.model.GearSet;
import nomad.common.model.SkillSet;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

public class LoadoutWriterTest {
	@Test
	public void gearPayloadIsCountThenItemsThenTerminator() {
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize());
		LoadoutWriter.writeGear(buffer);

		assertThat(buffer.readableBytes()).isEqualTo(LoadoutWriter.gearPayloadSize());

		var count = buffer.getInt(0);
		assertThat(count).isPositive();
		// count, then five bytes per item, then a 32-byte terminator.
		assertThat(LoadoutWriter.gearPayloadSize()).isEqualTo(4 + count * 5 + 32);
	}

	/** Every colour variant is advertised as unlocked. */
	@Test
	public void gearAdvertisesAllColours() {
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize());
		LoadoutWriter.writeGear(buffer);

		assertThat(buffer.getInt(5)).isEqualTo(0xffffffff);
	}

	@Test
	public void gearTerminatorIsAllBitsSet() {
		var buffer = Unpooled.buffer(LoadoutWriter.gearPayloadSize());
		LoadoutWriter.writeGear(buffer);

		for (var i = LoadoutWriter.gearPayloadSize() - 32; i < LoadoutWriter.gearPayloadSize(); i++) {
			assertThat(buffer.getByte(i)).as("terminator byte %d", i).isEqualTo((byte) 0xff);
		}
	}

	@Test
	public void skillsPayloadListsEverySkill() {
		var buffer = Unpooled.buffer(LoadoutWriter.skillsPayloadSize());
		LoadoutWriter.writeSkills(buffer);

		assertThat(buffer.readableBytes()).isEqualTo(LoadoutWriter.skillsPayloadSize());
		assertThat(buffer.getInt(0)).isEqualTo(LoadoutWriter.SKILL_COUNT);

		// Ids run 1..25, four bytes each.
		assertThat(buffer.getByte(4)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(4 + 24 * 4)).isEqualTo((byte) 25);
	}

	/** Three skills are advertised at a lower experience than the rest. */
	@Test
	public void skillsUseTheLowerExperienceForTheExceptions() {
		var buffer = Unpooled.buffer(LoadoutWriter.skillsPayloadSize());
		LoadoutWriter.writeSkills(buffer);

		for (var skill = 1; skill <= LoadoutWriter.SKILL_COUNT; skill++) {
			var offset = 4 + (skill - 1) * 4;
			var expected = (skill == 17 || skill == 20 || skill == 22) ? 0x2000 : 0x6000;
			assertThat(buffer.getShort(offset + 1)).as("skill %d", skill).isEqualTo((short) expected);
		}
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
}
