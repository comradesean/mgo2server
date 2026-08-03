package mgo2server.common;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HexFormat;
import java.util.Map;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * <b>The guard that keeps 1.36 work out of 1.0 behaviour.</b>
 * <p>
 * Two divergences went in on 2026-08-02 to get a 1.36 client past login, both wrong for the
 * release-day disc build: the login reply's perks grammar and the check-session key. They arrived
 * as {@code System.getenv} reads on {@code static final} fields, which is untestable and which had
 * already put {@code SessionFieldTest} and {@code AuthWebControllerTest} one exported variable away
 * from failing.
 * <p>
 * This file exists so that cannot recur. It asserts three things:
 * <ol>
 *   <li><b>Unset means 1.0</b> — a deployment that never heard of this toggle serves the disc
 *       build, so the default can never drift to a later version by accident.</li>
 *   <li><b>{@link ClientVersion#V1_0}'s whole row is pinned</b> to capture-proven literals. Every
 *       divergence is a column on that enum, so a change made "for 1.36" that touches 1.0 shows up
 *       here as a failing literal rather than as a wrong byte on the wire weeks later.</li>
 *   <li><b>No source file reads a version-specific environment variable</b> outside this class.
 *       That is the structural half: the values can only live on the enum.</li>
 * </ol>
 */
class ClientVersionTest {
	private static ClientVersion of(Map<String, String> env) {
		return ClientVersion.from(env::get);
	}

	// ---------------------------------------------------------------- defaults

	@Test
	void anEmptyEnvironmentIsTheDiscBuild() {
		// The point of the file. v1 targets release day; a deployment that has never been told
		// otherwise must not serve a later build's protocol.
		assertThat(of(Map.of())).isEqualTo(ClientVersion.V1_0);
	}

	@Test
	void blankFallsBackToTheDiscBuildRatherThanFailing() {
		// compose writes KEY= for an unset variable, which arrives as "" and not null.
		assertThat(of(Map.of(ClientVersion.ENV, ""))).isEqualTo(ClientVersion.V1_0);
	}

	// ------------------------------------------------------------------ pins

	@Test
	void theDiscRowIsPinnedExactly() {
		var disc = ClientVersion.V1_0;

		assertThat(disc.label()).isEqualTo("1.0");
		assertThat(disc.loginPerks())
			.as("one integer; 1.0's parser requires ',' after it (0xBB172C)")
			.isEqualTo("1000000");
		assertThat(disc.sessionKeyResource()).isEqualTo("crypto/session.key");
		assertThat(HexFormat.of().formatHex(disc.sessionIv()))
			.as("first eight bytes of the disc kit's derived context")
			.isEqualTo("b0781d5365e3910e");
		assertThat(disc.hubEntryTextLength())
			.as("0x4902 entry carries a 64-byte text block on 1.0, making the entry 99 bytes")
			.isEqualTo(64);
		assertThat(disc.isDisc()).isTrue();
		assertThat(disc.is136()).isFalse();
	}

	@Test
	void the136RowIsPinnedExactly() {
		var patch = ClientVersion.V1_36;

		assertThat(patch.label()).isEqualTo("1.36");
		assertThat(patch.loginPerks())
			.as("ten integers, nine underscores; 1.36 requires '_' after each (0xD6EE70)")
			.isEqualTo("1000_1000_5000_10000_1000_3000_1000_1000_2000_1000");
		assertThat(patch.loginPerks().split("_", -1)).hasSize(10);
		assertThat(patch.sessionKeyResource()).isEqualTo("crypto/session_136.key");
		assertThat(HexFormat.of().formatHex(patch.sessionIv()))
			.as("first eight bytes of the patch kit's derived context")
			.isEqualTo("35d5c38ed0110ea8");
		assertThat(patch.hubEntryTextLength())
			.as("1.36 deleted the text block with the subtype-5 scan; entry is 35 bytes")
			.isZero();
		assertThat(patch.is136()).isTrue();
	}

	@Test
	void noTwoVersionsShareADivergentValue() {
		// If a column ever becomes identical across versions it is not a divergence and should not
		// be on this enum; if it becomes identical by accident, one build is being served the
		// other's value.
		assertThat(ClientVersion.V1_0.loginPerks())
			.isNotEqualTo(ClientVersion.V1_36.loginPerks());
		assertThat(ClientVersion.V1_0.sessionKeyResource())
			.isNotEqualTo(ClientVersion.V1_36.sessionKeyResource());
		assertThat(ClientVersion.V1_0.sessionIv())
			.isNotEqualTo(ClientVersion.V1_36.sessionIv());
		assertThat(ClientVersion.V1_0.hubEntryTextLength())
			.isNotEqualTo(ClientVersion.V1_36.hubEntryTextLength());
	}

	@Test
	void everyVersionShipsItsKeyResource() {
		for (var version : ClientVersion.values()) {
			assertThat(ClientVersion.class.getClassLoader()
				.getResourceAsStream(version.sessionKeyResource()))
				.as("key resource for %s", version.label())
				.isNotNull();
		}
	}

	@Test
	void sessionIvIsCopiedSoCallersCannotMutateTheTable() {
		var first = ClientVersion.V1_0.sessionIv();
		first[0] = 0;

		assertThat(ClientVersion.V1_0.sessionIv()[0]).isEqualTo((byte) 0xb0);
	}

	// ----------------------------------------------------------------- parsing

	@Test
	void parsesBothLabels() {
		assertThat(of(Map.of(ClientVersion.ENV, "1.0"))).isEqualTo(ClientVersion.V1_0);
		assertThat(of(Map.of(ClientVersion.ENV, "1.36"))).isEqualTo(ClientVersion.V1_36);
	}

	@Test
	void toleratesSurroundingWhitespace() {
		assertThat(of(Map.of(ClientVersion.ENV, "  1.36  "))).isEqualTo(ClientVersion.V1_36);
	}

	@Test
	void rejectsAnythingElseNamingBothAlternativesAndTheBadValue() {
		// An operator reading a dead container's log should not have to guess the spelling.
		assertThatThrownBy(() -> of(Map.of(ClientVersion.ENV, "1.30")))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("1.0")
			.hasMessageContaining("1.36")
			.hasMessageContaining("1.30")
			.hasMessageContaining(ClientVersion.ENV);
	}

	@Test
	void rejectsNearMissesRatherThanGuessing() {
		// "1" and "1.360" are the shapes a hurried edit produces; silently accepting either would
		// serve the wrong protocol.
		for (var bad : new String[] { "1", "1.360", "136", "disc", "patch" }) {
			assertThatThrownBy(() -> of(Map.of(ClientVersion.ENV, bad)))
				.as("must reject %s", bad)
				.isInstanceOf(IllegalArgumentException.class);
		}
	}

	// ----------------------------------------------------------- no leakage

	/**
	 * The structural guard: version-specific values may only live on {@link ClientVersion}.
	 * <p>
	 * Both of these variables existed on 2026-08-02 and were removed by the same change that added
	 * this enum. Reintroducing either would rebuild the split-brain where an operator has to set
	 * two unrelated variables consistently and the test suite silently depends on neither being
	 * set.
	 * <p>
	 * <b>It matches the read, not the name.</b> The first version of this test matched the bare
	 * variable name and immediately failed on {@code SessionField}'s own comment explaining why the
	 * variable is gone — which is exactly the note a future reader needs. Banning the discussion
	 * would cost more than it saves; banning {@code getenv("...")} is the thing that actually
	 * matters.
	 */
	@Test
	void noSourceFileReadsAVersionSpecificEnvironmentVariable() throws Exception {
		var retired = new String[] {
			"getenv(\"MGO2SERVER_SESSION_KIT\")",
			"getenv(\"MGO2SERVER_LOGIN_PERKS\")",
		};
		var main = Path.of("src", "main", "java");

		try (Stream<Path> files = Files.walk(main)) {
			var offenders = files
				.filter(p -> p.toString().endsWith(".java"))
				.filter(p -> {
					try {
						var text = Files.readString(p);
						return Stream.of(retired).anyMatch(text::contains);
					} catch (Exception e) {
						throw new IllegalStateException("could not read " + p, e);
					}
				})
				.map(Path::toString)
				.toList();

			assertThat(offenders)
				.as("version-specific values belong on ClientVersion, not in a System.getenv read")
				.isEmpty();
		}
	}
}
