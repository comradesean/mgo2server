package nomad.common;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import nomad.common.model.*;
import org.jdbi.v3.core.Jdbi;
import org.jdbi.v3.core.mapper.reflect.BeanMapper;
import org.jdbi.v3.stringtemplate4.StringTemplateEngine;

import javax.sql.DataSource;
import java.time.ZoneOffset;
import java.util.TimeZone;

/**
 * Owns the connection pool and the configured {@link Jdbi} instance.
 * <p>
 * Held rather than static so tests can point it at a throwaway container and close it afterwards.
 */
public final class Database implements AutoCloseable {
	private final HikariDataSource dataSource;

	private final Jdbi jdbi;

	private Database(HikariDataSource dataSource, Jdbi jdbi) {
		this.dataSource = dataSource;
		this.jdbi = jdbi;
	}

	public static Database create(Config config) {
		return create(config.dbUrl(), config.dbUser(), config.dbPassword(), config.dbPoolMaxSize());
	}

	public static Database create(String url, String username, String password) {
		return create(url, username, password, 10);
	}

	public static Database create(String url, String username, String password, int poolMaxSize) {
		// dtouve: Hack for Postgres JDBC driver
		TimeZone.setDefault(TimeZone.getTimeZone(ZoneOffset.UTC));

		var hikariConfig = new HikariConfig();
		hikariConfig.setJdbcUrl(url);
		hikariConfig.setUsername(username);
		hikariConfig.setPassword(password);
		hikariConfig.setMaximumPoolSize(poolMaxSize);
		hikariConfig.setPoolName("nomad");

		var dataSource = new HikariDataSource(hikariConfig);
		return new Database(dataSource, createJdbi(dataSource));
	}

	public static Jdbi createJdbi(DataSource dataSource) {
		var jdbi = Jdbi.create(dataSource);

		jdbi.registerRowMapper(BeanMapper.factory(Account.class));
		jdbi.registerRowMapper(BeanMapper.factory(Chara.class));
		jdbi.registerRowMapper(BeanMapper.factory(CharaAppearance.class));
		jdbi.registerRowMapper(BeanMapper.factory(CharaSettings.class));
		jdbi.registerRowMapper(BeanMapper.factory(ChatMacro.class));
		jdbi.registerRowMapper(BeanMapper.factory(EquippedSkills.class));
		jdbi.registerRowMapper(BeanMapper.factory(CharaRoomConfiguration.class));
		jdbi.registerRowMapper(BeanMapper.factory(Clan.class));
		jdbi.registerRowMapper(BeanMapper.factory(Game.class));
		jdbi.registerRowMapper(BeanMapper.factory(HostSettings.class));
		jdbi.registerRowMapper(BeanMapper.factory(Lobby.class));
		jdbi.registerRowMapper(BeanMapper.factory(News.class));
		jdbi.registerRowMapper(BeanMapper.factory(Room.class));
		jdbi.registerRowMapper(BeanMapper.factory(RoomChara.class));
		jdbi.registerRowMapper(BeanMapper.factory(RoomConfiguration.class));

		jdbi.setTemplateEngine(new StringTemplateEngine());

		return jdbi;
	}

	public Jdbi jdbi() {
		return jdbi;
	}

	public DataSource dataSource() {
		return dataSource;
	}

	@Override
	public void close() {
		dataSource.close();
	}
}
