package nomad.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.TestDatabase;
import nomad.common.crypto.SessionIds;
import nomad.game.BaseGameClientServerIT;
import nomad.game.GameError;
import nomad.game.GameListEntry;
import nomad.game.LobbyType;
import nomad.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Hosting a game and seeing it in the browser, end to end.
 */
public class HostAndGameListIT extends BaseGameClientServerIT {
	private static final String SESSION = "abcd1234";

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
				.bind("session", SESSION)
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

	/** Logs in, then runs the given requests in order, collecting every reply. */
	private List<GamePacket> exchange(int expectedReplies, GamePacket... requests) {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionIds.encode(SESSION));

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
							|| packet.getCommand() == GameListGameController.GAME_LIST_END)) {
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

	private static GamePacket createGame() {
		return new GamePacket(HostGameController.CREATE_GAME);
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
}
