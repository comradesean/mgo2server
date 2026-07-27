package mgo2server.common.service;

import org.jdbi.v3.core.Jdbi;
import org.jdbi.v3.core.statement.Query;

import java.util.List;

/**
 * The Rankings screens, both the player board and the clan board.
 * <p>
 * <b>Rankings are not part of the lobby TCP protocol.</b> Nothing in the {@code 0x4xxx} command
 * space serves them; the screen POSTs to {@code rank/mgogetrank.html} (players) or
 * {@code rank/mgogetrank_clan.html} (clans) and parses a binary reply. See
 * {@code mgo2server.web.controller.RankingWebController} for the wire format and
 * {@link mgo2server.common.crypto.RankingScramble} for the obfuscation every reply carries.
 * <p>
 * This class answers the only question the endpoint actually asks: <em>order these subjects by
 * some quantity, and give me a window of the result plus the size of the whole board.</em> Which
 * quantity is chosen by the {@code skey} parameter.
 *
 * <h2>What {@code skey} means</h2>
 * The value set is [ELF] — the menu-row tables at {@code 0x914140} (player) and {@code 0x9153A0}
 * (clan) only ever produce {@code skey} in {@code {0, 2, 3, 4, 5, 6}}, with {@code 0, 2, 3, 4, 5}
 * on the player endpoint and {@code 2, 3, 6} on the clan endpoint. The <em>meanings</em> below are
 * [INFERRED] and should be read as such:
 * <ul>
 *   <li>{@code skey 4} and {@code skey 5} are the only two rows the client renders as a
 *       fixed-point {@code x.yy} with a ten-segment gauge ([ELF] {@code 0x910740}, multiplier
 *       {@code 0x3B800000} = 1/256). A ten-segment gauge over a 1..5 star average is what the Host
 *       Score and Instructor Score rows are, so those two rows are star ratings in 8.8 fixed
 *       point. That much is solid. <b>Which of the two is host and which is instructor is
 *       [INFERRED] from menu order alone</b> (lobby strings 18252 "Host Score Rankings" precedes
 *       18258 "Instructor Score Rankings", and row 9 precedes row 10).</li>
 *   <li>{@code skey 0} is the only key that varies {@code rule} — seven consecutive menu rows send
 *       {@code skey 0} with {@code rule} 0, 1, 3, 5, 2, 7, 4 [ELF]. Seven per-mode rows is exactly
 *       the shape of "Score Rankings", so {@code skey 0} is read as score, split by game mode.</li>
 *   <li>{@code skey 2} is the one player row carrying the TOTAL/MONTH toggle [ELF: its {@code term}
 *       is the selector, every other player row hardcodes {@code term 0}]. A per-month board reads
 *       as Activeness, so it is mapped to time played.</li>
 *   <li>{@code skey 3} is mapped to grade points. This is the weakest of the inferences: it rests
 *       on {@code skey 3} appearing on both endpoints with {@code term} fixed, and on grade point
 *       being the one board the UI describes as untabulated rather than periodic.</li>
 *   <li>{@code skey 6} appears on the clan endpoint only.</li>
 * </ul>
 * If one of these is wrong the screen shows a defensible number in the wrong column; nothing
 * desyncs, because the reply's shape does not depend on {@code skey}. A capture of a real Konami
 * ranking response would settle all of it at once and none exists.
 *
 * <h2>Where the numbers come from</h2>
 * Everything is derived at query time from data already stored — {@code round_report},
 * {@code account}, {@code instructor_review}, {@code clan_member} — in the same spirit as the stats
 * and history screens. There is no ranking table and no precomputed board.
 * <p>
 * <b>{@code skey 4} returns an empty board on purpose.</b> We store no host rating anywhere: the
 * host-evaluation path is unimplemented, so there is nothing to sort. An empty board is a
 * well-formed answer the client renders as an unselectable row ([ELF] {@code 0x911674}: a
 * {@code total} of zero disables the row), and it is the honest one. Inventing a column of zeroes
 * would look identical on screen while claiming we had measured something.
 */
public class RankingService {
	/** Score, split by game mode — the {@code rule} parameter selects the mode. [INFERRED] */
	public static final int SKEY_SCORE = 0;

	/** Time played. The one player row with a TOTAL/MONTH toggle. [INFERRED] */
	public static final int SKEY_ACTIVENESS = 2;

	/** Grade points. [INFERRED], and the least certain of these mappings. */
	public static final int SKEY_GRADE_POINT = 3;

	/** Host rating, 8.8 fixed point. Rendered with a gauge [ELF]; we hold no source data. */
	public static final int SKEY_HOST_RATING = 4;

