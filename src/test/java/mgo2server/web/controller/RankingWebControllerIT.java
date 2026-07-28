package mgo2server.web.controller;

import mgo2server.TestDatabase;
import mgo2server.common.crypto.RankingScramble;
import mgo2server.common.service.RankingService;
import mgo2server.web.BaseWebClientServerIT;
import okhttp3.FormBody;
import okhttp3.Request;
import okhttp3.Response;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The Rankings screens end to end: POST the six form fields the client sends, then read the reply
 * back the way the client reads it — descramble, then little-endian.
 * <p>
 * The request and reply shapes are [ELF] (see {@link RankingWebController}); which quantity each
 * {@code skey} selects is [INFERRED], so the assertions here are about <em>ordering, paging and
 * framing</em>, which are protocol, rather than about a particular column meaning anything.
 */
public class RankingWebControllerIT extends BaseWebClientServerIT {
	private static final int HEADER_SIZE = 12;

	private static final int RECORD_SIZE = 28;

	private static final int NAME_SIZE = 16;

	/** [ELF] the client sends 100 for a page and 1 for its own standing. */
	private static final int PAGE_RECORDS = 100;

	private record Board(int count, long total, long ignored, List<Row> rows) {
	}

	private record Row(long rank, long id, String name, long value) {
	}

	/** Reads a reply exactly as the client does: descramble in place, then little-endian fields. */
	private static Board decode(byte[] body) {
		var plain = RankingScramble.apply(body.clone());
		var buffer = ByteBuffer.wrap(plain).order(ByteOrder.LITTLE_ENDIAN);

		var count = buffer.getInt();
		var total = Integer.toUnsignedLong(buffer.getInt());
		var ignored = Integer.toUnsignedLong(buffer.getInt());

		var rows = new ArrayList<Row>();
		for (var i = 0; i < count; i++) {
			var rank = Integer.toUnsignedLong(buffer.getInt());
			var id = Integer.toUnsignedLong(buffer.getInt());

			var name = new byte[NAME_SIZE];
			buffer.get(name);

			rows.add(new Row(rank, id, text(name), Integer.toUnsignedLong(buffer.getInt())));
		}

		return new Board(count, total, ignored, rows);
	}

	/** The client runs the field through strlen, so the name is what precedes the first NUL. */
	private static String text(byte[] field) {
		var length = 0;
		while (length < field.length && field[length] != 0) {
			length++;
		}
		return new String(field, 0, length, StandardCharsets.ISO_8859_1);
	}

	private byte[] post(String path, int term, int rule, int skey, int from, int records,
			String idField, long id) throws IOException {
		var form = new FormBody.Builder()
			.add("term", Integer.toString(term))
			.add("rule", Integer.toString(rule))
			.add("skey", Integer.toString(skey))
			.add("from", Integer.toString(from))
			.add("records", Integer.toString(records))
			.add(idField, Long.toString(id))
			.build();

		var request = new Request.Builder().url(host + path).post(form).build();

		try (Response response = client.newCall(request).execute()) {
			// [ELF 0xBB2D14] anything but 200 aborts the screen before the body is looked at.
			assertThat(response.code()).isEqualTo(200);

			var body = response.body();
			assertThat(body).isNotNull();
			return body.bytes();
		}
	}

	private byte[] players(int term, int rule, int skey, int from, int records, long pid)
			throws IOException {
		return post(RankingWebController.PLAYER_PATH, term, rule, skey, from, records, "pid", pid);
	}

	private byte[] clans(int term, int skey, int from, int records, long cid) throws IOException {
		return post(RankingWebController.CLAN_PATH, term, 8, skey, from, records, "cid", cid);
	}

	/** Characters with distinct experience, so the grade-point board has a known order. */
	private List<Long> givenCharacters(String... names) {
		var ids = new ArrayList<Long>();
		var jdbi = TestDatabase.get().jdbi();

		for (var i = 0; i < names.length; i++) {
			var experience = (names.length - i) * 100;
			var accountId = jdbi.withHandle(handle ->
				handle.createUpdate("""
						insert into account (username, password, slots, main_exp, alt_exp)
						values (:username, 'x', 3, :exp, 0)
						""")
					.bind("username", "player" + names[0] + ids.size())
					.bind("exp", experience)
					.executeAndReturnGeneratedKeys("id")
					.mapTo(Long.class)
					.one());

			var name = names[i];
			var charaId = jdbi.withHandle(handle ->
				handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
					.bind("account", accountId)
					.bind("name", name)
					.executeAndReturnGeneratedKeys("id")
					.mapTo(Long.class)
					.one());

			// main_chara_id decides which experience pool counts, the same split the stats
			// screens use.
			jdbi.useHandle(handle ->
				handle.createUpdate("update account set main_chara_id = :chara where id = :id")
					.bind("chara", charaId)
					.bind("id", accountId)
					.execute());

			ids.add(charaId);
		}
		return ids;
	}

