package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.CharaSettings;

import java.nio.charset.StandardCharsets;

/**
 * Packs a character's gameplay and interface settings into the 0x4120 payload.
 * <p>
 * Almost every setting shares a byte with another, and several are stored one higher than they go
 * on the wire — the speed sliders are 1-based to the player and 0-based to the client, while the
 * music volume runs the other way. Those adjustments are the whole reason this is a separate,
 * tested class: an off-by-one here moves a slider by one notch, which nothing would ever fail on.
 */
public final class GameplaySettingsWriter {
	public static final int PAYLOAD_SIZE = 0x150;

	private static final int CODEC_NAME_LENGTH = 64;

	/**
	 * The 32 bytes closing {@code 0x4120} — the player's <b>Filter Host List</b>, <b>Sort Host
	 * List</b> and <b>Player Search</b> preferences. All zeros: no filtering, sort by name ascending,
	 * partial and case-insensitive search.
	 *
	 * <p><b>This used to be an inherited constant, and it was hiding games.</b> The old value
	 * {@code 01 00 10 00 00 00 00 10 11 10 …} was reproduced byte for byte from the original server
	 * with the note "undocumented", and once the disc labels were extracted (2026-07-29) it turned
	 * out to say three things we would never have chosen:
	 * <ul>
	 * <li><b>Filter = Enabled</b> (b0lo) — the master switch on;</li>
	 * <li><b>Password Lock = "Display Only Disabled"</b> (b2hi) — <b>every password-locked game
	 * hidden from every player's browser</b>;</li>
	 * <li><b>Match Case = Case Sensitive</b> (b7hi) — player search failing on the wrong capital.</li>
	 * </ul>
	 * Everything else was already neutral, which is what made the three stand out. The client's own
	 * default for this whole region is zero — its validator memsets 33 bytes at {@code 0x9472E8} —
	 * so zeros are the game's answer, not merely ours.
	 *
	 * <p><b>The map</b>, extracted from {@code lobby/scenerio.gcx} string set
	 * {@code $strres:9789 $strres:11033} and confirmed against each nibble's own getter, help-string
	 * ids and value labels — two independent code paths per field. Bytes 0..7 are sixteen 4-bit
	 * fields; {@code 0} means "----", i.e. no filtering, for every filter row:
	 *
	 * <pre>
	 * b0lo Filter (master)      0 Disabled | 1 Enabled
	 * b0hi (no callers)         b1lo (no callers)      -- dead nibbles, not merely unnamed
	 * b1hi Number of Players    0 ---- | 1 Display Only Open Games
	 * b2lo Level Limit          0 ---- | 1 Only Not Restricted | 2 Only Restricted
	 * b2hi Password Lock        0 ---- | 1 Only Disabled | 2 Only Enabled
	 * b3lo Weapon Restrictions  0 ---- | 1 Only Not Restricted | 2 Only Restricted
	 * b3hi Friendly Fire        0 ---- | 1 Only Disabled | 2 Only Enabled
	 * b4lo Voice Chat           0 ---- | 1 Only Disabled | 2 Only Enabled
	 * b4hi Network Quality      0 ---- | 1 Only Good | 2 Normal or Better
	 * b5lo Friends              0 ---- | 1 Only When Present
	 * b5hi Blocked Players      0 ---- | 1 Will Not Display
	 * b6lo Sort key             0 Name | 1 Players Joined | 2 Network Quality
	 * b6hi Sort order           0 Ascending | 1 Descending
	 * b7lo Search match         0 Partial and Exact | 1 Exact Only
	 * b7hi Search case          0 Case Insensitive | 1 Case Sensitive
	 * </pre>
	 *
	 * <p>Screens: FILTERING SETTING ({@code 0x9084BC}), SORT HOST LIST ({@code 0x90C010}) and PLAYER
	 * SEARCH ({@code 0x90E264}) — the last being the {@code ST1_ON-OFF}/{@code ST2_ON-OFF} widgets.
	 * The ELF also carries a developer name table at {@code 0xE0D548}-{@code 0xE0DBF0} naming these
	 * same fields.
	 *
	 * <p><b>Bytes 8..31 have no reader at all</b> and stay zero.
	 *
	 * <p><b>A correction to an earlier reading:</b> these nibbles were once documented with a clamp
	 * table (b6lo ≤ 1, b6hi forced to 0). That was wrong — the setters {@code 0x906DC8} and
	 * {@code 0x906DE0} contain no clamp, they mask to four bits; b6lo is genuinely three-state,
	 * cycling 0..2 at {@code 0x90C4C0}, and b6hi is a live toggle at {@code 0x90C694}.
	 *
	 * <p>These are per-player preferences, so a future feature is persisting them per character
	 * rather than pushing one set to everybody. The client does not send them back in
	 * {@code 0x4110} — its write-back is 304 bytes, this packet minus exactly these 32 — so
	 * whatever persistence existed used some other path.
	 */
	private static final byte[] TRAILER = new byte[32];

	private GameplaySettingsWriter() {
	}

	/** Speeds are shown 1-based but sent 0-based. */
	private static int speed(int value) {
		return (value - 1) & 0b1111;
	}

	public static int privacyA(CharaSettings s) {
		var value = 1;
		value |= (s.getOnlineStatusMode() & 0b11) << 4;
		value |= s.isEmailFriendsOnly() ? 0b01000000 : 0;
		return value;
	}

