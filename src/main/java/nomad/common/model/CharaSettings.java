package nomad.common.model;

/**
 * Gameplay and interface settings for one character, as edited in the options screens.
 */
public class CharaSettings {
	private long charaId;

	private int onlineStatusMode;

	private int normalViewSpeed;

	private int shoulderViewSpeed;

	private int firstViewSpeed;

	private int viewChangeSpeed;

	private int hudDisplaySize;

	private int weaponSwitchMode;

	private int weaponSwitchA;

	private int weaponSwitchB;

	private int weaponSwitchC;

	private int weaponSwitchNow;

	private int weaponSwitchBefore;

	private int itemSwitchMode;

	private int codec1a;

	private int codec1b;

	private int codec1c;

	private int codec1d;

	private int codec2a;

	private int codec2b;

	private int codec2c;

	private int codec2d;

	private int codec3a;

	private int codec3b;

	private int codec3c;

	private int codec3d;

	private int codec4a;

	private int codec4b;

	private int codec4c;

	private int codec4d;

	private int voiceChatRecognitionLevel;

	private int voiceChatVolume;

	private int headsetVolume;

	private int bgmVolume;

	private boolean emailFriendsOnly;

	private boolean receiveNotices = true;

	private boolean receiveInvites = true;

	private boolean normalViewVerticalInvert;

	private boolean normalViewHorizontalInvert;

	private boolean shoulderViewVerticalInvert;

	private boolean shoulderViewHorizontalInvert;

	private boolean firstViewVerticalInvert;

	private boolean firstViewHorizontalInvert;

	private boolean firstViewPlayerDirection = true;

	private boolean firstViewMemory;

	private boolean radarLockNorth;

	private boolean radarFloorHide;

	private boolean hudHideNameTags;

	private boolean lockOnEnabled;

	private String codec1Name = "";

	private String codec2Name = "";

	private String codec3Name = "";

	private String codec4Name = "";

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getOnlineStatusMode() {
		return onlineStatusMode;
	}

	public void setOnlineStatusMode(int onlineStatusMode) {
		this.onlineStatusMode = onlineStatusMode;
	}

	public int getNormalViewSpeed() {
		return normalViewSpeed;
	}

	public void setNormalViewSpeed(int normalViewSpeed) {
		this.normalViewSpeed = normalViewSpeed;
	}

	public int getShoulderViewSpeed() {
		return shoulderViewSpeed;
	}

	public void setShoulderViewSpeed(int shoulderViewSpeed) {
		this.shoulderViewSpeed = shoulderViewSpeed;
	}

	public int getFirstViewSpeed() {
		return firstViewSpeed;
	}

	public void setFirstViewSpeed(int firstViewSpeed) {
		this.firstViewSpeed = firstViewSpeed;
	}

	public int getViewChangeSpeed() {
		return viewChangeSpeed;
	}

	public void setViewChangeSpeed(int viewChangeSpeed) {
		this.viewChangeSpeed = viewChangeSpeed;
	}

	public int getHudDisplaySize() {
		return hudDisplaySize;
	}

	public void setHudDisplaySize(int hudDisplaySize) {
		this.hudDisplaySize = hudDisplaySize;
	}

	public int getWeaponSwitchMode() {
		return weaponSwitchMode;
	}

	public void setWeaponSwitchMode(int weaponSwitchMode) {
		this.weaponSwitchMode = weaponSwitchMode;
	}

	public int getWeaponSwitchA() {
		return weaponSwitchA;
	}

	public void setWeaponSwitchA(int weaponSwitchA) {
		this.weaponSwitchA = weaponSwitchA;
	}

	public int getWeaponSwitchB() {
		return weaponSwitchB;
	}

	public void setWeaponSwitchB(int weaponSwitchB) {
		this.weaponSwitchB = weaponSwitchB;
	}

	public int getWeaponSwitchC() {
		return weaponSwitchC;
	}

	public void setWeaponSwitchC(int weaponSwitchC) {
		this.weaponSwitchC = weaponSwitchC;
	}

