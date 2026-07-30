package mgo2server;

import mgo2server.common.Database;
import mgo2server.common.database.Migrations;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.stream.Collectors;

/**
 * One Postgres container and one migrated schema for the whole test JVM.
 * <p>
 * Starting a container and migrating per test class costs seconds each time. Instead the container
 * starts once on first use and individual tests get isolation from {@link #reset()}, which
 * truncates every table and restarts identity sequences so row ids are predictable.
 */
public final class TestDatabase {
	private static final String IMAGE = "postgres:17-alpine";

	private static PostgreSQLContainer<?> container;

	private static Database database;

	private TestDatabase() {
	}

	public static synchronized Database get() {
		if (database == null) {
			container = new PostgreSQLContainer<>(IMAGE);
			container.start();

			database = Database.create(container.getJdbcUrl(), container.getUsername(), container.getPassword());
			Migrations.migrate(database.dataSource());

			// Testcontainers' Ryuk reaps the container; closing the pool is ours to do.
			Runtime.getRuntime().addShutdownHook(new Thread(database::close));
		}
		return database;
	}

	/** Empties every application table, leaving the schema and Flyway history intact. */
	public static void reset() {
		var db = get();
		db.jdbi().useHandle(handle -> {
			// Uses != rather than <>: Jdbi renders through StringTemplate, which reads <...> as an
			// expression and fails to compile the statement.
			// `skill` and `gear_item` are reference data a migration seeds, not test state —
			// truncating them would leave every character with no skills or gear to own, since
			// chara_skill and chara_gear both seed by selecting from them. Same reasoning as
			// schema_version: if a migration put the rows there, a reset has no business removing
			// them. Anything else added as a seeded catalogue belongs in this list too.
			var tables = handle.createQuery("""
					select tablename from pg_tables
					where schemaname = 'public'
					  and tablename != 'schema_version'
					  and tablename != 'skill'
					  and tablename != 'gear_item'
					""")
				.mapTo(String.class)
				.list();

			if (tables.isEmpty()) {
				return;
			}

			var targets = tables.stream()
				.map(t -> "public.\"" + t + "\"")
				.collect(Collectors.joining(", "));
			handle.execute("truncate table " + targets + " restart identity cascade");
		});
	}
}
