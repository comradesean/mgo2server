package mgo2server.common.model;

public class Account {
	private long id;

	private String username;

	private String password;

	private int slots;

	private String session;

	private Long mainCharaId;

	private Long currentCharaId;

	private int mainExp;

	private int altExp;

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

	/**
	 * How many character slots this account may fill. Sent in {@code 0x3049}'s header, where the
	 * client uses it as the number of rows on the character-selection screen.
	 * <p>
	 * <b>Operator policy, one to four.</b> One by default: retail sold the rest, and the screen still
	 * offers "Use your Metal Gear Points to buy an additional character registration slot". Four is
	 * the retail maximum, enforced as a database constraint because the packet does not enforce it —
	 * {@code 0x3049} has room for eight entries and would carry a larger value without complaint.
	 * <p>
	 * Grant more per account with {@code update account set slots = N where ...} — it is read fresh
	 * on every character-list fetch, so it takes effect on the next visit to that screen with no
	 * restart.
	 * <p>
	 * Lowering it below the number of characters an account already has would hide the surplus
	 * rather than delete them; the characters remain in the database and reappear if the count goes
	 * back up.
	 */
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

	public int getMainExp() {
		return mainExp;
	}

	public void setMainExp(int mainExp) {
		this.mainExp = mainExp;
	}

	public int getAltExp() {
		return altExp;
	}

	public void setAltExp(int altExp) {
		this.altExp = altExp;
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
