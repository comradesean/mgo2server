package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
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
 * Player search and match history, end to end.
 * <p>
 * The reply shapes assert what the client's parsers consume, traced from the binary: start and
 * end carry a u32 result code that must be 0 — a nonzero value aborts the screen with an error
 * dialog (observed live as {@code 1032:00000005} when a count of 5 was sent; handlers
 * {@code 0xD3ADF4}/{@code 0xD3ACF8} for history, {@code 0xD45DF0}/{@code 0xD45CF4} for search),
 * and the client counts the records itself; each search record is 59 bytes ({@code 0xD45F38}).
 * The matching semantics themselves — substring for partial, and the case toggle — are operator
 * policy; those assertions are regression guards, not correctness checks.
 */
public class SocialGameControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private static final int SEARCH_ENTRY_SIZE = 59;

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
					insert into account (username, password, session, slots)
					values ('player', 'x', :session, 3)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = insertCharacter(name);

		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
				.bind("chara", charaId).bind("id", accountId).execute());
	}

	private long insertCharacter(String name) {
		var id = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", id).execute());
		return id;
	}

	/** Checks in with the selected character, sends {@code request}, collects until {@code untilCommand}. */
	private List<GamePacket> loginThen(GamePacket request, int untilCommand) {
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
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(request);
					return;
				}
				replies.add(packet);
				if (packet.getCommand() == untilCommand) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	private static GamePacket searchPacket(int criteria, int matchCase, String name) {
		var payload = Unpooled.buffer();
		payload.writeByte(criteria);
		payload.writeByte(matchCase);
		var bytes = new byte[16];
		var encoded = name.getBytes(StandardCharsets.ISO_8859_1);
		System.arraycopy(encoded, 0, bytes, 0, Math.min(encoded.length, bytes.length));
		payload.writeBytes(bytes);
		return new GamePacket(SocialGameController.PLAYER_SEARCH, payload);
	}

	private static String nameAt(ByteBuf payload, int offset) {
		var bytes = new byte[16];
		payload.getBytes(offset, bytes);
		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, 0, end, StandardCharsets.ISO_8859_1);
	}

	// ---------- player search ----------

	@Test
	public void partialSearchMatchesSubstrings() {
		givenSelectedCharacter("Snake");
		var eater = insertCharacter("SnakeEater");
		insertCharacter("Otacon");

		var replies = loginThen(searchPacket(0, 1, "Snake"),
			SocialGameController.PLAYER_SEARCH_END);

		assertThat(replies).hasSize(3);
		assertThat(replies.get(0).getCommand()).isEqualTo(SocialGameController.PLAYER_SEARCH_START);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);

		var entries = replies.get(1);
		assertThat(entries.getCommand()).isEqualTo(SocialGameController.PLAYER_SEARCH_ENTRIES);
		assertThat(entries.getPayload().readableBytes()).isEqualTo(2 * SEARCH_ENTRY_SIZE);
		assertThat(entries.getPayload().getInt(0)).isEqualTo((int) charaId);
		assertThat(nameAt(entries.getPayload(), 4)).isEqualTo("Snake");
		assertThat(entries.getPayload().getInt(SEARCH_ENTRY_SIZE)).isEqualTo((int) eater);
		assertThat(nameAt(entries.getPayload(), SEARCH_ENTRY_SIZE + 4)).isEqualTo("SnakeEater");

		assertThat(replies.get(2).getPayload().getInt(0)).isEqualTo(0);
	}

	@Test
	public void fullSearchMatchesExactNameOnly() {
		givenSelectedCharacter("Snake");
		insertCharacter("SnakeEater");

		var replies = loginThen(searchPacket(1, 1, "Snake"),
			SocialGameController.PLAYER_SEARCH_END);

		assertThat(replies).hasSize(3);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
		assertThat(nameAt(replies.get(1).getPayload(), 4)).isEqualTo("Snake");
	}

	@Test
	public void caseToggleControlsSensitivity() {
		givenSelectedCharacter("Snake");

		var sensitive = loginThen(searchPacket(0, 1, "snake"),
			SocialGameController.PLAYER_SEARCH_END);
		assertThat(sensitive).hasSize(2);
		assertThat(sensitive.get(0).getPayload().getInt(0)).isEqualTo(0);

		var insensitive = loginThen(searchPacket(0, 0, "snake"),
			SocialGameController.PLAYER_SEARCH_END);
		assertThat(insensitive).hasSize(3);
		assertThat(insensitive.get(0).getPayload().getInt(0)).isEqualTo(0);
	}

	/** A name of SQL wildcards must match literally (i.e. nothing), not every character. */
	@Test
	public void searchEscapesWildcards() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(searchPacket(0, 1, "%_%"),
			SocialGameController.PLAYER_SEARCH_END);

		assertThat(replies).hasSize(2);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
	}

	// ---------- match history ----------

	/**
	 * While the record fields are being mapped, history serves the TEMPORARY fingerprint rows.
	 * The wire-shape assertions (25-byte records, result-code-0 start/end) are the durable
	 * part; the row contents change when real match records land.
	 */
	@Test
	public void matchHistoryServesFingerprintRows() {
		givenSelectedCharacter("Snake");

		var request = Unpooled.buffer();
		request.writeInt((int) charaId);
		var replies = loginThen(new GamePacket(SocialGameController.GET_MATCH_HISTORY, request),
			SocialGameController.MATCH_HISTORY_END);

		assertThat(replies).hasSize(3);
		assertThat(replies.get(0).getCommand()).isEqualTo(SocialGameController.MATCH_HISTORY_START);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(4);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
		var entries = replies.get(1);
		assertThat(entries.getCommand()).isEqualTo(SocialGameController.MATCH_HISTORY_ENTRIES);
		assertThat(entries.getPayload().readableBytes()).isEqualTo(5 * 25);
		assertThat(entries.getPayload().getInt(25 + 4)).isEqualTo(9102); // row 2 entry id
		assertThat(replies.get(2).getCommand()).isEqualTo(SocialGameController.MATCH_HISTORY_END);
		assertThat(replies.get(2).getPayload().getInt(0)).isEqualTo(0);
	}

	/** The 201-byte reply shape is ELF-traced (parser 0xD3D874): u32 result 0, then 197 bytes. */
	@Test
	public void playerDetailsEchoesIdInFingerprintCard() {
		givenSelectedCharacter("Snake");

		var request = Unpooled.buffer();
		request.writeInt(9101);
		var replies = loginThen(new GamePacket(SocialGameController.GET_PLAYER_DETAILS, request),
			SocialGameController.PLAYER_DETAILS_RESULT);

		assertThat(replies).hasSize(1);
		var payload = replies.get(0).getPayload();
		assertThat(payload.readableBytes()).isEqualTo(201);
		assertThat(payload.getInt(0)).isEqualTo(0);    // result code
		assertThat(payload.getInt(4)).isEqualTo(9101); // id echo
	}

	@Test
	public void matchDetailsServesFingerprintRows() {
		givenSelectedCharacter("Snake");

		var request = Unpooled.buffer();
		request.writeInt(9101);
		var replies = loginThen(new GamePacket(SocialGameController.GET_MATCH_DETAILS, request),
			SocialGameController.MATCH_DETAILS_END);

		assertThat(replies).hasSize(3);
		assertThat(replies.get(0).getCommand()).isEqualTo(SocialGameController.MATCH_DETAILS_START);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
		assertThat(replies.get(1).getPayload().readableBytes()).isEqualTo(3 * 93);
		assertThat(replies.get(2).getCommand()).isEqualTo(SocialGameController.MATCH_DETAILS_END);
		assertThat(replies.get(2).getPayload().getInt(0)).isEqualTo(0);
	}
}
