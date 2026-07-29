package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.GameListEntry;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Hosting a game and seeing it in the browser, end to end.
 */
public class HostAndGameListIT extends BaseGameClientServerIT {
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
					insert into account (username, password, session, slots)
					values (:name, 'x', :session, 3)
					""")
				.bind("name", name)
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name, experience)"
					+ " values (:account, :name, 500)")
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

	/** Logs in, then runs the given requests in order, collecting every reply. */
	private List<GamePacket> exchange(int expectedReplies, GamePacket... requests) {
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

				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(requests[sent[0]++]);
					return;
				}

				replies.add(packet);

				// Move on to the next request once this one's reply sequence has ended.
				if (sent[0] < requests.length
						&& (packet.getCommand() == HostGameController.CREATE_GAME_RESULT
							|| packet.getCommand() == GameListGameController.GAME_LIST_END
							|| packet.getCommand() == GameListGameController.GAME_DETAILS
							|| packet.getCommand() == GameListGameController.JOIN_GAME_RESULT
							|| packet.getCommand()
								== CharacterConnectController.UPDATE_CONNECTION_INFO_RESULT)) {
					ctx.writeAndFlush(requests[sent[0]++]);
					return;
				}

				if (replies.size() >= expectedReplies) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	/** Reads one column of a game row with an explicit type. */
	private static <T> T column(long gameId, String columnName, Class<T> type) {
		return TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select " + columnName + " from game where id=:id")
				.bind("id", gameId)
				.mapTo(type)
				.one());
	}

	private static GamePacket getGameList() {
		return new GamePacket(GameListGameController.GET_GAME_LIST,
			Unpooled.wrappedBuffer(new byte[] { 0, 0, 0, 2 }));
	}

	/** A second character on its own account, to cast a vote from. */
	private long givenVoter(String name) {
		var jdbi = TestDatabase.get().jdbi();
		var account = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values (:name, 'x', :name, 3)
					""")
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		return jdbi.withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:a, :name)")
				.bind("a", account).bind("name", name)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
	}

	private static void givenHostVote(long gameId, long host, long voter, int rating) {
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("""
					insert into host_review (game_id, host_chara_id, voter_chara_id, rating)
					values (:g, :h, :v, :r)
					""")
				.bind("g", gameId).bind("h", host).bind("v", voter).bind("r", rating)
				.execute());
	}

	private static GamePacket createGame() {
		return new GamePacket(HostGameController.CREATE_GAME);
	}

	/**
	 * An empty {@code 0x4310}. Adequate here because the ban check runs before the payload is read
	 * at all — a valid settings blob would test the parser, not the refusal.
	 */
	private static GamePacket checkHostSettings() {
		return new GamePacket(HostGameController.CHECK_HOST_SETTINGS);
	}

	@Test
	public void emptyLobbyListsNoGames() {
		givenSelectedCharacter("Snake");

		var replies = exchange(2, getGameList());

		assertThat(replies).hasSize(2);
		assertThat(replies.get(0).getCommand()).isEqualTo(GameListGameController.GAME_LIST_START);
		assertThat(replies.get(1).getCommand()).isEqualTo(GameListGameController.GAME_LIST_END);
	}

	@Test
	public void createsGameFromDefaultHostSettings() {
		givenSelectedCharacter("Snake");

		var replies = exchange(1, createGame());

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(HostGameController.CREATE_GAME_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		var gameId = replies.get(0).getPayload().getInt(4);
		assertThat(gameId).isPositive();

		// Default settings are named after the host.
		var name = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select name from game where id=:id")
				.bind("id", gameId).mapTo(String.class).one());
		assertThat(name).isEqualTo("Snake");
	}

	/** The host is put into their own game, so it is never advertised as empty. */
	@Test
	public void hostJoinsTheirOwnGame() {
		givenSelectedCharacter("Snake");

		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		var players = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from game_player where game_id=:id")
				.bind("id", gameId).mapTo(Integer.class).one());

		assertThat(players).isEqualTo(1);
	}

	@Test
	public void hostedGameAppearsInTheList() {
		givenSelectedCharacter("Snake");

		var replies = exchange(4, createGame(), getGameList());

		var entries = replies.stream()
			.filter(p -> p.getCommand() == GameListGameController.GAME_LIST_ENTRIES)
			.toList();

		assertThat(entries).hasSize(1);
		var payload = entries.get(0).getPayload();
		assertThat(payload.readableBytes()).isEqualTo(GameListEntry.SIZE);

		var name = new byte[16];
		payload.getBytes(4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Snake");

		// One player present: the host.
		assertThat(payload.getByte(29)).isEqualTo((byte) 1);
	}

	/** The browser shows mean experience across the players in a game. */
	@Test
	public void listReportsAverageExperience() {
		givenSelectedCharacter("Snake");

		var replies = exchange(4, createGame(), getGameList());
		var entries = replies.stream()
			.filter(p -> p.getCommand() == GameListGameController.GAME_LIST_ENTRIES)
			.toList();

		// The host is their account's main character, so the main pool applies.
		assertThat(entries.get(0).getPayload().getInt(40)).isEqualTo(500);
	}

	/** Host settings materialise on first use rather than needing to be seeded. */
	@Test
	public void hostSettingsAreCreatedOnDemand() {
		givenSelectedCharacter("Snake");

		exchange(1, createGame());

		var rows = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_host_settings where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());

		assertThat(rows).isEqualTo(1);
	}

	/** Settings edited in the database are reflected in the next game hosted. */
	@Test
	public void createdGameCarriesStoredSettings() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					insert into chara_host_settings (chara_id, type, name, max_players,
						friendly_fire, voice_chat, team_kill_kick)
					values (:id, 0, 'Shadow Moses', 8, true, true, 3)
					""")
			.bind("id", charaId).execute());

		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		// Read column by column with explicit types: mapToMap returns whatever boxed type the
		// driver picks for smallint, which is not worth asserting against.
		String name = column(gameId, "name", String.class);
		Integer maxPlayers = column(gameId, "max_players", Integer.class);
		Boolean friendlyFire = column(gameId, "friendly_fire", Boolean.class);
		Boolean voiceChat = column(gameId, "voice_chat", Boolean.class);
		Integer teamKillKick = column(gameId, "team_kill_kick", Integer.class);

		assertThat(name).isEqualTo("Shadow Moses");
		assertThat(maxPlayers).isEqualTo(8);
		assertThat(friendlyFire).isTrue();
		assertThat(voiceChat).isTrue();
		assertThat(teamKillKick).isEqualTo(3);
	}

	/** Those settings must reach the wire as the bitfields the browser reads. */
	@Test
	public void listEntryReflectsStoredSettings() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					insert into chara_host_settings (chara_id, type, name, friendly_fire,
						voice_chat, team_kill_kick, password)
					values (:id, 0, 'Shadow Moses', true, true, 3, 'hunter2')
					""")
			.bind("id", charaId).execute());

		var replies = exchange(4, createGame(), getGameList());
		var payload = replies.stream()
			.filter(p -> p.getCommand() == GameListGameController.GAME_LIST_ENTRIES)
			.toList().get(0).getPayload();

		assertThat(payload.getByte(20) & 0b1).isEqualTo(0b1);          // password set
		assertThat(payload.getByte(27) & 0b1000).isEqualTo(0b1000);    // friendly fire
		assertThat(payload.getByte(28) & 0b1000000).isEqualTo(0b1000000); // voice chat
		assertThat(payload.getByte(28) & 0b10000000).isEqualTo(0b10000000); // team kill kick
	}

	private static GamePacket getGameDetails(int gameId) {
		var payload = Unpooled.buffer();
		payload.writeInt(gameId);
		return new GamePacket(GameListGameController.GET_GAME_DETAILS, payload);
	}

	/** Details for a hosted game: the reply the details, join and player-list screens gate on. */
	@Test
	public void detailsDescribeAHostedGame() {
		givenSelectedCharacter("Snake");

		var created = exchange(1, createGame());
		var gameId = created.get(0).getPayload().getInt(4);

		var replies = exchange(1, getGameDetails(gameId));

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(GameListGameController.GAME_DETAILS);

		var payload = replies.get(0).getPayload();
		assertThat(payload.readableBytes())
			.isEqualTo(mgo2server.game.GameDetails.FIXED_SIZE
				+ mgo2server.game.GameDetails.PLAYER_SIZE);
		assertThat(payload.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(payload.getInt(4)).isEqualTo(gameId);

		var name = new byte[16];
		payload.getBytes(8, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Snake");

		// One player — the host — with the main pool's experience.
		assertThat(payload.getByte(235)).isEqualTo((byte) 1);
		var base = mgo2server.game.GameDetails.FIXED_SIZE;
		assertThat(payload.getInt(base)).isEqualTo((int) charaId);
		assertThat(payload.getInt(base + 24)).isEqualTo(500);
	}

	/** A nonzero result is the answer for a game that vanished between list and click. */
	@Test
	public void detailsForAMissingGameReturnAnError() {
		givenSelectedCharacter("Snake");

		var replies = exchange(1, getGameDetails(999_999));

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(GameListGameController.GAME_DETAILS);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(4);
		assertThat(replies.get(0).getPayload().getInt(0))
			.isNotEqualTo(GameError.NONE.result());
	}

	private static GamePacket joinGame(int gameId) {
		var payload = Unpooled.buffer();
		payload.writeInt(gameId);
		return new GamePacket(GameListGameController.JOIN_GAME, payload);
	}

	private static GamePacket registerEndpoint() {
		// 0x4700: private port, 16-byte private IP, public port. The public IP comes off the
		// socket, so it is not in the payload.
		var payload = Unpooled.buffer();
		payload.writeShort(5731);
		var ip = "192.168.1.100";
		for (var i = 0; i < 16; i++) {
			payload.writeByte(i < ip.length() ? ip.charAt(i) : 0);
		}
		payload.writeShort(5730);
		return new GamePacket(CharacterConnectController.UPDATE_CONNECTION_INFO, payload);
	}

	/** A join succeeds once the host has registered its peer-to-peer endpoint. */
	@Test
	public void joinReturnsTheHostEndpoint() {
		givenSelectedCharacter("Snake");

		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		var replies = exchange(2, registerEndpoint(), joinGame(gameId));

		var join = replies.stream()
			.filter(p -> p.getCommand() == GameListGameController.JOIN_GAME_RESULT)
			.toList().get(0);
		assertThat(join.getPayload().readableBytes()).isEqualTo(mgo2server.game.GameJoin.SIZE);
		assertThat(join.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		// The public IP is read from the loopback socket the test connects over.
		var publicIp = new byte[16];
		join.getPayload().getBytes(4, publicIp);
		assertThat(new String(publicIp, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isNotEmpty();
		assertThat(join.getPayload().getUnsignedShort(20)).isEqualTo(5730);
		assertThat(join.getPayload().getUnsignedShort(38)).isEqualTo(5731);
	}

	/** Without a registered host endpoint a join fails rather than returning a blank success. */
	@Test
	public void joinFailsWhenHostHasNoEndpoint() {
		givenSelectedCharacter("Snake");

		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		var replies = exchange(1, joinGame(gameId));

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(GameListGameController.JOIN_GAME_RESULT);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(4);
		assertThat(replies.get(0).getPayload().getInt(0)).isNotEqualTo(GameError.NONE.result());
	}

	/**
	 * A banned account is refused the join, with the sentence the client ships for it.
	 * <p>
	 * {@code -541} renders as "You are currently banned from creating and joining games." and is
	 * accepted on both halves of play, so one code and one column cover hosting and joining.
	 */
	@Test
	public void bannedAccountCannotJoin() {
		givenSelectedCharacter("Snake");
		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);
		banCurrentAccount(OffsetDateTime.now().plusDays(1));

		var replies = exchange(1, joinGame(gameId));

		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.GAME_BANNED_FROM_PLAY.result());
	}

	/**
	 * A ban that has run out is not a ban. The comparison does the work, so nothing has to sweep
	 * the column and an expired row is indistinguishable from a clean one.
	 */
	@Test
	public void expiredBanDoesNotRefuseTheJoin() {
		givenSelectedCharacter("Snake");
		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);
		banCurrentAccount(OffsetDateTime.now().minusDays(1));

		var replies = exchange(2, registerEndpoint(), joinGame(gameId));

		var join = replies.stream()
			.filter(p -> p.getCommand() == GameListGameController.JOIN_GAME_RESULT)
			.toList().get(0);
		assertThat(join.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	/**
	 * A banned account cannot host either, and the refusal lands on {@code 0x4311} rather than on
	 * create: {@code 0x4317}'s code test has zero spans, so every value there renders the same
	 * generic sentence and the ban would be invisible.
	 */
	@Test
	public void bannedAccountCannotHost() {
		givenSelectedCharacter("Snake");
		banCurrentAccount(OffsetDateTime.now().plusDays(1));

		var replies = exchange(1, checkHostSettings());

		assertThat(replies.get(0).getCommand())
			.isEqualTo(HostGameController.CHECK_HOST_SETTINGS_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.GAME_BANNED_FROM_PLAY.result());
	}

	/** Sets the ban directly; there is no in-game way to do it, and there is not meant to be. */
	private void banCurrentAccount(OffsetDateTime until) {
		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("update account set banned_until = :until")
			.bind("until", until)
			.execute());
	}

	/** A game left over from a previous run is cleared, so it never haunts the browser. */
	@Test
	public void staleGamesAreClearedFromLobby() {
		givenSelectedCharacter("Snake");
		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		var lobbyId = column(gameId, "lobby_id", Long.class);
		var removed = new mgo2server.common.service.GameService(TestDatabase.get().jdbi())
			.deleteGamesInLobby(lobbyId);

		assertThat(removed).isGreaterThanOrEqualTo(1);
		assertThat(new mgo2server.common.service.GameService(TestDatabase.get().jdbi())
			.get(gameId)).isEmpty();
	}

	@Test
	public void refusesGameListBeforeLogin() {
		givenSelectedCharacter("Snake");

		var replies = new ArrayList<GamePacket>();
		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(getGameList());
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
					ctx.close();
				}
			}
		});

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.INVALID_SESSION.result());
	}

	/**
	 * A host's rating reaches the browser, which reads the dead {@code game.host_score} and
	 * {@code game.host_votes} columns on the wire. Nothing has ever written those, so every host
	 * showed as unrated however many votes they had; they are now derived from {@code host_review}.
	 * <p>
	 * Sum over count, not a pre-divided average — the client draws
	 * {@code clamp(ceil(2 * numerator / denominator), 0, 10)} half-stars, so the ratio is the
	 * average.
	 */
	@Test
	public void gameDetailsCarryTheHostsRatingFromHostReview() {
		givenSelectedCharacter("Snake");
		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);
		givenHostVote(gameId, charaId, givenVoter("Raiden"), 5);
		givenHostVote(gameId, charaId, givenVoter("Otacon"), 2);

		var details = exchange(1, getGameDetails(gameId)).get(0).getPayload();

		assertThat(details.getInt(159)).as("rating SUM, the star numerator").isEqualTo(7);
		assertThat(details.getInt(163)).as("vote COUNT, the denominator").isEqualTo(2);
	}

	/** A host nobody has rated reports zero votes rather than a stale or invented number. */
	@Test
	public void anUnratedHostReportsNoVotes() {
		givenSelectedCharacter("Snake");
		var gameId = exchange(1, createGame()).get(0).getPayload().getInt(4);

		var details = exchange(1, getGameDetails(gameId)).get(0).getPayload();

		assertThat(details.getInt(159)).isZero();
		assertThat(details.getInt(163)).isZero();
	}

}