	/** Framing: a board with no subjects is still a well-formed twelve-byte reply. */
	@Test
	public void emptyBoardIsAWellFormedReply() throws IOException {
		var body = players(0, 8, RankingService.SKEY_GRADE_POINT, 0, PAGE_RECORDS, 0);

		assertThat(body).hasSize(HEADER_SIZE);

		var board = decode(body);
		assertThat(board.count()).isZero();
		assertThat(board.total()).isZero();
		assertThat(board.rows()).isEmpty();
	}

	/** Size, ordering and dense 1-based ranks. */
	@Test
	public void playerBoardIsOrderedAndRanked() throws IOException {
		var ids = givenCharacters("Alpha", "Bravo", "Charlie");

		var body = players(0, 8, RankingService.SKEY_GRADE_POINT, 0, PAGE_RECORDS, 0);

		assertThat(body).hasSize(HEADER_SIZE + 3 * RECORD_SIZE);

		var board = decode(body);
		assertThat(board.count()).isEqualTo(3);
		assertThat(board.total()).isEqualTo(3);
		// [ELF 0x912BE0] the third header word is read into a stack slot and never used again.
		assertThat(board.ignored()).isZero();

		assertThat(board.rows()).extracting(Row::rank).containsExactly(1L, 2L, 3L);
		assertThat(board.rows()).extracting(Row::name)
			.containsExactly("Alpha", "Bravo", "Charlie");
		assertThat(board.rows()).extracting(Row::id)
			.containsExactly(ids.get(0), ids.get(1), ids.get(2));
		assertThat(board.rows()).extracting(Row::value).containsExactly(300L, 200L, 100L);
	}

	/**
	 * {@code from} is a row offset and {@code total} stays the size of the whole board, because
	 * that is what the client's scroll limit compares against [ELF 0x9119C0].
	 */
	@Test
	public void windowIsOffsetButTotalIsTheWholeBoard() throws IOException {
		givenCharacters("Alpha", "Bravo", "Charlie");

		var board = decode(players(0, 8, RankingService.SKEY_GRADE_POINT, 1, PAGE_RECORDS, 0));

		assertThat(board.count()).isEqualTo(2);
		assertThat(board.total()).isEqualTo(3);
		assertThat(board.rows()).extracting(Row::name).containsExactly("Bravo", "Charlie");
		assertThat(board.rows()).extracting(Row::rank).containsExactly(2L, 3L);
	}

	/** Past the end of the board: no rows, but the total still reports the board's size. */
	@Test
	public void windowPastTheEndIsEmptyButKeepsTheTotal() throws IOException {
		givenCharacters("Alpha", "Bravo");

		var board = decode(players(0, 8, RankingService.SKEY_GRADE_POINT, 50, PAGE_RECORDS, 0));

		assertThat(board.count()).isZero();
		assertThat(board.total()).isEqualTo(2);
	}

	/**
	 * The own-standing mode: {@code records=1} with the character's own id, which must come back
	 * carrying its true rank rather than 1.
	 */
	@Test
	public void ownStandingCarriesTheTrueRank() throws IOException {
		var ids = givenCharacters("Alpha", "Bravo", "Charlie");

		var body = players(0, 8, RankingService.SKEY_GRADE_POINT, 0, 1, ids.get(2));

		assertThat(body).hasSize(HEADER_SIZE + RECORD_SIZE);

		var board = decode(body);
		assertThat(board.count()).isEqualTo(1);
		assertThat(board.total()).isEqualTo(3);
		assertThat(board.rows().getFirst().rank()).isEqualTo(3);
		assertThat(board.rows().getFirst().name()).isEqualTo("Charlie");
	}

	/**
	 * The client drops the entire reply when the record count exceeds what it asked for
	 * ([ELF] {@code 0x912AF4}), so the window must never overrun {@code records}.
	 */
	@Test
	public void neverReturnsMoreRecordsThanRequested() throws IOException {
		givenCharacters("Alpha", "Bravo", "Charlie");

		var board = decode(players(0, 8, RankingService.SKEY_GRADE_POINT, 0, 2, 0));

		assertThat(board.count()).isEqualTo(2);
		assertThat(board.total()).isEqualTo(3);
	}

