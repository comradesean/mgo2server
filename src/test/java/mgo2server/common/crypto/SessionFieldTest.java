package mgo2server.common.crypto;

import org.junit.jupiter.api.Test;

import java.util.HexFormat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Pins the check-session transform to bytes captured from a real client (BLUS30109).
 * <p>
 * These are not synthetic vectors: each is a login token this server issued paired with the
 * {@code 0x3003} field the game then sent back. They are the only evidence that the transform is
 * right, so they are worth more than any amount of round-trip testing against ourselves.
 */
class SessionFieldTest {
	@Test
	void reproducesTheFieldACapturedClientSent() {
		// Login reply was "0,122345677,1000000,1888e089ebe181fd"; the client's check-session
		// packet then carried this sixteen-byte field.
		assertThat(SessionField.of("1888e089ebe181fd"))
			.isEqualTo(HexFormat.of().parseHex("a5a0dd9199494cf00e06ae9dc4655563"));
	}

	@Test
	void chainsBlocksSoTheFirstHalfDependsOnlyOnTheFirstEightCharacters() {
		// A second capture stored the token prefix "29bfaad0" and produced a field beginning
		// 5f8e0a4b4f7c5372. The rest of that token was not recorded, but because each block is
		// transformed from its own plaintext, the leading eight bytes must still match — which is
		// what makes this an independent confirmation rather than a restatement of the first.
		var field = SessionField.of("29bfaad0" + "aaaaaaaa");

		assertThat(HexFormat.of().formatHex(field))
			.startsWith("5f8e0a4b4f7c5372");
	}

	@Test
	void storesTheFieldAsHexSoCheckSessionIsAPlainLookup() {
		var token = "1888e089ebe181fd";

		assertThat(SessionField.stored(token))
			.isEqualTo("a5a0dd9199494cf00e06ae9dc4655563")
			.isEqualTo(SessionField.stored(SessionField.of(token)));
	}

	@Test
	void rejectsTokensThatAreNotSixteenCharacters() {
		assertThatThrownBy(() -> SessionField.of("1888e089"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("16");
	}
}
