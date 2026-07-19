package nomad.common.model;

public class Chara {
	private long id;

	private long accountId;

	private String name;

	private int level;

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
