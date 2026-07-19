package nomad.common.model;

import java.util.Arrays;

public class RoomConfiguration {
	private long id;

	private String name = "";

	private String password = "";

	private int stance = 0;

	private String comment = "Good luck.";

	private int[] matchModes = {};

	private int[] matchMaps = {};

	private int[] matchFlags = {};

	private boolean dedicatedHost = false;

	private int maxPlayers = 16;

	private int briefingMinutes = 2;

	private boolean statsEnabled = false;

	private boolean friendlyFireEnabled = false;

	private boolean autoAimEnabled = false;

	private boolean uniqueCharactersEnabled = false;

	private boolean uniqueCharactersRandom = false;

	private int uniqueCharacterForRedTeam = 0;

	private int uniqueCharacterForBlueTeam = 2;

	private boolean enemyNameTagsEnabled = true;

	private boolean silentModeEnabled = false;

	private boolean teamsAutoAssigned = true;

	private boolean doTeamsSwitchPositions = true;

	private boolean ghostsEnabled = false;

	private boolean quickJoinAllowed = false;

	private boolean levelLimitEnabled = false;

	private int levelLimitBase = 0;

	private int levelLimitTolerance = 0;

	private boolean voiceChatEnabled = true;

	private int teamKillKickCount = 3;

	private int idleKickMinutes = 5;

	private boolean weaponRestrictionsEnabled = false;

	private boolean vzEnabled = true;

	private boolean p90Enabled = true;

	private boolean mp5Enabled = true;

	private boolean patriotEnabled = true;

	private boolean akEnabled = true;

	private boolean m4Enabled = true;

	private boolean mk17Enabled = true;

	private boolean xm8Enabled = true;

	private boolean g3a3Enabled = true;

	private boolean svdEnabled = true;

	private boolean mosinEnabled = true;

	private boolean m14Enabled = true;

	private boolean vssEnabled = true;

	private boolean dsrEnabled = true;

	private boolean m870Enabled = true;

	private boolean saigaEnabled = true;

	private boolean m60Enabled = true;

	private boolean shieldEnabled = true;

	private boolean rpgEnabled = true;

	private boolean knifeEnabled = true;

	private boolean gsrEnabled = true;

	private boolean mk2Enabled = true;

	private boolean operatorEnabled = true;

	private boolean g18Enabled = true;

	private boolean mk23Enabled = true;

	private boolean deEnabled = true;

	private boolean grenadeEnabled = true;

	private boolean wpEnabled = true;

	private boolean stunEnabled = true;

	private boolean chaffEnabled = true;

	private boolean smokeEnabled = true;

	private boolean smokeRedEnabled = true;

	private boolean smokeGreenEnabled = true;

	private boolean smokeYellowEnabled = true;

	private boolean elocEnabled = true;

	private boolean claymoreEnabled = true;

	private boolean sgMineEnabled = true;

	private boolean c4Enabled = true;

	private boolean sgSatchelEnabled = true;

	private boolean magazineEnabled = true;

	private boolean suppressorEnabled = true;

	private boolean gp30Enabled = true;

	private boolean xm320Enabled = true;

	private boolean masterKeyEnabled = true;

	private boolean scopeEnabled = true;

	private boolean sightEnabled = true;

	private boolean laserEnabled = true;

	private boolean lightHgEnabled = true;

	private boolean lightLgEnabled = true;

	private boolean gripEnabled = true;

	private boolean envgEnabled = true;

	private boolean drumEnabled = true;

	private int deathMatchMinutes = 5;

	private int deathMatchRounds = 1;

	private int deathMatchTickets = 30;

	private int teamDeathMatchMinutes = 5;

	private int teamDeathMatchRounds = 2;

	private int teamDeathMatchTickets = 51;

	private int rescueMinutes = 7;

	private int rescueRounds = 2;

	private int captureMinutes = 4;

	private int captureRounds = 2;

	private boolean captureExtraTimeEnabled = false;

	private int sneakingMinutes = 7;

	private int sneakingRounds = 2;

	private int sneakingSnakeLives = 3;

	private int baseMinutes = 5;

	private int baseRounds = 2;

	private int bombMinutes = 7;

	private int bombRounds = 2;

	private int teamSneakingMinutes = 10;

