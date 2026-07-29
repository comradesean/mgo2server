package mgo2server.common.model;

public class Chara {
	private long id;

	private long accountId;

	private String name;

	private int level;

	private boolean active = true;

	private String oldName;

	private java.time.OffsetDateTime createdAt;

	private String comment = "";

	private int rank;

	/**
	 * The character's experience, and the only thing any <em>level</em> on screen is derived from —
	 * see {@link mgo2server.common.Level}. Not {@link #rank}, which is dead.
	 * <p>
	 * Per character since V59. It was two pools on the account (main and alt), which meant a second
	 * alt shared the first one's level; the wire has always carried it per character, at
	 * {@code 0x4101} entry offset {@code 0x01c}.
	 * <p>
	 * The client owns this value: it reports an absolute total at the end of every round and we
	 * persist what it says, decreases included. A {@code u16} on the wire, so 65535 is the ceiling.
	 */
	private int experience;

	public long getId() {
		return id;
	}

	public int getExperience() {
		return experience;
	}

	public void setExperience(int experience) {
		this.experience = experience;
	}

	public void setId(long id) {
		this.id = id;
	}

	public long getAccountId() {
		return accountId;
	}

	public void setAccountId(long accountId) {
		this.accountId = accountId;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public int getLevel() {
		return level;
	}

	public void setLevel(int level) {
		this.level = level;
	}

	public boolean isActive() {
		return active;
	}

	public void setActive(boolean active) {
		this.active = active;
	}

	public String getOldName() {
		return oldName;
	}

	public void setOldName(String oldName) {
		this.oldName = oldName;
	}

	public String getComment() {
		return comment;
	}

	public void setComment(String comment) {
		this.comment = comment;
	}

	public int getRank() {
		return rank;
	}

	public void setRank(int rank) {
		this.rank = rank;
	}

	public java.time.OffsetDateTime getCreatedAt() {
		return createdAt;
	}

	public void setCreatedAt(java.time.OffsetDateTime createdAt) {
		this.createdAt = createdAt;
	}
	@Override
	public String toString() {
		return "Chara{" +
			"id=" + id +
			", accountId=" + accountId +
			", name='" + name + '\'' +
			", level=" + level +
			'}';
	}
}
