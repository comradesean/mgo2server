package mgo2server.common.model;

/**
 * The settings a character hosts games with, kept per lobby subtype.
 * <p>
 * Typed rather than the original's JSON blob, because the game list has to derive bitfields
 * from these on every request and that is much easier to verify against real fields.
 */
public class HostSettings {
	private long charaId;

	private int type;

	private String name = "";

	private String password;

	private String comment = "";

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

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getType() {
		return type;
	}

	public void setType(int type) {
		this.type = type;
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
		return "HostSettings{charaId=" + charaId + ", type=" + type + ", name='" + name + "'}";
	}
}
