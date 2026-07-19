package nomad.common;

/**
 * Character name rules, ported from Nomad's {@code Util.checkName} and the checks in
 * {@code Users.createCharacter}.
 * <p>
 * The permitted character set is what the game can actually render: printable Latin-1 minus a few
 * gaps. Names are also the mechanism behind soft deletion — a deleted character is renamed to a
 * reserved prefix so its old name becomes available again.
 */
public final class CharacterNames {
	public static final int MAX_LENGTH = 16;

	/** Prefix used to park the names of deleted characters; players may not use it. */
	public static final String DELETED_PREFIX = ":#";

	private static final String[] RESERVED_PREFIXES = { DELETED_PREFIX, "GM_", "GM-", "GM.", "GM," };

	private static final String[] RESERVED_NAMES = { "SaveMGO" };

	private static final String VALID_CHARACTERS =
		" !\"#$%&'()*+,-./0123456789:;<=>?@"
			+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`"
			+ "abcdefghijklmnopqrstuvwxyz{|}~"
			+ "¡¢£¥¦ª«°µº»¿"
			+ "ÀÁÂÃÄÅÆÇÈÉÊË"
			+ "ÌÍÎÏÑÒÓÔÕÖ×Ø"
			+ "ÙÚÛÜÝß"
			+ "àáâãäåæçèéêë"
			+ "ìíîïñòóôõö÷ø"
			+ "ùúûüýÿ";

	/** Why a name was refused, mapping onto the error the client is sent. */
	public enum Result {
		OK,
		INVALID,
		RESERVED_PREFIX,
		RESERVED_NAME,
	}

	private CharacterNames() {
	}

	public static Result check(String name) {
		if (name == null || name.isEmpty() || name.length() > MAX_LENGTH) {
			return Result.INVALID;
		}

		for (var prefix : RESERVED_PREFIXES) {
			if (name.startsWith(prefix)) {
				return Result.RESERVED_PREFIX;
			}
		}

		for (var reserved : RESERVED_NAMES) {
			if (name.equalsIgnoreCase(reserved)) {
				return Result.RESERVED_NAME;
			}
		}

		// Leading and trailing spaces are refused so names cannot be padded to impersonate.
		if (name.charAt(0) == ' ' || name.charAt(name.length() - 1) == ' ') {
			return Result.INVALID;
		}

		for (var i = 0; i < name.length(); i++) {
			if (VALID_CHARACTERS.indexOf(name.charAt(i)) < 0) {
				return Result.INVALID;
			}
		}

		return Result.OK;
	}

	/** The placeholder name a deleted character is parked under, freeing its real name. */
	public static String deletedName(long charaId) {
		return DELETED_PREFIX + charaId;
	}
}
