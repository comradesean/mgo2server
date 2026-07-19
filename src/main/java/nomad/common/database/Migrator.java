package nomad.common.database;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.jdbi.v3.core.Jdbi;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Migrator {
	private record MigrationInfo(long version, String name) {
	}

	private static final Logger logger = LogManager.getLogger();

	private final Jdbi jdbi;

	public Migrator(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	public void run() {
		var migrationDir = Paths.get("./migration/");
		try {
			var version = 0L;
			try (var handle = jdbi.open()) {
				handle.execute("""
						CREATE TABLE IF NOT EXISTS public.migration
						(
							id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
							version bigint NOT NULL,
							CONSTRAINT migration_pkey PRIMARY KEY (version)
						)
					""");

				version = handle.createQuery("select version from migration order by version desc limit 1")
					.mapTo(Long.class)
					.findOne()
					.orElse(0L);
			}
			logger.info("Database is version " + version);

			List<MigrationInfo> migrations;
			try (var f = Files.list(migrationDir)) {
				var pattern = Pattern.compile("^(\\d+).*\\.sql$");
				migrations = f.map(e -> pattern.matcher(e.getFileName().toString()))
					.filter(Matcher::matches)
					.map(e -> new MigrationInfo(Long.parseLong(e.group(1)), e.group()))
					.sorted(Comparator.comparing(MigrationInfo::version))
					.toList();
			}

			for (var migration : migrations) {
				if (migration.version <= version) {
					logger.info("Skipping migration version " + migration.version);
					continue;
				}

				logger.info("Running migration version " + migration.version);

				var path = migrationDir.resolve(migration.name);
				var sql = Files.readString(path);
				try (var handle = jdbi.open()) {
					handle.createScript(sql).execute();

					handle.createUpdate("insert into migration (version) values (:version)")
						.bind("version", migration.version)
						.execute();
				}
			}

			try (var handle = jdbi.open()) {
				version = handle.createQuery("select version from migration order by version desc limit 1")
					.mapTo(Long.class)
					.findOne()
					.orElse(0L);
			}
			logger.info("Database updated to version " + version);
		} catch (IOException e) {
			logger.error("Failed to run migration.", e);
		}
	}
}
