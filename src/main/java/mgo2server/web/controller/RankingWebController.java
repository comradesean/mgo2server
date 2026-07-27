package mgo2server.web.controller;

import io.jooby.Jooby;
import io.jooby.MediaType;
import mgo2server.common.crypto.RankingScramble;
import mgo2server.common.service.RankingService;
import mgo2server.web.IWebController;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/**
 * The Rankings screens — player board and clan board.
 * <p>
 * <b>This is not a lobby command.</b> The Rankings menu never touches the {@code 0x4xxx} TCP
 * protocol; it POSTs to two HTTP endpoints and parses a binary reply. The {@code 0x4Axx} block,
 * which reads like a plausible ranking family from its id, is a different subsystem — its records
 * embed the 204-byte game-settings block, so it belongs to games, not boards.
 *
 * <h2>The request</h2>
 * [ELF] {@code MGO2.elf} BLUS30109, ranking translation unit at {@code 0x90F31C}-{@code 0x915308}.
 * The URL is the network config's base URL (config slot 2, {@code 0x884B34}) with a relative path
 * {@code strcat}'d onto it at {@code 0x911224}:
 * <pre>
 *   rank/mgogetrank.html        players
 *   rank/mgogetrank_clan.html   clans
 * </pre>
 * It is a <b>POST</b>, not a GET: the transport picks its method from a flag word
 * ({@code 0xBB4254}, {@code flags &amp; 1}) and the ranking caller passes 3. The six parameters go
 * in an {@code application/x-www-form-urlencoded} body, always in this order and never omitted
 * ({@code 0x911288} onward), each rendered with {@code "%u"}:
 * <pre>
 *   term=..&amp;rule=..&amp;skey=..&amp;from=..&amp;records=..&amp;pid=..     (players)
 *   term=..&amp;rule=..&amp;skey=..&amp;from=..&amp;records=..&amp;cid=..     (clans)
 * </pre>
 * {@code rule} is masked to 4 bits and {@code skey} to 3 at the call site. {@code from} is the row
 * offset of the window, advanced by 50 as the cursor runs off it ({@code 0x911B28}).
 * {@code records} is 1 when the client wants its own standing (and then {@code pid}/{@code cid}
 * carries its own id) or 100 for a page (and then the id is 0) — those are the only two values it
 * ever sends ({@code 0x910FEC}).
 *
 * <h2>The reply</h2>
 * A binary blob, <b>little-endian</b> — the reader at {@code 0xBC3CE8} assembles
 * {@code b[3]&lt;&lt;24 | b[2]&lt;&lt;16 | b[1]&lt;&lt;8 | b[0]}, which is the opposite order from every
 * lobby packet in this protocol. Layout, from the parser at {@code 0x912A94}:
 * <table>
 *   <tr><th>offset</th><th>size</th><th>field</th></tr>
 *   <tr><td>0</td><td>4</td><td>record count {@code N}</td></tr>
 *   <tr><td>4</td><td>4</td><td>{@code total} — entries on the whole board</td></tr>
 *   <tr><td>8</td><td>4</td><td>read and discarded ({@code 0x912BE0}); we send 0</td></tr>
 * </table>
 * then {@code N} records of <b>28 bytes</b>, stride 112 in the client's own array:
 * <table>
 *   <tr><th>offset</th><th>size</th><th>field</th></tr>
 *   <tr><td>0</td><td>4</td><td>rank, 1-based</td></tr>
 *   <tr><td>4</td><td>4</td><td>character id, or clan id on the clan endpoint</td></tr>
 *   <tr><td>8</td><td>16</td><td>name</td></tr>
 *   <tr><td>24</td><td>4</td><td>value</td></tr>
 * </table>
 * So a reply is {@code 12 + 28 * N} bytes. The whole thing is then obfuscated — see
 * {@link RankingScramble}, and note that a cleartext reply is not rejected, it is silently
 * misparsed.
 *
 * <h2>The two ways to get this wrong</h2>
 * There are exactly two rejections in the client, and both are worth stating because everything
 * else fails silently:
 * <ol>
 *   <li>An HTTP status other than <b>200</b> ({@code 0xBB2D14}).</li>
 *   <li>{@code N} greater than the {@code records} the client asked for ({@code 0x912AF4}) — the
 *       whole reply is dropped and the screen bails. {@link RankingService#MAX_RECORDS} and the
 *       clamp in the service exist for this.</li>
 * </ol>
 * There is no magic prefix, no checksum and no minimum length. In particular the reader does
 * <b>not</b> bounds-check against the body length ({@code 0xBC3CE8} tests only for null), so a
 * reply that is short for its own {@code N} is parsed off whatever the 10 240-byte buffer already
 * held — the same silent-underrun failure mode the lobby protocol has, and the reason {@code N} is
 * always written as the number of records actually serialised.
 */
