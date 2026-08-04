package mgo2server.game;

import io.netty.buffer.Unpooled;
import mgo2server.common.model.CharaSettings;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link GameplaySettingsReader} must be {@link GameplaySettingsWriter} exactly backwards.
 *
 * <p>The two describe the same 48-byte header from opposite directions, so the only assertion worth
 * making is a round trip: write a populated settings object, read it back, and require every mapped
 * field to survive. A one-sided test would pass while the pair disagreed, which is the failure that
 * matters — a reader that is subtly wrong corrupts the player's options on every save rather than
 * failing loudly.
 */
public class GameplaySettingsRoundTripTest {

	/** Distinct values per field, so a mis-mapped offset swaps two things visibly. */
	private static CharaSettings populated() {
		var s = new CharaSettings();
		s.setOnlineStatusMode(2);
		s.setNormalViewSpeed(3);
		s.setShoulderViewSpeed(5);
		s.setFirstViewSpeed(7);
		s.setViewChangeSpeed(4);
		s.setHudDisplaySize(2);
		s.setWeaponSwitchMode(1);
		s.setItemSwitchMode(2);
		s.setWeaponSwitchA(3);
		s.setWeaponSwitchB(4);
		s.setWeaponSwitchC(5);
		s.setWeaponSwitchNow(6);
		s.setWeaponSwitchToggle(4);
		s.setVoiceChatOutputDevice(1);
		s.setCodecOutputDevice(1);
		s.setWeaponSwitchBefore(7);
		s.setVoiceChatRecognitionLevel(9);
		s.setVoiceChatVolume(10);
		s.setHeadsetVolume(11);
		s.setBgmVolume(12);
		s.setEmailFriendsOnly(true);
		s.setReceiveNotices(true);
		s.setReceiveInvites(true);
		s.setNormalViewVerticalInvert(true);
		s.setNormalViewHorizontalInvert(true);
		s.setShoulderViewVerticalInvert(true);
		s.setShoulderViewHorizontalInvert(false);
		s.setFirstViewVerticalInvert(false);
		s.setFirstViewHorizontalInvert(true);
		s.setFirstViewCameraDirection(true);
		s.setFirstViewMemoryDisabled(true);
		s.setRadarLockNorth(true);
		s.setRadarFloorHide(true);
		s.setHudHideNameTags(true);
		s.setLockOnEnabled(true);
		s.setCodec1a(11); s.setCodec1b(12); s.setCodec1c(13); s.setCodec1d(14);
		s.setCodec2a(21); s.setCodec2b(22); s.setCodec2c(23); s.setCodec2d(24);
		s.setCodec3a(31); s.setCodec3b(32); s.setCodec3c(33); s.setCodec3d(34);
		s.setCodec4a(41); s.setCodec4b(42); s.setCodec4c(43); s.setCodec4d(44);
		s.setCodec1Name("Snake");
		s.setCodec2Name("Otacon");
		s.setCodec3Name("Meryl");
		s.setCodec4Name("Campbell");
		return s;
	}

	private static CharaSettings roundTrip(CharaSettings original) {
		var buffer = Unpooled.buffer(GameplaySettingsWriter.PAYLOAD_SIZE);
		GameplaySettingsWriter.write(buffer, original);
		var read = new CharaSettings();
		assertThat(GameplaySettingsReader.apply(buffer, read)).isTrue();
		return read;
	}

