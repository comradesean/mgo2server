package mgo2server.common.crypto;

import mgo2server.common.ClientVersion;
import org.junit.jupiter.api.Test;

import java.util.HexFormat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Pins the check-session transform to bytes captured from real clients.
 * <p>
 * These are not synthetic vectors: each is a login token this server issued paired with the
 * {@code 0x3003} field the game then sent back. They are the only evidence that the transform is
 * right, so they are worth more than any amount of round-trip testing against ourselves.
 *
 * <h2>Every vector names its client version, and that is load-bearing</h2>
 * The key is not one value. It comes from a file named {@code kit} that the game opens at startup —
 * the disc ships one, the 1.36 patch ships another that shadows it — so the two builds derive
 * different fields from the same token. {@link ClientVersion} carries both schedules and both IVs.
 * <p>
 * <b>Until 2026-08-02 this file did not name a version</b>, because {@link SessionField} chose its
 * key from {@code MGO2SERVER_SESSION_KIT} on a {@code static final} field frozen at class load.
 * The vectors below are disc-key vectors, so they would have failed had that variable ever been set
 * in Maven's environment — and {@code server.env} did set it. They passed only because
 * {@code server.env} is consumed by {@code compose.yaml} and never reaches {@code mvn}. Passing the
 * version explicitly is what makes these pins independent of configuration.
 */
class SessionFieldTest {
	@Test
	void reproducesTheFieldACapturedDiscClientSent() {
		// 1.0. Login reply was "0,122345677,1000000,1888e089ebe181fd"; the client's check-session
		// packet then carried this sixteen-byte field.
		assertThat(SessionField.of(ClientVersion.V1_0, "1888e089ebe181fd"))
			.isEqualTo(HexFormat.of().parseHex("a5a0dd9199494cf00e06ae9dc4655563"));
	}

	@Test
	void reproducesTheFieldACaptured136ClientSent() {
		// 1.36, captured live 2026-08-02. The account's stored field inverted to this token, and
		// the client's 0x3003 carried the value below — the derivation that identified the patch
		// kit as the difference between the builds.
		assertThat(SessionField.stored(ClientVersion.V1_36, "f5a0880bc3a40336"))
			.isEqualTo("8dde80bae7eac2753b7c89139395cb21");
	}

	@Test
	void theTwoBuildsDeriveDifferentFieldsFromTheSameToken() {
		var token = "1888e089ebe181fd";

		// If these ever match, the two key resources have become the same file and one build is
		// silently being served the other's key.
		assertThat(SessionField.stored(ClientVersion.V1_0, token))
			.isNotEqualTo(SessionField.stored(ClientVersion.V1_36, token));
	}

	@Test
	void chainsBlocksSoTheFirstHalfDependsOnlyOnTheFirstEightCharacters() {
		// A second disc capture stored the token prefix "29bfaad0" and produced a field beginning
		// 5f8e0a4b4f7c5372. The rest of that token was not recorded, but because each block is
		// transformed from its own plaintext, the leading eight bytes must still match — which is
		// what makes this an independent confirmation rather than a restatement of the first.
		var field = SessionField.of(ClientVersion.V1_0, "29bfaad0" + "aaaaaaaa");

		assertThat(HexFormat.of().formatHex(field))
			.startsWith("5f8e0a4b4f7c5372");
	}

	@Test
	void storesTheFieldAsHexSoCheckSessionIsAPlainLookup() {
		var token = "1888e089ebe181fd";

		assertThat(SessionField.stored(ClientVersion.V1_0, token))
			.isEqualTo("a5a0dd9199494cf00e06ae9dc4655563")
			.isEqualTo(SessionField.stored(SessionField.of(ClientVersion.V1_0, token)));
	}

	@Test
	void rejectsTokensThatAreNotSixteenCharacters() {
		assertThatThrownBy(() -> SessionField.of(ClientVersion.V1_0, "1888e089"))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("16");
	}
}
