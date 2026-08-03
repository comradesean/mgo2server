package mgo2server.web.controller;

import mgo2server.common.ClientVersion;
import org.junit.jupiter.api.Test;

import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.*;

/**
 * The login reply has to satisfy the parser inside the game's own binary, which is stricter than
 * "comma separated" suggests — and <b>the two client builds enforce different grammars</b>.
 *
 * <p><b>1.0 (disc), parser {@code 0xBB16B0}:</b>
 * <pre>
 *   strtol(base 10); expect ','; strtol; expect ','; strtol; expect ','; token
 * </pre>
 * The byte after the third integer is loaded at {@code 0xBB172C} and must be {@code ','}.
 *
 * <p><b>1.36, parser {@code 0xD6EE34}-{@code 0xD6F07C}:</b> the third field is <em>ten</em>
 * integers. It reads an integer then requires {@code '_'} at {@code 0xD6EE70} — nine times — and
 * only the tenth is followed by {@code ','}. An empty third field is also accepted
 * ({@code 0xD6EE3C} jumps straight to the token).
 *
 * <p>Every failure surfaces as {@code 090B:00000001}. <b>There is no value valid for both</b>,
 * which is why the grammar lives on {@link ClientVersion} and each test below names its version
 * explicitly rather than inheriting one from the environment.
 *
 * <p><b>Corrected 2026-08-02.</b> This file previously asserted that an underscore-joined perks
 * field "would be rejected", full stop, calling it "the reply we used to send, asserted to be
 * invalid". That is true only for 1.0. The underscore form is exactly what 1.36 <em>requires</em> —
 * so the inherited {@code Array(10).fill("1000000").join("_")} that {@code CLAUDE.md} cites as the
 * project's cautionary tale had the right <em>shape</em> for a later build, and only the magnitude
 * wrong. The test is kept, renamed, and now asserts both directions.
 */
public class AuthWebControllerTest {
	/**
	 * 1.0: three decimal integers, each followed immediately by a comma, then exactly 16 characters
	 * with no separator or whitespace among them.
	 */
	private static final Pattern V1_0_GRAMMAR = Pattern.compile("^\\d+,\\d+,\\d+,[^\\s,]{16}$");

	/** 1.36: ten integers separated by nine underscores, then the token. */
	private static final Pattern V1_36_GRAMMAR =
		Pattern.compile("^\\d+,\\d+,\\d+(_\\d+){9},[^\\s,]{16}$");

	@Test
	public void v1_0ReplyMatchesTheGrammarThatBuildEnforces() {
		var reply = AuthWebController.successReply(ClientVersion.V1_0, 122345677, "84486ef2cca76f51");

		assertThat(reply).matches(V1_0_GRAMMAR);
	}

	@Test
	public void v1_36ReplyMatchesTheGrammarThatBuildEnforces() {
		var reply = AuthWebController.successReply(ClientVersion.V1_36, 122345677, "84486ef2cca76f51");

		assertThat(reply).matches(V1_36_GRAMMAR);
	}

	@Test
	public void neitherGrammarAcceptsTheOthersReply() {
		var disc = AuthWebController.successReply(ClientVersion.V1_0, 1, "0123456789abcdef");
		var patch = AuthWebController.successReply(ClientVersion.V1_36, 1, "0123456789abcdef");

		// The whole reason the version is a toggle and not a default: no single value serves both.
		assertThat(disc).doesNotMatch(V1_36_GRAMMAR);
		assertThat(patch).doesNotMatch(V1_0_GRAMMAR);
	}

	@Test
	public void v1_0ThirdFieldIsASingleIntegerFollowedByAComma() {
		var reply = AuthWebController.successReply(ClientVersion.V1_0, 1, "0123456789abcdef");

		// The exact check at 0xBB172C: load the byte after the third integer, require ','.
		var thirdFieldStart = reply.indexOf(',', reply.indexOf(',') + 1) + 1;
		var afterThirdInteger = thirdFieldStart;
		while (afterThirdInteger < reply.length() && Character.isDigit(reply.charAt(afterThirdInteger))) {
			afterThirdInteger++;
		}

		assertThat(afterThirdInteger)
			.as("third field must contain at least one digit")
			.isGreaterThan(thirdFieldStart);
		assertThat(reply.charAt(afterThirdInteger))
			.as("byte after the third integer, which 1.0 requires to be a comma")
			.isEqualTo(',');
	}

	@Test
	public void v1_36ThirdFieldIsTenIntegersWithNineUnderscores() {
		var reply = AuthWebController.successReply(ClientVersion.V1_36, 1, "0123456789abcdef");
		var third = reply.split(",")[2];

		// 1.36 reads an integer then requires '_' (0xD6EE70), nine times over.
		assertThat(third.split("_", -1))
			.as("ten integers, so nine underscores")
			.hasSize(10);
		assertThat(third.chars().filter(c -> c == '_').count()).isEqualTo(9);
	}

	@Test
	public void sessionTokenIsExactlySixteenCharactersForBothBuilds() {
		for (var version : ClientVersion.values()) {
			var reply = AuthWebController.successReply(version, 7, "0123456789abcdef");

			assertThat(reply.substring(reply.lastIndexOf(',') + 1))
				.as("token length for %s", version.label())
				.hasSize(16);
		}
	}
}
