package nomad.game;

/**
 * Error codes the client understands, ported from Nomad's {@code savemgo.nomad.util.Error}.
 * <p>
 * Codes are sent masked with {@link #MASK} except for the handful the retail server sent
 * unmasked, which are marked {@code official} — the client compares those against literal values.
 */
public enum GameError {
	/** General */
	NONE(0, true),
	NOT_IMPLEMENTED(0xff),
	GENERAL(0x1),
	INVALID_SESSION(0x2),

	/** User */
	CHARACTER_NAME_INVALID(0x10),
	CHARACTER_NAME_PREFIX(0x11),
	CHARACTER_NAME_RESERVED(0x12),
	CHARACTER_NAME_TAKEN(-260, true),
	CHARACTER_CANNOT_DELETE_YET(0x14),

	/** Character */
	CHARACTER_DOES_NOT_EXIST(0x20),

	/** Game */
	GAME_PLACEHOLDER(0x30),

	/** Clan */
	CLAN_DOES_NOT_EXIST(0x40),
	CLAN_NOT_A_MEMBER(0x41),
	CLAN_IN_A_CLAN(0x42),
	CLAN_NO_APPLICATION(0x43),
	CLAN_HAS_APPLICATION(0x44),
	CLAN_NOT_A_LEADER(0x45);

	/** Applied to the high bytes so the client recognises the value as an error. */
	public static final int MASK = 0xC0FFEE << 8;

	private final int code;

	private final boolean official;

	GameError(int code) {
		this(code, false);
	}

	GameError(int code, boolean official) {
		this.code = code;
		this.official = official;
	}

	public int code() {
		return code;
	}

	/** The value as it goes on the wire. */
	public int result() {
		return official ? code : (code | MASK);
	}
}
