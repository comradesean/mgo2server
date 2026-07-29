package mgo2server.game;

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
	/**
	 * The delete cooldown, refused server-side. {@code -268} -> dialog 22787, <em>"A fixed amount
	 * of time must pass in order to delete a character.\nUnable to delete character."</em> — the op
	 * is {@code 0x3103}, dispatcher {@code 0x94F60C}.
	 * <p>
	 * This was {@code 0x14}, an inherited placeholder that went out masked as {@code 0xC0FFEE14}
	 * and matched nothing in the client's table. It looked correct in testing only because the
	 * <em>client</em> pre-checks the cooldown and puts up its own information screen with the
	 * remaining time, so our reply was never the thing being read. A backstop that has never been
	 * seen is not a backstop that works.
	 */
	CHARACTER_CANNOT_DELETE_YET(-268, true),

	/**
	 * Refuses a lobby connect: <em>"You cannot login to this lobby."</em>
	 * <p>
	 * [ELF] The lobby-connect state machine compares the completed request's result at
	 * {@code 0x947198} onward — {@code -240} to dialog 2340, {@code -402} to 2640, and both
	 * {@code -403} and {@code -404} to dialog <b>2355</b>, which is this sentence. Anything else it
	 * does not name falls through to 2339, "Unable to connect to lobby."
	 * <p>
	 * {@code -404} is chosen over {@code -403} because it is the code the client's own beginner
	 * check passes when it raises the same dialog itself ({@code li r4,-404} at {@code 0x892250}),
	 * so a refusal from us is indistinguishable from the one the client would have made.
	 * <p>
	 * Unmasked: this is the client's own code, not one of ours.
	 */
	LOBBY_ENTRY_REFUSED(-404, true),

	/** Character */
	CHARACTER_DOES_NOT_EXIST(0x20),

	/** Game */
	GAME_PLACEHOLDER(0x30),

	/**
	 * Automatching. Every one of these is {@code official}, and that is not a detail — a masked
	 * {@code 0xC0FFEExx} matches nothing in the client's table, so it would fall through to the
	 * generic arm and print the wrong sentence with our number inside it. This is exactly the trap
	 * {@link #CHARACTER_CANNOT_DELETE_YET} above records.
	 * <p>
	 * The codes are a <em>discriminated set</em>, read from the client at the sites named in
	 * {@code dev/docs/AUTOMATCH.md} §6. Anything nonzero that is not in the set still produces a
	 * dialog; there is no benign nonzero result here.
	 */
	/**
	 * {@code 0x4321}: "Password is incorrect.\nUnable to connect to host."
	 * <p>
	 * [ELF, 2026-07-29] Chain {@code 0x94483C}, raised at {@code 0x944C58}, code taken from the
	 * slot-38 getter {@code 0xD3FA34}; disc string 22386. Recovered by a sweep of all 4352 codes,
	 * so the discrimination is exhaustive rather than sampled.
	 * <p>
	 * Before this existed we answered a mistyped password with {@link #GENERAL}, which prints
	 * <em>"Unable to connect to host."</em> — true, useless, and the most common failure a player
	 * will ever hit. It reads as the server being broken rather than as a typo.
	 */
	GAME_PASSWORD_INCORRECT(-540, true),

	/**
	 * {@code 0x4321}: "Maximum number of characters already reached.\nUnable to connect to host."
	 * <p>
	 * [ELF, 2026-07-29] Same chain as {@link #GAME_PASSWORD_INCORRECT}; disc string 22380.
	 * <b>Nothing sends this yet</b> — {@code joinGame} has no capacity check at all, so a full game
	 * is joined rather than refused. The refusal and its sentence both exist; the check does not.
	 */
	GAME_FULL(-503, true),

	/**
	 * {@code 0x4321} / {@code 0x4311}: "You are currently banned from creating and joining games."
	 * <p>
	 * [ELF, 2026-07-29] Accepted on <b>both</b> replies, so one value covers hosting and joining.
	 * Disc string 22583. There is no ban enforcement in this server yet; when there is, this is the
	 * code, and it is recorded now so the next person does not go looking for two.
	 */
	GAME_BANNED_FROM_PLAY(-541, true),

	/**
	 * {@code 0x4315}: "Unable to locate host."
	 * <p>
	 * [ELF, 2026-07-29] Chain {@code 0x8B5244}, raised at {@code 0x8B5280}, code from the slot-36
	 * getter {@code 0xD3FA8C}; dialog 3599, disc string 22422. Every other nonzero value falls
	 * through to dialog 2831, <em>"Unable to acquire host information."</em> — which reads as a
	 * server fault when the real condition is that the game went away.
	 */
	GAME_HOST_NOT_FOUND(-506, true),

	/**
	 * {@code 0x3106}: "You are the leader of a clan.\nEither disband the clan or assign another
	 * character as leader."
	 * <p>
	 * [ELF, 2026-07-29] Chain {@code 0x94F60C}, raised at {@code 0x94F674}, wait slot {@code 0x11},
	 * getter {@code 0xD36C8C}; dialog 2658, disc string 22769. Recovered by a sweep of all 4353
	 * codes with zero unmodelled, and the arm's positive control is {@code -268} — the delete
	 * cooldown we already ship — reproducing its documented sentence.
	 * <p>
	 * <b>This supersedes an auto-succession policy added earlier the same day.</b> That version
	 * promoted the longest-standing member (or disbanded a one-member clan) and let the delete
	 * through, on the reasoning that this code was unestablished and refusing would show a generic
	 * sentence. It is established, and it does not merely refuse — it tells the player the two ways
	 * out. Choosing a successor on their behalf is a policy invention the game itself declines to
	 * make, so we decline too.
	 */
	CHARACTER_IS_CLAN_LEADER(-1212, true),

	AUTOMATCH_NOT_OPEN(-970, true),

	/** {@code 0x43e1}: "Unable to start automatching." [0x93CF50] */
	AUTOMATCH_CANNOT_START(-950, true),

	/** {@code 0x43e3}: "Unable to cancel automatching." [0x93D208] */
	AUTOMATCH_CANNOT_CANCEL(-952, true),

	/**
	 * {@code 0x43e3}: the only code that <b>parks the client silently</b> — no dialog, straight to
	 * the dormant state [0x93D1EC]. For a cancel that arrives after a match has already been
	 * assigned, where erroring would be a lie and succeeding would strand the match.
	 */
	AUTOMATCH_CANCEL_TOO_LATE(-953, true),

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
