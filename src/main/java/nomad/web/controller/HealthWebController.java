package nomad.web.controller;

import io.jooby.Jooby;
import io.jooby.StatusCode;
import nomad.web.IWebController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import javax.sql.DataSource;

/**
 * Liveness and readiness probes.
 * <p>
 * {@code /health} answers "is the process up"; {@code /ready} answers "can it actually serve",
 * which for this server means the connection pool can hand out a working connection.
 */
public class HealthWebController implements IWebController {
	private static final Logger logger = LogManager.getLogger();

	private static final int VALIDATION_TIMEOUT_SECONDS = 2;

	private final DataSource dataSource;

	public HealthWebController(DataSource dataSource) {
		this.dataSource = dataSource;
	}

	@Override
	public void use(Jooby jooby) {
		jooby.get("/health", ctx -> "OK");

		jooby.get("/ready", ctx -> {
			try (var connection = dataSource.getConnection()) {
				if (connection.isValid(VALIDATION_TIMEOUT_SECONDS)) {
					return "OK";
				}
				logger.warn("Readiness check failed: connection reported invalid.");
			} catch (Exception e) {
				logger.warn("Readiness check failed.", e);
			}
			ctx.setResponseCode(StatusCode.SERVICE_UNAVAILABLE);
			return "UNAVAILABLE";
		});
	}
}
