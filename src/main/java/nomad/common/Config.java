package nomad.common;

/**
 * Runtime configuration, read from the environment.
 * <p>
 * Every value has a development-friendly default so a bare {@code docker compose up} works, but
 * nothing secret is baked into the image: {@code NOMAD_DB_PASSWORD} is expected to be injected.
 */
import java.util.function.UnaryOperator;

public record Config(
	String dbUrl,
	String dbUser,
	String dbPassword,
	int dbPoolMaxSize,
	int gamePort,
	int webPort
) {
	public static final String DEFAULT_DB_URL = "jdbc:postgresql://localhost:5432/nomad";

	public static final int DEFAULT_GAME_PORT = 5730;

	public static final int DEFAULT_WEB_PORT = 8080;

	public static Config fromEnv() {
		return from(System::getenv);
	}

	/** Reads from an arbitrary lookup rather than the process environment, so it can be tested. */
	public static Config from(UnaryOperator<String> env) {
		return new Config(
			string(env, "NOMAD_DB_URL", DEFAULT_DB_URL),
			string(env, "NOMAD_DB_USER", "nomad"),
			string(env, "NOMAD_DB_PASSWORD", "nomad"),
			integer(env, "NOMAD_DB_POOL_MAX_SIZE", 10),
			integer(env, "NOMAD_GAME_PORT", DEFAULT_GAME_PORT),
			integer(env, "NOMAD_WEB_PORT", DEFAULT_WEB_PORT)
		);
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
		return "Config[dbUrl=%s, dbUser=%s, dbPassword=***, dbPoolMaxSize=%d, gamePort=%d, webPort=%d]"
			.formatted(dbUrl, dbUser, dbPoolMaxSize, gamePort, webPort);
	}
}