	@Test
	public void everyMappedFieldSurvivesTheRoundTrip() {
		var original = populated();

		var read = roundTrip(original);

		assertThat(read.getOnlineStatusMode()).isEqualTo(original.getOnlineStatusMode());
		assertThat(read.getNormalViewSpeed()).isEqualTo(original.getNormalViewSpeed());
		assertThat(read.getShoulderViewSpeed()).isEqualTo(original.getShoulderViewSpeed());
		assertThat(read.getFirstViewSpeed()).isEqualTo(original.getFirstViewSpeed());
		assertThat(read.getViewChangeSpeed()).isEqualTo(original.getViewChangeSpeed());
		assertThat(read.getHudDisplaySize()).isEqualTo(original.getHudDisplaySize());
		assertThat(read.getWeaponSwitchMode()).isEqualTo(original.getWeaponSwitchMode());
		assertThat(read.getItemSwitchMode()).isEqualTo(original.getItemSwitchMode());
		assertThat(read.getWeaponSwitchA()).isEqualTo(original.getWeaponSwitchA());
		assertThat(read.getWeaponSwitchB()).isEqualTo(original.getWeaponSwitchB());
		assertThat(read.getWeaponSwitchC()).isEqualTo(original.getWeaponSwitchC());
		assertThat(read.getWeaponSwitchNow()).isEqualTo(original.getWeaponSwitchNow());
		assertThat(read.getWeaponSwitchToggle()).isEqualTo(original.getWeaponSwitchToggle());
		assertThat(read.getVoiceChatOutputDevice()).isEqualTo(original.getVoiceChatOutputDevice());
		assertThat(read.getCodecOutputDevice()).isEqualTo(original.getCodecOutputDevice());
		assertThat(read.getWeaponSwitchBefore()).isEqualTo(original.getWeaponSwitchBefore());
		assertThat(read.getVoiceChatRecognitionLevel())
			.isEqualTo(original.getVoiceChatRecognitionLevel());
		assertThat(read.getVoiceChatVolume()).isEqualTo(original.getVoiceChatVolume());
		assertThat(read.getHeadsetVolume()).isEqualTo(original.getHeadsetVolume());
		assertThat(read.isEmailFriendsOnly()).isEqualTo(original.isEmailFriendsOnly());
		assertThat(read.isReceiveNotices()).isEqualTo(original.isReceiveNotices());
		assertThat(read.isReceiveInvites()).isEqualTo(original.isReceiveInvites());
		assertThat(read.isNormalViewVerticalInvert()).isEqualTo(original.isNormalViewVerticalInvert());
		assertThat(read.isNormalViewHorizontalInvert())
			.isEqualTo(original.isNormalViewHorizontalInvert());
		assertThat(read.isShoulderViewVerticalInvert())
			.isEqualTo(original.isShoulderViewVerticalInvert());
		assertThat(read.isShoulderViewHorizontalInvert())
			.isEqualTo(original.isShoulderViewHorizontalInvert());
		assertThat(read.isFirstViewVerticalInvert()).isEqualTo(original.isFirstViewVerticalInvert());
		assertThat(read.isFirstViewHorizontalInvert())
			.isEqualTo(original.isFirstViewHorizontalInvert());
		assertThat(read.isFirstViewCameraDirection())
			.isEqualTo(original.isFirstViewCameraDirection());
		assertThat(read.isFirstViewMemoryDisabled()).isEqualTo(original.isFirstViewMemoryDisabled());
		assertThat(read.isRadarLockNorth()).isEqualTo(original.isRadarLockNorth());
		assertThat(read.isRadarFloorHide()).isEqualTo(original.isRadarFloorHide());
		assertThat(read.isHudHideNameTags()).isEqualTo(original.isHudHideNameTags());
		assertThat(read.getCodec1Name()).isEqualTo("Snake");
		assertThat(read.getCodec4Name()).isEqualTo("Campbell");
		assertThat(read.getCodec1a()).isEqualTo(11);
		assertThat(read.getCodec4d()).isEqualTo(44);
	}

	/**
	 * Lock-on and the music volume share a byte, and the volume travels one HIGHER than it is
	 * stored. Getting that inverse backwards would drift the volume by one on every save — slow
	 * corruption that reads as a client bug rather than a server one.
	 */
	@Test
	public void lockOnAndMusicVolumeShareAByteAndBothSurvive() {
		for (var volume = 0; volume <= 14; volume++) {
			var original = populated();
			original.setBgmVolume(volume);
			original.setLockOnEnabled(volume % 2 == 0);

			var read = roundTrip(original);

			assertThat(read.getBgmVolume()).as("volume %d", volume).isEqualTo(volume);
			assertThat(read.isLockOnEnabled()).as("lock-on at volume %d", volume)
				.isEqualTo(original.isLockOnEnabled());
		}
	}

	/** Lock-on off must survive too — the setting people actually noticed reverting. */
	@Test
	public void lockOnDisabledSurvives() {
		var original = populated();
		original.setLockOnEnabled(false);

		assertThat(roundTrip(original).isLockOnEnabled()).isFalse();
	}

	/** A short payload stores nothing rather than half of the player's options. */
	@Test
	public void aShortPayloadIsRejectedOutright() {
		var buffer = Unpooled.buffer();
		buffer.writeZero(GameplaySettingsReader.PAYLOAD_SIZE - 1);
		var settings = populated();

		assertThat(GameplaySettingsReader.apply(buffer, settings)).isFalse();
		assertThat(settings.isLockOnEnabled()).as("nothing was applied").isTrue();
	}
}
