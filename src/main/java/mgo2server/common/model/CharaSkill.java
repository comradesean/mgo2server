package mgo2server.common.model;

/**
 * One skill a character owns, as {@code 0x4125} advertises it and {@code 0x4129} repeats it.
 * <p>
 * A row exists only for a skill the character has: the client memsets its whole 128-entry array
 * before applying what we send, so an id we omit reads back as level 0 with a clear flag. That is
 * the mechanism any future locking hangs off — see {@code dev/proto/outbound/mgo2_cmd_4125_s2c.ksy}.
 */
public class CharaSkill {
	/** Ids the client defines. Beyond this every id-keyed lookup in the client clamps to 17. */
	public static final int MAX_ID = 17;

	/**
	 * The highest id granted at character creation. 17 is withheld deliberately: it is the record
	 * the training screen reads, and a character that has it skips the training parameter fetch
	 * entirely. Withholding it is what leaves room for it to be earned.
	 */
	public static final int STARTING_MAX_ID = 16;

	/**
	 * The lowest experience the client will display. Its skill-list builder rejects any record
	 * with {@code experience <= 8191} outright ({@code 0x8DD5F0}), so a skill below this is
	 * indistinguishable from one we never sent — confirmed live 2026-07-26 with 1 and 8191 both
	 * invisible and 8192 visible. Level is {@code min(experience >> 13, 3)}, making this level 1.
	 */
	public static final int MINIMUM_VISIBLE_EXPERIENCE = 8192;

	private long charaId;

	private int skillId;

	/**
	 * Experience, a u16 on the wire. The client shows a level of {@code min(experience >> 13, 3)},
	 * so only 0, 8192, 16384 and 24576 change what it renders.
	 */
	private int experience;

	/**
	 * The third wire byte. Read in exactly one place in the client — skill 17's, where a present
	 * record with a zero flag enables the training menu entry — and sent as 0 everywhere so far.
	 */
	private int flag;

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getSkillId() {
		return skillId;
	}

	public void setSkillId(int skillId) {
		this.skillId = skillId;
	}

	public int getExperience() {
		return experience;
	}

	public void setExperience(int experience) {
		this.experience = experience;
	}

	public int getFlag() {
		return flag;
	}

	public void setFlag(int flag) {
		this.flag = flag;
	}
}