	private int teamSneakingRounds = 2;

	private int stealthDeathMatchMinutes = 3;

	private int stealthDeathMatchRounds = 2;

	private int intervalMinutes = 20;

	private int stealthCaptureMinutes = 5;

	private int stealthCaptureRounds = 2;

	private boolean stealthCaptureExtraTimeEnabled = true;

	private int raceMinutes = 5;

	private int raceRounds = 2;

	private boolean raceExtraTimeEnabled = true;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public String getPassword() {
		return password;
	}

	public void setPassword(String password) {
		this.password = password;
	}

	public int getStance() {
		return stance;
	}

	public void setStance(int stance) {
		this.stance = stance;
	}

	public String getComment() {
		return comment;
	}

	public void setComment(String comment) {
		this.comment = comment;
	}

	public int[] getMatchModes() {
		return matchModes;
	}

	public void setMatchModes(int[] matchModes) {
		this.matchModes = matchModes;
	}

	public int[] getMatchMaps() {
		return matchMaps;
	}

	public void setMatchMaps(int[] matchMaps) {
		this.matchMaps = matchMaps;
	}

	public int[] getMatchFlags() {
		return matchFlags;
	}

	public void setMatchFlags(int[] matchFlags) {
		this.matchFlags = matchFlags;
	}

	public boolean isDedicatedHost() {
		return dedicatedHost;
	}

	public void setDedicatedHost(boolean dedicatedHost) {
		this.dedicatedHost = dedicatedHost;
	}

	public int getMaxPlayers() {
		return maxPlayers;
	}

	public void setMaxPlayers(int maxPlayers) {
		this.maxPlayers = maxPlayers;
	}

	public int getBriefingMinutes() {
		return briefingMinutes;
	}

	public void setBriefingMinutes(int briefingMinutes) {
		this.briefingMinutes = briefingMinutes;
	}

	public boolean isStatsEnabled() {
		return statsEnabled;
	}

	public void setStatsEnabled(boolean statsEnabled) {
		this.statsEnabled = statsEnabled;
	}

	public boolean isFriendlyFireEnabled() {
		return friendlyFireEnabled;
	}

	public void setFriendlyFireEnabled(boolean friendlyFireEnabled) {
		this.friendlyFireEnabled = friendlyFireEnabled;
	}

	public boolean isAutoAimEnabled() {
		return autoAimEnabled;
	}

	public void setAutoAimEnabled(boolean autoAimEnabled) {
		this.autoAimEnabled = autoAimEnabled;
	}

	public boolean isUniqueCharactersEnabled() {
		return uniqueCharactersEnabled;
	}

	public void setUniqueCharactersEnabled(boolean uniqueCharactersEnabled) {
		this.uniqueCharactersEnabled = uniqueCharactersEnabled;
	}

	public boolean isUniqueCharactersRandom() {
		return uniqueCharactersRandom;
	}

	public void setUniqueCharactersRandom(boolean uniqueCharactersRandom) {
		this.uniqueCharactersRandom = uniqueCharactersRandom;
	}

	public int getUniqueCharacterForRedTeam() {
		return uniqueCharacterForRedTeam;
	}

	public void setUniqueCharacterForRedTeam(int uniqueCharacterForRedTeam) {
		this.uniqueCharacterForRedTeam = uniqueCharacterForRedTeam;
	}

	public int getUniqueCharacterForBlueTeam() {
		return uniqueCharacterForBlueTeam;
	}

	public void setUniqueCharacterForBlueTeam(int uniqueCharacterForBlueTeam) {
		this.uniqueCharacterForBlueTeam = uniqueCharacterForBlueTeam;
	}

	public boolean isEnemyNameTagsEnabled() {
		return enemyNameTagsEnabled;
	}

	public void setEnemyNameTagsEnabled(boolean enemyNameTagsEnabled) {
		this.enemyNameTagsEnabled = enemyNameTagsEnabled;
	}

	public boolean isSilentModeEnabled() {
		return silentModeEnabled;
	}

	public void setSilentModeEnabled(boolean silentModeEnabled) {
		this.silentModeEnabled = silentModeEnabled;
	}

	public boolean isTeamsAutoAssigned() {
		return teamsAutoAssigned;
	}

