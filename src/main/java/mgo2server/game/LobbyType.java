package mgo2server.game;

/**
 * The kind of lobby a server instance is serving.
 * <p>
 * The original runs one server per lobby and dispatches a different command set for each, so a
 * gate never answers character commands. That split matters for more than tidiness: check-session
 * behaves differently per type, identifying the player by account in an account lobby and by
 * character in a game lobby.
 */
public enum LobbyType {
	/** Hands out the lobby list; the first thing a client talks to. */
	GATE(0),

	/** Character selection: list, create, select, delete. */
	ACCOUNT(1),

	/** The lobby proper, where a selected character plays. */
	GAME(2);

	private final int id;

	LobbyType(int id) {
		this.id = id;
	}

	public int id() {
		return id;
	}

	public static LobbyType fromId(int id) {
		for (var type : values()) {
			if (type.id == id) {
				return type;
			}
		}
		throw new IllegalArgumentException("Unknown lobby type: " + id);
	}
}
