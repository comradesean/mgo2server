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

	/**
	 * The five-field location block at the end of a search record — settled 2026-07-31, served
	 * since 2026-08-01. It was five deliberate zeros while the reading was tier 4.
	 * <p>
	 * A player who is not connected gets zeros and an empty name, which the client renders as
	 * {@code "----"}; the row still appears, because search results are not gated on this.
	 */
	@Test
	public void searchResultsCarryLocationForAConnectedPlayer() {
		givenSelectedCharacter("Snake");
		var found = insertCharacter("SnakeEater");
		services.getPresenceService().enter(found, lobbyId);

		var replies = loginThen(searchPacket(1, 1, "SnakeEater"),
			SocialGameController.PLAYER_SEARCH_END);
		var entry = replies.get(1).getPayload();

		assertThat(entry.getInt(0)).isEqualTo((int) found);
		// u16 lobby_id, then the lobby's own name -- the column the layout calls STRING_F_LIST_LOBBY.
		assertThat(entry.getUnsignedShort(0x14)).isEqualTo((int) lobbyId);
		assertThat(nameAt(entry, 0x16)).isEqualTo("Test");
		// Not in a game, so the game half stays empty rather than inventing one.
		assertThat(entry.getInt(0x26)).isZero();
		assertThat(nameAt(entry, 0x2A)).isEmpty();
		// The trailing u8 is the SEARCH table's category enum (0x8E1110), which has no arm 9 --
		// unlike the match-history table. This fixture's lobby is subtype 1, Free Battle.
		assertThat(entry.getUnsignedByte(0x3A)).isEqualTo((short) lobbySubtype());
	}

	/** A player nobody has seen connect has no location, and must still appear in the results. */
	@Test
	public void searchResultsForAnOfflinePlayerCarryZeros() {
		givenSelectedCharacter("Snake");
		var found = insertCharacter("SnakeEater");

		var replies = loginThen(searchPacket(1, 1, "SnakeEater"),
			SocialGameController.PLAYER_SEARCH_END);
		var entry = replies.get(1).getPayload();

		assertThat(entry.getInt(0)).isEqualTo((int) found);
		assertThat(entry.getUnsignedShort(0x14)).isZero();
		assertThat(nameAt(entry, 0x16)).isEmpty();
		assertThat(entry.getUnsignedByte(0x3A)).isZero();
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

	/**
	 * The second byte means <b>match case</b>, so 0 matches "snake" against "Snake" and 1 does not.
	 * <p>
	 * Reverted 2026-07-31: this read the byte inverted from 2026-07-27 to today, on the strength of
	 * a live "bob"/"Bob" test at the time. A later live-play report — toggling to "case sensitive"
	 * is what found "Sean" from a "sean" query — says that polarity was backwards. This is a
	 * live-play report from notes, not a fresh packet capture; if it flips again, capture the real
	 * bytes (DEBUG logging) rather than trusting either direction from play-testing alone.
	 */
	@Test
	public void caseToggleControlsSensitivity() {
		givenSelectedCharacter("Snake");

		var ignoringCase = loginThen(searchPacket(0, 0, "snake"),
			SocialGameController.PLAYER_SEARCH_END);
		assertThat(ignoringCase).hasSize(3);
		assertThat(ignoringCase.get(0).getPayload().getInt(0)).isEqualTo(0);
		assertThat(nameAt(ignoringCase.get(1).getPayload(), 4)).isEqualTo("Snake");

		var matchingCase = loginThen(searchPacket(0, 1, "snake"),
			SocialGameController.PLAYER_SEARCH_END);
		assertThat(matchingCase).hasSize(2);
		assertThat(matchingCase.get(0).getPayload().getInt(0)).isEqualTo(0);
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
	 * History rows derive from {@code round_report}: other characters with a report in a game
	 * the viewer has a report in. Record fields all live-confirmed 2026-07-23: last-met epoch
	 * seconds, character id, name, u8 0.
	 */
	@Test
	public void matchHistoryListsPlayersFromSharedGames() {
		givenSelectedCharacter("Snake");
		var raiden = insertCharacter("Raiden");
		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("""
					insert into round_report (game_id, host_chara_id, chara_id)
					values (777, :host, :host), (777, :host, :met)
					""")
				.bind("host", charaId).bind("met", raiden).execute();
		});

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
		assertThat(entries.getPayload().readableBytes()).isEqualTo(25);
		assertThat(entries.getPayload().getInt(0)).isGreaterThan(0); // last-met, epoch seconds
		assertThat(entries.getPayload().getInt(4)).isEqualTo((int) raiden);
		assertThat(nameAt(entries.getPayload(), 8)).isEqualTo("Raiden");
		assertThat(entries.getPayload().getByte(24)).isEqualTo((byte) 0);
		assertThat(replies.get(2).getCommand()).isEqualTo(SocialGameController.MATCH_HISTORY_END);
		assertThat(replies.get(2).getPayload().getInt(0)).isEqualTo(0);
	}

	/** No shared games: the empty success triple (start then end, result 0, no item packet). */
	@Test
	public void matchHistoryEmptyWithoutSharedGames() {
		givenSelectedCharacter("Snake");

		var request = Unpooled.buffer();
		request.writeInt((int) charaId);
		var replies = loginThen(new GamePacket(SocialGameController.GET_MATCH_HISTORY, request),
			SocialGameController.MATCH_HISTORY_END);

		assertThat(replies).hasSize(2);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
		assertThat(replies.get(1).getPayload().getInt(0)).isEqualTo(0);
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

	/**
	 * Match details answers an empty list rather than invented rows.
	 * <p>
	 * This test used to assert three fingerprint records — literal {@code "FP-DETAIL-LONG-1"} text
	 * and fabricated ids — reached the client. They did, on a real screen, for every request. The
	 * 93-byte record is ELF-traced but entirely unlabelled, so there is nothing honest to put in it,
	 * and an empty list says "no details" where invented rows say something false the player can
	 * read.
	 * <p>
	 * The precedent is why this matters: a sibling fingerprint string was parsed as a bitfield and
	 * minted 17 medals nobody had earned.
	 */
	@Test
	public void matchDetailsServesAnEmptyList() {
		givenSelectedCharacter("Snake");

		var request = Unpooled.buffer();
		request.writeInt(9101);
		var replies = loginThen(new GamePacket(SocialGameController.GET_MATCH_DETAILS, request),
			SocialGameController.MATCH_DETAILS_END);

		// Start and end only — the client is still answered, which is what keeps it from stalling.
		assertThat(replies).hasSize(2);
		assertThat(replies.get(0).getCommand()).isEqualTo(SocialGameController.MATCH_DETAILS_START);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(0);
		assertThat(replies.get(1).getCommand()).isEqualTo(SocialGameController.MATCH_DETAILS_END);
		assertThat(replies.get(1).getPayload().getInt(0)).isEqualTo(0);
	}
}