public class RankingWebController implements IWebController {
	private static final Logger logger = LogManager.getLogger();

	public static final String PLAYER_PATH = "/us/mgo2/rank/mgogetrank.html";

	public static final String CLAN_PATH = "/us/mgo2/rank/mgogetrank_clan.html";

	/** Record count, board total, and the word the parser reads and throws away. */
	private static final int HEADER_SIZE = 12;

	/** [ELF] rank, id, 16-byte name, value. */
	private static final int RECORD_SIZE = 28;

	private static final int NAME_SIZE = 16;

	/**
	 * The client copies the 16 name bytes into a stack buffer it never clears and then calls
	 * {@code strlen} on them ({@code 0x912D30} reads 16 raw bytes into {@code r1+128};
	 * {@code 0xAF7140} takes their length). A name that fills all sixteen has no terminator, so the
	 * length runs into whatever the frame held. We therefore emit at most fifteen characters and
	 * guarantee a NUL.
	 * <p>
	 * This is a deliberate, bounded truncation rather than protocol: a sixteen-character name is
	 * legal everywhere else, and the lobby protocol's own 16-byte name fields are safe because
	 * <em>there</em> the client appends its own NUL. Losing the last character of the longest names
	 * is the smaller defect.
	 */
	private static final int MAX_NAME_LENGTH = NAME_SIZE - 1;

	/** [ELF] the client masks {@code rule} to four bits and {@code skey} to three. */
	private static final int RULE_MASK = 0x0F;

	private static final int SKEY_MASK = 0x07;

	private final RankingService rankingService;

	public RankingWebController(RankingService rankingService) {
		this.rankingService = rankingService;
	}

	@Override
	public void use(Jooby jooby) {
		jooby.post(PLAYER_PATH, ctx -> {
			var request = Request.from(ctx.form("term").intValue(0), ctx.form("rule").intValue(0),
				ctx.form("skey").intValue(0), ctx.form("from").intValue(0),
				ctx.form("records").intValue(0), ctx.form("pid").longValue(0));

			var page = rankingService.players(request.term(), request.rule(), request.skey(),
				request.from(), request.records(), request.subject());

			logger.info("Player ranking skey={} rule={} term={} from={} records={} pid={} -> {} of {}.",
				request.skey(), request.rule(), request.term(), request.from(), request.records(),
				request.subject(), page.entries().size(), page.total());

			ctx.setResponseType(MediaType.octetStream);
			return encode(page);
		});

		jooby.post(CLAN_PATH, ctx -> {
			var request = Request.from(ctx.form("term").intValue(0), ctx.form("rule").intValue(0),
				ctx.form("skey").intValue(0), ctx.form("from").intValue(0),
				ctx.form("records").intValue(0), ctx.form("cid").longValue(0));

			var page = rankingService.clans(request.term(), request.skey(), request.from(),
				request.records(), request.subject());

			logger.info("Clan ranking skey={} term={} from={} records={} cid={} -> {} of {}.",
				request.skey(), request.term(), request.from(), request.records(),
				request.subject(), page.entries().size(), page.total());

			ctx.setResponseType(MediaType.octetStream);
			return encode(page);
		});
	}

	/** The six form fields, with the masks the client applies before it sends them. */
	record Request(int term, int rule, int skey, int from, int records, long subject) {
		static Request from(int term, int rule, int skey, int from, int records, long subject) {
			return new Request(term, rule & RULE_MASK, skey & SKEY_MASK, Math.max(from, 0),
				records, Math.max(subject, 0));
		}
	}

	/**
	 * Serialises a board window and scrambles it. {@code N} is taken from the list actually
	 * written, never from what was requested — see the underrun note on the class.
	 */
	static byte[] encode(RankingService.RankingPage page) {
		var entries = page.entries();

		var buffer = ByteBuffer.allocate(HEADER_SIZE + RECORD_SIZE * entries.size())
			.order(ByteOrder.LITTLE_ENDIAN);

		buffer.putInt(entries.size());
		buffer.putInt((int) page.total());
		buffer.putInt(0);

		for (var entry : entries) {
			buffer.putInt((int) entry.rank());
			buffer.putInt((int) entry.id());
			buffer.put(name(entry.name()));
			buffer.putInt((int) entry.value());
		}

		return RankingScramble.apply(buffer.array());
	}

	/** A name as sixteen bytes, NUL-padded, always terminated. See {@link #MAX_NAME_LENGTH}. */
	private static byte[] name(String value) {
		var field = new byte[NAME_SIZE];
		if (value == null) {
			return field;
		}

		var text = value.length() > MAX_NAME_LENGTH ? value.substring(0, MAX_NAME_LENGTH) : value;
		var bytes = text.getBytes(StandardCharsets.ISO_8859_1);
		System.arraycopy(bytes, 0, field, 0, bytes.length);
		return field;
	}
}
