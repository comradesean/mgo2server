package mgo2server.common.model;

public class Account {
	private long id;

	private String username;

	private String password;

	private int slots;

	private String session;

	private Long mainCharaId;

	private Long currentCharaId;



	/**
	 * Operator-set play ban, or null. See {@code V51__account_ban.sql}.
	 * <p>
	 * On the account and not the character on purpose: a ban a player can shrug off by switching
	 * character is not a ban, and the client's own sentence agrees — "<em>You</em> are currently
	 * banned", not "this character is".
	 */
	private java.time.OffsetDateTime bannedUntil;

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

	/**
	 * The {@code 0x3049} trailer's entitlement byte — bit 0 unlocks 32 gated entries in the client.
	 * <p>
	 * Per account and editable live (V62): read on every character-list fetch, so an {@code UPDATE}
	 * applies on the next reconnect with no restart.
	 * <p>
	 * <b>Defaults to 0 (V64).</b> Bit 0 grants the day-one paid MGO Codec Pack, so it is granted
	 * deliberately per account and never inherited — the old default of 3 handed a purchased item
	 * to everyone. Bit 1 has no reader on this build.
	 * <p>
	 * See {@code CharacterGameController} for what the bit does and {@code dev/docs/POST_LAUNCH.md}
	 * for the policy and the second-pack question.
	 */
	private int entitlements = 0;

	/**
	 * The {@code 0x3049} trailer's byte at index 1. We have always sent {@code 0x07} and <b>no bit
	 * of it is understood</b>.
	 * <p>
	 * Per account (V63) for the same reason as {@link #entitlements}: so the three set bits can be
	 * isolated by an {@code UPDATE} and a reconnect instead of guessed at. Named by wire position
	 * rather than by a guess at meaning, following the {@code unread_NNN} precedent.
	 */
	private int entitlementsIndex1 = 7;

	public int getEntitlements() {
		return entitlements;
	}

	public int getEntitlementsIndex1() {
		return entitlementsIndex1;
	}

	public void setEntitlementsIndex1(int entitlementsIndex1) {
		this.entitlementsIndex1 = entitlementsIndex1;
	}

	public void setEntitlements(int entitlements) {
		this.entitlements = entitlements;
	}

	public Long getCurrentCharaId() {
		return currentCharaId;
	}

	public void setCurrentCharaId(Long currentCharaId) {
		this.currentCharaId = currentCharaId;
	}

	public java.time.OffsetDateTime getBannedUntil() {
		return bannedUntil;
	}

	public void setBannedUntil(java.time.OffsetDateTime bannedUntil) {
		this.bannedUntil = bannedUntil;
	}

	/**
	 * Whether play is barred right now.
	 * <p>
	 * An expired ban needs no cleanup — the comparison does the work, so nothing has to sweep the
	 * column.
	 */
	public boolean isBannedAt(java.time.OffsetDateTime now) {
		return bannedUntil != null && bannedUntil.isAfter(now);
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
