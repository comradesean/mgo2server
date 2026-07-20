package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.CharaSettings;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.*;

/**
 * The 0x4120 payload packs nearly every setting two-to-a-byte, and several are adjusted by one on
 * the way out. An error here moves a slider a notch or inverts a toggle — nothing crashes, so
 * each field is pinned individually.
 */
public class GameplaySettingsWriterTest {
	/** Matches the column defaults, i.e. a character that has never touched the options screen. */
	private static CharaSettings defaults() {
		var s = new CharaSettings();
		s.setNormalViewSpeed(5);
		s.setShoulderViewSpeed(5);
		s.setFirstViewSpeed(5);
		s.setViewChangeSpeed(5);
		s.setReceiveNotices(true);
		s.setReceiveInvites(true);
		s.setFirstViewPlayerDirection(true);
		s.setWeaponSwitchMode(2);
		s.setWeaponSwitchB(1);
		s.setWeaponSwitchC(2);
		s.setWeaponSwitchBefore(1);
		s.setItemSwitchMode(2);
		s.setVoiceChatRecognitionLevel(5);
		s.setVoiceChatVolume(5);
		s.setHeadsetVolume(5);
		s.setBgmVolume(10);
		return s;
	}

	@Test
	public void payloadIsExactlySizedForTheClient() {
		var buffer = Unpooled.buffer(GameplaySettingsWriter.PAYLOAD_SIZE);
		GameplaySettingsWriter.write(buffer, defaults());

		assertThat(buffer.readableBytes()).isEqualTo(0x150);
	}

	/** Speeds are 1-based to the player and 0-based on the wire. */
	@Test
	public void speedsAreSentOneLowerThanStored() {
		var s = defaults();
		s.setNormalViewSpeed(1);
		assertThat(GameplaySettingsWriter.normalView(s) >>> 4).isZero();

		s.setNormalViewSpeed(10);
		assertThat(GameplaySettingsWriter.normalView(s) >>> 4).isEqualTo(9);
	}

	/** Music volume goes the other way: one higher than stored. */
	@Test
	public void musicVolumeIsSentOneHigherThanStored() {
		var s = defaults();
		s.setBgmVolume(10);

		assertThat(GameplaySettingsWriter.lockOnAndBgm(s) >>> 4).isEqualTo(11);
	}

	@Test
	public void lockOnSharesAByteWithMusicVolume() {
		var s = defaults();
		s.setLockOnEnabled(true);

		assertThat(GameplaySettingsWriter.lockOnAndBgm(s) & 0b1).isEqualTo(1);
		assertThat(GameplaySettingsWriter.lockOnAndBgm(s) >>> 4).isEqualTo(11);
	}

	@Test
	public void privacyPacksOnlineStatusAndFlags() {
		var s = defaults();
		s.setOnlineStatusMode(2);
		s.setEmailFriendsOnly(true);

		var a = GameplaySettingsWriter.privacyA(s);
		assertThat(a & 0b1).isEqualTo(1);              // constant bit
		assertThat((a >>> 4) & 0b11).isEqualTo(2);     // online status
		assertThat(a & 0b01000000).isEqualTo(0b01000000);

		var b = GameplaySettingsWriter.privacyB(s);
		assertThat(b & 0b1).isEqualTo(0b1);            // notices
		assertThat(b & 0b10000).isEqualTo(0b10000);    // invites
	}

	@Test
	public void viewInvertsAreIndependentBits() {
		var s = defaults();
		s.setNormalViewVerticalInvert(true);
		assertThat(GameplaySettingsWriter.normalView(s) & 0b11).isEqualTo(0b1);

		s.setNormalViewHorizontalInvert(true);
		assertThat(GameplaySettingsWriter.normalView(s) & 0b11).isEqualTo(0b11);
	}

	/** First-person view carries an extra flag the other views do not. */
	@Test
	public void firstViewCarriesPlayerDirection() {
		var s = defaults();
		s.setFirstViewPlayerDirection(true);
		assertThat(GameplaySettingsWriter.firstView(s) & 0b100).isEqualTo(0b100);

		s.setFirstViewPlayerDirection(false);
		assertThat(GameplaySettingsWriter.firstView(s) & 0b100).isZero();
	}

	@Test
	public void radarAndHudPackTheirFlags() {
		var s = defaults();
		s.setRadarLockNorth(true);
		s.setRadarFloorHide(true);
		assertThat(GameplaySettingsWriter.radar(s)).isEqualTo(0b10001);

		s.setHudDisplaySize(2);
		s.setHudHideNameTags(true);
		assertThat(GameplaySettingsWriter.hudDisplay(s)).isEqualTo(0b10010);
	}

