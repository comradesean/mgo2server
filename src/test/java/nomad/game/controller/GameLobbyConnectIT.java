package nomad.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.TestDatabase;
import nomad.common.crypto.SessionIds;
import nomad.common.model.ChatMacro;
import nomad.game.BaseGameClientServerIT;
import nomad.game.GameError;
import nomad.game.LobbyType;
import nomad.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Entering a game lobby: check in with a character id, then ask for the connect burst.
 */
public class GameLobbyConnectIT extends BaseGameClientServerIT {
	private static final String SESSION = "abcd1234";

	private long accountId;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	/** An account that has already selected a character, as it would be on arriving here. */
	private void givenSelectedCharacter(String name) {
		accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, main_exp, alt_exp)
					values ('player', 'x', :session, 3, 1234, 99)
					""")
				.bind("session", SESSION)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		// Identity sequences restart between tests, so without this the account and character ids
		// both come out as 1 and a test that confuses the two would pass by coincidence.
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, 'Filler')")
				.bind("account", accountId).execute());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		assertThat(charaId).isNotEqualTo(accountId);

		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", charaId).execute();
			handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
				.bind("chara", charaId).bind("id", accountId).execute();
		});
	}

	/** Checks in with {@code claimedId}, then sends 0x4100 and collects the burst. */
	private List<GamePacket> connect(long claimedId, int expectedPackets) {
		var login = Unpooled.buffer();
		login.writeInt((int) claimedId);
		login.writeBytes(SessionIds.encode(SESSION));

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
				replies.add(packet);

				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					if (packet.getPayload().getInt(0) != GameError.NONE.result()) {
						ctx.close();
						return;
					}
					ctx.writeAndFlush(new GamePacket(CharacterConnectController.CONNECT));
					return;
				}

				if (replies.size() >= expectedPackets) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	/** A game lobby identifies the player by character, not by account. */
	@Test
	public void checksInWithCharacterId() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, 4);

		assertThat(replies.get(0).getCommand())
			.isEqualTo(AccountGameController.CHECK_SESSION_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	/** Sending the account id, as an account lobby would expect, must be refused here. */
	@Test
	public void rejectsAccountIdInGameLobby() {
		givenSelectedCharacter("Snake");

		var replies = connect(accountId, 1);

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.INVALID_SESSION.result());
	}

	@Test
	public void rejectsCheckInWithNoCharacterSelected() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set current_chara_id = null where id = :id")
				.bind("id", accountId).execute());

		var replies = connect(charaId, 1);

		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.INVALID_SESSION.result());
	}

	/** Check-in must not clear the selection here, unlike in an account lobby. */
	@Test
	public void keepsSelectedCharacter() {
		givenSelectedCharacter("Snake");

		connect(charaId, 4);

		var current = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select current_chara_id from account where id=:id")
				.bind("id", accountId).mapTo(Long.class).findOne());

		assertThat(current).contains(charaId);
	}

	@Test
	public void connectBurstSendsCharacterInfoThenChatMacros() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, 4);

		assertThat(replies).hasSize(4);
		assertThat(replies.get(1).getCommand()).isEqualTo(CharacterConnectController.CHARACTER_INFO);
		assertThat(replies.get(2).getCommand()).isEqualTo(CharacterConnectController.CHAT_MACROS);
		assertThat(replies.get(3).getCommand()).isEqualTo(CharacterConnectController.CHAT_MACROS);
	}

	@Test
	public void characterInfoCarriesIdNameAndExperience() {
		givenSelectedCharacter("Snake");

		var info = connect(charaId, 4).get(1).getPayload();

		assertThat(info.getInt(0)).isEqualTo((int) charaId);

		var name = new byte[16];
		info.getBytes(4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Snake");

		// This character is the account's main, so it draws on the main experience pool.
		assertThat(info.getInt(28)).isEqualTo(1234);
		assertThat(info.readableBytes()).isEqualTo(0x243);
	}

	/** An alt draws on the other pool. */
	@Test
	public void alternateCharacterUsesAltExperience() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set main_chara_id = null where id = :id")
				.bind("id", accountId).execute());

		var info = connect(charaId, 4).get(1).getPayload();

		assertThat(info.getInt(28)).isEqualTo(99);
	}

	/** Both macro packets are full-width, with the type byte leading each. */
	@Test
	public void chatMacrosAreSentAsTwoFullSets() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, 4);
		var expectedSize = 1 + ChatMacro.PER_TYPE * ChatMacro.TEXT_LENGTH;

		assertThat(replies.get(2).getPayload().readableBytes()).isEqualTo(expectedSize);
		assertThat(replies.get(3).getPayload().readableBytes()).isEqualTo(expectedSize);
		assertThat(replies.get(2).getPayload().getByte(0)).isEqualTo((byte) 0);
		assertThat(replies.get(3).getPayload().getByte(0)).isEqualTo((byte) 1);
	}

	@Test
	public void chatMacrosReturnStoredText() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("""
					insert into chara_chat_macro (chara_id, type, index, text)
					values (:id, 0, 1, 'Enemy spotted')
					""")
				.bind("id", charaId).execute());

		var macros = connect(charaId, 4).get(2).getPayload();

		var entry = new byte[ChatMacro.TEXT_LENGTH];
		macros.getBytes(1 + ChatMacro.TEXT_LENGTH, entry);
		assertThat(new String(entry, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Enemy spotted");
	}

	/** The connect burst is only served to an authenticated connection. */
	@Test
	public void refusesConnectBurstBeforeCheckIn() {
		givenSelectedCharacter("Snake");

		var replies = new ArrayList<GamePacket>();
		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CharacterConnectController.CONNECT));
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

	/** A game lobby must not answer commands that belong to other lobby types. */
	@Test
	public void doesNotServeAccountLobbyCommands() {
		givenSelectedCharacter("Snake");

		var replies = new ArrayList<GamePacket>();
		client.run(3, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CharacterGameController.GET_CHARACTER_LIST));
				ctx.executor().schedule((Runnable) ctx::close, 1, java.util.concurrent.TimeUnit.SECONDS);
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
				}
			}
		});

		assertThat(replies).isEmpty();
	}
}
