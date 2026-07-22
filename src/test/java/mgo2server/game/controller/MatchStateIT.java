package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameDetails;
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

		var replies = new ArrayList<GamePacket>();
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

		return replies;
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
		assertThat(replies.get(0).getPayload().readableBytes()).isZero();

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

	@Test
	public void postGameInfoCarriesTheCharactersRankAndExperience() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update chara set rank = 7 where id = :id")
				.bind("id", charaId).execute());

		var replies = exchange(new GamePacket(HostGameController.GET_POST_GAME_INFO));

		var payload = replies.get(0).getPayload();
		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.POST_GAME_INFO_RESULT);
		assertThat(payload.readableBytes()).isEqualTo(0x8b);
		assertThat(payload.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(payload.getByte(4)).isEqualTo((byte) 7);        // rank
		assertThat(payload.getInt(5)).isEqualTo(500);              // main-pool experience
		assertThat(payload.getShort(0x0E + 1)).isEqualTo((short) 0x6000); // skill 1 exp
		assertThat(payload.getInt(0x76)).isEqualTo(500);           // grade points mirror exp
		assertThat(payload.getInt(0x86)).isEqualTo((int) charaId);
	}

	private static void writeInt(byte[] bytes, int offset, int value) {
		bytes[offset] = (byte) (value >>> 24);
		bytes[offset + 1] = (byte) (value >>> 16);
		bytes[offset + 2] = (byte) (value >>> 8);
		bytes[offset + 3] = (byte) value;
	}
}