	/**
	 * Names are NUL-terminated inside the sixteen-byte field. The client copies them into an
	 * uninitialised stack buffer and calls {@code strlen} ({@code 0x912D30}, {@code 0xAF7140}), so
	 * a name that filled all sixteen bytes would have no terminator to stop at.
	 */
	@Test
	public void namesAreAlwaysTerminatedWithinTheField() throws IOException {
		givenCharacters("SixteenCharsXXXX");

		var body = players(0, 8, RankingService.SKEY_GRADE_POINT, 0, PAGE_RECORDS, 0);

		var plain = RankingScramble.apply(body.clone());
		var field = new byte[NAME_SIZE];
		System.arraycopy(plain, HEADER_SIZE + 8, field, 0, NAME_SIZE);

		assertThat(field[NAME_SIZE - 1]).isZero();
		assertThat(text(field)).isEqualTo("SixteenCharsXXX");
	}

	/** The reply is obfuscated, so a cleartext read of it must not produce the field values. */
	@Test
	public void replyIsScrambledOnTheWire() throws IOException {
		givenCharacters("Alpha");

		var body = players(0, 8, RankingService.SKEY_GRADE_POINT, 0, PAGE_RECORDS, 0);

		var raw = ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN);
		assertThat(raw.getInt()).isNotEqualTo(1);

		assertThat(new String(body, StandardCharsets.ISO_8859_1)).doesNotContain("Alpha");
		assertThat(decode(body).rows().getFirst().name()).isEqualTo("Alpha");
	}

	/** The clan endpoint answers the same shape, keyed by clan id. */
	@Test
	public void clanBoardUsesTheSameFraming() throws IOException {
		var ids = givenCharacters("Leader");
		var jdbi = TestDatabase.get().jdbi();

		var clanId = jdbi.withHandle(handle ->
			handle.createUpdate("""
					insert into clan (name, description, leader_chara_id)
					values ('Best Clan', '', :leader)
					""")
				.bind("leader", ids.getFirst())
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into clan_member (chara_id, clan_id, state) values (:chara, :clan, 2)
					""")
				.bind("chara", ids.getFirst())
				.bind("clan", clanId)
				.execute());

		var board = decode(clans(2, RankingService.SKEY_GRADE_POINT, 0, PAGE_RECORDS, 0));

		assertThat(board.count()).isEqualTo(1);
		assertThat(board.total()).isEqualTo(1);
		assertThat(board.rows().getFirst().id()).isEqualTo(clanId);
		assertThat(board.rows().getFirst().name()).isEqualTo("Best Clan");
		assertThat(board.rows().getFirst().rank()).isEqualTo(1);
	}

	/**
	 * Host rating has no stored source, so its board is deliberately empty rather than a column of
	 * zeroes. A zero total is what makes the client render the row as unselectable
	 * ([ELF] {@code 0x911674}).
	 */
	@Test
	public void hostRatingBoardIsEmptyUntilSomebodyVotes() throws IOException {
		givenCharacters("Alpha", "Bravo");

		var board = decode(players(0, 8, RankingService.SKEY_HOST_RATING, 0, PAGE_RECORDS, 0));

		assertThat(board.count()).isZero();
		assertThat(board.total()).isZero();
	}

	/**
	 * Host rating had no source at all until {@code 0x43c4} was identified on 2026-07-28, and this
	 * board returned an empty result on purpose rather than a column of zeroes. It has one now, so
	 * the empty case above must be "nobody voted" rather than "nothing measures it" — otherwise
	 * that test would keep passing for a reason that had stopped being true.
	 */
	@Test
	public void hostRatingBoardRanksTheVotesItIsGiven() throws IOException {
		var ids = givenCharacters("Alpha", "Bravo");
		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("""
					insert into host_review (game_id, host_chara_id, voter_chara_id, rating)
					values (900, :alpha, :bravo, 5), (901, :bravo, :alpha, 3)
					""")
			.bind("alpha", ids.get(0))
			.bind("bravo", ids.get(1))
			.execute());

		var board = decode(players(0, 8, RankingService.SKEY_HOST_RATING, 0, PAGE_RECORDS, 0));

		assertThat(board.count()).isEqualTo(2);
		assertThat(board.total()).isEqualTo(2);
		// 8.8 fixed point, the scale the client's ten-segment gauge divides by 256.
		assertThat(board.rows().get(0).value()).isEqualTo(5 * 256);
		assertThat(board.rows().get(1).value()).isEqualTo(3 * 256);
	}
}
