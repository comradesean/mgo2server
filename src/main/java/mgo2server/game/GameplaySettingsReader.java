package mgo2server.game;

import io.netty.buffer.ByteBuf;
import mgo2server.common.model.CharaSettings;

import java.nio.charset.StandardCharsets;

/**
 * Parses {@code 0x4110}, the client's gameplay-options write-back, into {@link CharaSettings}.
 *
 * <p><b>Why this exists.</b> Every Gameplay Option — Lock-On, view speeds, inverts, HUD size,
 * volumes, codec entries — reverted to its stored value after each session, because the client's
 * write-back was acknowledged and thrown away. {@code 0x4120} was already sending the stored row
 * correctly, so the round trip was broken on exactly one side.
 *
 * <p><b>The layout is not guessed.</b> {@code 0x4110} is <b>304 bytes</b>, which is
 * {@code 0x4120}'s payload truncated at {@code 0x130}: the same 48-byte settings header and the
 * same four 64-byte codec names, without the 32-byte list-preferences trailer. That is read from
 * the builder at {@code 0xD3BFC0} — one 48-byte blob write, then a four-pass loop of 64-byte
 * writes, then the seal. So this class is {@link GameplaySettingsWriter} run backwards, and the
 * two must be changed together.
 *
 * <p><b>Unmapped bytes are left alone rather than zeroed.</b> The header has a 6-byte gap at
 * {@code +5}, a byte at {@code +12} and a 9-byte gap at {@code +21} that the writer sends as zero
 * and nothing has identified. Reading them into nowhere is correct; inventing a meaning for them
 * is how this project has previously lost days.
 */
public final class GameplaySettingsReader {

	/** {@code 0x130}. The whole payload: 48-byte header plus four 64-byte codec names. */
	public static final int PAYLOAD_SIZE = 0x130;

	private static final int CODEC_NAME_LENGTH = 64;

	private GameplaySettingsReader() {
	}

