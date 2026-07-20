package mgo2server.common;

/**
 * Character name rules.
 * <p>
 * These come from three different authorities and it is worth keeping them apart, because only the
 * first is binding (see the evidence hierarchy in {@code CLAUDE.md}):
 * <ul>
 *   <li><b>Protocol.</b> {@link #MAX_LENGTH} is fixed by the wire format — name fields are 16
 *       bytes in the character list (0x3049) and character info (0x4101), and the client will not
 *       send more.</li>
 *   <li><b>Presentation.</b> {@code VALID_CHARACTERS} is claimed to be what the game can render.
 *       That claim is inherited from Nomad's {@code Util.checkName} and has <em>not</em> been
 *       checked against the binary's font tables. Treat a rejection here as unproven.</li>
 *   <li><b>Operator policy.</b> The reserved prefixes and names are choices, not protocol. The
 *       game reserves nothing.</li>
 * </ul>
 * Names are also the mechanism behind soft deletion: a deleted character is renamed to a reserved
 * prefix so its old name becomes available again. That is ours and is genuinely load-bearing.
 */
public final class CharacterNames {
	public static final int MAX_LENGTH = 16;

	/**
	 * Prefix used to park the names of deleted characters; players may not use it. Load-bearing:
	 * soft deletion depends on it, so a player taking this prefix would collide with a tombstone.
	 */
	public static final String DELETED_PREFIX = ":#";

	/**
	 * Operator policy, not protocol. The {@code GM} variants keep staff-looking names out of
	 * player hands and are inherited from Nomad; the game itself reserves nothing.
	 */
	private static final String[] RESERVED_PREFIXES = { DELETED_PREFIX, "GM_", "GM-", "GM.", "GM," };

	/**
	 * Operator policy, and empty by design.
	 * <p>
	 * This used to contain {@code "SaveMGO"} — another server's own name, inherited wholesale from
	 * their {@code Util.checkName}. It protected their branding, not anything of ours, and no
	 * player of this server has a reason to be refused it. Kept as a hook for a future operator to
	 * populate rather than deleted, since the machinery around it is sound.
	 */
	private static final String[] RESERVED_NAMES = {};

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

		// Case-insensitively, for the same reason leading spaces are refused below: the point is to
		// stop a player looking like staff, and "gm_snake" looks exactly as much like staff as
		// "GM_Snake". This used to be a case-sensitive startsWith, which the reserved-name check
		// beside it was not -- so the prefix policy was bypassable by lowercasing it.
		var folded = name.toLowerCase(java.util.Locale.ROOT);
		for (var prefix : RESERVED_PREFIXES) {
			if (folded.startsWith(prefix.toLowerCase(java.util.Locale.ROOT))) {
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
