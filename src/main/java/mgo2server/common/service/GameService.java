package mgo2server.common.service;

import mgo2server.common.model.ConnectionInfo;
import mgo2server.common.model.Game;
import mgo2server.common.model.HostSettings;
import org.jdbi.v3.core.Jdbi;

import java.nio.charset.StandardCharsets;
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

	/**
	 * Players currently sitting in games, grouped by lobby — the occupancy figure the gate's lobby
	 * list shows. Derived from {@code game_player} rather than a live presence table, so players
	 * idling in a lobby without having joined a game are invisible; that turns "always 0" into
	 * "0 unless games are up", the cheapest of the sketches in {@code dev/docs/BACKLOG.md}.
	 * Operator policy, not protocol: nothing pins what the original counted here.
	 */
	public java.util.Map<Long, Integer> countPlayersByLobby() {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select g.lobby_id as lobby_id, count(*) as players
					from game_player gp
					join game g on g.id = gp.game_id
					group by g.lobby_id
					""")
				.map((rs, ctx) -> java.util.Map.entry(rs.getLong("lobby_id"), rs.getInt("players")))
				.collectToMap(java.util.Map.Entry::getKey, java.util.Map.Entry::getValue));
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
	public record GamePlayer(long charaId, String name, int experience, int ping) {
	}

	/**
	 * The players in a game, host first — the details reply lists the host's entry before
	 * everyone else. Experience follows the same main/alt split as {@link #averageExperience}.
	 */
	public List<GamePlayer> getPlayers(long gameId, long hostCharaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select c.id, c.name, gp.ping,
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
					rs.getInt("exp"), rs.getInt("ping")))
				.list());
	}

	/** The game a character hosts in a lobby, if any — a character hosts at most one. */
	public Optional<Game> getHostedGame(long lobbyId, long hostCharaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from game where lobby_id=:lobby and host_chara_id=:host")
				.bind("lobby", lobbyId)
				.bind("host", hostCharaId)
				.mapTo(Game.class)
				.findOne());
	}

	/**
	 * Saves the raw {@code 0x4310} settings blob a character pushed, keyed by lobby subtype like
	 * the parsed settings row, so {@code 0x4304} can replay it next session. Upserts because the
	 * push arrives before create-game materialises the settings row on first use.
	 */
	public void saveHostSettingsBlob(long charaId, int type, byte[] blob) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into chara_host_settings (chara_id, type, blob) values (:id, :type, :blob)
					on conflict (chara_id, type) do update set blob = excluded.blob
					""")
				.bind("id", charaId)
				.bind("type", type)
				.bind("blob", blob)
				.execute());
	}

	/** The last {@code 0x4310} blob a character pushed for a lobby subtype, if any. */
	public Optional<byte[]> getHostSettingsBlob(long charaId, int type) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select blob from chara_host_settings
					where chara_id=:id and type=:type and blob is not null
					""")
				.bind("id", charaId)
				.bind("type", type)
				.mapTo(byte[].class)
				.findOne());
	}

	/**
	 * The host advanced the rotation ({@code 0x4392}): record which entry is current and the
	 * rule/map/flags it resolves to, so the browser and details reflect the round actually up.
	 */
	public void setCurrentGame(long gameId, int index, int rule, int map, int flags) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update game set current_game=:index, rule=:rule, map=:map, flags=:flags,
						last_update=now()
					where id=:id
					""")
				.bind("index", index)
				.bind("rule", rule)
				.bind("map", map)
				.bind("flags", flags)
				.bind("id", gameId)
				.execute());
	}

	/**
	 * The host's latency report ({@code 0x4398}): its own ping onto the game row (shown in the
	 * browser), each player's onto their roster row (shown in the player list), and the game's
	 * {@code last_update} touched — the report doubles as the host's heartbeat, which is what the
	 * reference uses it for.
	 */
	public void updatePings(long gameId, int hostPing, java.util.Map<Long, Integer> playerPings) {
		jdbi.useHandle(handle -> {
			handle.createUpdate("update game set ping=:ping, last_update=now() where id=:id")
				.bind("ping", hostPing)
				.bind("id", gameId)
				.execute();
			var batch = handle.prepareBatch(
				"update game_player set ping=:ping where game_id=:game and chara_id=:chara");
			playerPings.forEach((charaId, ping) ->
				batch.bind("game", gameId).bind("chara", charaId).bind("ping", ping).add());
			batch.execute();
		});
	}

	/**
	 * Hands a game to a new host ({@code 0x43a0}). The old host leaves the roster, matching the
	 * reference: it passed hosting because it is quitting. Joins keep working unchanged because
	 * {@code 0x4320} reads the host's endpoint from {@code chara_connection} by the game's host id
	 * at join time, and the new host registered its own endpoint on lobby entry.
	 */
	public void passHost(long gameId, long oldHostCharaId, long newHostCharaId) {
		jdbi.useHandle(handle -> {
			handle.createUpdate("update game set host_chara_id=:host, last_update=now() where id=:id")
				.bind("host", newHostCharaId)
				.bind("id", gameId)
				.execute();
			handle.createUpdate("delete from game_player where game_id=:game and chara_id=:chara")
				.bind("game", gameId)
				.bind("chara", oldHostCharaId)
				.execute();
		});
	}

	/**
	 * Snapshots the roster at round start ({@code 0x43ca}) into {@code game_round}, replacing the
	 * previous round's snapshot. The snapshot lives apart from the roster on purpose: its whole
	 * job is to let {@link #playedLastRound} answer true for a player who has since <em>left</em>
	 * the game, so the host's end-of-round stat report for a quitter still applies — the case the
	 * reference's {@code playersLastRound} list exists for.
	 */
	public void markRoundPlayers(long gameId) {
		// Insert-only, no delete: game_round accumulates everyone who has been in the game (it is
		// also populated on join/create) so a mid-round quitter's stats still apply. Refreshing
		// the current roster here is redundant with that but harmless — kept for the 0x43c8
		// start-round path if this client ever sends it.
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into game_round (game_id, chara_id)
					select game_id, chara_id from game_player where game_id=:id
					on conflict do nothing
					""")
				.bind("id", gameId)
				.execute());
	}

	/** Whether a character was in the game when the current round started, roster or not. */
	public boolean playedLastRound(long gameId, long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select exists (
						select 1 from game_round where game_id=:game and chara_id=:chara
					)
					""")
				.bind("game", gameId)
				.bind("chara", charaId)
				.mapTo(Boolean.class)
				.one());
	}

	/**
	 * One decoded {@code 0x4390} report. {@code structA} is the 15 s16 counters at wire
	 * {@code 0x05}–{@code 0x22} in wire order (confirmed labels live at fixed indices — kills 0,
	 * deaths 1, score 3, stuns 4, headshots 6, headshot-deaths 7, rounds-played 12);
	 * {@code detail} is the 58 s16 struct-B block, empty in the short report form.
	 */
	public record RoundReport(long gameId, long hostCharaId, long charaId, int flag,
			short[] structA, long seconds, long experienceTotal, long detailPresent,
			short[] detail, long trailingWord, boolean aborted) {
	}

	/**
	 * Stores one {@code 0x4390} report verbatim — the single write of the stats/history store
	 * (BACKLOG, "Match/encounter history"): lifetime, period and per-mode stats and the
	 * met-players history are all derived from these rows at query time.
	 */
	public void insertRoundReport(RoundReport report) {
		jdbi.useHandle(handle -> {
			// Core Jdbi has no argument factory for java.sql.Array, so the struct-B block is
			// bound as a Postgres array literal and cast in the statement.
			var detail = new StringBuilder("{");
			for (var i = 0; i < report.detail().length; i++) {
				detail.append(i == 0 ? "" : ",").append(report.detail()[i]);
			}
			detail.append('}');

			var update = handle.createUpdate("""
					insert into round_report
						(game_id, host_chara_id, chara_id, flag_0x04,
						 kills, deaths, counter_0x09, score, stuns, counter_0x0f,
						 headshots, headshot_deaths, counter_0x15, counter_0x17,
						 counter_0x19, counter_0x1b, rounds_played, counter_0x1f, counter_0x21,
						 seconds_in_game, experience_total, detail_present, detail_counters,
						 trailing_word, aborted)
					values (:game, :host, :chara, :flag,
						 :a0, :a1, :a2, :a3, :a4, :a5, :a6, :a7, :a8, :a9,
						 :a10, :a11, :a12, :a13, :a14,
						 :seconds, :exp, :detailPresent, cast(:detail as smallint[]),
						 :trailing, :aborted)
					""")
				.bind("game", report.gameId())
				.bind("host", report.hostCharaId())
				.bind("chara", report.charaId())
				.bind("flag", report.flag())
				.bind("seconds", report.seconds())
				.bind("exp", report.experienceTotal())
				.bind("detailPresent", report.detailPresent())
				.bind("detail", detail.toString())
				.bind("trailing", report.trailingWord())
				.bind("aborted", report.aborted());
			for (var i = 0; i < 15; i++) {
				update.bind("a" + i, report.structA()[i]);
			}
			update.execute();
		});
	}

	/** One row of the met-players history: a player encountered, and when last. */
	public record MetPlayer(long charaId, String name, long lastMetEpochSeconds) {
	}

	/**
	 * The met-players history for {@code 0x4680}, derived from {@code round_report}: every other
	 * character with a report in a game the viewer has a report in, newest encounter first.
	 * Pairing is per game, not per round — the frame carries no round counter, and sharing a game
	 * is what the screen's "players you ran into" means. Soft-deleted characters appear under
	 * their placeholder name rather than vanishing.
	 */
	public List<MetPlayer> metPlayers(long charaId, int limit) {
		// The join uses != rather than the SQL-standard form: Jdbi renders through
		// StringTemplate, which reads angle brackets as an expression and fails to compile the
		// statement (same trap TestDatabase.reset() documents) — and that goes for SQL comments
		// too, so this note lives out here.
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select o.chara_id, c.name,
						extract(epoch from max(o.reported_at))::bigint as last_met
					from round_report mine
					join round_report o
						on o.game_id = mine.game_id and o.chara_id != mine.chara_id
					join chara c on c.id = o.chara_id
					where mine.chara_id = :chara
					group by o.chara_id, c.name
					order by last_met desc
					limit :limit
					""")
				.bind("chara", charaId)
				.bind("limit", limit)
				.map((rs, ctx) -> new MetPlayer(rs.getLong("chara_id"), rs.getString("name"),
					rs.getLong("last_met")))
				.list());
	}

	/**
	 * Applies the host's end-of-round experience report ({@code 0x4390}) to a character's account
	 * pool — the main pool if the target is the account's main character, the alt pool otherwise,
	 * the same split every other experience read uses. The value is an <b>absolute total</b>, not
	 * a delta, per the reference. An aborted round instead docks 60 points, floored at zero —
	 * that penalty is the reference's <em>operator policy</em>, inherited knowingly.
	 */
	public void applyRoundExperience(long charaId, int experience, boolean aborted) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update account a set
						main_exp = case
							when a.main_chara_id = :chara then
								case when :aborted then greatest(0, a.main_exp - 60) else :exp end
							else a.main_exp end,
						alt_exp = case
							when a.main_chara_id = :chara then a.alt_exp
							else case when :aborted then greatest(0, a.alt_exp - 60) else :exp end
							end
					from chara c
					where c.account_id = a.id and c.id = :chara
					""")
				.bind("chara", charaId)
				.bind("aborted", aborted)
				.bind("exp", experience)
				.execute());
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

			// Also into game_round: anyone who has been in the game counts as "played", so the
			// host's end-of-round stat report (0x4390) still applies to a player who quit
			// mid-round. This is populated here and on join rather than depending on the round
			// snapshot (0x43ca/0x43c8), which this client rarely sends.
			handle.createUpdate("insert into game_round (game_id, chara_id) values (:game, :chara)")
				.bind("game", gameId)
				.bind("chara", hostCharaId)
				.execute();

			return gameId;
		});
	}

	private static int blobU32(byte[] b, int off) {
		return ((b[off] & 0xff) << 24) | ((b[off + 1] & 0xff) << 16)
			| ((b[off + 2] & 0xff) << 8) | (b[off + 3] & 0xff);
	}

	/** Reads a fixed-width, NUL-terminated ISO-8859-1 string from the blob. */
	private static String blobString(byte[] b, int off, int max) {
		if (off >= b.length) {
			return "";
		}
		var limit = Math.min(off + max, b.length);
		var end = off;
		while (end < limit && b[end] != 0) {
			end++;
		}
		return new String(b, off, end - off, StandardCharsets.ISO_8859_1);
	}

	/**
	 * Applies a host's {@code 0x4310} settings blob to a game: the fields it genuinely carries into
	 * their columns, plus the raw blob into {@code host_settings} (replayed by the details reply for
	 * the per-mode timer table at {@code 0xFC} and uniques).
	 * <p>
	 * Handled here: name(0x00), comment(0x10), password(flag 0x90 / text 0x91), dedicated(0xA1),
	 * round-0 rule/map/flags(0xA3), max players(0xE5), briefing time(0xE6 BE u32), stance(0xF6),
	 * level-limit tolerance(0xF7) and base(0xF8 BE u32), the Common Settings toggle bitfields
	 * commonA(0x142)/commonB(0x143), idle-kick(0x146) and team-kill-kick(0x148) counts — each
	 * zeroed when its enable bit (commonA bit 0 / commonB bit 7) is off — and non-stat from the
	 * host-options byte(0x155, bit 1).
	 * <p>
	 * <b>Provenance:</b> the toggle location and the {@code 0xF8} base were <b>confirmed by a live
	 * capture 2026-07-22</b> — hosting twice with only friendly fire flipped moved exactly bit 3 of
	 * byte {@code 0x142}, and the level-limit-disabled baseline read 0 at {@code 0xF8} — settling
	 * the conflict between Nomad's decode and an earlier ELF reading that put a u16 base at
	 * {@code 0x142} (which had been storing commonA/commonB garbage as the base). The bit map
	 * matches {@code GameListEntry}'s packers bit for bit, so the list/details replies now
	 * round-trip real toggles. See OBSERVED.md, "Where the Common Settings toggles live".
	 */
	public void applyHostSettings(long gameId, byte[] blob) {
		if (blob == null || blob.length < 0x156) {
			return;
		}
		var passwordSet = (blob[0x90] & 0xff) != 0;
		var commonA = blob[0x142] & 0xff;
		var commonB = blob[0x143] & 0xff;
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update game set
						name = :name, comment = :comment, password = :password,
						rule = :rule, map = :map, flags = :flags, dedicated = :dedicated,
						max_players = :maxPlayers, briefing_time = :briefingTime, stance = :stance,
						level_limit_enabled = :levelLimitEnabled,
						level_limit_tolerance = :tolerance, level_limit_base = :base,
						friendly_fire = :friendlyFire, ghosts = :ghosts, auto_aim = :autoAim,
						uniques_enabled = :uniques, teams_switch = :teamsSwitch,
						auto_assign = :autoAssign, silent_mode = :silentMode,
						enemy_nametags = :enemyNametags, voice_chat = :voiceChat,
						non_stat = :nonStat,
						idle_kick = :idleKick, team_kill_kick = :teamKillKick,
						host_settings = :blob
					where id = :id
					""")
				.bind("name", blobString(blob, 0x00, 16))
				.bind("comment", blobString(blob, 0x10, 128))
				.bind("password", passwordSet ? blobString(blob, 0x91, 16) : null)
				.bind("dedicated", (blob[0xA1] & 0xff) != 0)
				.bind("rule", blob[0xA3] & 0xff)
				.bind("map", blob[0xA4] & 0xff)
				.bind("flags", blob[0xA5] & 0xff)
				.bind("maxPlayers", blob[0xE5] & 0xff)
				.bind("briefingTime", blobU32(blob, 0xE6))
				.bind("stance", blob[0xF6] & 0xff)
				.bind("tolerance", blob[0xF7] & 0xff)
				.bind("base", blobU32(blob, 0xF8))
				.bind("levelLimitEnabled", (commonB & 0b10000) != 0)
				.bind("friendlyFire", (commonA & 0b1000) != 0)
				.bind("ghosts", (commonA & 0b10000) != 0)
				// Oddity, pinned 2026-07-22: bit 5 (Nomad: auto-aim) is set in EVERY capture from
				// this client, all-disabled baselines included, and no aim setting exists anywhere
				// in this build's Create screens — later-patch content or fed from player settings.
				// Decoded as transcribed; on this client the column simply always reads true.
				.bind("autoAim", (commonA & 0b100000) != 0)
				// Uniques (bit 7, selectors 0x140/0x141) are the one commonA field the capture
				// sweep could NOT verify: the setting is absent from this build's Create screens
				// (expansion-era content). Reference-only — see BACKLOG, "Unique characters".
				.bind("uniques", (commonA & 0b10000000) != 0)
				.bind("teamsSwitch", (commonB & 0b1) != 0)
				.bind("autoAssign", (commonB & 0b10) != 0)
				.bind("silentMode", (commonB & 0b100) != 0)
				.bind("enemyNametags", (commonB & 0b1000) != 0)
				.bind("voiceChat", (commonB & 0b1000000) != 0)
				.bind("nonStat", (blob[0x155] & 0b10) != 0)
				.bind("idleKick", (commonA & 0b1) != 0 ? blob[0x146] & 0xff : 0)
				.bind("teamKillKick", (commonB & 0b10000000) != 0 ? blob[0x148] & 0xff : 0)
				.bind("blob", blob)
				.bind("id", gameId)
				.execute());
	}

	/**
	 * Updates the name, comment and password of the game a character is hosting — the in-game host
	 * edit ({@code 0x43c0}). A character hosts at most one game per lobby, so this keys on the host
	 * character rather than a game id the edit does not carry. A {@code null} password clears the
	 * lock.
	 */
	public void updateGameSettings(long lobbyId, long hostCharaId, String name, String comment,
			String password) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update game set name = :name, comment = :comment, password = :password
					where lobby_id = :lobbyId and host_chara_id = :host
					""")
				.bind("name", name)
				.bind("comment", comment)
				.bind("password", password)
				.bind("lobbyId", lobbyId)
				.bind("host", hostCharaId)
				.execute());
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
		// Record round membership too — see createGame. A quitter stays in game_round so their
		// end-of-round stats still apply.
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into game_round (game_id, chara_id) values (:game, :chara)
					on conflict do nothing
					""")
				.bind("game", gameId)
				.bind("chara", charaId)
				.execute());
	}
}
