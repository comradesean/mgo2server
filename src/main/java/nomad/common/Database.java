package nomad.common;

import nomad.common.model.*;
import org.jdbi.v3.core.Jdbi;
import org.jdbi.v3.core.mapper.reflect.BeanMapper;
import org.jdbi.v3.stringtemplate4.StringTemplateEngine;

import java.time.ZoneOffset;
import java.util.TimeZone;

public class Database {
	public static Jdbi getJdbi() {
		// dtouve: Hack for Postgres JDBC driver
		TimeZone.setDefault(TimeZone.getTimeZone(ZoneOffset.UTC));

		var url = "jdbc:postgresql://localhost:15432/nomad";
		var username = "postgres";
		var password = "password";
		return getJdbi(url, username, password);
	}

	public static Jdbi getJdbi(String url, String username, String password) {
		var jdbi = Jdbi.create(url, username, password);

		jdbi.registerRowMapper(BeanMapper.factory(Account.class));
		jdbi.registerRowMapper(BeanMapper.factory(Chara.class));
		jdbi.registerRowMapper(BeanMapper.factory(CharaRoomConfiguration.class));
		jdbi.registerRowMapper(BeanMapper.factory(Clan.class));
		jdbi.registerRowMapper(BeanMapper.factory(Lobby.class));
		jdbi.registerRowMapper(BeanMapper.factory(News.class));
		jdbi.registerRowMapper(BeanMapper.factory(Room.class));
		jdbi.registerRowMapper(BeanMapper.factory(RoomChara.class));
		jdbi.registerRowMapper(BeanMapper.factory(RoomConfiguration.class));

		jdbi.setTemplateEngine(new StringTemplateEngine());

		return jdbi;
	}
}