	public void setTeamsAutoAssigned(boolean teamsAutoAssigned) {
		this.teamsAutoAssigned = teamsAutoAssigned;
	}

	public boolean isDoTeamsSwitchPositions() {
		return doTeamsSwitchPositions;
	}

	public void setDoTeamsSwitchPositions(boolean doTeamsSwitchPositions) {
		this.doTeamsSwitchPositions = doTeamsSwitchPositions;
	}

	public boolean isGhostsEnabled() {
		return ghostsEnabled;
	}

	public void setGhostsEnabled(boolean ghostsEnabled) {
		this.ghostsEnabled = ghostsEnabled;
	}

	public boolean isQuickJoinAllowed() {
		return quickJoinAllowed;
	}

	public void setQuickJoinAllowed(boolean quickJoinAllowed) {
		this.quickJoinAllowed = quickJoinAllowed;
	}

	public boolean isLevelLimitEnabled() {
		return levelLimitEnabled;
	}

	public void setLevelLimitEnabled(boolean levelLimitEnabled) {
		this.levelLimitEnabled = levelLimitEnabled;
	}

	public int getLevelLimitBase() {
		return levelLimitBase;
	}

	public void setLevelLimitBase(int levelLimitBase) {
		this.levelLimitBase = levelLimitBase;
	}

	public int getLevelLimitTolerance() {
		return levelLimitTolerance;
	}

	public void setLevelLimitTolerance(int levelLimitTolerance) {
		this.levelLimitTolerance = levelLimitTolerance;
	}

	public boolean isVoiceChatEnabled() {
		return voiceChatEnabled;
	}

	public void setVoiceChatEnabled(boolean voiceChatEnabled) {
		this.voiceChatEnabled = voiceChatEnabled;
	}

	public int getTeamKillKickCount() {
		return teamKillKickCount;
	}

	public void setTeamKillKickCount(int teamKillKickCount) {
		this.teamKillKickCount = teamKillKickCount;
	}

	public int getIdleKickMinutes() {
		return idleKickMinutes;
	}

	public void setIdleKickMinutes(int idleKickMinutes) {
		this.idleKickMinutes = idleKickMinutes;
	}

	public boolean isWeaponRestrictionsEnabled() {
		return weaponRestrictionsEnabled;
	}

	public void setWeaponRestrictionsEnabled(boolean weaponRestrictionsEnabled) {
		this.weaponRestrictionsEnabled = weaponRestrictionsEnabled;
	}

	public boolean isVzEnabled() {
		return vzEnabled;
	}

	public void setVzEnabled(boolean vzEnabled) {
		this.vzEnabled = vzEnabled;
	}

	public boolean isP90Enabled() {
		return p90Enabled;
	}

	public void setP90Enabled(boolean p90Enabled) {
		this.p90Enabled = p90Enabled;
	}

	public boolean isMp5Enabled() {
		return mp5Enabled;
	}

	public void setMp5Enabled(boolean mp5Enabled) {
		this.mp5Enabled = mp5Enabled;
	}

	public boolean isPatriotEnabled() {
		return patriotEnabled;
	}

	public void setPatriotEnabled(boolean patriotEnabled) {
		this.patriotEnabled = patriotEnabled;
	}

	public boolean isAkEnabled() {
		return akEnabled;
	}

	public void setAkEnabled(boolean akEnabled) {
		this.akEnabled = akEnabled;
	}

	public boolean isM4Enabled() {
		return m4Enabled;
	}

	public void setM4Enabled(boolean m4Enabled) {
		this.m4Enabled = m4Enabled;
	}

	public boolean isMk17Enabled() {
		return mk17Enabled;
	}

	public void setMk17Enabled(boolean mk17Enabled) {
		this.mk17Enabled = mk17Enabled;
	}

	public boolean isXm8Enabled() {
		return xm8Enabled;
	}

	public void setXm8Enabled(boolean xm8Enabled) {
		this.xm8Enabled = xm8Enabled;
	}

	public boolean isG3a3Enabled() {
		return g3a3Enabled;
	}

	public void setG3a3Enabled(boolean g3a3Enabled) {
		this.g3a3Enabled = g3a3Enabled;
	}

	public boolean isSvdEnabled() {
		return svdEnabled;
	}

