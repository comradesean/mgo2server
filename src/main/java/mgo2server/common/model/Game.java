package mgo2server.common.model;

import java.time.OffsetDateTime;

/** A hosted game, as advertised in a lobby's game list. */
public class Game {
	private long id;

	private long lobbyId;

	private long hostCharaId;

	private String name = "";

	private String password;

	private String comment = "";

	private int currentGame;

	private int rule;

	private int map;

	private int flags;


	private short[] rotationRules;

	private short[] rotationMaps;

	private short[] rotationFlags;

	private byte[] weaponRestrictions;

	private int[] ruleTimers;

	private int uniqueRed;

	private int uniqueBlue;

	private boolean captureExtraTime;

	private int sneakingSnakeKills;

	private byte[] unreadTail;

	private int ping;

	private int hostScore;

	private int hostVotes;

	private OffsetDateTime lastUpdate;

	private int stance;

	private int maxPlayers;

	private int briefingTime;

	private int levelLimitBase;

	private int levelLimitTolerance;

	private int teamKillKick;

	private int idleKick;

	private boolean dedicated;

	private boolean nonStat;

	private boolean friendlyFire;

	private boolean autoAim;

	private boolean uniquesEnabled;

	private boolean enemyNametags;

	private boolean silentMode;

	private boolean autoAssign;

	private boolean teamsSwitch;

	private boolean ghosts;

	private boolean voiceChat;

	private boolean levelLimitEnabled;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public long getLobbyId() {
		return lobbyId;
	}

	public void setLobbyId(long lobbyId) {
		this.lobbyId = lobbyId;
	}

	public long getHostCharaId() {
		return hostCharaId;
	}

