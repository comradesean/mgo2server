package nomad.web.controller;

import org.junit.jupiter.api.Test;

import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.*;

/**
 * The login reply has to satisfy the parser inside the game's own binary, which is stricter than
 * "comma separated" suggests. From MGO2.elf at {@code 0xBB16B0}, the client runs:
 *
 * <pre>
 *   strtol(base 10); expect ','; strtol; expect ','; strtol; expect ','; token
 * </pre>
 *
 * Every one of those steps branches to the failure path — surfacing as 090B:00000001 — if it is
 * not met, and the token is measured and must be exactly 16 characters. A perks field written as
 * an underscore-joined list, which is what mgo2-server sends, fails at the byte after the third
 * integer. That was a real bug; these tests exist so it cannot come back.
 */
public class AuthWebControllerTest {
	/**
	 * Three decimal integers, each followed immediately by a comma, then exactly 16 characters
	 * with no separator or whitespace among them.
	 */
	private static final Pattern CLIENT_GRAMMAR = Pattern.compile("^\\d+,\\d+,\\d+,[^\\s,]{16}$");

	@Test
	public void successReplyMatchesTheGrammarTheClientEnforces() {
		var reply = AuthWebController.successReply(122345677, "84486ef2cca76f51");

		assertThat(reply).matches(CLIENT_GRAMMAR);
	}

	@Test
	public void thirdFieldIsASingleIntegerFollowedByAComma() {
		var reply = AuthWebController.successReply(1, "0123456789abcdef");

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
			.as("byte after the third integer, which the client requires to be a comma")
			.isEqualTo(',');
	}

	@Test
	public void sessionTokenIsExactlySixteenCharacters() {
		var reply = AuthWebController.successReply(7, "0123456789abcdef");

		assertThat(reply.substring(reply.lastIndexOf(',') + 1)).hasSize(16);
	}

	@Test
	public void underscoreJoinedPerksWouldBeRejected() {
		// Guards the regression itself: the reply we used to send, asserted to be invalid.
		var old = "0,122345677,1000000_1000000_1000000,84486ef2cca76f51";

		assertThat(old).doesNotMatch(CLIENT_GRAMMAR);
	}
}