	public void setSvdEnabled(boolean svdEnabled) {
		this.svdEnabled = svdEnabled;
	}

	public boolean isMosinEnabled() {
		return mosinEnabled;
	}

	public void setMosinEnabled(boolean mosinEnabled) {
		this.mosinEnabled = mosinEnabled;
	}

	public boolean isM14Enabled() {
		return m14Enabled;
	}

	public void setM14Enabled(boolean m14Enabled) {
		this.m14Enabled = m14Enabled;
	}

	public boolean isVssEnabled() {
		return vssEnabled;
	}

	public void setVssEnabled(boolean vssEnabled) {
		this.vssEnabled = vssEnabled;
	}

	public boolean isDsrEnabled() {
		return dsrEnabled;
	}

	public void setDsrEnabled(boolean dsrEnabled) {
		this.dsrEnabled = dsrEnabled;
	}

	public boolean isM870Enabled() {
		return m870Enabled;
	}

	public void setM870Enabled(boolean m870Enabled) {
		this.m870Enabled = m870Enabled;
	}

	public boolean isSaigaEnabled() {
		return saigaEnabled;
	}

	public void setSaigaEnabled(boolean saigaEnabled) {
		this.saigaEnabled = saigaEnabled;
	}

	public boolean isM60Enabled() {
		return m60Enabled;
	}

	public void setM60Enabled(boolean m60Enabled) {
		this.m60Enabled = m60Enabled;
	}

	public boolean isShieldEnabled() {
		return shieldEnabled;
	}

	public void setShieldEnabled(boolean shieldEnabled) {
		this.shieldEnabled = shieldEnabled;
	}

	public boolean isRpgEnabled() {
		return rpgEnabled;
	}

	public void setRpgEnabled(boolean rpgEnabled) {
		this.rpgEnabled = rpgEnabled;
	}

	public boolean isKnifeEnabled() {
		return knifeEnabled;
	}

	public void setKnifeEnabled(boolean knifeEnabled) {
		this.knifeEnabled = knifeEnabled;
	}

	public boolean isGsrEnabled() {
		return gsrEnabled;
	}

	public void setGsrEnabled(boolean gsrEnabled) {
		this.gsrEnabled = gsrEnabled;
	}

	public boolean isMk2Enabled() {
		return mk2Enabled;
	}

	public void setMk2Enabled(boolean mk2Enabled) {
		this.mk2Enabled = mk2Enabled;
	}

	public boolean isOperatorEnabled() {
		return operatorEnabled;
	}

	public void setOperatorEnabled(boolean operatorEnabled) {
		this.operatorEnabled = operatorEnabled;
	}

	public boolean isG18Enabled() {
		return g18Enabled;
	}

	public void setG18Enabled(boolean g18Enabled) {
		this.g18Enabled = g18Enabled;
	}

	public boolean isMk23Enabled() {
		return mk23Enabled;
	}

	public void setMk23Enabled(boolean mk23Enabled) {
		this.mk23Enabled = mk23Enabled;
	}

	public boolean isDeEnabled() {
		return deEnabled;
	}

	public void setDeEnabled(boolean deEnabled) {
		this.deEnabled = deEnabled;
	}

	public boolean isGrenadeEnabled() {
		return grenadeEnabled;
	}

	public void setGrenadeEnabled(boolean grenadeEnabled) {
		this.grenadeEnabled = grenadeEnabled;
	}

	public boolean isWpEnabled() {
		return wpEnabled;
	}

	public void setWpEnabled(boolean wpEnabled) {
		this.wpEnabled = wpEnabled;
	}

	public boolean isStunEnabled() {
		return stunEnabled;
	}

	public void setStunEnabled(boolean stunEnabled) {
		this.stunEnabled = stunEnabled;
	}

	public boolean isChaffEnabled() {
		return chaffEnabled;
	}

	public void setChaffEnabled(boolean chaffEnabled) {
		this.chaffEnabled = chaffEnabled;
	}

	public boolean isSmokeEnabled() {
		return smokeEnabled;
	}

	public void setSmokeEnabled(boolean smokeEnabled) {
		this.smokeEnabled = smokeEnabled;
	}

	public boolean isSmokeRedEnabled() {
		return smokeRedEnabled;
	}

