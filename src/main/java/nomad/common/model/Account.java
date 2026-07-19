package nomad.common.model;

public class Account {
	private long id;

	private String username;

	private String password;

	private int slots;

	private String session;

	private Long mainCharaId;

	private Long currentCharaId;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public String getUsername() {
		return username;
	}

	public void setUsername(String username) {
		this.username = username;
	}

	public String getPassword() {
		return password;
	}

	public void setPassword(String password) {
		this.password = password;
	}

	public int getSlots() {
		return slots;
	}

	public void setSlots(int slots) {
		this.slots = slots;
	}

	public String getSession() {
		return session;
	}

	public void setSession(String session) {
		this.session = session;
	}

	public Long getMainCharaId() {
		return mainCharaId;
	}

	public void setMainCharaId(Long mainCharaId) {
		this.mainCharaId = mainCharaId;
	}

	public Long getCurrentCharaId() {
		return currentCharaId;
	}

	public void setCurrentCharaId(Long currentCharaId) {
		this.currentCharaId = currentCharaId;
	}

	@Override
	public String toString() {
		return "Account{" +
			"id=" + id +
			", username='" + username + '\'' +
			", slots=" + slots +
			'}';
	}
}
