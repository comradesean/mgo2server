package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.common.service.CharacterService;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameDetails;
import mgo2server.common.model.CharaSkill;
import mgo2server.game.GameError;
import mgo2server.game.HostSettingsReply;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The in-match host commands: settings persistence and replay (0x4310/0x4304), rotation advance
 * (0x4392), ping reports (0x4398), the round snapshot (0x43ca), stat application (0x4390) and
 * pass-host (0x43a0).
 * <p>
 * The request layouts exercised here are transcribed from GHzGangster/Nomad (tier 4) — these are
 * <b>regression guards for the transcription</b>, not proof the layouts fit {@code BLUS30109};
 * each command still needs a live-client pass.
 * <p>
 * A quirk these tests work around: closing the connection tears down any game the character still
 * hosts ({@code HostGameController.onDisconnect}), so a test that wants to inspect the game row
 * after the exchange either asserts through a protocol reply instead, or ends the exchange by
 * passing the game to another character so it survives the close.
 */
public class MatchStateIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private long accountId;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private void givenSelectedCharacter(String name) {
		accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, main_exp)
					values (:name, 'x', :session, 3, 500)
					""")
				.bind("name", name)
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		grantStartingSkills(charaId);

		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
			.bind("chara", charaId).bind("id", accountId).execute());
	}

	/** A game hosted by the selected character, materialised directly so its id is known. */
	private long givenHostedGame() {
		var jdbi = TestDatabase.get().jdbi();
		var gameId = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into game (lobby_id, host_chara_id, name, host_settings)
					values (:lobby, :host, 'g', :blob)
					""")
				.bind("lobby", lobbyId)
				.bind("host", charaId)
				.bind("blob", settingsBlob())
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		jdbi.useHandle(handle ->
			handle.createUpdate("insert into game_player (game_id, chara_id) values (:g, :c)")
				.bind("g", gameId).bind("c", charaId).execute());
		return gameId;
	}

	/** A second character on another account, inserted straight into the roster. */
	private long givenJoinedPlayer(long gameId, String name) {
		var jdbi = TestDatabase.get().jdbi();
		var otherAccount = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, alt_exp)
					values (:name, 'x', :name, 3, 100)
					""")
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		var otherChara = jdbi.withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", otherAccount).bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		jdbi.useHandle(handle ->
			handle.createUpdate("insert into game_player (game_id, chara_id) values (:g, :c)")
				.bind("g", gameId).bind("c", otherChara).execute());
		return otherChara;
	}

	/**
	 * Logs in, then plays the requests one at a time, advancing after each reply — every command
	 * used here answers with exactly one packet.
	 */
	private List<GamePacket> exchange(GamePacket... requests) {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));

		// Appended from the netty read thread; synchronized so the returned snapshot cannot race
		// a late read after the run times out (seen once as a ConcurrentModificationException).
		var replies = java.util.Collections.synchronizedList(new ArrayList<GamePacket>());
		var sent = new int[] { 0 };

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}

				if (packet.getCommand() != AccountGameController.CHECK_SESSION_RESULT) {
					replies.add(packet);
				}

				if (sent[0] < requests.length) {
					ctx.writeAndFlush(requests[sent[0]++]);
				} else {
					ctx.close();
				}
			}
		});

		synchronized (replies) {
			return new ArrayList<>(replies);
		}
	}

	/** A synthetic 0x4310 blob: name, two rotation entries, and marker bytes in the tail. */
	private static byte[] settingsBlob() {
		var blob = new byte[0x156];
		blob[0] = 'S';
		blob[1] = 'S';
		// Rotation entry 0: rule 3, map 7, flags 1. Entry 1: rule 4, map 8, flags 2.
		blob[0xA3] = 3;
		blob[0xA4] = 7;
		blob[0xA5] = 1;
		blob[0xA6] = 4;
		blob[0xA7] = 8;
		blob[0xA8] = 2;
		blob[0xE5] = 12;           // max players
		blob[0x142] = (byte) 0x24; // stored opaquely; see BACKLOG on the 0x142/0x143 conflict
		blob[0x155] = 0x02;        // host options
		return blob;
	}

	private static GamePacket pushSettings() {
		return new GamePacket(HostGameController.CHECK_HOST_SETTINGS,
			Unpooled.wrappedBuffer(settingsBlob()));
	}

	private static GamePacket getDetails(long gameId) {
		var payload = Unpooled.buffer();
		payload.writeInt((int) gameId);
		return new GamePacket(GameListGameController.GET_GAME_DETAILS, payload);
	}

	private GamePacket passHostTo(long target) {
		var payload = Unpooled.buffer();
		payload.writeInt((int) charaId).writeInt((int) target);
		return new GamePacket(HostGameController.PASS_HOST, payload);
	}

	@Test
	public void savedSettingsComeBackRemapped() {
		givenSelectedCharacter("Snake");

		var replies = exchange(pushSettings(),
			new GamePacket(HostGameController.GET_HOST_SETTINGS));

		assertThat(replies).hasSize(2);
		var settings = replies.get(1);
		assertThat(settings.getCommand()).isEqualTo(HostGameController.HOST_SETTINGS_RESULT);
		// 0x4305 is Blowfish-encrypted outbound, so the wire payload is the reply zero-padded to
		// the cipher's 8-byte boundary; the real client sees the same padded length.
		assertThat(settings.getPayload().readableBytes())
			.isEqualTo((HostSettingsReply.SIZE + 7) / 8 * 8);
		assertThat(settings.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		// Name re-based from request 0x00 to reply 0x04; rotation from 0xA3 to 0xA6.
		assertThat(settings.getPayload().getByte(0x04)).isEqualTo((byte) 'S');
		assertThat(settings.getPayload().getByte(0xA6)).isEqualTo((byte) 3);
		assertThat(settings.getPayload().getByte(0xE8)).isEqualTo((byte) 12);
	}

	@Test
	public void aCharacterWithNothingSavedGetsTheEmptyBlock() {
		givenSelectedCharacter("Snake");

		var replies = exchange(new GamePacket(HostGameController.GET_HOST_SETTINGS));

		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(128);
	}

	/** Asserted through the details reply: the game row is torn down when the host disconnects. */
	@Test
	public void setGameAdvancesTheRotation() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();

		var setGame = new GamePacket(HostGameController.SET_GAME,
			Unpooled.wrappedBuffer(new byte[] { 1 }));
		var replies = exchange(setGame, getDetails(gameId));

		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.SET_GAME_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		var details = replies.get(1).getPayload();
		// Round 0 of the details rotation (offset 0xA8) reflects the entry the host advanced to.
		assertThat(details.getByte(0x0A8)).isEqualTo((byte) 4);
		assertThat(details.getByte(0x0A9)).isEqualTo((byte) 8);
		assertThat(details.getByte(0x0AA)).isEqualTo((byte) 2);
	}

	/**
	 * Ends with a pass-host so the game row survives the disconnect teardown and the ping columns
	 * can be read back — which makes this test depend on pass-host working (covered on its own
	 * below).
	 */
	@Test
	public void pingReportsLandOnTheGameAndTheRoster() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		var report = Unpooled.buffer();
		report.writeInt(48); // the host's own ping
		report.writeInt((int) joiner).writeInt(96);
		report.writeInt(0).writeInt(999); // a zero id is skipped, as in the reference

		var replies = exchange(new GamePacket(HostGameController.UPDATE_PINGS, report),
			getDetails(gameId), passHostTo(joiner));

		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.UPDATE_PINGS_RESULT);
		// 4 bytes, not empty, since 2026-07-26: the 0x4399 parser (0xD40530) reads a u32
		// unconditionally and feeds it to wait slot 44. The empty reply only ever "worked" because
		// the read primitives bound-check the 1023-byte receive buffer instead of the payload
		// length, so the client took four bytes of stale buffer as its result code. This assertion
		// used to require the empty form.
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(Integer.BYTES);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		// The joiner's entry is second (host first); ping sits 20 bytes into the 28-byte entry.
		var details = replies.get(1).getPayload();
		assertThat(details.getInt(GameDetails.FIXED_SIZE + GameDetails.PLAYER_SIZE + 20))
			.isEqualTo(96);

		var jdbi = TestDatabase.get().jdbi();
		var hostPing = jdbi.withHandle(handle ->
			handle.createQuery("select ping from game where id=:id")
				.bind("id", gameId).mapTo(Integer.class).one());
		assertThat(hostPing).isEqualTo(48);
	}

	/**
	 * The snapshot's reason to exist: a player who leaves mid-round must still receive the host's
	 * end-of-round report. The roster row is deleted between round start and the report, mid
	 * exchange, exactly as a quit would do it.
	 */
	@Test
	public void statsStillApplyToAPlayerWhoLeftMidRound() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		var stats = new byte[0xB8];
		writeInt(stats, 0, (int) joiner);
		writeInt(stats, 0x27, 2500);

		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				switch (packet.getCommand()) {
					case AccountGameController.CHECK_SESSION_RESULT ->
						ctx.writeAndFlush(new GamePacket(HostGameController.START_ROUND));
					case HostGameController.START_ROUND_RESULT -> {
						// The joiner quits after the round started.
						TestDatabase.get().jdbi().useHandle(handle ->
							handle.createUpdate("delete from game_player where chara_id=:c")
								.bind("c", joiner).execute());
						ctx.writeAndFlush(new GamePacket(HostGameController.UPDATE_STATS,
							Unpooled.wrappedBuffer(stats)));
					}
					case HostGameController.UPDATE_STATS_RESULT -> ctx.close();
					default -> { }
				}
			}
		});

		var joinerExp = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("""
					select a.alt_exp from account a join chara c on c.account_id = a.id
					where c.id = :c
					""")
				.bind("c", joiner).mapTo(Integer.class).one());
		assertThat(joinerExp).isEqualTo(2500);
	}

	@Test
	public void statsApplyOnlyToPlayersInTheRound() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		// Nomad's read: target id at 0, experience at 0x27, aborted byte at 0xB7.
		var stats = new byte[0xB8];
		writeInt(stats, 0, (int) joiner);
		writeInt(stats, 0x27, 4321);
		var stranger = new byte[0xB8];
		writeInt(stranger, 0, 999999);
		writeInt(stranger, 0x27, 7777);

		var replies = exchange(
			new GamePacket(HostGameController.START_ROUND),
			new GamePacket(HostGameController.UPDATE_STATS, Unpooled.wrappedBuffer(stats)),
			new GamePacket(HostGameController.UPDATE_STATS, Unpooled.wrappedBuffer(stranger)));

		assertThat(replies).extracting(GamePacket::getCommand).containsExactly(
			HostGameController.START_ROUND_RESULT,
			HostGameController.UPDATE_STATS_RESULT,
			HostGameController.UPDATE_STATS_RESULT);

		// The joiner is not their account's main character, so the alt pool takes the total.
		var joinerExp = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("""
					select a.alt_exp from account a join chara c on c.account_id = a.id
					where c.id = :c
					""")
				.bind("c", joiner).mapTo(Integer.class).one());
		assertThat(joinerExp).isEqualTo(4321);
	}

	/**
	 * The report length this client actually sends — 167 bytes, confirmed live 2026-07-22 with
	 * the experience field matching a 50,000-exp account to the byte. Shorter than Nomad's
	 * assumed minimum, so it has no aborted byte; it must still apply.
	 */
	@Test
	public void a167ByteStatReportApplies() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		var stats = new byte[167];
		writeInt(stats, 0, (int) joiner);
		writeInt(stats, 0x27, 1234);

		var replies = exchange(
			new GamePacket(HostGameController.UPDATE_STATS, Unpooled.wrappedBuffer(stats)));

		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.UPDATE_STATS_RESULT);
		var joinerExp = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("""
					select a.alt_exp from account a join chara c on c.account_id = a.id
					where c.id = :c
					""")
				.bind("c", joiner).mapTo(Integer.class).one());
		assertThat(joinerExp).isEqualTo(1234);
	}

	/**
	 * Each report is stored verbatim as one round_report row — the single source every stats
	 * and history screen derives from. Lifetime totals are sums over these rows, so two reports
	 * for the same character make two rows, not one accumulated row.
	 */
	@Test
	public void statReportStoresOneRoundReportRowPerReport() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		// Two rounds: kills 5 then 3, deaths 2 then 4, score 26 then -3, headshots 5 then 2,
		// headshot-deaths 2 then 0, stuns 1 then 0.
		var r1 = statReport((int) joiner, 5, 2, 26, 5, 2, 1);
		var r2 = statReport((int) joiner, 3, 4, -3, 2, 0, 0);
		exchange(
			new GamePacket(HostGameController.UPDATE_STATS, Unpooled.wrappedBuffer(r1)),
			new GamePacket(HostGameController.UPDATE_STATS, Unpooled.wrappedBuffer(r2)));

		var rows = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select * from round_report where chara_id=:c order by id")
				.bind("c", joiner).mapToMap().list());
		assertThat(rows).hasSize(2);
		assertThat(((Number) rows.get(0).get("game_id")).longValue()).isEqualTo(gameId);
		assertThat(((Number) rows.get(0).get("host_chara_id")).longValue()).isEqualTo(charaId);
		assertThat(((Number) rows.get(0).get("kills")).intValue()).isEqualTo(5);
		assertThat(((Number) rows.get(0).get("deaths")).intValue()).isEqualTo(2);
		assertThat(((Number) rows.get(0).get("score")).intValue()).isEqualTo(26);
		assertThat(((Number) rows.get(0).get("headshots")).intValue()).isEqualTo(5);
		assertThat(((Number) rows.get(0).get("headshot_deaths")).intValue()).isEqualTo(2);
		assertThat(((Number) rows.get(0).get("stuns")).intValue()).isEqualTo(1);
		assertThat(((Number) rows.get(1).get("kills")).intValue()).isEqualTo(3);
		assertThat(((Number) rows.get(1).get("score")).intValue()).isEqualTo(-3);

		// Wire 0x23 is {u16 team-win flag, u16 seconds}; zeros in this frame land as 0/0.
		assertThat(((Number) rows.get(0).get("team_win")).intValue()).isEqualTo(0);
		assertThat(((Number) rows.get(0).get("seconds_in_game")).intValue()).isEqualTo(0);

		// The 167-byte long form carries the 58-slot struct-B block (zeros in this frame).
		var lifetimeKills = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select sum(kills) from round_report where chara_id=:c")
				.bind("c", joiner).mapTo(Integer.class).one());
		assertThat(lifetimeKills).isEqualTo(8);
	}

	/** A 167-byte report with the confirmed scoreboard slots set (signed s16 at 0x05 + 2*i). */
	private static byte[] statReport(int charaId, int kills, int deaths, int score, int headshots,
			int headshotDeaths, int stuns) {
		var r = new byte[167];
		writeInt(r, 0, charaId);
		writeShort(r, 0x05, kills);
		writeShort(r, 0x07, deaths);
		writeShort(r, 0x0b, score);
		writeShort(r, 0x0d, stuns);
		writeShort(r, 0x11, headshots);
		writeShort(r, 0x13, headshotDeaths);
		return r;
	}

	private static void writeShort(byte[] bytes, int offset, int value) {
		bytes[offset] = (byte) (value >>> 8);
		bytes[offset + 1] = (byte) value;
	}

	@Test
	public void passHostRekeysTheGameAndDropsTheOldHost() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		var replies = exchange(passHostTo(joiner));

		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.PASS_HOST_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		var jdbi = TestDatabase.get().jdbi();
		var newHost = jdbi.withHandle(handle ->
			handle.createQuery("select host_chara_id from game where id=:id")
				.bind("id", gameId).mapTo(Long.class).one());
		assertThat(newHost).isEqualTo(joiner);
		var oldHostRows = jdbi.withHandle(handle ->
			handle.createQuery("select count(*) from game_player where chara_id=:c")
				.bind("c", charaId).mapTo(Integer.class).one());
		assertThat(oldHostRows).isZero();
	}

	/**
	 * The 0x4310 toggle decode, pinned at the offsets the live capture confirmed (2026-07-22:
	 * flipping only friendly fire moved bit 3 of byte 0x142; the disabled level limit read 0 at
	 * 0xF8). Bit map is Nomad's, identical to GameListEntry's packers.
	 */
	@Test
	public void appliedBlobDecodesTheToggleBitfields() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();

		var blob = settingsBlob();
		blob[0xA1] = 1;            // dedicated
		blob[0xF8] = 0;
		blob[0xF9] = 0;
		blob[0xFA] = 0;
		blob[0xFB] = 42;           // level-limit base, u32
		blob[0x142] = 0b00101101;  // commonA: idle-kick enable, always-set, friendly fire, auto-aim
		blob[0x143] = (byte) 0b11010101; // commonB: switch, silent, level limit, voice, tk enable
		blob[0x146] = 5;           // idle-kick count
		blob[0x148] = 3;           // team-kill count
		blob[0x155] = 0b10;        // host options: non-stat
		services.getGameService().applyHostSettings(gameId, blob);

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select * from game where id=:id").bind("id", gameId)
				.mapToMap().one());
		assertThat(row.get("friendly_fire")).isEqualTo(true);
		assertThat(row.get("ghosts")).isEqualTo(false);
		assertThat(row.get("auto_aim")).isEqualTo(true);
		assertThat(row.get("uniques_enabled")).isEqualTo(false);
		assertThat(row.get("teams_switch")).isEqualTo(true);
		assertThat(row.get("auto_assign")).isEqualTo(false);
		assertThat(row.get("silent_mode")).isEqualTo(true);
		assertThat(row.get("enemy_nametags")).isEqualTo(false);
		assertThat(row.get("voice_chat")).isEqualTo(true);
		assertThat(row.get("level_limit_enabled")).isEqualTo(true);
		assertThat(((Number) row.get("level_limit_base")).intValue()).isEqualTo(42);
		assertThat(((Number) row.get("idle_kick")).intValue()).isEqualTo(5);
		assertThat(((Number) row.get("team_kill_kick")).intValue()).isEqualTo(3);
		assertThat(row.get("non_stat")).isEqualTo(true);
		assertThat(row.get("dedicated")).isEqualTo(true);
	}

	/** With the enable bits off, the kick counts are zeroed even when the sliders carry values. */
	@Test
	public void disabledKicksAreZeroedRegardlessOfTheirCounts() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();

		var blob = settingsBlob();
		blob[0x142] = 0b00000100;  // enables off
		blob[0x143] = 0;
		blob[0x146] = 5;
		blob[0x148] = 3;
		services.getGameService().applyHostSettings(gameId, blob);

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select idle_kick, team_kill_kick from game where id=:id")
				.bind("id", gameId).mapToMap().one());
		assertThat(((Number) row.get("idle_kick")).intValue()).isZero();
		assertThat(((Number) row.get("team_kill_kick")).intValue()).isZero();
	}

	/**
	 * The ADDLIST cycle: add friend (0x4500 → 0x4502), then clear it (0x4510 → 0x4512). Layouts
	 * and reply ids are ELF-confirmed; a live client ran the full none→friend→blocked→none loop
	 * in one session 2026-07-22.
	 */
	@Test
	public void addListSetsAndClearsARelationship() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var target = givenJoinedPlayer(gameId, "Raiden");

		var add = Unpooled.buffer();
		add.writeByte(1).writeInt((int) target); // state 1 = blocked
		var remove = Unpooled.buffer();
		remove.writeByte(1).writeInt((int) target);

		var replies = exchange(
			new GamePacket(HostGameController.ADD_LIST, add),
			new GamePacket(HostGameController.REMOVE_LIST, remove));

		// 0x4502 add reply: {u32 0, u32 id, u8 state, name[16]} = 25 bytes.
		var added = replies.get(0);
		assertThat(added.getCommand()).isEqualTo(HostGameController.ADD_LIST_ENTRY);
		assertThat(added.getPayload().readableBytes()).isEqualTo(25);
		assertThat(added.getPayload().getInt(0)).isZero();
		assertThat(added.getPayload().getInt(4)).isEqualTo((int) target);
		assertThat(added.getPayload().getByte(8)).isEqualTo((byte) 1);

		// 0x4512 remove reply: {u32 0, u8 state, u32 id} = 9 bytes, and the row the add wrote is
		// gone (the add is proven by the 0x4502 above; both requests run before this returns).
		var removed = replies.get(1);
		assertThat(removed.getCommand()).isEqualTo(HostGameController.REMOVE_LIST_ENTRY);
		assertThat(removed.getPayload().readableBytes()).isEqualTo(9);
		assertThat(removed.getPayload().getByte(4)).isEqualTo((byte) 1);
		assertThat(removed.getPayload().getInt(5)).isEqualTo((int) target);
		var remaining = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_relation where chara_id=:c")
				.bind("c", charaId).mapTo(Integer.class).one());
		assertThat(remaining).isZero();
	}

	/** The stored relations replay into the 0x4101 login arrays — friend ids at 0x29, blocked at 0xA9. */
	@Test
	public void relationsPopulateTheLoginArrays() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var friend = givenJoinedPlayer(gameId, "Otacon");
		var blocked = givenJoinedPlayer(gameId, "Ocelot");
		services.getCharacterService().setRelation(charaId, friend, CharacterService.RELATION_FRIEND);
		services.getCharacterService().setRelation(charaId, blocked, CharacterService.RELATION_BLOCKED);

		var replies = exchange(new GamePacket(CharacterConnectController.CONNECT));

		var info = replies.stream()
			.filter(p -> p.getCommand() == CharacterConnectController.CHARACTER_INFO)
			.findFirst().orElseThrow().getPayload();
		assertThat(info.getInt(0x29)).isEqualTo((int) friend);  // first friend id
		assertThat(info.getInt(0xA9)).isEqualTo((int) blocked); // first blocked id
	}

	/**
	 * Start round ({@code 0x43c8}) replies {@code {u32 result, u32 saved_instructor}} — result 0 lets
	 * the round proceed, and <b>the second word must be zero</b>.
	 * <p>
	 * It is not a round token. The parser stores a nonzero second word into {@code profile+0x32F8}
	 * ({@code 0xD3FF6C}, guarded on {@code != 0}), which the join announcement carries to every peer
	 * as P2P message 36 and which suppresses the post-graduation recognition prompt. We used to send
	 * the game id here, which stamped every character that ever started a round. (Renumbered from
	 * the dead {@code 0x43ca}.)
	 */
	@Test
	public void startRoundReplyLeavesTheSavedInstructorUntouched() {
		givenSelectedCharacter("Snake");
		givenHostedGame();

		var replies = exchange(new GamePacket(HostGameController.START_ROUND));

		var reply = replies.get(0);
		assertThat(reply.getCommand()).isEqualTo(HostGameController.START_ROUND_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(8);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(reply.getPayload().getInt(4))
			.describedAs("nonzero here permanently suppresses the recognition prompt")
			.isZero();
	}

	/** Joining records round membership so a quitter's later stats still apply (0x43c8-independent). */
	@Test
	public void joiningRecordsRoundMembership() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var joiner = givenJoinedPlayer(gameId, "Raiden");

		services.getGameService().addPlayer(gameId, joiner);

		var inRound = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from game_round where game_id=:g and chara_id=:c")
				.bind("g", gameId).bind("c", joiner).mapTo(Integer.class).one());
		assertThat(inRound).isEqualTo(1);
	}

	/**
	 * The standalone roster fetch ({@code 0x4580}) returns the requested state's relations as a
	 * count-led {@code 0x4581}/{@code 0x4582}/{@code 0x4583} triple, 59-byte entries. ELF-derived,
	 * not yet client-verified.
	 */
	@Test
	public void rosterFetchReturnsTheRequestedStatesRelations() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var friend = givenJoinedPlayer(gameId, "Otacon");
		var blocked = givenJoinedPlayer(gameId, "Ocelot");
		services.getCharacterService().setRelation(charaId, friend, CharacterService.RELATION_FRIEND);
		services.getCharacterService().setRelation(charaId, blocked, CharacterService.RELATION_BLOCKED);

		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));
		var replies = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					var req = Unpooled.buffer();
					req.writeByte(CharacterService.RELATION_FRIEND); // ask for the friends list
					ctx.writeAndFlush(new GamePacket(HostGameController.LIST_ROSTER, req));
					return;
				}
				replies.add(packet);
				if (packet.getCommand() == HostGameController.LIST_ROSTER_END) {
					ctx.close();
				}
			}
		});

		assertThat(replies).extracting(GamePacket::getCommand).containsExactly(
			HostGameController.LIST_ROSTER_START,
			HostGameController.LIST_ROSTER_ENTRIES,
			HostGameController.LIST_ROSTER_END);
		// The start is a RESULT CODE, not a count. Sending the count here is what produced
		// "Unable to acquire Friend List.(1002:00000001)" live on 2026-07-26: the parser at
		// 0xD469C0 stores a nonzero value as the transaction's failure code, so one friend
		// became error 1. This assertion used to expect 1 and was pinning the bug.
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		var entry = replies.get(1).getPayload();
		assertThat(entry.readableBytes()).isEqualTo(59);
		assertThat(entry.getInt(0)).isEqualTo((int) friend);
		var name = new byte[16];
		entry.getBytes(4, name);
		assertThat(new String(name, java.nio.charset.StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Otacon");
		// The u16 at wire 0x14 must be nonzero or the 0x4583 end handler drops the record from
		// the display array (0xD466D4) — the roster would render empty with every record parsed.
		assertThat(entry.getUnsignedShort(0x14)).isNotZero();
		assertThat(replies.get(2).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	/**
	 * Training time is accumulated from presence, not from the host's reports — because the host
	 * only reports when someone leaves early, and a host that quits first reports nobody. The
	 * teardown path is the one that used to lose a whole session.
	 */
	/**
	 * The instructor review ({@code 0x43c8} from a student in a combat-training lobby) records the
	 * relationship when the student recognised the instructor, but grants nothing on its own — the
	 * skill and the announcement ride the end-of-round stats report instead.
	 */
	@Test
	public void reviewingAnInstructorRecordsTheGraduationWithoutAwardingYet() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var student = givenJoinedPlayer(gameId, "Otacon");
		givenCombatTrainingLobby();

		services.getCharacterService().recordGraduation(student, charaId, 4, true, 0x01);

		var instructor = services.getCharacterService().instructorOf(student).orElseThrow();
		assertThat(instructor.instructorName()).isEqualTo("Snake");
		assertThat(instructor.rating()).isEqualTo(4);
		// The instructor has no record of their own, so they are first generation.
		assertThat(instructor.generation()).isEqualTo(2);
		assertThat(services.getCharacterService().getSkills(student))
			.extracting(mgo2server.common.model.CharaSkill::getSkillId)
			.doesNotContain(CharacterService.INSTRUCTOR_SKILL_ID);
	}

	/** Konami's documented instructor rule: "Level 3 or above and 20 or more hours of gameplay". */
	private static void givenInstructorEligible(long charaId) {
		TestDatabase.get().jdbi().useHandle(handle -> {
			// Play time comes from round_report now, not from a stored counter — the gate reads the
			// same sum the stats screen shows. One round carrying the whole requirement is enough;
			// the rule must be a playable mode (0..5) because training time deliberately does not
			// count toward "20 or more hours of gameplay".
			handle.createUpdate("""
					insert into round_report (game_id, host_chara_id, chara_id, rule, seconds_in_game)
					values (777, :id, :id, 0, :seconds)
					""")
				.bind("id", charaId)
				.bind("seconds", CharacterService.INSTRUCTOR_MIN_SECONDS)
				.execute();
			// Level comes from experience, not rank, and the check reads whichever pool applies to
			// that character — a joined player's account has an alt pool and no main character.
			handle.createUpdate("""
					update account set main_exp = :exp, alt_exp = :exp
					where id = (select account_id from chara where id = :id)
					""")
				.bind("exp", CharacterService.LEVEL_3_EXPERIENCE)
				.bind("id", charaId)
				.execute();
		});
	}

	/** The stats report is what actually hands over the skill and the announcement. */
	@Test
	public void theStatsReportAwardsTheSkillAndAnnouncementAfterARecognisedGraduation() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var student = givenJoinedPlayer(gameId, "Otacon");
		givenCombatTrainingLobby();

		givenInstructorEligible(student);
		var graduation = services.getCharacterService().recordGraduation(student, charaId, 5, true, 0x01);
		assertThat(graduation.recognised()).isTrue();

		assertThat(services.getCharacterService().awardPendingInstructorSkill(student)).isTrue();
		// Idempotent: every later report finds the skill already held and sends no second letter.
		assertThat(services.getCharacterService().awardPendingInstructorSkill(student)).isFalse();

		assertThat(services.getCharacterService().getSkills(student))
			.extracting(mgo2server.common.model.CharaSkill::getSkillId)
			.contains(CharacterService.INSTRUCTOR_SKILL_ID);

		var mail = services.getCharacterService().mailbox(student, 8);
		assertThat(mail).hasSize(1);
		assertThat(mail.get(0).counterparty()).isEqualTo("GameMaster");
		assertThat(mail.get(0).subject()).contains("Instructor Skill");
	}

	/**
	 * Answering <b>no</b> to "Save current instructor ... as the instructor for your personal data?"
	 * ({@code 0x43c8} answer byte {@code 0x00}) leaves the rating on file and nothing else — no
	 * relationship, and no skill however many stats reports follow.
	 */
	@Test
	public void decliningToRecogniseTheInstructorRecordsOnlyTheRating() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var student = givenJoinedPlayer(gameId, "Otacon");
		givenCombatTrainingLobby();

		var graduation = services.getCharacterService()
			.recordGraduation(student, charaId, 5, false, 0x00);

		assertThat(graduation.recognised()).isFalse();
		assertThat(services.getCharacterService().instructorOf(student)).isEmpty();
		assertThat(services.getCharacterService().awardPendingInstructorSkill(student)).isFalse();
		assertThat(services.getCharacterService().getSkills(student))
			.extracting(mgo2server.common.model.CharaSkill::getSkillId)
			.doesNotContain(CharacterService.INSTRUCTOR_SKILL_ID);
		assertThat(services.getCharacterService().mailbox(student, 8)).isEmpty();
	}

	/** Graduating again re-parents the student without a second letter. */
	@Test
	public void regraduatingReplacesTheInstructorWithoutAnotherAnnouncement() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var student = givenJoinedPlayer(gameId, "Otacon");
		var second = givenJoinedPlayer(gameId, "Meryl");
		givenCombatTrainingLobby();

		givenInstructorEligible(student);
		services.getCharacterService().recordGraduation(student, charaId, 5, true, 0x01);
		services.getCharacterService().awardPendingInstructorSkill(student);
		services.getCharacterService().recordGraduation(student, second, 2, true, 0x01);
		services.getCharacterService().awardPendingInstructorSkill(student);

		var instructor = services.getCharacterService().instructorOf(student).orElseThrow();
		assertThat(instructor.instructorName()).isEqualTo("Meryl");
		assertThat(instructor.rating()).isEqualTo(2);
		assertThat(services.getCharacterService().mailbox(student, 8)).hasSize(1);
	}

	private void givenCombatTrainingLobby() {
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update lobby set subtype = 8 where id = :id")
				.bind("id", lobbyId).execute());
	}

	@Test
	public void endingAGameCreditsEveryPlayersTrainingTime() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();
		var student = givenJoinedPlayer(gameId, "Otacon");

		var jdbi = TestDatabase.get().jdbi();
		// Combat training, and both players joined a minute ago.
		jdbi.useHandle(handle -> {
			handle.createUpdate("update lobby set subtype = 8 where id = :id")
				.bind("id", lobbyId).execute();
			handle.createUpdate("""
					update game_player set joined_at = now() - interval '60 seconds'
					where game_id = :game
					""").bind("game", gameId).execute();
		});

		services.getGameService().deleteGame(gameId);

		var instructor = services.getCharacterService().trainingSeconds(charaId);
		var learner = services.getCharacterService().trainingSeconds(student);

		// The host's seconds land in the instructor column, everyone else's in the student column.
		assertThat(instructor.instructor()).isBetween(59L, 62L);
		assertThat(instructor.student()).isZero();
		assertThat(learner.student()).isBetween(59L, 62L);
		assertThat(learner.instructor()).isZero();
		// Subtype 8 is combat training, so neither is training-mode time.
		assertThat(instructor.trainingMode()).isZero();
		assertThat(learner.trainingMode()).isZero();
	}

	/** A Free Battle round is not training time, whoever hosted it. */
	@Test
	public void ordinaryGamesCreditNoTrainingTime() {
		givenSelectedCharacter("Snake");
		var gameId = givenHostedGame();

		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					update game_player set joined_at = now() - interval '60 seconds'
					where game_id = :game
					""").bind("game", gameId).execute());

		services.getGameService().deleteGame(gameId);

		var totals = services.getCharacterService().trainingSeconds(charaId);
		assertThat(totals.trainingMode()).isZero();
		assertThat(totals.instructor()).isZero();
		assertThat(totals.student()).isZero();
	}

	@Test
	public void postGameInfoCarriesTheCharactersRankAndExperience() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update chara set rank = 7 where id = :id")
				.bind("id", charaId).execute());

		var replies = exchange(new GamePacket(HostGameController.GET_POST_GAME_INFO));

		var payload = replies.get(0).getPayload();
		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.POST_GAME_INFO_RESULT);
		// 39 fixed bytes plus one 4-byte record per skill the character owns. 0x8b was this same
		// arithmetic back when the table was a hard-coded 25 entries; it is now the character's
		// rows, and a new character is granted 1..16.
		assertThat(payload.readableBytes()).isEqualTo(39 + CharaSkill.STARTING_MAX_ID * 4);
		assertThat(payload.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(payload.getByte(4)).isEqualTo((byte) 7);        // rank
		assertThat(payload.getInt(5)).isEqualTo(500);              // main-pool experience
		// Skill 1's experience, from the character's own row — the starting grant is level 1.
		assertThat(payload.getShort(0x0E + 1))
			.isEqualTo((short) CharaSkill.MINIMUM_VISIBLE_EXPERIENCE);
		// The tail sits after the skill records, so its offsets move with the table size; they were
		// 0x76 and 0x86 when the table was a fixed 25 entries.
		var tail = 14 + CharaSkill.STARTING_MAX_ID * 4;
		assertThat(payload.getInt(tail + 4)).isEqualTo(500);       // grade points mirror exp
		assertThat(payload.getInt(tail + 20)).isEqualTo((int) charaId);
	}

	private static void writeInt(byte[] bytes, int offset, int value) {
		bytes[offset] = (byte) (value >>> 24);
		bytes[offset + 1] = (byte) (value >>> 16);
		bytes[offset + 2] = (byte) (value >>> 8);
		bytes[offset + 3] = (byte) value;
	}
}
