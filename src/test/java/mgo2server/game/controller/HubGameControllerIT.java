package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.ClientVersion;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The hub's lobby list, {@code 0x4900}.
 * <p>
 * The entry size is the point of this class. The client's parser at {@code 0xD47E18} reads a fixed
 * 99 bytes per entry and its read primitives bound-check against the 1023-byte packet buffer
 * rather than against the payload length, so a short entry does not fail — it silently resumes
 * partway into the next one, and every lobby after the first is rubbish. That is a tier-1
 * assertion: 99 is read out of the binary, not out of a reference server, both of which write 35.
 */
public class HubGameControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	/** index, subtype word, id, name, text block, open and close times, open flag. */
	private static final int ENTRY_SIZE = 99;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private void givenSelectedCharacter() {
		var accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values ('hub', 'x', :session, 3)
					""")
				.bind("session", SessionField.stored(ClientVersion.V1_0, TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, 'Snake')")
				.bind("account", accountId)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara
					where id = :id
					""")
			.bind("chara", charaId).bind("id", accountId).execute());
	}

	private void addGameLobby(String name, int subtype, int port) {
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					insert into lobby (type, subtype, name, ip, port)
					values (2, :subtype, :name, '127.0.0.1', :port)
					""")
			.bind("subtype", subtype).bind("name", name).bind("port", port).execute());
	}

	/** Logs in, asks for the lobby info, and collects replies up to the end marker. */
	private List<GamePacket> requestLobbyInfo() {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(ClientVersion.V1_0, TOKEN));

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
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(new GamePacket(HubGameController.GET_GAME_LOBBY_INFO));
					return;
				}

				replies.add(packet);
				if (packet.getCommand() == HubGameController.GAME_LOBBY_INFO_END) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	@Test
	public void everyEntryIsNinetyNineBytes() {
		givenSelectedCharacter();
		// One beyond the lobby the base class creates for this game server.
		addGameLobby("Basic Training", 7, 5731);

		var replies = requestLobbyInfo();

		assertThat(replies).hasSize(3);
		assertThat(replies.get(1).getCommand())
			.isEqualTo(HubGameController.GAME_LOBBY_INFO_ENTRIES);
		assertThat(replies.get(1).getPayload().readableBytes()).isEqualTo(2 * ENTRY_SIZE);
	}

	@Test
	public void writesFieldsAtTheOffsetsTheParserReads() {
		givenSelectedCharacter();
		addGameLobby("Basic Training", 7, 5731);

		var entries = requestLobbyInfo().get(1).getPayload();
		var second = ENTRY_SIZE;

		assertThat(entries.getInt(second)).isEqualTo(1);
		// Subtype is a u8 at +4 — the top byte of what the references write as an attribute word.
		assertThat(entries.getUnsignedByte(second + 4)).isEqualTo((short) 7);

		var name = new byte[16];
		entries.getBytes(second + 0x0a, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Basic Training");

		// The 64-byte text block: unused by every category except subtype 5, but its absence is
		// what desynchronises the parser.
		var text = new byte[64];
		entries.getBytes(second + 0x1a, text);
		assertThat(text).containsOnly((byte) 0);

		assertThat(entries.getInt(second + 0x5a)).isEqualTo(0);
		assertThat(entries.getInt(second + 0x5e)).isEqualTo(0);
		assertThat(entries.getUnsignedByte(second + 0x62)).isEqualTo((short) 1);
	}

	/**
	 * The training parameter fetch. Ten bytes, five u16s — the size is read from the parser at
	 * {@code 0xD3A560}, which performs exactly five u16 reads; the values it carries are not.
	 */
	@Test
	public void answersTrainingParamsWithFiveHalfwords() {
		givenSelectedCharacter();

		var replies = new ArrayList<GamePacket>();
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(ClientVersion.V1_0, TOKEN));

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
					var request = Unpooled.buffer();
					request.writeByte(8);
					ctx.writeAndFlush(
						new GamePacket(HubGameController.GET_TRAINING_PARAMS, request));
					return;
				}

				replies.add(packet);
				ctx.close();
			}
		});

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand())
			.isEqualTo(HubGameController.TRAINING_PARAMS_RESULT);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(10);
	}

	/** The override parses only a well-formed set of five; anything else keeps the defaults. */
	@Test
	public void trainingParamsOverrideNeedsExactlyFiveNumbers() {
		assertThat(HubGameController.trainingParams("1,2,3,4,5"))
			.containsExactly(1, 2, 3, 4, 5);
		assertThat(HubGameController.trainingParams(" 1 , 2 , 3 , 4 , 5 "))
			.containsExactly(1, 2, 3, 4, 5);
		// Four values, six values, junk and blank all fall back rather than sending a short reply,
		// because the five-read count is protocol while the values are not.
		assertThat(HubGameController.trainingParams("1,2,3,4")).containsExactly(10, 21, 58, 8, 97);
		assertThat(HubGameController.trainingParams("1,2,3,4,5,6")).containsExactly(10, 21, 58, 8, 97);
		assertThat(HubGameController.trainingParams("1,2,x,4,5")).containsExactly(10, 21, 58, 8, 97);
		assertThat(HubGameController.trainingParams("")).containsExactly(10, 21, 58, 8, 97);
		assertThat(HubGameController.trainingParams(null)).containsExactly(10, 21, 58, 8, 97);
	}

	/** Only game lobbies are listed; the hub menu has no category for the other types. */
	@Test
	public void skipsNonGameLobbies() {
		givenSelectedCharacter();
		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
				insert into lobby (type, subtype, name, ip, port)
				values (0, 0, 'Gate', '127.0.0.1', 5732)
				""").execute());

		var replies = requestLobbyInfo();

		assertThat(replies.get(1).getPayload().readableBytes()).isEqualTo(ENTRY_SIZE);
	}
}
