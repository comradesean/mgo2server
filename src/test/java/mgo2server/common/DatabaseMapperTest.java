package mgo2server.common;

import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.io.IOException;
import java.lang.reflect.Proxy;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Guards against a mistake made twice already: adding a model and forgetting to register a Jdbi
 * mapper for it. The omission compiles, passes unit tests, and only surfaces at runtime as
 * "No mapper registered for type ..." from whichever query happens to touch it first.
 * <p>
 * Rather than listing the models by hand — a list that would itself drift — this discovers every
 * class in the model package and asserts each one can be mapped.
 */
public class DatabaseMapperTest {
	private static List<Class<?>> modelClasses() {
		var packageName = "mgo2server.common.model";
		var resource = DatabaseMapperTest.class.getClassLoader()
			.getResource(packageName.replace('.', '/'));

		assertThat(resource).as("model package must be on the classpath").isNotNull();

		var classes = new ArrayList<Class<?>>();
		try (var entries = Files.list(Path.of(resource.getPath()))) {
			entries.filter(path -> path.toString().endsWith(".class"))
				.map(path -> path.getFileName().toString().replace(".class", ""))
				// Skip nested classes; only top-level models are mapped.
				.filter(name -> !name.contains("$"))
				.sorted()
				.forEach(name -> {
					try {
						classes.add(Class.forName(packageName + "." + name));
					} catch (ClassNotFoundException e) {
						throw new IllegalStateException(e);
					}
				});
		} catch (IOException e) {
			throw new UncheckedIOException(e);
		}
		return classes;
	}

	/** A DataSource that exists only to satisfy Jdbi's constructor. */
	private static DataSource neverConnects() {
		return (DataSource) Proxy.newProxyInstance(
			DatabaseMapperTest.class.getClassLoader(),
			new Class<?>[] { DataSource.class },
			(proxy, method, args) -> {
				throw new UnsupportedOperationException("This test must not open a connection");
			});
	}

	@Test
	public void everyModelHasARegisteredRowMapper() {
		var models = modelClasses();
		assertThat(models).as("expected to discover the model classes").isNotEmpty();

		// Registration is what is under test, and findFor consults the registry without opening a
		// connection, so a datasource that refuses to connect is sufficient.
		var jdbi = Database.createJdbi(neverConnects());

		var unmapped = models.stream()
			.filter(model -> jdbi.getConfig(org.jdbi.v3.core.mapper.RowMappers.class)
				.findFor(model).isEmpty())
			.map(Class::getSimpleName)
			.toList();

		assertThat(unmapped)
			.as("models without a row mapper in Database.createJdbi")
			.isEmpty();
	}
}
