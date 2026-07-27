package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.service.ClanService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Clans: creating one, and reporting the one a character belongs to.
 * <p>
 * The clan record is one struct the client keeps at a fixed place in its profile, and two commands
 * fill it: {@code 0x4122} carries it inside the connect burst, and {@code 0x4b47} replaces it on
 * demand. Both write the same five fields, which is how the layout below is known:
 * <table>
 *   <tr><th>profile</th><th>field</th></tr>
 *   <tr><td>{@code +6816}</td><td>clan id, 0 when none</td></tr>
 *   <tr><td>{@code +6820}</td><td>clan name, 16 bytes plus a client-side NUL</td></tr>
 *   <tr><td>{@code +6837}</td><td>membership state — 0 pending, 1 member, 2 leader, 99 none</td></tr>
 *   <tr><td>{@code +6838}</td><td>privilege mask</td></tr>
 *   <tr><td>{@code +6872}</td><td>emblem flag, 3 when the clan has one</td></tr>
 * </table>
 */
public class ClanGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/**
	 * Create a clan: {@code name[16]} then {@code description[128]}, both fixed-width, 144 bytes.
	 * Capture-confirmed 2026-07-27 — "best clan" / "numbuh 1" arrived exactly as the ksy predicted.
	 * <p>
	 * The client validates before sending ({@code 0xD579AC}): the name must be 3..16 characters and
	 * pass the character-class check {@code 0xD32DD0}, the description at most 128. So a name that
	 * reaches us is already well-formed and the only failure left is a collision.
	 */
	public static final int CREATE_CLAN = 0x4b00;

	/**
	 * {@code {u32 result, u32 clan_id}}. On {@code result == 0} the client stores the second word as
	 * its clan id and sets itself leader — {@code 0xD56E84} {@code lwz r9,116(r1)} /
	 * {@code stw r9,6816}, {@code 0xD56E90} {@code li r0,2; stb r0,6837}. A nonzero result ends the
	 * payload after four bytes and the client keeps whatever record it had.
	 */
	public static final int CREATE_CLAN_RESULT = 0x4b01;

	/**
	 * A second clan-scoped fetch, payload the clan id, sent right after the profile. Reply
	 * {@code 0x4b4d} is the same shape as {@code 0x4b49}: {@code {s4 result, byte[768]}}, block
	 * opaque to the parser, request slot 103.
	 */
	public static final int CLAN_DETAIL = 0x4b4c;

	public static final int CLAN_DETAIL_RESULT = 0x4b4d;

	/**
	 * The clan member list, payload the clan id. A start/items/end triple in the same shape as the
	 * social lists we already serve ({@code 0x4601}/{@code 0x4602}/{@code 0x4603}): the start and
	 * end packets carry a <b>result code, never a count</b> — sending a count there produced the
	 * live {@code 1032:00000005} error on the social path, and the client counts the item records
	 * itself. Items are {@code 0x4b54}, 68 wire bytes each.
	 */
	public static final int CLAN_MEMBERS = 0x4b52;

	public static final int CLAN_MEMBERS_START = 0x4b53;

	public static final int CLAN_MEMBERS_ENTRIES = 0x4b54;

	public static final int CLAN_MEMBERS_END = 0x4b55;

	/**
	 * One roster row: 68 wire bytes. The head is the same {@code {u32 id, name[16], u8 status}} shape
	 * as the session clan record and the profile block, so it is filled as character id, character
	 * name and membership state; the remaining 47 bytes — two more 16-byte names and three numbers —
	 * are [UNKNOWN] and stay zero. If the roster renders the right names in the right order, the
	 * head is confirmed and the rest can be worked out from what is missing on screen.
	 */
	private static final int MEMBER_RECORD_SIZE = 68;

	/**
	 * Sent unprompted at login by any character who <b>is in a clan</b> — the payload is the client's
	 * own cached clan id, read straight out of {@code session_ctx+0x1AA0} rather than passed in
	 * ({@code 0xD577A4}). It appeared the moment {@code 0x4122} first reported a real clan, and
	 * blocks: character select hangs without a reply.
	 */
	public static final int CLAN_DATA = 0x4b48;

	/**
	 * {@code {s4 result, byte[768]}} — 772 bytes on success, 4 on error.
	 * <p>
	 * The parser reads the block with {@code 0xD5D018} as one opaque run and <b>never looks
	 * inside</b>; the client NUL-terminates at {@code +768}, so whatever consumes it downstream
	 * treats it as a string or a table of them. Contents [UNKNOWN] — 768 zeros is the honest reply
	 * until a screen shows us what it wants, and it is a well-formed one because the parser's only
	 * requirement is the length.
	 */
	public static final int CLAN_DATA_RESULT = 0x4b49;

	/** The opaque block of {@code 0x4b49}, whose length is the only thing the parser checks. */
	private static final int CLAN_DATA_BLOCK = 768;

	/** 768 / 16 — how many 16-byte names the block holds if it is a name table. */
	private static final int APPLICANT_NAME_SLOTS = 48;

	/**
	 * The clan profile request: one u32, the clan id ({@code 0xD567F0}). Sent from Clan Affiliation.
	 */
	public static final int CLAN_PROFILE = 0x4b20;

	/**
	 * The clan profile block, <b>777 bytes</b> when {@code result == 0} and 4 when it is not
	 * ({@code 0xD58C04} jumps straight to end-read). Most of it is still unmapped; three fields are
	 * not, and they are the three that matter for the screen to mean anything:
	 * <ul>
	 *   <li>{@code T+0x00} the clan id — <b>the client cross-checks this against the id it already
	 *       holds and drops the packet on a mismatch</b>, so it must echo the request</li>
	 *   <li>{@code T+0x04} a 16-byte name and {@code T+0x15} a status byte — the same
	 *       {id, name[16], status} shape as the session's own clan record at
	 *       {@code session_ctx+0x1AA0}</li>
	 *   <li>{@code T+0x67A} 128 bytes — the description. The create request read <em>its</em>
	 *       description from {@code arg+0x67A}, the identical offset, so the client keeps the clan
	 *       in one struct and both commands address the same field</li>
	 * </ul>
	 * Everything else is zero until a screen shows us what it wants: member counts, the emblem, the
	 * 512-byte blob at {@code T+0x700}, and three further 16-byte names whose owners are unknown.
	 */
	public static final int CLAN_PROFILE_RESULT = 0x4b21;

	/** {@code 0x4b21} on success. Checked against what we write, since most of it is padding. */
	private static final int PROFILE_SIZE = 777;

	/** The description field, at {@code T+0x67A} in the client's clan struct. */
	private static final int DESCRIPTION_LENGTH = 128;

	/**
	 * The clan probe, a bare u16 the client sends both during the connect burst and when the clan
	 * menu opens.
	 * <p>
	 * <b>It blocks, despite what we recorded.</b> `dev/proto/blanks/inbound/mgo2_cmd_4b46_c2s.ksy`
	 * says "the live trace proves the client does not wait for one" and warns against replying
	 * speculatively — true of the connect burst, where it fires unprompted and the player walks on.
	 * From the clan menu it stalls and fails with <em>Unable to update clan information
	 * (1933:FFFFFF60)</em>, observed 2026-07-27. One command, two contexts, and only one of them
	 * was ever tested. The sender {@code 0xD58510} advances flow state via
	 * {@code 0xD32E08(session, 98, 1)} either way, so the difference is in what the screen does
	 * next, not in the request.
	 */
	public static final int CLAN_INFO = 0x4b46;

	public static final int CLAN_INFO_RESULT = 0x4b47;

	/** Clan name field: 16 bytes on the wire; the client appends its own NUL at {@code +6820}. */
	private static final int CLAN_NAME_LENGTH = 16;

	/**
	 * {@code s4 result}, {@code u4 id}, {@code u1 state}, {@code u2 privileges}, {@code u1 emblem},
	 * {@code 16} name — 28 bytes, in the parser's read order at {@code 0xD5835C}, which is not the
	 * struct order (the u2 is read before the second u1 although it lands higher).
	 */
	private static final int RESULT_SIZE = 28;

	// ---------------------------------------------------------------------------------------------
	// The rest of the family. Every id below is answered in the shape its parser demands so no clan
	// screen can stall; where the reply carries data we do not understand, it carries zeros rather
	// than invented values. Sizes come from the parsers in dev/proto/blanks/outbound.
	// ---------------------------------------------------------------------------------------------

	/** Requests whose reply is a bare {@code u32} result. */
	private static final int[][] RESULT_ONLY = {
		{ 0x4b04, 0x4b05 },   // no payload
		{ 0x4b30, 0x4b31 },
		{ 0x4b32, 0x4b33 },
		{ 0x4b36, 0x4b37 },
		{ 0x4b50, 0x4b51 },   // 769-byte bulk block write
		{ 0x4b60, 0x4b61 },
		{ 0x4b62, 0x4b63 },
	};

	/** {@code {u32 result, byte[768]}}, the block opaque to the parser. */
	private static final int[][] BLOCK_768 = {
		{ 0x4b48, 0x4b49 },
		{ 0x4b4a, 0x4b4b },
		{ 0x4b4c, 0x4b4d },
	};

	/** Start/items/end triples. Items are never sent: the record layouts are not understood. */
	private static final int[][] LIST_TRIPLES = {
		{ 0x4b90, 0x4b91, 0x4b93 },   // 44-byte records, request names a player
	};

	/**
	 * The clan list, with paging: {@code {u8 kind, s32 amount, u8}} ({@code 0xD58164}). {@code kind}
	 * selects the arm — 1 steps back 100, 2 forward 100, 4 is absolute, 0 and 3 are the first page —
	 * and the client's own array holds 100 entries ({@code cmpwi r4,99} at {@code 0xD561E4}), so 100
	 * is the page size. The ksy read this as a "points or funds adjust"; the ±100 step is paging.
	 */
	public static final int CLAN_LIST = 0x4b10;

	/**
	 * List header, three words, and it raises <b>two</b> completion events ({@code 0xD558B4} and
	 * {@code 0xD558D4}) so two UI waiters key off it. The two words after the result are
	 * [UNKNOWN]; total-and-offset is the obvious reading and is what is sent, but the entries are
	 * size-driven so the client counts them itself either way.
	 */
	private static final int CLAN_LIST_HEADER = 0x4b11;

	/** Entries, 48 bytes each, size-driven with no count ({@code 0xD5CEB0} at {@code 0xD560BC}). */
	private static final int CLAN_LIST_ENTRIES = 0x4b12;

	private static final int CLAN_LIST_END = 0x4b13;

	private static final int CLAN_LIST_PAGE = 100;

	/**
	 * Apply to join, payload the clan id. The client will not even send this unless its session clan
	 * record holds a non-zero id — it returns {@code -24} without transmitting — which is why this
	 * only started arriving once {@code 0x4b81} carried a real {@code subject_id}.
	 * <p>
	 * After sending, the client writes the id into its own record with <b>status 0, pending</b>
	 * ({@code 0xD58714}), leaving 1 and 2 to come from the server. So the application is a real
	 * state on both sides, and we store it as one.
	 */
	public static final int APPLY_TO_JOIN = 0x4b42;

	private static final int APPLY_TO_JOIN_RESULT = 0x4b43;

	/** The applicant list, payload the clan id: {@code 0x4b75} records of 93 bytes. */
	public static final int APPLICANTS = 0x4b73;

	private static final int APPLICANTS_START = 0x4b74;

	private static final int APPLICANTS_ENTRIES = 0x4b75;

	private static final int APPLICANTS_END = 0x4b76;

	/** {@code u32 id, text[64], name[16], u8, s32, u32} — 93 bytes. */
	private static final int APPLICANT_RECORD_SIZE = 93;

	private static final int APPLICANT_TEXT_LENGTH = 64;

	/**
	 * An action naming a player: {@code {u8, u8, name[16]}}. The two selector bytes are [UNKNOWN] —
	 * they are logged on every call so the codes can be read off real use rather than guessed.
	 */
	public static final int MEMBER_ACTION = 0x4b90;

	private static final int MEMBER_ACTION_START = 0x4b91;

	private static final int MEMBER_ACTION_END = 0x4b93;

	/** {@code u32 id, name[16], u32, name[16], u8 x4, u32} — 48 bytes. */
	private static final int CLAN_LIST_RECORD_SIZE = 48;

	/** {@code 0x4b70} -> the per-mode stat grid, {@code 4 + 4 + 8*18*4} = 584 bytes. */
	private static final int CLAN_STATS = 0x4b70;

	private static final int CLAN_STATS_RESULT = 0x4b71;

	private static final int CLAN_STATS_SIZE = 584;

	/**
	 * The page selector in {@code 0x4b71}: <b>must be 2 or 3</b>. Any other value fails the whole
	 * packet with {@code -71} and discards the grid ({@code 0xD599C8}) — which is why a zero here
	 * rendered as "no records" rather than as zeroed stats. Both pages are sent, as {@code 0x4105}
	 * does for its cumulative/weekly pair; page 2 additionally zeroes all four page slots on receipt,
	 * so it goes first.
	 */
	private static final int[] STAT_PAGES = { 2, 3 };

	/**
	 * The clan privilege mask, wire {@code u16}. <b>Zero.</b>
	 * <p>
	 * Granting a leader all sixteen bits was tried on 2026-07-27 and <b>reverted the same minute</b>.
	 * It did not make Apply Emblem send anything, so the mask is not that gate; and it put a "!"
	 * badge on the clan and sent the client into a hard poll loop — {@code 0x4b46} every ~73 ms
	 * without pause — because at least one bit means "something is pending" and nothing we serve
	 * ever satisfies it. The whole value is OR-ed into a UI flags word at {@code 0xAB0118}, so a
	 * blanket grant lights up states the server has no way to clear.
	 * <p>
	 * The lesson is narrower than "don't set the mask": <b>do not turn on unknown bits in bulk.</b>
	 * When a bit is wanted, set that bit alone and watch for a poll loop.
	 */
	private static final int LEADER_PRIVILEGES = 0;

	/** {@code 0x4b80} -> a 217-byte partial profile update, request slot 113. */
	private static final int CLAN_PROFILE_PART = 0x4b80;

	private static final int CLAN_PROFILE_PART_RESULT = 0x4b81;

	private static final int CLAN_PROFILE_PART_SIZE = 217;

	/**
	 * The 128-byte text write. [INFERRED] it edits the clan description: it is the only 128-byte
	 * text field in the subsystem, and both {@code 0x4b00}'s description and {@code 0x4b21}'s
	 * {@code text_67a} live at struct offset {@code 0x67A}.
	 * <p>
	 * [CONFIRMED 2026-07-27] Setting <b>Clan Comment</b> to "bench" sent exactly this, 128 bytes,
	 * and setting <b>Clan Notice</b> to "watching you" sent {@code 0x4b66}, 512 bytes. So the two
	 * text writes are the two text fields, in the sizes their struct offsets predicted — and that
	 * also identifies the 512-byte blob at {@code T+0x700} in the profile block, which the spec had
	 * down as an unknown "long text block or packed table".
	 */
	private static final int SET_DESCRIPTION = 0x4b64;

	private static final int SET_DESCRIPTION_RESULT = 0x4b65;

	/** The clan notice: 512 bytes, the {@code T+0x700} blob. See {@link #SET_DESCRIPTION}. */
	private static final int SET_NOTICE = 0x4b66;

	private static final int SET_NOTICE_RESULT = 0x4b67;

	private static final int NOTICE_LENGTH = 512;

	private final ClanService clanService;

	public ClanGameController(ClanService clanService) {
		this.clanService = clanService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CLAN_INFO, this::clanInfo);
		handlers.put(CREATE_CLAN, this::createClan);
		handlers.put(CLAN_PROFILE, this::clanProfile);
		handlers.put(CLAN_MEMBERS, this::clanMembers);

		for (var pair : RESULT_ONLY) {
			handlers.put(pair[0], ctx -> writeResult(ctx, pair[1]));
		}
		for (var pair : BLOCK_768) {
			handlers.put(pair[0], ctx -> writeBlock(ctx, pair[1]));
		}
		for (var triple : LIST_TRIPLES) {
			handlers.put(triple[0], ctx -> {
				writeResult(ctx, triple[1]);
				writeResult(ctx, triple[2]);
			});
		}
		handlers.put(CLAN_LIST, this::clanList);
		handlers.put(APPLY_TO_JOIN, this::applyToJoin);
		handlers.put(APPLICANTS, this::applicants);
		handlers.put(MEMBER_ACTION, this::memberAction);
		handlers.put(WITHDRAW, this::withdraw);
		handlers.put(CLAN_STATS, ctx -> {
			for (var page : STAT_PAGES) {
				var buffer = ctx.buffer(CLAN_STATS_SIZE);
				buffer.writeInt(GameError.NONE.result()).writeInt(page)
					.writeZero(CLAN_STATS_SIZE - 2 * Integer.BYTES);
				ctx.write(new GamePacket(CLAN_STATS_RESULT, buffer));
			}
		});
		handlers.put(CLAN_PROFILE_PART, this::viewedClanInfo);
		handlers.put(SET_DESCRIPTION, this::setDescription);
		handlers.put(SET_NOTICE, this::setNotice);
	}

	/** Stores the clan's description. See {@link #SET_DESCRIPTION} for why this is the description. */
	private void setDescription(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		if (charaId != null && payload.readableBytes() >= DESCRIPTION_LENGTH) {
			var description = readNulTerminated(payload, DESCRIPTION_LENGTH);
			var membership = clanService.membershipOf(charaId);
			if (membership.state() == ClanService.STATE_LEADER) {
				clanService.setDescription(membership.id(), description);
				logger.info("Clan {} description set by character {}.", membership.id(), charaId);
			} else {
				logger.info("Character {} tried to set a clan description without leading one.",
					charaId);
			}
		}
		writeResult(ctx, SET_DESCRIPTION_RESULT);
	}

	/** Stores the clan's notice, the 512-byte text. Leader only, like the description. */
	private void setNotice(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		if (charaId != null && payload.readableBytes() >= NOTICE_LENGTH) {
			var notice = readNulTerminated(payload, NOTICE_LENGTH);
			var membership = clanService.membershipOf(charaId);
			if (membership.state() == ClanService.STATE_LEADER) {
				clanService.setNotice(membership.id(), notice);
				logger.info("Clan {} notice set by character {}.", membership.id(), charaId);
			}
		}
		writeResult(ctx, SET_NOTICE_RESULT);
	}

	/**
	 * {@code {u32 result, byte[768]}}.
	 * <p>
	 * [EXPERIMENT 2026-07-27] The block is filled with the names of the clan's <b>pending
	 * applicants</b>, 16 bytes each, when the caller leads that clan; zeros otherwise.
	 * <p>
	 * The reasoning: the leader's client has never sent any applicant-list command, so it does not
	 * believe there is anything to approve, and something must tell it. This block is 768 bytes —
	 * exactly {@value #APPLICANT_NAME_SLOTS} x 16 — the parser never inspects it, and the client
	 * NUL-terminates at +768, which the spec notes means "a C string or a table of them". A table of
	 * 16-byte names is what an applicant list would look like. If an approve option appears, that is
	 * confirmed; if nothing changes, the block is something else and this reverts to zeros.
	 */
	private void writeBlock(GameControllerContext ctx, int command) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var membership = charaId == null ? ClanService.Membership.NONE
			: clanService.membershipOf(charaId);

		var buffer = ctx.buffer(Integer.BYTES + CLAN_DATA_BLOCK);
		buffer.writeInt(GameError.NONE.result());

		var written = 0;
		if (membership.state() == ClanService.STATE_LEADER) {
			for (var applicant : clanService.applicantsFor(membership.id())) {
				if (written == APPLICANT_NAME_SLOTS) {
					break;
				}
				BufferUtil.writeString(buffer, applicant.name(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				written++;
			}
			if (written > 0) {
				logger.info("Clan {}: reporting {} pending applicant(s) in the {} block.",
					membership.id(), written, Integer.toHexString(command));
			}
		}
		buffer.writeZero(CLAN_DATA_BLOCK - written * CLAN_NAME_LENGTH);

		ctx.write(new GamePacket(command, buffer));
	}

	/** A fixed-size reply whose body is not understood: result 0 then zeros to the parser's length. */
	private void writeZeroPadded(GameControllerContext ctx, int command, int size) {
		var buffer = ctx.buffer(size);
		buffer.writeInt(GameError.NONE.result()).writeZero(size - Integer.BYTES);
		ctx.write(new GamePacket(command, buffer));
	}


	/**
	 * The member list, as an empty triple for now.
	 * <p>
	 * The record layout is known to be 68 wire bytes of {@code {u32, name[16], u8, ...}} but whose
	 * name and what the rest means are not, so no rows are sent rather than rows full of guesses —
	 * an empty list is well-formed and the screen will say so honestly. The clan currently has one
	 * member, its founder, so this is the next thing to fill in once a record can be built from
	 * evidence.
	 */
	private void clanMembers(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;
		var members = clanId == 0L ? java.util.List.<ClanService.Member>of()
			: clanService.membersOf(clanId);

		writeResult(ctx, CLAN_MEMBERS_START);
		if (!members.isEmpty()) {
			// Size-driven, no leading count: the client reads records until the payload runs out.
			var buffer = ctx.buffer(members.size() * MEMBER_RECORD_SIZE);
			for (var member : members) {
				var start = buffer.writerIndex();
				buffer.writeInt((int) member.charaId());                        // +0x00
				BufferUtil.writeString(buffer, member.name(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);                                          // +0x04
				buffer.writeByte(member.state());                               // +0x15
				buffer.writeZero(MEMBER_RECORD_SIZE - (buffer.writerIndex() - start));
			}
			ctx.write(new GamePacket(CLAN_MEMBERS_ENTRIES, buffer));
		}
		writeResult(ctx, CLAN_MEMBERS_END);
	}

	/**
	 * The clan list. Header, then one entry per clan, then the end packet.
	 * <p>
	 * The request's {@code amount} is the absolute offset for kind 4 and a already-stepped value for
	 * the paging arms, so it is used directly; negatives clamp to the first page.
	 */
	private void clanList(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var start = 1;
		if (payload.readableBytes() >= 6) {
			payload.readByte();               // kind: which arm the client chose
			start = payload.readInt();        // signed — the only signed serializer in the family
			payload.readByte();
		}

		// The amount is a 1-BASED ENTRY INDEX, not a page number: after being shown one entry the
		// client asked for 101 (kind 2 = value + 100), which is "start at the 101st clan".
		//
		// The client pages optimistically — it asks for the next 100 without knowing whether they
		// exist — so the request must be CLAMPED to the real range rather than honoured literally.
		// Answering "here are 0 clans, starting at 101, out of a total of 1" is self-contradictory,
		// and the screen renders it as "2 out of 1" and then corrupts the list on the next scroll.
		// Clamping to the last populated page makes paging past the end a no-op instead.
		var total = clanService.countClans();
		var lastPageStart = total == 0 ? 0 : ((total - 1) / CLAN_LIST_PAGE) * CLAN_LIST_PAGE;
		var offset = Math.min(Math.max(0, start - 1), lastPageStart);
		var clans = clanService.listClans(offset, CLAN_LIST_PAGE);

		// The two words are {offset, total}, IN THAT ORDER — they were swapped, which is the whole
		// "2 out of 1" bug. The client stores them at block+0x08 and block+0x0C and renders a
		// "%d/%d" page indicator (0xE11518, drawn at 0xAC11A4 and 0xAC2958) as:
		//     left  = A <= 0 ? 1 : (A - 1) / 100 + 2
		//     right = (B - 1) / 100 + 1
		// Sending A = 1 put it in the 1..100 bucket and rendered page 2 — of 1. The record count
		// never enters this text at all, which is why changing the rows changed nothing.
		//
		// Corroborated by the sibling clan-search triple, which fills the same two slots itself:
		// 0x4b93 sets block+0x08 = 0 and block+0x0C = the record count (0xD54D64, 0xD54D78).
		var header = ctx.buffer(3 * Integer.BYTES);
		header.writeInt(GameError.NONE.result())
			.writeInt(offset)                     // 0-based row offset of this page
			.writeInt(total);                     // every clan, across all pages
		ctx.write(new GamePacket(CLAN_LIST_HEADER, header));

		if (!clans.isEmpty()) {
			var buffer = ctx.buffer(clans.size() * CLAN_LIST_RECORD_SIZE);
			for (var clan : clans) {
				var recordStart = buffer.writerIndex();
				buffer.writeInt((int) clan.id());
				BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				buffer.writeInt(clanService.memberCount(clan.id()));            // +0x14
				// The second 16-byte name: the leader is the only other name a list row could want,
				// and it renders correctly, so this one is settled.
				BufferUtil.writeString(buffer, clan.leaderName(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				buffer.writeZero(4);                                            // +0x28..0x2b
				buffer.writeInt((int) clan.createdAt());                        // +0x2c
				buffer.writeZero(CLAN_LIST_RECORD_SIZE - (buffer.writerIndex() - recordStart));
			}
			ctx.write(new GamePacket(CLAN_LIST_ENTRIES, buffer));
		}

		writeResult(ctx, CLAN_LIST_END);
	}

	/**
	 * Clan Info for a clan picked out of the list — including one the player is not in.
	 * <p>
	 * This is the counterpart to {@code 0x4b20}, which cannot serve a non-member: that reply's id is
	 * cross-checked against the client's own clan id and the packet is dropped on a mismatch. This
	 * one's {@code subject_id} is explicitly <b>not</b> cross-checked, which is what makes it the
	 * "look at someone else's clan" path.
	 * <p>
	 * It also unblocks joining. {@code 0x4b42}'s sender refuses to transmit unless the session clan
	 * record at {@code session_ctx+0x1AA0} holds a non-zero id, returning {@code -24}
	 * ({@code FFFFFFE8}) without sending anything — which is exactly the error Apply produced while
	 * this reply was 217 zero bytes.
	 */
	private void viewedClanInfo(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;
		var clan = clanService.clanById(clanId).orElse(null);
		if (clan == null) {
			ctx.write(CLAN_PROFILE_PART_RESULT, GameError.GENERAL);
			return;
		}

		var buffer = ctx.buffer(CLAN_PROFILE_PART_SIZE);
		var start = buffer.writerIndex();
		buffer.writeInt(GameError.NONE.result());
		buffer.writeInt((int) clan.id());                                     // T+0x00
		BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);                                                // T+0x04
		// T+0x18 is the founding date and T+0x58 the member count, NOT the other way round: with
		// them swapped the info screen showed 1785129141 members — the epoch seconds, verbatim.
		buffer.writeInt((int) clan.createdAt());                              // T+0x18
		BufferUtil.writeString(buffer, clan.leaderName(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);                                                // T+0x1c
		buffer.writeZero(1);                                                  // T+0x378
		BufferUtil.writeString(buffer, clan.description(), StandardCharsets.ISO_8859_1,
			DESCRIPTION_LENGTH);                                              // T+0x67A
		buffer.writeZero(4);                                                  // T+0x1B34
		buffer.writeInt(clanService.memberCount(clan.id()));                  // T+0x58
		buffer.writeZero(CLAN_PROFILE_PART_SIZE - (buffer.writerIndex() - start));

		ctx.write(new GamePacket(CLAN_PROFILE_PART_RESULT, buffer));
	}

	/**
	 * Cancel Join / leave, no payload ({@code 0x4b40}). Identified live 2026-07-27: it is what the
	 * pending-applicant screen's "Cancel Join" button sends, and answering it with a bare result
	 * left the application in place.
	 */
	public static final int WITHDRAW = 0x4b40;

	private static final int WITHDRAW_RESULT = 0x4b41;

	/** Withdraws a pending application, or leaves the clan. */
	private void withdraw(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId != null && clanService.withdraw(charaId)) {
			logger.info("Character {} withdrew from their clan.", charaId);
		}
		writeResult(ctx, WITHDRAW_RESULT);
	}

	/** Records the application and acknowledges it. */
	private void applyToJoin(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;

		if (charaId != null && clanId != 0 && clanService.clanById(clanId).isPresent()) {
			clanService.apply(charaId, clanId);
			logger.info("Character {} applied to join clan {}.", charaId, clanId);
			writeResult(ctx, APPLY_TO_JOIN_RESULT);
		} else {
			ctx.write(APPLY_TO_JOIN_RESULT, GameError.GENERAL);
		}
	}

	/** The pending applicants a leader has to approve. */
	private void applicants(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;
		var pending = clanId == 0L ? java.util.List.<ClanService.Member>of()
			: clanService.applicantsFor(clanId);

		writeResult(ctx, APPLICANTS_START);
		if (!pending.isEmpty()) {
			var buffer = ctx.buffer(pending.size() * APPLICANT_RECORD_SIZE);
			for (var applicant : pending) {
				var recordStart = buffer.writerIndex();
				buffer.writeInt((int) applicant.charaId());
				// The 64-byte text: applications carry no message on the wire (0x4b42 sends only an
				// id), so there is nothing to put here until we find what writes it.
				buffer.writeZero(APPLICANT_TEXT_LENGTH);
				BufferUtil.writeString(buffer, applicant.name(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				buffer.writeZero(APPLICANT_RECORD_SIZE - (buffer.writerIndex() - recordStart));
			}
			ctx.write(new GamePacket(APPLICANTS_ENTRIES, buffer));
		}
		writeResult(ctx, APPLICANTS_END);
	}

	/**
	 * A leader acting on a named player — approve, reject, promote or kick.
	 * <p>
	 * The two selector bytes are not understood, so this does the one thing that is unambiguous when
	 * the named player is a <b>pending applicant</b> of the caller's clan: approve them. The bytes
	 * are logged on every call, so the real codes can be read off use and the other actions
	 * implemented from evidence instead of guesswork. Anything else is acknowledged and ignored.
	 */
	private void memberAction(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();

		if (charaId != null && payload.readableBytes() >= 18) {
			var selector = payload.readUnsignedByte();
			var argument = payload.readUnsignedByte();
			var name = readNulTerminated(payload, CLAN_NAME_LENGTH);
			var membership = clanService.membershipOf(charaId);

			logger.info("0x4b90 from character {}: selector 0x{}, argument 0x{}, name '{}'.",
				charaId, Integer.toHexString(selector), Integer.toHexString(argument), name);

			if (membership.state() == ClanService.STATE_LEADER
					&& clanService.approveByName(membership.id(), name)) {
				logger.info("Clan {}: '{}' approved by character {}.", membership.id(), name, charaId);
			}
		}

		writeResult(ctx, MEMBER_ACTION_START);
		writeResult(ctx, MEMBER_ACTION_END);
	}

	/** Everything a leader may do, nothing for anyone else. See {@link #LEADER_PRIVILEGES}. */
	private static int privileges(int state) {
		return state == ClanService.STATE_LEADER ? LEADER_PRIVILEGES : 0;
	}

	/** A start/end packet: one u32 result code. Both must be 0, or the screen shows the error. */
	private void writeResult(GameControllerContext ctx, int command) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(command, buffer));
	}


	/**
	 * Answers Clan Affiliation with the requested clan's profile.
	 * <p>
	 * The id is echoed because the client validates it against its own copy; a clan it does not know
	 * about, or an id we cannot find, gets a 4-byte failure rather than a zero-filled block, so the
	 * screen reports an error instead of rendering a nameless clan.
	 */
	private void clanProfile(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < Integer.BYTES) {
			ctx.write(CLAN_PROFILE_RESULT, GameError.GENERAL);
			return;
		}

		var clanId = payload.readInt() & 0xFFFFFFFFL;
		var clan = clanService.clanById(clanId).orElse(null);
		if (clan == null) {
			logger.warn("Clan profile requested for unknown clan {}.", clanId);
			ctx.write(CLAN_PROFILE_RESULT, GameError.GENERAL);
			return;
		}

		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var state = charaId == null ? ClanService.STATE_NONE
			: clanService.membershipOf(charaId).state();

		var buffer = ctx.buffer(PROFILE_SIZE);
		var start = buffer.writerIndex();
		buffer.writeInt(GameError.NONE.result());
		buffer.writeInt((int) clan.id());                                     // T+0x00
		BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);                                                // T+0x04
		buffer.writeByte(state);                                              // T+0x15
		buffer.writeZero(4);                                                  // T+0x18
		BufferUtil.writeString(buffer, clan.leaderName(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);                                                // T+0x1c
		buffer.writeZero(4 + 16);                                             // T+0x30, T+0x34
		buffer.writeZero(4);                                                  // T+0x48
		buffer.writeInt(clanService.memberCount(clan.id()));                  // T+0x58  members
		buffer.writeZero(4 + 4 + 4 + 4 + 4);                                  // T+0x5c .. T+0x6c
		buffer.writeZero(4 + 1 + 1 + 1 + 1);                                  // flags, T+0x74..0x378
		BufferUtil.writeString(buffer, clan.description(), StandardCharsets.ISO_8859_1,
			DESCRIPTION_LENGTH);                                              // T+0x67A
		buffer.writeZero(4);                                                  // T+0x6FC
		BufferUtil.writeString(buffer, clan.notice(), StandardCharsets.ISO_8859_1,
			NOTICE_LENGTH);                                                   // T+0x700, the notice
		// T+0x904 is the FOUNDING DATE, Unix seconds — identified 2026-07-27 by sending every
		// candidate slot the date offset by a different number of days and reading which one the
		// screen displayed. T+0x18 and T+0x48 had each been tried and rendered as 1969-12-31.
		buffer.writeInt((int) clan.createdAt());                              // T+0x904
		buffer.writeZero(16);                                                 // T+0x908 name_d
		buffer.writeZero(4 + 4 + 4);                                          // T+0x1B2C .. T+0x1B34

		assert buffer.writerIndex() - start == PROFILE_SIZE
			: "Clan profile must be " + PROFILE_SIZE + " bytes";

		ctx.write(new GamePacket(CLAN_PROFILE_RESULT, buffer));
	}

	/** Creates the clan and makes the sender its leader, which is what the client assumes on 0. */
	private void createClan(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId == null) {
			ctx.write(CREATE_CLAN_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < ClanService.NAME_MAX_LENGTH + ClanService.DESCRIPTION_MAX_LENGTH) {
			logger.warn("Create clan: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(CREATE_CLAN_RESULT, GameError.GENERAL);
			return;
		}

		var name = readNulTerminated(payload, ClanService.NAME_MAX_LENGTH);
		var description = readNulTerminated(payload, ClanService.DESCRIPTION_MAX_LENGTH);
		if (name.length() < ClanService.NAME_MIN_LENGTH) {
			// The client checks this itself before sending, so reaching here means a modified or
			// replayed packet rather than a player mistake.
			logger.warn("Create clan: name '{}' is shorter than the client's own minimum.", name);
			ctx.write(CREATE_CLAN_RESULT, GameError.GENERAL);
			return;
		}

		var clanId = clanService.createClan(charaId, name, description);
		if (clanId.isEmpty()) {
			logger.info("Character {} tried to create clan '{}': name already taken.", charaId, name);
			ctx.write(CREATE_CLAN_RESULT, GameError.GENERAL);
			return;
		}

		logger.info("Character {} created clan {} '{}'.", charaId, clanId.get(), name);
		var buffer = ctx.buffer(2 * Integer.BYTES);
		buffer.writeInt(GameError.NONE.result()).writeInt(clanId.get().intValue());
		ctx.write(new GamePacket(CREATE_CLAN_RESULT, buffer));
	}

	/**
	 * Answers the probe with the character's clan record, or state 99 when they have none.
	 * <p>
	 * Always {@code result = 0}, never an error: a nonzero result ends the payload after four bytes
	 * ({@code 0xD5835C} reads no further), which would leave the client's existing record in place
	 * rather than correcting it. "No clan" is a record, not a failure.
	 */
	private void clanInfo(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var membership = charaId == null ? ClanService.Membership.NONE
			: clanService.membershipOf(charaId);

		var buffer = ctx.buffer(RESULT_SIZE);
		buffer.writeInt(GameError.NONE.result())
			.writeInt((int) membership.id())
			.writeByte(membership.state())
			.writeShort(privileges(membership.state()))
			.writeByte(0);   // emblem: 3 when the clan has one, and none do
		BufferUtil.writeString(buffer, membership.name(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);

		ctx.write(new GamePacket(CLAN_INFO_RESULT, buffer));
	}

	/** Reads a fixed-width field the client pads with NULs. */
	private static String readNulTerminated(ByteBuf buffer, int length) {
		var bytes = new byte[Math.min(length, buffer.readableBytes())];
		buffer.readBytes(bytes);

		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}

		return new String(bytes, 0, end, StandardCharsets.ISO_8859_1);
	}
}