	public void setHostCharaId(long hostCharaId) {
		this.hostCharaId = hostCharaId;
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

	public String getComment() {
		return comment;
	}

	public void setComment(String comment) {
		this.comment = comment;
	}

	public int getCurrentGame() {
		return currentGame;
	}

	public void setCurrentGame(int currentGame) {
		this.currentGame = currentGame;
	}

	public int getRule() {
		return rule;
	}

	public void setRule(int rule) {
		this.rule = rule;
	}

	public int getFlags() {
		return flags;
	}

	public void setFlags(int flags) {
		this.flags = flags;
	}

	public short[] getRotationRules() {
		return rotationRules;
	}

	public void setRotationRules(short[] rotationRules) {
		this.rotationRules = rotationRules;
	}

	public short[] getRotationMaps() {
		return rotationMaps;
	}

	public void setRotationMaps(short[] rotationMaps) {
		this.rotationMaps = rotationMaps;
	}

	public short[] getRotationFlags() {
		return rotationFlags;
	}

	public void setRotationFlags(short[] rotationFlags) {
		this.rotationFlags = rotationFlags;
	}

	public byte[] getWeaponRestrictions() {
		return weaponRestrictions;
	}

	public void setWeaponRestrictions(byte[] weaponRestrictions) {
		this.weaponRestrictions = weaponRestrictions;
	}

	public int[] getRuleTimers() {
		return ruleTimers;
	}

	public void setRuleTimers(int[] ruleTimers) {
		this.ruleTimers = ruleTimers;
	}

	public int getUniqueRed() {
		return uniqueRed;
	}

	public void setUniqueRed(int uniqueRed) {
		this.uniqueRed = uniqueRed;
	}

	public int getUniqueBlue() {
		return uniqueBlue;
	}

	public void setUniqueBlue(int uniqueBlue) {
		this.uniqueBlue = uniqueBlue;
	}

	public boolean isCaptureExtraTime() {
		return captureExtraTime;
	}

	public void setCaptureExtraTime(boolean captureExtraTime) {
		this.captureExtraTime = captureExtraTime;
	}

	public int getSneakingSnakeKills() {
		return sneakingSnakeKills;
	}

	public void setSneakingSnakeKills(int sneakingSnakeKills) {
		this.sneakingSnakeKills = sneakingSnakeKills;
	}

	/**
	 * The 14 bytes the client writes as one raw block. Its first eight are the byte-sized timers the
	 * game-details reply replays; byte 10 carries the host-options flags {@code non_stat} comes from.
	 */
	public byte[] getUnreadTail() {
		return unreadTail;
	}

	public void setUnreadTail(byte[] unreadTail) {
		this.unreadTail = unreadTail;
	}


	public int getMap() {
		return map;
	}

	public void setMap(int map) {
		this.map = map;
	}

	public int getPing() {
		return ping;
	}

	public void setPing(int ping) {
		this.ping = ping;
	}

	public int getHostScore() {
		return hostScore;
	}

	public void setHostScore(int hostScore) {
		this.hostScore = hostScore;
	}

	public int getHostVotes() {
		return hostVotes;
	}

	public void setHostVotes(int hostVotes) {
		this.hostVotes = hostVotes;
	}

	public OffsetDateTime getLastUpdate() {
		return lastUpdate;
	}

	public void setLastUpdate(OffsetDateTime lastUpdate) {
		this.lastUpdate = lastUpdate;
	}

	public int getStance() {
		return stance;
	}

	public void setStance(int stance) {
		this.stance = stance;
	}

	public int getMaxPlayers() {
		return maxPlayers;
	}

	public void setMaxPlayers(int maxPlayers) {
		this.maxPlayers = maxPlayers;
	}

	public int getBriefingTime() {
		return briefingTime;
	}

	public void setBriefingTime(int briefingTime) {
		this.briefingTime = briefingTime;
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

	public int getTeamKillKick() {
		return teamKillKick;
	}

	public void setTeamKillKick(int teamKillKick) {
		this.teamKillKick = teamKillKick;
	}

	public int getIdleKick() {
		return idleKick;
	}

	public void setIdleKick(int idleKick) {
		this.idleKick = idleKick;
	}

	public boolean isDedicated() {
		return dedicated;
	}

	public void setDedicated(boolean dedicated) {
		this.dedicated = dedicated;
	}

	public boolean isNonStat() {
		return nonStat;
	}

	public void setNonStat(boolean nonStat) {
		this.nonStat = nonStat;
	}

	public boolean isFriendlyFire() {
		return friendlyFire;
	}

	public void setFriendlyFire(boolean friendlyFire) {
		this.friendlyFire = friendlyFire;
	}

	public boolean isAutoAim() {
		return autoAim;
	}

	public void setAutoAim(boolean autoAim) {
		this.autoAim = autoAim;
	}

	public boolean isUniquesEnabled() {
		return uniquesEnabled;
	}

	public void setUniquesEnabled(boolean uniquesEnabled) {
		this.uniquesEnabled = uniquesEnabled;
	}

	public boolean isEnemyNametags() {
		return enemyNametags;
	}

	public void setEnemyNametags(boolean enemyNametags) {
		this.enemyNametags = enemyNametags;
	}

	public boolean isSilentMode() {
		return silentMode;
	}

	public void setSilentMode(boolean silentMode) {
		this.silentMode = silentMode;
	}

	public boolean isAutoAssign() {
		return autoAssign;
	}

	public void setAutoAssign(boolean autoAssign) {
		this.autoAssign = autoAssign;
	}

	public boolean isTeamsSwitch() {
		return teamsSwitch;
	}

	public void setTeamsSwitch(boolean teamsSwitch) {
		this.teamsSwitch = teamsSwitch;
	}

	public boolean isGhosts() {
		return ghosts;
	}

	public void setGhosts(boolean ghosts) {
		this.ghosts = ghosts;
	}

	public boolean isVoiceChat() {
		return voiceChat;
	}

	public void setVoiceChat(boolean voiceChat) {
		this.voiceChat = voiceChat;
	}

	public boolean isLevelLimitEnabled() {
		return levelLimitEnabled;
	}

	public void setLevelLimitEnabled(boolean levelLimitEnabled) {
		this.levelLimitEnabled = levelLimitEnabled;
	}

	@Override
	public String toString() {
		return "Game{id=" + id + ", name='" + name + "', lobbyId=" + lobbyId + "}";
	}
}
