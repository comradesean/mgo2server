package nomad.common;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.*;

public class ConfigTest {
	private static Config configFrom(Map<String, String> env) {
		return Config.from(env::get);
	}

	@Test
	public void usesDefaultsWhenEnvironmentIsEmpty() {
		var config = configFrom(Map.of());

		assertThat(config.dbUrl()).isEqualTo(Config.DEFAULT_DB_URL);
		assertThat(config.dbUser()).isEqualTo("nomad");
		assertThat(config.gamePort()).isEqualTo(Config.DEFAULT_GAME_PORT);
		assertThat(config.webPort()).isEqualTo(Config.DEFAULT_WEB_PORT);
		assertThat(config.dbPoolMaxSize()).isEqualTo(10);
	}

	@Test
	public void readsOverridesFromEnvironment() {
		var config = configFrom(Map.of(
			"NOMAD_DB_URL", "jdbc:postgresql://db:5432/prod",
			"NOMAD_DB_USER", "admin",
			"NOMAD_DB_PASSWORD", "s3cret",
			"NOMAD_DB_POOL_MAX_SIZE", "25",
			"NOMAD_GAME_PORT", "6000",
			"NOMAD_WEB_PORT", "9090"
		));

		assertThat(config.dbUrl()).isEqualTo("jdbc:postgresql://db:5432/prod");
		assertThat(config.dbUser()).isEqualTo("admin");
		assertThat(config.dbPassword()).isEqualTo("s3cret");
		assertThat(config.dbPoolMaxSize()).isEqualTo(25);
		assertThat(config.gamePort()).isEqualTo(6000);
		assertThat(config.webPort()).isEqualTo(9090);
	}

	@Test
	public void treatsBlankValuesAsUnset() {
		var config = configFrom(Map.of("NOMAD_DB_URL", "   ", "NOMAD_GAME_PORT", ""));

		assertThat(config.dbUrl()).isEqualTo(Config.DEFAULT_DB_URL);
		assertThat(config.gamePort()).isEqualTo(Config.DEFAULT_GAME_PORT);
	}

	@Test
	public void rejectsNonNumericPort() {
		assertThatThrownBy(() -> configFrom(Map.of("NOMAD_GAME_PORT", "not-a-port")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("NOMAD_GAME_PORT");
	}

	@Test
	public void doesNotLeakPasswordInToString() {
		var config = configFrom(Map.of("NOMAD_DB_PASSWORD", "hunter2"));

		assertThat(config.toString()).doesNotContain("hunter2").contains("***");
	}
}