	public void setSmokeRedEnabled(boolean smokeRedEnabled) {
		this.smokeRedEnabled = smokeRedEnabled;
	}

	public boolean isSmokeGreenEnabled() {
		return smokeGreenEnabled;
	}

	public void setSmokeGreenEnabled(boolean smokeGreenEnabled) {
		this.smokeGreenEnabled = smokeGreenEnabled;
	}

	public boolean isSmokeYellowEnabled() {
		return smokeYellowEnabled;
	}

	public void setSmokeYellowEnabled(boolean smokeYellowEnabled) {
		this.smokeYellowEnabled = smokeYellowEnabled;
	}

	public boolean isElocEnabled() {
		return elocEnabled;
	}

	public void setElocEnabled(boolean elocEnabled) {
		this.elocEnabled = elocEnabled;
	}

	public boolean isClaymoreEnabled() {
		return claymoreEnabled;
	}

	public void setClaymoreEnabled(boolean claymoreEnabled) {
		this.claymoreEnabled = claymoreEnabled;
	}

	public boolean isSgMineEnabled() {
		return sgMineEnabled;
	}

	public void setSgMineEnabled(boolean sgMineEnabled) {
		this.sgMineEnabled = sgMineEnabled;
	}

	public boolean isC4Enabled() {
		return c4Enabled;
	}

	public void setC4Enabled(boolean c4Enabled) {
		this.c4Enabled = c4Enabled;
	}

	public boolean isSgSatchelEnabled() {
		return sgSatchelEnabled;
	}

	public void setSgSatchelEnabled(boolean sgSatchelEnabled) {
		this.sgSatchelEnabled = sgSatchelEnabled;
	}

	public boolean isMagazineEnabled() {
		return magazineEnabled;
	}

	public void setMagazineEnabled(boolean magazineEnabled) {
		this.magazineEnabled = magazineEnabled;
	}

	public boolean isSuppressorEnabled() {
		return suppressorEnabled;
	}

	public void setSuppressorEnabled(boolean suppressorEnabled) {
		this.suppressorEnabled = suppressorEnabled;
	}

	public boolean isGp30Enabled() {
		return gp30Enabled;
	}

	public void setGp30Enabled(boolean gp30Enabled) {
		this.gp30Enabled = gp30Enabled;
	}

	public boolean isXm320Enabled() {
		return xm320Enabled;
	}

	public void setXm320Enabled(boolean xm320Enabled) {
		this.xm320Enabled = xm320Enabled;
	}

	public boolean isMasterKeyEnabled() {
		return masterKeyEnabled;
	}

	public void setMasterKeyEnabled(boolean masterKeyEnabled) {
		this.masterKeyEnabled = masterKeyEnabled;
	}

	public boolean isScopeEnabled() {
		return scopeEnabled;
	}

	public void setScopeEnabled(boolean scopeEnabled) {
		this.scopeEnabled = scopeEnabled;
	}

	public boolean isSightEnabled() {
		return sightEnabled;
	}

	public void setSightEnabled(boolean sightEnabled) {
		this.sightEnabled = sightEnabled;
	}

	public boolean isLaserEnabled() {
		return laserEnabled;
	}

	public void setLaserEnabled(boolean laserEnabled) {
		this.laserEnabled = laserEnabled;
	}

	public boolean isLightHgEnabled() {
		return lightHgEnabled;
	}

	public void setLightHgEnabled(boolean lightHgEnabled) {
		this.lightHgEnabled = lightHgEnabled;
	}

	public boolean isLightLgEnabled() {
		return lightLgEnabled;
	}

	public void setLightLgEnabled(boolean lightLgEnabled) {
		this.lightLgEnabled = lightLgEnabled;
	}

	public boolean isGripEnabled() {
		return gripEnabled;
	}

	public void setGripEnabled(boolean gripEnabled) {
		this.gripEnabled = gripEnabled;
	}

	public boolean isEnvgEnabled() {
		return envgEnabled;
	}

	public void setEnvgEnabled(boolean envgEnabled) {
		this.envgEnabled = envgEnabled;
	}

	public boolean isDrumEnabled() {
		return drumEnabled;
	}

	public void setDrumEnabled(boolean drumEnabled) {
		this.drumEnabled = drumEnabled;
	}

