package mgo2server.common;

import java.util.function.UnaryOperator;

/**
 * Which build of the game client this deployment serves.
 * <p>
 * <b>This enum is the complete list of everything that differs between the two builds.</b> That is
 * its purpose, not a side effect: every version-specific value is a constructor argument, so the
 * whole divergence surface is the table below and nothing can diverge anywhere else without being
 * added here first.
 *
 * <h2>Why this shape</h2>
 * Adding a divergence means adding a column, and a column cannot be added without answering
 * <em>"what does 1.0 do?"</em>. A change made only for {@link #V1_36} therefore shows up as a diff
 * to the {@link #V1_0} row, and that row is pinned literal-by-literal by
 * {@code ClientVersionTest}. Scattering the same values across {@code System.getenv} reads — which
 * is how they arrived — gives neither property.
 * <p>
 * The hazard that motivated this is concrete rather than theoretical. Both values below previously
 * lived on {@code static final} fields initialised from the environment at class load, and
 * {@code SessionFieldTest} and {@code AuthWebControllerTest} pin capture-proven 1.0 vectors while
 * reading those same statics. {@code server.env} sets both to their 1.36 values today; those tests
 * passed only because {@code server.env} is consumed by {@code compose.yaml} and never reaches
 * Maven. Nothing enforced the separation.
 *
 * <h2>Scope</h2>
 * <b>The default is {@link #V1_0}, and an unset environment can never serve 1.36.</b> v1 targets
 * the release-day disc build; see {@code CLAUDE.md} "Target version: release day" and
 * {@code dev/docs/BUILD_1_36.md}.
 */
public enum ClientVersion {
	/** The release-day disc build. What v1 targets, and the default. */
	V1_0("1.0", "1000000", "crypto/session.key", new byte[] {
		(byte) 0xb0, (byte) 0x78, (byte) 0x1d, (byte) 0x53,
		(byte) 0x65, (byte) 0xe3, (byte) 0x91, (byte) 0x0e,
	}, 64),

	/** The 1.36 patch build. Not served by default; see {@code dev/docs/BUILD_1_36.md}. */
	V1_36("1.36", "1000_1000_5000_10000_1000_3000_1000_1000_2000_1000", "crypto/session_136.key",
		new byte[] {
			(byte) 0x35, (byte) 0xd5, (byte) 0xc3, (byte) 0x8e,
			(byte) 0xd0, (byte) 0x11, (byte) 0x0e, (byte) 0xa8,
		}, 0);

	/** The env var that selects a version. */
	public static final String ENV = "MGO2SERVER_CLIENT_VERSION";

	private final String label;

	private final String loginPerks;

	private final String sessionKeyResource;

	private final byte[] sessionIv;

	private final int hubEntryTextLength;

	ClientVersion(String label, String loginPerks, String sessionKeyResource, byte[] sessionIv,
			int hubEntryTextLength) {
		this.label = label;
		this.loginPerks = loginPerks;
		this.sessionKeyResource = sessionKeyResource;
		this.sessionIv = sessionIv;
		this.hubEntryTextLength = hubEntryTextLength;
	}

	/** How this version is written in configuration: {@code "1.0"} or {@code "1.36"}. */
	public String label() {
		return label;
	}

	/**
	 * The third field of the login reply, whose <b>grammar differs between the builds</b>.
	 * <p>
	 * <b>1.0 requires exactly one integer.</b> Its parser (disc {@code 0xBB16B0}) runs three
	 * {@code strtol} calls each followed by a literal comma, and at {@code 0xBB172C} branches to the
	 * failure path unless the byte after the third integer is {@code ','}.
	 * <p>
	 * <b>1.36 requires ten integers separated by nine underscores</b>, or an empty field. Its parser
	 * reads an integer then requires {@code '_'} (1.36 {@code 0xD6EE70}); seeing {@code ','} it
	 * jumps to the failure label and the client raises {@code 090B:00000001}, "Unable to connect to
	 * server". An empty field is accepted and leaves the client's table at its own defaults.
	 * <p>
	 * <b>There is no value valid for both.</b> The 1.36 values mirror the table the binary itself
	 * ships at {@code 0x122A5D0} rather than the {@code 1000000} an upstream server sends, which is
	 * 100-1000x them.
	 * <p>
	 * Historical note worth keeping, because {@code CLAUDE.md} cites it as the project's cautionary
	 * tale: the inherited {@code Array(10).fill("1000000").join("_")} was called "transcribed
	 * correctly and genuinely wrong for this client". Half of that is now corrected — the
	 * <em>shape</em> was right, for a later build. Only the magnitude was wrong.
	 */
	public String loginPerks() {
		return loginPerks;
	}

	/**
	 * Classpath resource holding the Blowfish schedule for the check-session transform.
	 *
	 * @see #sessionIv() for why this is tied to the version rather than to the install
	 */
	public String sessionKeyResource() {
		return sessionKeyResource;
	}