	/** Instructor rating, 8.8 fixed point. Rendered with a gauge [ELF]. */
	public static final int SKEY_INSTRUCTOR_RATING = 5;

	/** Clan-only key. [INFERRED] as the clan's combined score. */
	public static final int SKEY_CLAN_SCORE = 6;

	/**
	 * Player boards use {@code term} 0 and 1, clan boards 2 and 3 [ELF: the clan menu adds two,
	 * {@code 0x9110F0}]. The odd member of each pair is the MONTH half of the screen's
	 * TOTAL/MONTH toggle, which is why the test is on the low bit rather than on the value.
	 */
	private static final int TERM_PERIODIC_BIT = 1;

	/**
	 * The client sends {@code records} 1 (its own rank) or 100 (a page) and never anything else
	 * [ELF {@code 0x910FEC}]. It <b>rejects the whole reply</b> if the record count exceeds what it
	 * asked for ([ELF] {@code 0x912AF4}), so the window is clamped rather than trusted; 100 is also
	 * well inside the 10 240-byte receive buffer, which would hold 365.
	 */
	public static final int MAX_RECORDS = 100;

	/** Ratings are carried as 8.8 fixed point [ELF {@code 0x91074C}]. */
	private static final int FIXED_POINT_SCALE = 256;

	/**
	 * One board row. {@code rank} is 1-based and dense; {@code value} is already in the units the
	 * client will render — scaled to 8.8 for the two rating boards, a plain count elsewhere.
	 */
	public record RankingEntry(long rank, long id, String name, long value) {
	}

	/**
	 * A window of a board plus the size of the whole board. {@code total} is what drives the
	 * client's scroll limit and its "rows to draw" count ([ELF] {@code 0x912BB0}), so it is the
	 * size of the entire ranking, not of {@code entries}.
	 */
	public record RankingPage(List<RankingEntry> entries, long total) {
	}

	/**
	 * Wraps a subject-and-value query into a ranked board. The inner query must yield
	 * {@code id}, {@code name} and {@code value}; ties break on id so paging is stable.
	 * <p>
	 * Note the deliberate absence of {@code &lt;} anywhere in these statements. Jdbi renders SQL
	 * through StringTemplate, which reads angle brackets as an expression and fails to compile the
	 * statement — the same trap {@code GameService.metPlayers} documents, and it applies to SQL
	 * comments too.
	 */
	private static final String RANKED = """
			with base as (%s),
			ranked as (
				select id, name, value,
					row_number() over (order by value desc, id) as rank
				from base
			)
			select id, name, value, rank from ranked
			""";

	private static final String PAGE = RANKED + " order by rank offset :from limit :records";

	private static final String SUBJECT = RANKED + " where id = :subject";

	private static final String TOTAL = "select count(*) from (%s) counted";

	/** Grade points, using the same main/alt split every other experience read uses. */
	private static final String PLAYER_GRADE_POINT = """
			select c.id as id, c.name as name,
				case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end as value
			from chara c
			join account a on a.id = c.account_id
			where c.active
			""";

	private static final String PLAYER_SCORE = """
			select c.id as id, c.name as name, coalesce(sum(r.score), 0) as value
			from chara c
			join round_report r on r.chara_id = c.id
			where c.active and r.rule = :rule %s
			group by c.id, c.name
			""";

	private static final String PLAYER_ACTIVENESS = """
			select c.id as id, c.name as name, coalesce(sum(r.seconds_in_game), 0) as value
			from chara c
			join round_report r on r.chara_id = c.id
			where c.active %s
			group by c.id, c.name
			""";

	private static final String PLAYER_INSTRUCTOR_RATING = """
			select c.id as id, c.name as name,
				round(avg(v.rating) * :scale)::bigint as value
			from chara c
			join instructor_review v on v.instructor_chara_id = c.id
			where c.active %s
			group by c.id, c.name
			""";

	/** No subject has a value, so the board is empty and its total is zero. */
	private static final String EMPTY_BOARD = """
			select c.id as id, c.name as name, 0::bigint as value
			from chara c
			where false
			""";

	/**
	 * Clan boards aggregate over members. Pending applicants ({@code state} 0) are excluded — they
	 * are not in the clan yet, and counting their play towards it would let a clan inflate its
	 * standing by leaving applications open.
	 */
	private static final String CLAN_SCORE = """
			select cl.id as id, cl.name as name, coalesce(sum(r.score), 0) as value
			from clan cl
			join clan_member m on m.clan_id = cl.id and m.state between 1 and 2
			join round_report r on r.chara_id = m.chara_id
			where true %s
			group by cl.id, cl.name
			""";