	public int getDeathMatchMinutes() {
		return deathMatchMinutes;
	}

	public void setDeathMatchMinutes(int deathMatchMinutes) {
		this.deathMatchMinutes = deathMatchMinutes;
	}

	public int getDeathMatchRounds() {
		return deathMatchRounds;
	}

	public void setDeathMatchRounds(int deathMatchRounds) {
		this.deathMatchRounds = deathMatchRounds;
	}

	public int getDeathMatchTickets() {
		return deathMatchTickets;
	}

	public void setDeathMatchTickets(int deathMatchTickets) {
		this.deathMatchTickets = deathMatchTickets;
	}

	public int getTeamDeathMatchMinutes() {
		return teamDeathMatchMinutes;
	}

	public void setTeamDeathMatchMinutes(int teamDeathMatchMinutes) {
		this.teamDeathMatchMinutes = teamDeathMatchMinutes;
	}

	public int getTeamDeathMatchRounds() {
		return teamDeathMatchRounds;
	}

	public void setTeamDeathMatchRounds(int teamDeathMatchRounds) {
		this.teamDeathMatchRounds = teamDeathMatchRounds;
	}

	public int getTeamDeathMatchTickets() {
		return teamDeathMatchTickets;
	}

	public void setTeamDeathMatchTickets(int teamDeathMatchTickets) {
		this.teamDeathMatchTickets = teamDeathMatchTickets;
	}

	public int getRescueMinutes() {
		return rescueMinutes;
	}

	public void setRescueMinutes(int rescueMinutes) {
		this.rescueMinutes = rescueMinutes;
	}

	public int getRescueRounds() {
		return rescueRounds;
	}

	public void setRescueRounds(int rescueRounds) {
		this.rescueRounds = rescueRounds;
	}

	public int getCaptureMinutes() {
		return captureMinutes;
	}

	public void setCaptureMinutes(int captureMinutes) {
		this.captureMinutes = captureMinutes;
	}

	public int getCaptureRounds() {
		return captureRounds;
	}

	public void setCaptureRounds(int captureRounds) {
		this.captureRounds = captureRounds;
	}

	public boolean isCaptureExtraTimeEnabled() {
		return captureExtraTimeEnabled;
	}

	public void setCaptureExtraTimeEnabled(boolean captureExtraTimeEnabled) {
		this.captureExtraTimeEnabled = captureExtraTimeEnabled;
	}

	public int getSneakingMinutes() {
		return sneakingMinutes;
	}

	public void setSneakingMinutes(int sneakingMinutes) {
		this.sneakingMinutes = sneakingMinutes;
	}

	public int getSneakingRounds() {
		return sneakingRounds;
	}

	public void setSneakingRounds(int sneakingRounds) {
		this.sneakingRounds = sneakingRounds;
	}

	public int getSneakingSnakeLives() {
		return sneakingSnakeLives;
	}

	public void setSneakingSnakeLives(int sneakingSnakeLives) {
		this.sneakingSnakeLives = sneakingSnakeLives;
	}

	public int getBaseMinutes() {
		return baseMinutes;
	}

	public void setBaseMinutes(int baseMinutes) {
		this.baseMinutes = baseMinutes;
	}

	public int getBaseRounds() {
		return baseRounds;
	}

	public void setBaseRounds(int baseRounds) {
		this.baseRounds = baseRounds;
	}

	public int getBombMinutes() {
		return bombMinutes;
	}

	public void setBombMinutes(int bombMinutes) {
		this.bombMinutes = bombMinutes;
	}

	public int getBombRounds() {
		return bombRounds;
	}

	public void setBombRounds(int bombRounds) {
		this.bombRounds = bombRounds;
	}

	public int getTeamSneakingMinutes() {
		return teamSneakingMinutes;
	}

	public void setTeamSneakingMinutes(int teamSneakingMinutes) {
		this.teamSneakingMinutes = teamSneakingMinutes;
	}

	public int getTeamSneakingRounds() {
		return teamSneakingRounds;
	}

	public void setTeamSneakingRounds(int teamSneakingRounds) {
		this.teamSneakingRounds = teamSneakingRounds;
	}

	public int getStealthDeathMatchMinutes() {
		return stealthDeathMatchMinutes;
	}