	public int getWeaponSwitchNow() {
		return weaponSwitchNow;
	}

	public void setWeaponSwitchNow(int weaponSwitchNow) {
		this.weaponSwitchNow = weaponSwitchNow;
	}

	public int getWeaponSwitchBefore() {
		return weaponSwitchBefore;
	}

	public void setWeaponSwitchBefore(int weaponSwitchBefore) {
		this.weaponSwitchBefore = weaponSwitchBefore;
	}

	public int getItemSwitchMode() {
		return itemSwitchMode;
	}

	public void setItemSwitchMode(int itemSwitchMode) {
		this.itemSwitchMode = itemSwitchMode;
	}

	public int getCodec1a() {
		return codec1a;
	}

	public void setCodec1a(int codec1a) {
		this.codec1a = codec1a;
	}

	public int getCodec1b() {
		return codec1b;
	}

	public void setCodec1b(int codec1b) {
		this.codec1b = codec1b;
	}

	public int getCodec1c() {
		return codec1c;
	}

	public void setCodec1c(int codec1c) {
		this.codec1c = codec1c;
	}

	public int getCodec1d() {
		return codec1d;
	}

	public void setCodec1d(int codec1d) {
		this.codec1d = codec1d;
	}

	public int getCodec2a() {
		return codec2a;
	}

	public void setCodec2a(int codec2a) {
		this.codec2a = codec2a;
	}

	public int getCodec2b() {
		return codec2b;
	}

	public void setCodec2b(int codec2b) {
		this.codec2b = codec2b;
	}

	public int getCodec2c() {
		return codec2c;
	}

	public void setCodec2c(int codec2c) {
		this.codec2c = codec2c;
	}

	public int getCodec2d() {
		return codec2d;
	}

	public void setCodec2d(int codec2d) {
		this.codec2d = codec2d;
	}

	public int getCodec3a() {
		return codec3a;
	}

	public void setCodec3a(int codec3a) {
		this.codec3a = codec3a;
	}

	public int getCodec3b() {
		return codec3b;
	}

	public void setCodec3b(int codec3b) {
		this.codec3b = codec3b;
	}

	public int getCodec3c() {
		return codec3c;
	}

	public void setCodec3c(int codec3c) {
		this.codec3c = codec3c;
	}

	public int getCodec3d() {
		return codec3d;
	}

	public void setCodec3d(int codec3d) {
		this.codec3d = codec3d;
	}

	public int getCodec4a() {
		return codec4a;
	}

	public void setCodec4a(int codec4a) {
		this.codec4a = codec4a;
	}

	public int getCodec4b() {
		return codec4b;
	}

	public void setCodec4b(int codec4b) {
		this.codec4b = codec4b;
	}

	public int getCodec4c() {
		return codec4c;
	}

	public void setCodec4c(int codec4c) {
		this.codec4c = codec4c;
	}

	public int getCodec4d() {
		return codec4d;
	}

	public void setCodec4d(int codec4d) {
		this.codec4d = codec4d;
	}

	public int getVoiceChatRecognitionLevel() {
		return voiceChatRecognitionLevel;
	}

	public void setVoiceChatRecognitionLevel(int voiceChatRecognitionLevel) {
		this.voiceChatRecognitionLevel = voiceChatRecognitionLevel;
	}

	public int getVoiceChatVolume() {
		return voiceChatVolume;
	}

	public void setVoiceChatVolume(int voiceChatVolume) {
		this.voiceChatVolume = voiceChatVolume;
	}

	public int getHeadsetVolume() {
		return headsetVolume;
	}

	public void setHeadsetVolume(int headsetVolume) {
		this.headsetVolume = headsetVolume;
	}

	public int getBgmVolume() {
		return bgmVolume;
	}

	public void setBgmVolume(int bgmVolume) {
		this.bgmVolume = bgmVolume;
	}

	public boolean isEmailFriendsOnly() {
		return emailFriendsOnly;
	}

	public void setEmailFriendsOnly(boolean emailFriendsOnly) {
		this.emailFriendsOnly = emailFriendsOnly;
	}

