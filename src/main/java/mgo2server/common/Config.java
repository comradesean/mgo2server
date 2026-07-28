package mgo2server.common;

/**
 * Runtime configuration, read from the environment.
 * <p>
 * Every value has a development-friendly default so a bare {@code docker compose up} works, but
 * nothing secret is baked into the image: {@code MGO2SERVER_DB_PASSWORD} is expected to be injected.
 */
import java.util.function.UnaryOperator;

public record Config(
	String dbUrl,
	String dbUser,
	String dbPassword,
	int dbPoolMaxSize,
	int gamePort,
	int webPort,
	int lobbyType,
	long lobbyId,
	int lobbySubtype,
	String advertiseIp,
	java.util.List<String> lobbyNames,
	boolean lobbyBeginnersOnly,
	int lobbyHubFlags
) {
	public static final String DEFAULT_DB_URL = "jdbc:postgresql://localhost:5432/mgo2server";

	public static final int DEFAULT_GAME_PORT = 5730;

	public static final int DEFAULT_WEB_PORT = 8080;

	/** Gate, so a default deployment answers the first thing a client asks for. */
	public static final int DEFAULT_LOBBY_TYPE = 0;

	/** Which lobby row this instance serves; only meaningful for a game lobby. */
	public static final int DEFAULT_LOBBY_ID = 1;

	public static Config fromEnv() {
		return from(System::getenv);
	}

	/** Reads from an arbitrary lookup rather than the process environment, so it can be tested. */
	public static Config from(UnaryOperator<String> env) {
		return new Config(
			string(env, "MGO2SERVER_DB_URL", DEFAULT_DB_URL),
			string(env, "MGO2SERVER_DB_USER", "mgo2server"),
			string(env, "MGO2SERVER_DB_PASSWORD", "mgo2server"),
			integer(env, "MGO2SERVER_DB_POOL_MAX_SIZE", 10),
			integer(env, "MGO2SERVER_GAME_PORT", DEFAULT_GAME_PORT),
			integer(env, "MGO2SERVER_WEB_PORT", DEFAULT_WEB_PORT),
			integer(env, "MGO2SERVER_LOBBY_TYPE", DEFAULT_LOBBY_TYPE),
			integer(env, "MGO2SERVER_LOBBY_ID", DEFAULT_LOBBY_ID),
			integer(env, "MGO2SERVER_LOBBY_SUBTYPE", 0),
			string(env, "MGO2SERVER_ADVERTISE_IP", ""),
			names(env, "MGO2SERVER_LOBBY_NAMES"),
			bool(env, "MGO2SERVER_LOBBY_BEGINNERS_ONLY"),
			integer(env, "MGO2SERVER_LOBBY_HUB_FLAGS", 0)
		);
	}

	/**
	 * The pool a lobby picks its display name from, comma-separated. Empty means "keep whatever
	 * name the row already has", which is what every lobby did before self-registration existed.
	 */
	private static java.util.List<String> names(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return java.util.List.of();
		}
		return java.util.Arrays.stream(value.split(","))
			.map(String::trim)
			.filter(n -> !n.isEmpty())
			.toList();
	}

	private static boolean bool(UnaryOperator<String> env, String name) {
		var value = env.apply(name);
		return value != null && ("true".equalsIgnoreCase(value.trim()) || "1".equals(value.trim()));
	}

	private static String string(UnaryOperator<String> env, String name, String fallback) {
		var value = env.apply(name);
		return value == null || value.isBlank() ? fallback : value;
	}

	private static int integer(UnaryOperator<String> env, String name, int fallback) {
		var value = env.apply(name);
		if (value == null || value.isBlank()) {
			return fallback;
		}
		try {
			return Integer.parseInt(value.trim());
		} catch (NumberFormatException e) {
			throw new IllegalArgumentException(name + " must be an integer, got: " + value, e);
		}
	}

	/** Redacts the password so a Config can be safely logged. */
	@Override
	public String toString() {
		return "Config[dbUrl=%s, dbUser=%s, dbPassword=***, dbPoolMaxSize=%d, gamePort=%d, webPort=%d, lobbyType=%d, lobbyId=%d, lobbySubtype=%d]"
			.formatted(dbUrl, dbUser, dbPoolMaxSize, gamePort, webPort, lobbyType, lobbyId, lobbySubtype);
	}
}