	public static int privacyB(CharaSettings s) {
		var value = 0;
		value |= s.isReceiveNotices() ? 0b1 : 0;
		value |= s.isReceiveInvites() ? 0b10000 : 0;
		return value;
	}

	public static int normalView(CharaSettings s) {
		var value = 0;
		value |= s.isNormalViewVerticalInvert() ? 0b1 : 0;
		value |= s.isNormalViewHorizontalInvert() ? 0b10 : 0;
		value |= speed(s.getNormalViewSpeed()) << 4;
		return value;
	}

	public static int shoulderView(CharaSettings s) {
		var value = 0;
		value |= s.isShoulderViewVerticalInvert() ? 0b1 : 0;
		value |= s.isShoulderViewHorizontalInvert() ? 0b10 : 0;
		value |= speed(s.getShoulderViewSpeed()) << 4;
		return value;
	}

	public static int firstView(CharaSettings s) {
		var value = 0;
		value |= s.isFirstViewVerticalInvert() ? 0b1 : 0;
		value |= s.isFirstViewHorizontalInvert() ? 0b10 : 0;
		value |= s.isFirstViewPlayerDirection() ? 0b100 : 0;
		value |= speed(s.getFirstViewSpeed()) << 4;
		return value;
	}

	public static int firstViewMemory(CharaSettings s) {
		return s.isFirstViewMemory() ? 0b10 : 0;
	}

	public static int radar(CharaSettings s) {
		var value = 0;
		value |= s.isRadarLockNorth() ? 0b1 : 0;
		value |= s.isRadarFloorHide() ? 0b10000 : 0;
		return value;
	}

	public static int hudDisplay(CharaSettings s) {
		var value = s.getHudDisplaySize() & 0b11;
		value |= s.isHudHideNameTags() ? 0b10000 : 0;
		return value;
	}

	/** Lock-on shares a byte with the music volume, which is sent one higher than it is stored. */
	public static int lockOnAndBgm(CharaSettings s) {
		var value = s.isLockOnEnabled() ? 0b1 : 0;
		value |= ((s.getBgmVolume() + 1) & 0b1111) << 4;
		return value;
	}

	public static int weaponSwitchAB(CharaSettings s) {
		return (s.getWeaponSwitchA() & 0b1111) | ((s.getWeaponSwitchB() & 0b1111) << 4);
	}

	public static int weaponSwitchC(CharaSettings s) {
		return s.getWeaponSwitchC() & 0b1111;
	}

	public static int weaponSwitchRecall(CharaSettings s) {
		return (s.getWeaponSwitchBefore() & 0b1111) | ((s.getWeaponSwitchNow() & 0b1111) << 4);
	}

	public static int switchModes(CharaSettings s) {
		return (s.getWeaponSwitchMode() & 0b1111) | ((s.getItemSwitchMode() & 0b1111) << 4);
	}

	public static int voiceChatA(CharaSettings s) {
		return 1 | ((s.getVoiceChatRecognitionLevel() & 0b1111) << 4);
	}

	public static int voiceChatB(CharaSettings s) {
		return (s.getVoiceChatVolume() & 0b1111) | ((s.getHeadsetVolume() & 0b1111) << 4);
	}

	public static void write(ByteBuf buffer, CharaSettings s) {
		var start = buffer.writerIndex();

		buffer.writeByte(privacyA(s))
			.writeByte(normalView(s))
			.writeByte(shoulderView(s))
			.writeByte(firstView(s))
			.writeByte(speed(s.getViewChangeSpeed()))
			.writeZero(6)
			.writeByte(switchModes(s))
			.writeZero(1)
			.writeByte(voiceChatA(s))
			.writeByte(voiceChatB(s))
			.writeByte(weaponSwitchAB(s))
			.writeByte(weaponSwitchC(s))
			.writeByte(weaponSwitchRecall(s))
			.writeByte(firstViewMemory(s))
			.writeByte(privacyB(s))
			.writeByte(lockOnAndBgm(s))
			.writeByte(radar(s))
			.writeByte(hudDisplay(s))
			.writeZero(9)
			.writeByte(s.getCodec1a()).writeByte(s.getCodec1b())
			.writeByte(s.getCodec1c()).writeByte(s.getCodec1d())
			.writeByte(s.getCodec2a()).writeByte(s.getCodec2b())
			.writeByte(s.getCodec2c()).writeByte(s.getCodec2d())
			.writeByte(s.getCodec3a()).writeByte(s.getCodec3b())
			.writeByte(s.getCodec3c()).writeByte(s.getCodec3d())
			.writeByte(s.getCodec4a()).writeByte(s.getCodec4b())
			.writeByte(s.getCodec4c()).writeByte(s.getCodec4d());

		BufferUtil.writeString(buffer, s.getCodec1Name(), StandardCharsets.ISO_8859_1, CODEC_NAME_LENGTH);
		BufferUtil.writeString(buffer, s.getCodec2Name(), StandardCharsets.ISO_8859_1, CODEC_NAME_LENGTH);
		BufferUtil.writeString(buffer, s.getCodec3Name(), StandardCharsets.ISO_8859_1, CODEC_NAME_LENGTH);
		BufferUtil.writeString(buffer, s.getCodec4Name(), StandardCharsets.ISO_8859_1, CODEC_NAME_LENGTH);

		// All zeros now, deliberately — see TRAILER. The experiment switch no longer needs a branch
		// here: bytes 0-7 are understood and neutral by choice rather than by accident, and 8..31
		// have no reader.
		buffer.writeBytes(TRAILER);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Gameplay settings payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
