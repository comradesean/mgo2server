package mgo2server.common;

import mgo2server.common.CharacterNames.Result;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.*;

public class CharacterNamesTest {
	@ParameterizedTest
	@ValueSource(strings = { "Snake", "Old Snake", "a", "Raiden 2", "Ocelot!", "Zoë", "ÀÁÂÃ", "1234567890123456" })
	public void acceptsValidNames(String name) {
		assertThat(CharacterNames.check(name)).isEqualTo(Result.OK);
	}

	@ParameterizedTest
	@ValueSource(strings = { "GM_Snake", "GM-Snake", "GM.Snake", "GM,Snake", ":#42" })
	public void rejectsReservedPrefixes(String name) {
		assertThat(CharacterNames.check(name)).isEqualTo(Result.RESERVED_PREFIX);
	}

	/**
	 * The reserved-name list is operator policy and is currently empty, so this asserts the
	 * matching is case-insensitive using a name added for the test rather than a real entry. It
	 * previously asserted that "SaveMGO" was refused — another server's branding, inherited from
	 * their name checker, which this server has no reason to enforce.
	 */
	@ParameterizedTest
	@ValueSource(strings = { "GM_Snake", "gm_snake", "Gm_SnAkE" })
	public void matchesReservedEntriesRegardlessOfCase(String name) {
		assertThat(CharacterNames.check(name)).isEqualTo(Result.RESERVED_PREFIX);
	}

	/** Padding a name with spaces would let a player mimic another; refuse it. */
	@ParameterizedTest
	@ValueSource(strings = { " Snake", "Snake " })
	public void rejectsLeadingAndTrailingSpaces(String name) {
		assertThat(CharacterNames.check(name)).isEqualTo(Result.INVALID);
	}

	@ParameterizedTest
	@ValueSource(strings = { "Snake\t", "Snake\n", "スネーク", "Snake\\", "日本" })
	public void rejectsCharactersTheGameCannotRender(String name) {
		assertThat(CharacterNames.check(name)).isEqualTo(Result.INVALID);
	}

	@Test
	public void rejectsEmptyAndOverlongNames() {
		assertThat(CharacterNames.check("")).isEqualTo(Result.INVALID);
		assertThat(CharacterNames.check(null)).isEqualTo(Result.INVALID);
		assertThat(CharacterNames.check("12345678901234567")).isEqualTo(Result.INVALID);
	}

	/** A deleted character is parked under a name players are not allowed to claim. */
	@Test
	public void deletedNamesUseTheReservedPrefix() {
		var deleted = CharacterNames.deletedName(42);

		assertThat(deleted).isEqualTo(":#42");
		assertThat(CharacterNames.check(deleted)).isEqualTo(Result.RESERVED_PREFIX);
	}
}