	public void setStealthDeathMatchMinutes(int stealthDeathMatchMinutes) {
		this.stealthDeathMatchMinutes = stealthDeathMatchMinutes;
	}

	public int getStealthDeathMatchRounds() {
		return stealthDeathMatchRounds;
	}

	public void setStealthDeathMatchRounds(int stealthDeathMatchRounds) {
		this.stealthDeathMatchRounds = stealthDeathMatchRounds;
	}

	public int getIntervalMinutes() {
		return intervalMinutes;
	}

	public void setIntervalMinutes(int intervalMinutes) {
		this.intervalMinutes = intervalMinutes;
	}

	public int getStealthCaptureMinutes() {
		return stealthCaptureMinutes;
	}

	public void setStealthCaptureMinutes(int stealthCaptureMinutes) {
		this.stealthCaptureMinutes = stealthCaptureMinutes;
	}

	public int getStealthCaptureRounds() {
		return stealthCaptureRounds;
	}

	public void setStealthCaptureRounds(int stealthCaptureRounds) {
		this.stealthCaptureRounds = stealthCaptureRounds;
	}

	public boolean isStealthCaptureExtraTimeEnabled() {
		return stealthCaptureExtraTimeEnabled;
	}

	public void setStealthCaptureExtraTimeEnabled(boolean stealthCaptureExtraTimeEnabled) {
		this.stealthCaptureExtraTimeEnabled = stealthCaptureExtraTimeEnabled;
	}

	public int getRaceMinutes() {
		return raceMinutes;
	}

	public void setRaceMinutes(int raceMinutes) {
		this.raceMinutes = raceMinutes;
	}

	public int getRaceRounds() {
		return raceRounds;
	}

	public void setRaceRounds(int raceRounds) {
		this.raceRounds = raceRounds;
	}

	public boolean isRaceExtraTimeEnabled() {
		return raceExtraTimeEnabled;
	}

	public void setRaceExtraTimeEnabled(boolean raceExtraTimeEnabled) {
		this.raceExtraTimeEnabled = raceExtraTimeEnabled;
	}

