package mgo2server.common.service;

import mgo2server.common.model.ConnectionInfo;
import mgo2server.common.model.Game;
import mgo2server.common.model.HostSettings;
import org.jdbi.v3.core.Jdbi;

import java.util.List;
import java.util.Optional;

public class GameService {
	private final Jdbi jdbi;

	public GameService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/** Games advertised in a lobby, newest last so the list does not reshuffle between requests. */
	public List<Game> getGames(long lobbyId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from game where lobby_id=:lobbyId order by id")
				.bind("lobbyId", lobbyId)
				.mapTo(Game.class)
				.list());
	}

	public Optional<Game> get(long gameId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from game where id=:id")
				.bind("id", gameId)
				.mapTo(Game.class)
				.findOne());
	}

	public int countPlayers(long gameId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select count(*) from game_player where game_id=:id")
				.bind("id", gameId)
				.mapTo(Integer.class)
				.one());
	}

	/**
	 * Mean experience of the players in a game, which the client shows in the browser. Experience
	 * lives on the account and is split between the main character and the alts, so this picks
	 * the pool matching each player's character.
	 */
	public int averageExperience(long gameId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select coalesce(avg(case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end), 0)
					from game_player gp
					join chara c on c.id = gp.chara_id
					join account a on a.id = c.account_id
					where gp.game_id = :id
					""")
				.bind("id", gameId)
				.mapTo(Integer.class)
				.one());
	}

	/** One row of a game's player list, as the details reply needs it. */
	public record GamePlayer(long charaId, String name, int experience) {
	}

	/**
	 * The players in a game, host first — the details reply lists the host's entry before
	 * everyone else. Experience follows the same main/alt split as {@link #averageExperience}.
	 */
	public List<GamePlayer> getPlayers(long gameId, long hostCharaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select c.id, c.name,
						case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end as exp
					from game_player gp
					join chara c on c.id = gp.chara_id
					join account a on a.id = c.account_id
					where gp.game_id = :id
					order by (gp.chara_id = :host) desc, gp.joined_at
					""")
				.bind("id", gameId)
				.bind("host", hostCharaId)
				.map((rs, ctx) -> new GamePlayer(rs.getLong("id"), rs.getString("name"),
					rs.getInt("exp")))
				.list());
	}

	/**
	 * The host settings a character uses for a lobby subtype, creating defaults on first use.
	 * The original does the same, materialising a default settings blob when none exists.
	 */
	public HostSettings getOrCreateHostSettings(long charaId, int type, String defaultName) {
		var existing = jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_host_settings where chara_id=:id and type=:type")
				.bind("id", charaId)
				.bind("type", type)
				.mapTo(HostSettings.class)
				.findOne());

		if (existing.isPresent()) {
			return existing.get();
		}

		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into chara_host_settings (chara_id, type, name)
					values (:id, :type, :name)
					on conflict do nothing
					""")
				.bind("id", charaId)
				.bind("type", type)
				.bind("name", defaultName)
				.execute());

		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_host_settings where chara_id=:id and type=:type")
				.bind("id", charaId)
				.bind("type", type)
				.mapTo(HostSettings.class)
				.one());
	}

	public void saveHostSettings(HostSettings settings) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update chara_host_settings set
						name = :name, password = :password, comment = :comment,
						stance = :stance, max_players = :maxPlayers, briefing_time = :briefingTime, level_limit_base = :levelLimitBase, level_limit_tolerance = :levelLimitTolerance, team_kill_kick = :teamKillKick, idle_kick = :idleKick, dedicated = :dedicated, non_stat = :nonStat, friendly_fire = :friendlyFire, auto_aim = :autoAim, uniques_enabled = :uniquesEnabled, enemy_nametags = :enemyNametags, silent_mode = :silentMode, auto_assign = :autoAssign, teams_switch = :teamsSwitch, ghosts = :ghosts, voice_chat = :voiceChat, level_limit_enabled = :levelLimitEnabled
					where chara_id = :charaId and type = :type
					""")
				.bindBean(settings)
				.execute());
	}

	/** Creates a game from a character's host settings and puts the host in it. */
	public long createGame(long lobbyId, long hostCharaId, HostSettings settings) {
		return jdbi.inTransaction(handle -> {
			var gameId = handle.createUpdate("""
					insert into game (lobby_id, host_chara_id, name, password, comment,
						stance, max_players, briefing_time, level_limit_base, level_limit_tolerance, team_kill_kick, idle_kick, dedicated, non_stat, friendly_fire, auto_aim, uniques_enabled, enemy_nametags, silent_mode, auto_assign, teams_switch, ghosts, voice_chat, level_limit_enabled)
					values (:lobbyId, :hostCharaId, :name, :password, :comment,
						:stance, :maxPlayers, :briefingTime, :levelLimitBase, :levelLimitTolerance, :teamKillKick, :idleKick, :dedicated, :nonStat, :friendlyFire, :autoAim, :uniquesEnabled, :enemyNametags, :silentMode, :autoAssign, :teamsSwitch, :ghosts, :voiceChat, :levelLimitEnabled)
					""")
				.bind("lobbyId", lobbyId)
				.bind("hostCharaId", hostCharaId)
				.bindBean(settings)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one();

			handle.createUpdate("insert into game_player (game_id, chara_id) values (:game, :chara)")
				.bind("game", gameId)
				.bind("chara", hostCharaId)
				.execute();

			return gameId;
		});
	}

	public void deleteGame(long gameId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("delete from game where id=:id").bind("id", gameId).execute());
	}

	/**
	 * Clears every game in a lobby. Called when the lobby server starts: a game only exists while
	 * its host holds a connection to this server, so any row that survived a restart is a ghost —
	 * it lingers in the browser but nobody is hosting it. {@code game_player} rows cascade.
	 *
	 * @return the number of stale games removed
	 */
	public int deleteGamesInLobby(long lobbyId) {
		return jdbi.withHandle(handle ->
			handle.createUpdate("delete from game where lobby_id=:lobbyId")
				.bind("lobbyId", lobbyId)
				.execute());
	}

	/** Records a character's peer-to-peer endpoints, replacing any previous registration. */
	public void saveConnectionInfo(ConnectionInfo info) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into chara_connection
						(chara_id, public_ip, public_port, private_ip, private_port, updated_at)
					values (:charaId, :publicIp, :publicPort, :privateIp, :privatePort, now())
					on conflict (chara_id) do update set
						public_ip = excluded.public_ip, public_port = excluded.public_port,
						private_ip = excluded.private_ip, private_port = excluded.private_port,
						updated_at = now()
					""")
				.bindBean(info)
				.execute());
	}

	/** The endpoints a character registered, if any — the host's, for a joining player. */
	public Optional<ConnectionInfo> getConnectionInfo(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_connection where chara_id=:id")
				.bind("id", charaId)
				.mapTo(ConnectionInfo.class)
				.findOne());
	}

	/**
	 * Removes a character from whatever game they are in — used when their peer connection to the
	 * host failed. The join-failed notification carries no game id, and a character can only be in
	 * one game at a time, so this keys on the character alone.
	 */
	public void removePlayerFromGames(long charaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("delete from game_player where chara_id=:chara")
				.bind("chara", charaId)
				.execute());
	}

	/** Adds a character to a game, ignoring a repeat join. */
	public void addPlayer(long gameId, long charaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into game_player (game_id, chara_id) values (:game, :chara)
					on conflict do nothing
					""")
				.bind("game", gameId)
				.bind("chara", charaId)
				.execute());
	}
}