	/**
	 * Applies a {@code 0x4110} payload to {@code settings}, mutating it in place.
	 *
	 * <p>Returns false and changes nothing when the payload is short — a truncated write-back is a
	 * protocol violation, and half-applying it would persist a mixture of the player's settings and
	 * whatever the buffer ran out on.
	 */
	public static boolean apply(ByteBuf payload, CharaSettings settings) {
		if (payload.readableBytes() < PAYLOAD_SIZE) {
			return false;
		}
		var base = payload.readerIndex();

		var privacyA = payload.getUnsignedByte(base);
		settings.setOnlineStatusMode((privacyA >> 4) & 0b11);
		settings.setEmailFriendsOnly((privacyA & 0b01000000) != 0);

		var normalView = payload.getUnsignedByte(base + 1);
		settings.setNormalViewVerticalInvert((normalView & 0b1) != 0);
		settings.setNormalViewHorizontalInvert((normalView & 0b10) != 0);
		settings.setNormalViewSpeed(speed(normalView >> 4));

		var shoulderView = payload.getUnsignedByte(base + 2);
		settings.setShoulderViewVerticalInvert((shoulderView & 0b1) != 0);
		settings.setShoulderViewHorizontalInvert((shoulderView & 0b10) != 0);
		settings.setShoulderViewSpeed(speed(shoulderView >> 4));

		var firstView = payload.getUnsignedByte(base + 3);
		settings.setFirstViewVerticalInvert((firstView & 0b1) != 0);
		settings.setFirstViewHorizontalInvert((firstView & 0b10) != 0);
		settings.setFirstViewCameraDirection((firstView & 0b100) != 0);
		settings.setFirstViewSpeed(speed(firstView >> 4));

		settings.setViewChangeSpeed(speed(payload.getUnsignedByte(base + 4)));

		// +5..+10 unmapped, +12 unmapped.
		var switchModes = payload.getUnsignedByte(base + 11);
		settings.setWeaponSwitchMode(switchModes & 0b1111);
		settings.setItemSwitchMode((switchModes >> 4) & 0b1111);

		// Three fields share this byte, and until 2026-08-04 only the top one was read back — so the
		// two audio-output-device choices were discarded on every write-back and reset on the next
		// login. See GameplaySettingsWriter#voiceChatA.
		var voiceChatA = payload.getUnsignedByte(base + 13);
		settings.setVoiceChatOutputDevice(voiceChatA & 0b11);
		settings.setCodecOutputDevice((voiceChatA >> 2) & 0b11);
		settings.setVoiceChatRecognitionLevel((voiceChatA >> 4) & 0b1111);

		var voiceChatB = payload.getUnsignedByte(base + 14);
		settings.setVoiceChatVolume(voiceChatB & 0b1111);
		settings.setHeadsetVolume((voiceChatB >> 4) & 0b1111);

		var weaponSwitchAB = payload.getUnsignedByte(base + 15);
		settings.setWeaponSwitchA(weaponSwitchAB & 0b1111);
		settings.setWeaponSwitchB((weaponSwitchAB >> 4) & 0b1111);

		// The quick-change dispatcher at 0x9C9070 reads three values in Cycle Mode, two in Recall
		// Mode and one in Toggle Mode — so +16 high is Recall's "Now" (read at 0x9C9E74) and +17
		// high is Toggle's single weapon (read at 0x9C9094). Both were mishandled until 2026-08-04.
		var cycleC = payload.getUnsignedByte(base + 16);
		settings.setWeaponSwitchC(cycleC & 0b1111);
		settings.setWeaponSwitchNow((cycleC >> 4) & 0b1111);

		var recall = payload.getUnsignedByte(base + 17);
		settings.setWeaponSwitchBefore(recall & 0b1111);
		settings.setWeaponSwitchToggle((recall >> 4) & 0b1111);

		// Low nibble compared against 1, not bit 1: 0 Enabled, 1 Disabled.
		settings.setFirstViewMemoryDisabled((payload.getUnsignedByte(base + 18) & 0b1111) != 0);

		var privacyB = payload.getUnsignedByte(base + 19);
		settings.setReceiveNotices((privacyB & 0b1) != 0);
		settings.setReceiveInvites((privacyB & 0b10000) != 0);

		// Lock-on shares a byte with the music volume, which travels one HIGHER than it is stored —
		// so the inverse subtracts one. Getting this backwards would drift the volume by one on
		// every single round trip, which is exactly the kind of slow corruption that looks like a
		// client bug.
		var lockOnAndBgm = payload.getUnsignedByte(base + 20);
		settings.setLockOnEnabled((lockOnAndBgm & 0b1) != 0);
		settings.setBgmVolume(Math.max(0, ((lockOnAndBgm >> 4) & 0b1111) - 1));

		var radar = payload.getUnsignedByte(base + 21);
		settings.setRadarLockNorth((radar & 0b1) != 0);
		settings.setRadarFloorHide((radar & 0b10000) != 0);

		var hud = payload.getUnsignedByte(base + 22);
		settings.setHudDisplaySize(hud & 0b11);
		settings.setHudHideNameTags((hud & 0b10000) != 0);

		// +23..+31 unmapped. Codec shortcut entries are four bytes each, at +32.
		settings.setCodec1a(payload.getUnsignedByte(base + 32));
		settings.setCodec1b(payload.getUnsignedByte(base + 33));
		settings.setCodec1c(payload.getUnsignedByte(base + 34));
		settings.setCodec1d(payload.getUnsignedByte(base + 35));
		settings.setCodec2a(payload.getUnsignedByte(base + 36));
		settings.setCodec2b(payload.getUnsignedByte(base + 37));
		settings.setCodec2c(payload.getUnsignedByte(base + 38));
		settings.setCodec2d(payload.getUnsignedByte(base + 39));
		settings.setCodec3a(payload.getUnsignedByte(base + 40));
		settings.setCodec3b(payload.getUnsignedByte(base + 41));
		settings.setCodec3c(payload.getUnsignedByte(base + 42));
		settings.setCodec3d(payload.getUnsignedByte(base + 43));
		settings.setCodec4a(payload.getUnsignedByte(base + 44));
		settings.setCodec4b(payload.getUnsignedByte(base + 45));
		settings.setCodec4c(payload.getUnsignedByte(base + 46));
		settings.setCodec4d(payload.getUnsignedByte(base + 47));

		settings.setCodec1Name(name(payload, base + 48));
		settings.setCodec2Name(name(payload, base + 48 + CODEC_NAME_LENGTH));
		settings.setCodec3Name(name(payload, base + 48 + CODEC_NAME_LENGTH * 2));
		settings.setCodec4Name(name(payload, base + 48 + CODEC_NAME_LENGTH * 3));

		return true;
	}

	/** Speeds are shown 1-based but sent 0-based — the inverse of the writer's {@code speed}. */
	private static int speed(int wire) {
		return (wire & 0b1111) + 1;
	}

	/** A NUL-terminated codec name out of its fixed 64-byte field. */
	private static String name(ByteBuf payload, int at) {
		var raw = payload.toString(at, CODEC_NAME_LENGTH, StandardCharsets.ISO_8859_1);
		var end = raw.indexOf(0);
		return end < 0 ? raw : raw.substring(0, end);
	}
}
