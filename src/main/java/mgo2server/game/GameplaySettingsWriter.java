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
	 * Fixed trailer the client expects. Undocumented; reproduced from the original byte for byte.
	 */
	private static final byte[] TRAILER = {
		(byte) 0x01, (byte) 0x00, (byte) 0x10, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x10,
		(byte) 0x11, (byte) 0x10, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00,
		(byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00,
		(byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00, (byte) 0x00,
	};

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

		buffer.writeBytes(TRAILER);

		assert buffer.writerIndex() - start == PAYLOAD_SIZE
			: "Gameplay settings payload must be " + PAYLOAD_SIZE + " bytes";
	}
}