	@Override
	public String toString() {
		return "RoomConfiguration{" +
			"id=" + id +
			", name='" + name + '\'' +
			", stance=" + stance +
			", comment='" + comment + '\'' +
			", matchModes=" + Arrays.toString(matchModes) +
			", matchMaps=" + Arrays.toString(matchMaps) +
			", matchFlags=" + Arrays.toString(matchFlags) +
			", dedicatedHost=" + dedicatedHost +
			", maxPlayers=" + maxPlayers +
			", briefingMinutes=" + briefingMinutes +
			", statsEnabled=" + statsEnabled +
			", friendlyFireEnabled=" + friendlyFireEnabled +
			", autoAimEnabled=" + autoAimEnabled +
			", uniqueCharactersEnabled=" + uniqueCharactersEnabled +
			", uniqueCharactersRandom=" + uniqueCharactersRandom +
			", uniqueCharacterForRedTeam=" + uniqueCharacterForRedTeam +
			", uniqueCharacterForBlueTeam=" + uniqueCharacterForBlueTeam +
			", enemyNameTagsEnabled=" + enemyNameTagsEnabled +
			", silentModeEnabled=" + silentModeEnabled +
			", teamsAutoAssigned=" + teamsAutoAssigned +
			", doTeamsSwitchPositions=" + doTeamsSwitchPositions +
			", ghostsEnabled=" + ghostsEnabled +
			", quickJoinAllowed=" + quickJoinAllowed +
			", levelLimitEnabled=" + levelLimitEnabled +
			", levelLimitBase=" + levelLimitBase +
			", levelLimitTolerance=" + levelLimitTolerance +
			", voiceChatEnabled=" + voiceChatEnabled +
			", teamKillKickCount=" + teamKillKickCount +
			", idleKickMinutes=" + idleKickMinutes +
			", weaponRestrictionsEnabled=" + weaponRestrictionsEnabled +
			", vzEnabled=" + vzEnabled +
			", p90Enabled=" + p90Enabled +
			", mp5Enabled=" + mp5Enabled +
			", patriotEnabled=" + patriotEnabled +
			", akEnabled=" + akEnabled +
			", m4Enabled=" + m4Enabled +
			", mk17Enabled=" + mk17Enabled +
			", xm8Enabled=" + xm8Enabled +
			", g3a3Enabled=" + g3a3Enabled +
			", svdEnabled=" + svdEnabled +
			", mosinEnabled=" + mosinEnabled +
			", m14Enabled=" + m14Enabled +
			", vssEnabled=" + vssEnabled +
			", dsrEnabled=" + dsrEnabled +
			", m870Enabled=" + m870Enabled +
			", saigaEnabled=" + saigaEnabled +
			", m60Enabled=" + m60Enabled +
			", shieldEnabled=" + shieldEnabled +
			", rpgEnabled=" + rpgEnabled +
			", knifeEnabled=" + knifeEnabled +
			", gsrEnabled=" + gsrEnabled +
			", mk2Enabled=" + mk2Enabled +
			", operatorEnabled=" + operatorEnabled +
			", g18Enabled=" + g18Enabled +
			", mk23Enabled=" + mk23Enabled +
			", deEnabled=" + deEnabled +
			", grenadeEnabled=" + grenadeEnabled +
			", wpEnabled=" + wpEnabled +
			", stunEnabled=" + stunEnabled +
			", chaffEnabled=" + chaffEnabled +
			", smokeEnabled=" + smokeEnabled +
			", smokeRedEnabled=" + smokeRedEnabled +
			", smokeGreenEnabled=" + smokeGreenEnabled +
			", smokeYellowEnabled=" + smokeYellowEnabled +
			", elocEnabled=" + elocEnabled +
			", claymoreEnabled=" + claymoreEnabled +
			", sgMineEnabled=" + sgMineEnabled +
			", c4Enabled=" + c4Enabled +
			", sgSatchelEnabled=" + sgSatchelEnabled +
			", magazineEnabled=" + magazineEnabled +
			", suppressorEnabled=" + suppressorEnabled +
			", gp30Enabled=" + gp30Enabled +
			", xm320Enabled=" + xm320Enabled +
			", masterKeyEnabled=" + masterKeyEnabled +
			", scopeEnabled=" + scopeEnabled +
			", sightEnabled=" + sightEnabled +
			", laserEnabled=" + laserEnabled +
			", lightHgEnabled=" + lightHgEnabled +
			", lightLgEnabled=" + lightLgEnabled +
			", gripEnabled=" + gripEnabled +
			", envgEnabled=" + envgEnabled +
			", drumEnabled=" + drumEnabled +
			", deathMatchMinutes=" + deathMatchMinutes +
			", deathMatchRounds=" + deathMatchRounds +
			", deathMatchTickets=" + deathMatchTickets +
			", teamDeathMatchMinutes=" + teamDeathMatchMinutes +
			", teamDeathMatchRounds=" + teamDeathMatchRounds +
			", teamDeathMatchTickets=" + teamDeathMatchTickets +
			", rescueMinutes=" + rescueMinutes +
			", rescueRounds=" + rescueRounds +
			", captureMinutes=" + captureMinutes +
			", captureRounds=" + captureRounds +
			", captureExtraTimeEnabled=" + captureExtraTimeEnabled +
			", sneakingMinutes=" + sneakingMinutes +
			", sneakingRounds=" + sneakingRounds +
			", sneakingSnakeLives=" + sneakingSnakeLives +
			", baseMinutes=" + baseMinutes +
			", baseRounds=" + baseRounds +
			", bombMinutes=" + bombMinutes +
			", bombRounds=" + bombRounds +
			", teamSneakingMinutes=" + teamSneakingMinutes +
			", teamSneakingRounds=" + teamSneakingRounds +
			", stealthDeathMatchMinutes=" + stealthDeathMatchMinutes +
			", stealthDeathMatchRounds=" + stealthDeathMatchRounds +
			", intervalMinutes=" + intervalMinutes +
			", stealthCaptureMinutes=" + stealthCaptureMinutes +
			", stealthCaptureRounds=" + stealthCaptureRounds +
			", stealthCaptureExtraTimeEnabled=" + stealthCaptureExtraTimeEnabled +
			", raceMinutes=" + raceMinutes +
			", raceRounds=" + raceRounds +
			", raceExtraTimeEnabled=" + raceExtraTimeEnabled +
			'}';
	}
}
