package nomad.common.model;

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

	public long getId() {
		return id;
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