	@Test
	public void weaponSwitchSlotsSharehBytes() {
		var s = defaults();
		s.setWeaponSwitchA(1);
		s.setWeaponSwitchB(2);
		s.setWeaponSwitchC(3);

		assertThat(GameplaySettingsWriter.weaponSwitchAB(s)).isEqualTo(0x21);
		assertThat(GameplaySettingsWriter.weaponSwitchC(s)).isEqualTo(3);
	}

	@Test
	public void recallPacksBeforeInTheLowNibble() {
		var s = defaults();
		s.setWeaponSwitchBefore(1);
		s.setWeaponSwitchNow(2);

		assertThat(GameplaySettingsWriter.weaponSwitchRecall(s)).isEqualTo(0x21);
	}

	@Test
	public void switchModesPacksWeaponAndItem() {
		var s = defaults();
		s.setWeaponSwitchMode(2);
		s.setItemSwitchMode(3);

		assertThat(GameplaySettingsWriter.switchModes(s)).isEqualTo(0x32);
	}

	@Test
	public void voiceChatBytesCarryTheirLevels() {
		var s = defaults();
		s.setVoiceChatRecognitionLevel(4);
		s.setVoiceChatVolume(5);
		s.setHeadsetVolume(6);

		assertThat(GameplaySettingsWriter.voiceChatA(s) & 0b1).isEqualTo(1);
		assertThat(GameplaySettingsWriter.voiceChatA(s) >>> 4).isEqualTo(4);
		assertThat(GameplaySettingsWriter.voiceChatB(s) & 0b1111).isEqualTo(5);
		assertThat(GameplaySettingsWriter.voiceChatB(s) >>> 4).isEqualTo(6);
	}

	@Test
	public void firstViewMemoryIsItsOwnByte() {
		var s = defaults();
		assertThat(GameplaySettingsWriter.firstViewMemory(s)).isZero();

		s.setFirstViewMemory(true);
		assertThat(GameplaySettingsWriter.firstViewMemory(s)).isEqualTo(0b10);
	}

	@Test
	public void codecFrequenciesAndNamesReachTheWire() {
		var s = defaults();
		s.setCodec1a(1);
		s.setCodec1b(3);
		s.setCodec4d(6);
		s.setCodec1Name("Alpha");
		s.setCodec4Name("Delta");

		var buffer = Unpooled.buffer(GameplaySettingsWriter.PAYLOAD_SIZE);
		GameplaySettingsWriter.write(buffer, s);

		// Sixteen codec bytes start at offset 32.
		assertThat(buffer.getByte(32)).isEqualTo((byte) 1);
		assertThat(buffer.getByte(33)).isEqualTo((byte) 3);
		assertThat(buffer.getByte(47)).isEqualTo((byte) 6);

		var name = new byte[64];
		buffer.getBytes(48, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Alpha");

		buffer.getBytes(48 + 3 * 64, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Delta");
	}

	/** Guards the offsets of the fields written before the codec block. */
	@Test
	public void writesPackedBytesAtTheExpectedOffsets() {
		var s = defaults();
		s.setOnlineStatusMode(1);
		s.setRadarLockNorth(true);

		var buffer = Unpooled.buffer(GameplaySettingsWriter.PAYLOAD_SIZE);
		GameplaySettingsWriter.write(buffer, s);

		assertThat(buffer.getByte(0)).isEqualTo((byte) GameplaySettingsWriter.privacyA(s));
		assertThat(buffer.getByte(1)).isEqualTo((byte) GameplaySettingsWriter.normalView(s));
		assertThat(buffer.getByte(2)).isEqualTo((byte) GameplaySettingsWriter.shoulderView(s));
		assertThat(buffer.getByte(3)).isEqualTo((byte) GameplaySettingsWriter.firstView(s));
		assertThat(buffer.getByte(4)).isEqualTo((byte) 4);   // view change speed, 5 - 1
		assertThat(buffer.getByte(11)).isEqualTo((byte) GameplaySettingsWriter.switchModes(s));
		assertThat(buffer.getByte(19)).isEqualTo((byte) GameplaySettingsWriter.privacyB(s));
		assertThat(buffer.getByte(21)).isEqualTo((byte) GameplaySettingsWriter.radar(s));
	}
}
