package nomad.common.crypto;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.util.HexFormat;

import static org.assertj.core.api.Assertions.*;

/**
 * Expected values come from running the original {@code Users.decryptSessionId}, so this rewrite
 * cannot drift from what a real client's login is decoded to.
 */
public class SessionIdsTest {
	private static final HexFormat HEX = HexFormat.of();

	@ParameterizedTest(name = "{0}")
	@CsvSource({
		"00112233445566770000000000000000,f4157479d9436471",
		"0102030405060708aabbccddeeff0011,18ee04e81dc1b5af",
	})
	public void matchesOriginalImplementation(String fieldHex, String expectedTokenHex) {
		var token = SessionIds.decode(HEX.parseHex(fieldHex));

		assertThat(HEX.formatHex(token.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1)))
			.isEqualTo(expectedTokenHex);
	}

	/** The original server mapped one specific field to a fixed token; keep that behaviour. */
	@Test
	public void mapsSentinelFieldToFixedToken() {
		var field = HEX.parseHex("e7bab426fe3f4073db9436df6ddbd39c");

		assertThat(SessionIds.decode(field)).isEqualTo("cafebabe");
	}

	@Test
	public void encodeAndDecodeRoundTrip() {
		assertThat(SessionIds.decode(SessionIds.encode("abcd1234"))).isEqualTo("abcd1234");
		assertThat(SessionIds.decode(SessionIds.encode("00000000"))).isEqualTo("00000000");
	}

	/** Pins the inverse against a value computed with the original implementation. */
	@Test
	public void encodeMatchesOriginalInverse() {
		var field = SessionIds.encode("abcd1234");

		assertThat(HEX.formatHex(java.util.Arrays.copyOf(field, SessionIds.LENGTH)))
			.isEqualTo("b934771d9e9ca402");
		assertThat(field).hasSize(SessionIds.FIELD_LENGTH);
	}

	@Test
	public void rejectsShortField() {
		assertThatThrownBy(() -> SessionIds.decode(new byte[4]))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("at least 8");
	}

	@Test
	public void rejectsWrongLengthToken() {
		assertThatThrownBy(() -> SessionIds.encode("short"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("8 characters");
	}
}
