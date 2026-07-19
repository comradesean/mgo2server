package nomad.common.database;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.flywaydb.core.Flyway;

import javax.sql.DataSource;

/**
 * Schema migration, backed by Flyway.
 * <p>
 * Migrations live on the classpath at {@code db/migration} so they ship inside the jar and do not
 * depend on the process working directory. Failure propagates: a server that cannot migrate must
 * not go on to serve traffic against an unknown schema.
 */
public final class Migrations {
	private static final Logger logger = LogManager.getLogger();

	public static final String LOCATION = "classpath:db/migration";

	private Migrations() {
	}

	public static void migrate(DataSource dataSource) {
		var flyway = Flyway.configure()
			.dataSource(dataSource)
			.locations(LOCATION)
			.table("schema_version")
			.load();

		var result = flyway.migrate();

		if (result.migrationsExecuted == 0) {
			logger.info("Database is up to date at version {}.", result.targetSchemaVersion);
		} else {
			logger.info("Applied {} migration(s), database is now at version {}.",
				result.migrationsExecuted, result.targetSchemaVersion);
		}
	}
}