	public boolean isReceiveNotices() {
		return receiveNotices;
	}

	public void setReceiveNotices(boolean receiveNotices) {
		this.receiveNotices = receiveNotices;
	}

	public boolean isReceiveInvites() {
		return receiveInvites;
	}

	public void setReceiveInvites(boolean receiveInvites) {
		this.receiveInvites = receiveInvites;
	}

	public boolean isNormalViewVerticalInvert() {
		return normalViewVerticalInvert;
	}

	public void setNormalViewVerticalInvert(boolean normalViewVerticalInvert) {
		this.normalViewVerticalInvert = normalViewVerticalInvert;
	}

	public boolean isNormalViewHorizontalInvert() {
		return normalViewHorizontalInvert;
	}

	public void setNormalViewHorizontalInvert(boolean normalViewHorizontalInvert) {
		this.normalViewHorizontalInvert = normalViewHorizontalInvert;
	}

	public boolean isShoulderViewVerticalInvert() {
		return shoulderViewVerticalInvert;
	}

	public void setShoulderViewVerticalInvert(boolean shoulderViewVerticalInvert) {
		this.shoulderViewVerticalInvert = shoulderViewVerticalInvert;
	}

	public boolean isShoulderViewHorizontalInvert() {
		return shoulderViewHorizontalInvert;
	}

	public void setShoulderViewHorizontalInvert(boolean shoulderViewHorizontalInvert) {
		this.shoulderViewHorizontalInvert = shoulderViewHorizontalInvert;
	}

	public boolean isFirstViewVerticalInvert() {
		return firstViewVerticalInvert;
	}

	public void setFirstViewVerticalInvert(boolean firstViewVerticalInvert) {
		this.firstViewVerticalInvert = firstViewVerticalInvert;
	}

	public boolean isFirstViewHorizontalInvert() {
		return firstViewHorizontalInvert;
	}

	public void setFirstViewHorizontalInvert(boolean firstViewHorizontalInvert) {
		this.firstViewHorizontalInvert = firstViewHorizontalInvert;
	}

	public boolean isFirstViewPlayerDirection() {
		return firstViewPlayerDirection;
	}

	public void setFirstViewPlayerDirection(boolean firstViewPlayerDirection) {
		this.firstViewPlayerDirection = firstViewPlayerDirection;
	}

	public boolean isFirstViewMemory() {
		return firstViewMemory;
	}

	public void setFirstViewMemory(boolean firstViewMemory) {
		this.firstViewMemory = firstViewMemory;
	}

	public boolean isRadarLockNorth() {
		return radarLockNorth;
	}

	public void setRadarLockNorth(boolean radarLockNorth) {
		this.radarLockNorth = radarLockNorth;
	}

	public boolean isRadarFloorHide() {
		return radarFloorHide;
	}

	public void setRadarFloorHide(boolean radarFloorHide) {
		this.radarFloorHide = radarFloorHide;
	}

	public boolean isHudHideNameTags() {
		return hudHideNameTags;
	}

	public void setHudHideNameTags(boolean hudHideNameTags) {
		this.hudHideNameTags = hudHideNameTags;
	}

	public boolean isLockOnEnabled() {
		return lockOnEnabled;
	}

	public void setLockOnEnabled(boolean lockOnEnabled) {
		this.lockOnEnabled = lockOnEnabled;
	}

	public String getCodec1Name() {
		return codec1Name;
	}

	public void setCodec1Name(String codec1Name) {
		this.codec1Name = codec1Name;
	}

	public String getCodec2Name() {
		return codec2Name;
	}

	public void setCodec2Name(String codec2Name) {
		this.codec2Name = codec2Name;
	}

	public String getCodec3Name() {
		return codec3Name;
	}

	public void setCodec3Name(String codec3Name) {
		this.codec3Name = codec3Name;
	}

	public String getCodec4Name() {
		return codec4Name;
	}

	public void setCodec4Name(String codec4Name) {
		this.codec4Name = codec4Name;
	}

	@Override
	public String toString() {
		return "CharaSettings{charaId=" + charaId + "}";
	}
}