	private static final String CLAN_ACTIVENESS = """
			select cl.id as id, cl.name as name, coalesce(sum(r.seconds_in_game), 0) as value
			from clan cl
			join clan_member m on m.clan_id = cl.id and m.state between 1 and 2
			join round_report r on r.chara_id = m.chara_id
			where true %s
			group by cl.id, cl.name
			""";

	private static final String CLAN_GRADE_POINT = """
			select cl.id as id, cl.name as name,
				coalesce(sum(case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end), 0)
					as value
			from clan cl
			join clan_member m on m.clan_id = cl.id and m.state between 1 and 2
			join chara c on c.id = m.chara_id and c.active
			join account a on a.id = c.account_id
			group by cl.id, cl.name
			""";

	/** The MONTH half of the toggle is the current calendar month, matching "Monthly Total". */
	private static final String WITHIN_MONTH =
		"and %s >= date_trunc('month', current_timestamp)";

	private final Jdbi jdbi;

	public RankingService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/**
	 * A page of the player board, or that player's own row when {@code charaId} is non-zero.
	 * <p>
	 * The client uses exactly those two modes: {@code records=100, pid=0} for a page and
	 * {@code records=1, pid=&lt;own id&gt;} for its own standing [ELF {@code 0x910F88}]. Keying on
	 * the id rather than on the record count is the more robust of the two equivalent tests.
	 */
	public RankingPage players(int term, int rule, int skey, int from, int records, long charaId) {
		return page(playerBase(term, rule, skey), rule, from, records, charaId);
	}

	/**
	 * A page of the clan board, or that clan's own row when {@code clanId} is non-zero.
	 * <p>
	 * The clan menu sends {@code rule 8} on every row [ELF {@code 0x9110F0}], i.e. it never splits
	 * a clan board by game mode, so no rule is threaded through here.
	 */
	public RankingPage clans(int term, int skey, int from, int records, long clanId) {
		return page(clanBase(term, skey), 0, from, records, clanId);
	}

	private String playerBase(int term, int rule, int skey) {
		return switch (skey) {
			case SKEY_SCORE -> PLAYER_SCORE.formatted(window(term, "r.reported_at"));
			case SKEY_ACTIVENESS -> PLAYER_ACTIVENESS.formatted(window(term, "r.reported_at"));
			case SKEY_GRADE_POINT -> PLAYER_GRADE_POINT;
			case SKEY_INSTRUCTOR_RATING ->
				PLAYER_INSTRUCTOR_RATING.formatted(window(term, "v.reviewed_at"));
			// Host rating has no stored source; see the class note.
			default -> EMPTY_BOARD;
		};
	}

	private String clanBase(int term, int skey) {
		return switch (skey) {
			case SKEY_ACTIVENESS -> CLAN_ACTIVENESS.formatted(window(term, "r.reported_at"));
			case SKEY_GRADE_POINT -> CLAN_GRADE_POINT;
			case SKEY_CLAN_SCORE -> CLAN_SCORE.formatted(window(term, "r.reported_at"));
			default -> EMPTY_BOARD;
		};
	}

	/** Empty for a lifetime board, a calendar-month predicate for the periodic half. */
	private static String window(int term, String column) {
		return (term & TERM_PERIODIC_BIT) == 0 ? "" : WITHIN_MONTH.formatted(column);
	}

	private RankingPage page(String base, int rule, int from, int records, long subject) {
		var limit = Math.clamp(records, 0, MAX_RECORDS);
		var offset = Math.max(from, 0);

		return jdbi.withHandle(handle -> {
			var total = bindBoard(handle.createQuery(TOTAL.formatted(base)), base, rule)
				.mapTo(Long.class)
				.one();

			if (limit == 0) {
				return new RankingPage(List.of(), total);
			}

			var query = subject == 0
				? handle.createQuery(PAGE.formatted(base)).bind("from", offset).bind("records", limit)
				: handle.createQuery(SUBJECT.formatted(base)).bind("subject", subject);

			var entries = bindBoard(query, base, rule)
				.map((rs, ctx) -> new RankingEntry(rs.getLong("rank"), rs.getLong("id"),
					rs.getString("name"), rs.getLong("value")))
				.list();

			return new RankingPage(entries, total);
		});
	}

	/**
	 * Binds only the parameters the chosen board actually declares. Jdbi rejects a binding the
	 * statement does not use — "superfluous named parameters" — so a blanket bind of every
	 * parameter any board might want fails on the boards that want none of them.
	 */
	private static Query bindBoard(Query query, String base, int rule) {
		if (base.contains(":rule")) {
			query.bind("rule", rule);
		}
		if (base.contains(":scale")) {
			query.bind("scale", FIXED_POINT_SCALE);
		}
		return query;
	}
}