	/**
	 * First eight bytes of the derived context, <b>paired with {@link #sessionKeyResource()}</b>.
	 * <p>
	 * The IV and the 56-byte key are two halves of one 64-byte derived context and must switch
	 * together; mixing one build's IV with another's schedule silently produces a wrong field rather
	 * than an error. Keeping both on this enum is what makes that impossible.
	 *
	 * <h2>Strictly this follows the INSTALL, not the executable</h2>
	 * The key is not compiled into the game. A registration function — disc {@code 0x2FA28}, 1.36
	 * {@code 0x2E4A0}, <em>byte-identical in both builds</em> — opens a file named {@code kit},
	 * reads 64 bytes and registers them as crypto mode 6. The disc ships one at
	 * {@code PS3_GAME/USRDIR/o/kit}; the 1.36 patch ships another at {@code o/dl/p/kit}, which
	 * <b>shadows</b> it. Decrypting each with the master context in the image reproduces the two
	 * schedules shipped here; the disc file reproduces {@code crypto/session.key} bit for bit, which
	 * is the control.
	 * <p>
	 * So a 1.0 executable run against a patched install would want 1.0 perks with the patch key, and
	 * <b>this enum cannot express that</b>. It is tied to the version anyway because the patch
	 * installs both together, so the combination only arises from deliberate mixing. <b>If it ever
	 * bites, add an override then</b> — building one now would be infrastructure for a hypothetical.
	 */
	public byte[] sessionIv() {
		return sessionIv.clone();
	}

	/**
	 * Bytes of per-lobby text in a {@code 0x4902} hub-list entry, straight after the 16-byte name.
	 * <p>
	 * <b>1.0 reads 64 bytes here; 1.36 reads none.</b> The disc parser ({@code 0xD47E18}) has one
	 * {@code li r5,64} feeding the raw-copy primitive at {@code 0xD48034}-{@code 0xD48038}; 1.36's
	 * ({@code 0xF15B30}) has <b>zero</b> — its only raw copies are {@code li r5,1} and
	 * {@code li r5,16}, and the read after the name is already the u32 open time. So the entry is
	 * <b>99 bytes on 1.0 and 35 on 1.36</b>.
	 * <p>
	 * It is coherent rather than arbitrary: the text block had exactly one consumer in the disc
	 * build, the subtype-5 branch at {@code 0x890504}, and 1.36 deleted the subtype-5 scan entirely.
	 * The field's only reader went away and the field went with it.
	 *
	 * <h2>Sending the wrong length does not error — it silently shifts every later entry</h2>
	 * The readers bound-check the 1024-byte receive buffer, not the payload length, so a
	 * misaligned entry is never rejected. Sending 99-byte entries to 1.36 was observed live on
	 * 2026-08-03: the client read our 495-byte payload at 35-byte stride, believed it had
	 * <b>15</b> entries, and produced a Lobby Select with Automatching working (entry 0's first 26
	 * bytes coincide between the layouts), <b>Free Battle present but dead</b> — its phantom entry's
	 * {@code lobbyId} landed past the payload end, so the gate lookup failed and the sub-list
	 * bounced — and <b>no Training row at all</b>, because nothing in the misparse had subtype 7
	 * or 8.
	 *
	 * <h2>The reference servers were right, for a build we do not target</h2>
	 * {@code mgo2_cmd_4902_s2c.ksy} records that "both reference servers write 35" and treats it as
	 * a bug. They were correct — for 1.36-era clients. This is the second time in one night that an
	 * "upstream is wrong" note turned out to be "upstream targets a different build"; the login
	 * perks field was the first. See {@link #loginPerks()}.
	 */
	public int hubEntryTextLength() {
		return hubEntryTextLength;
	}

	public boolean isDisc() {
		return this == V1_0;
	}

	public boolean is136() {
		return this == V1_36;
	}

	/**
	 * Parses a configured value.
	 * <p>
	 * Case-insensitive and trimmed, and the message names the variable, lists both alternatives and
	 * echoes the offending value — the shape {@code AutomatchPolicy.Mode.of} established, because an
	 * operator reading a container's death message should not have to guess the spelling.
	 * <p>
	 * Matching is on {@link #label()} rather than {@link #name()}: {@code 1.0} and {@code 1.36} are
	 * not legal Java identifiers.
	 *
	 * @param name the environment variable's name, so the error can name it
	 */
	public static ClientVersion of(String value, String name) {
		for (var version : values()) {
			if (version.label.equalsIgnoreCase(value.trim())) {
				return version;
			}
		}
		throw new IllegalArgumentException(
			name + " must be one of 1.0 or 1.36, got: " + value);
	}

	/** Reads the version from a lookup, defaulting to {@link #V1_0} when absent or blank. */
	public static ClientVersion from(UnaryOperator<String> env) {
		var value = env.apply(ENV);
		return value == null || value.isBlank() ? V1_0 : of(value, ENV);
	}
}
