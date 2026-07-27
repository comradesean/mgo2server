package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.service.CharacterService;
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

	/**
	 * Cancel Join / leave, no payload ({@code 0x4b40}). Identified live 2026-07-27: it is what the
	 * pending-applicant screen's "Cancel Join" button sends, and answering it with a bare result
	 * left the application in place.
	 */
	public static final int WITHDRAW = 0x4b40;

	private static final int WITHDRAW_RESULT = 0x4b41;

	/**
	 * Clan search: {@code {u8 exact_only, u8 ignore_case, name[16]}} — the two bytes are the
	 * screen's own toggles, "Partial and Exact Matches" vs "Exact Matches Only" and "Case Sensitive"
	 * vs "Case Insensitive".
	 * <p>
	 * Note the polarity of the second byte: <b>1 ignores case</b>. It was named
	 * {@code case_sensitive} here and read the right way round in {@link #clanSearch} anyway, so the
	 * name was harmless — but the identical byte on the player-search screen had a test asserting
	 * the inverted meaning on no authority but the field's own name. A field name is not evidence.
	 * <p>
	 * This opcode was also registered twice, as this and as a "member action" that read the same two
	 * bytes as {@code {selector, argument}}. Search is what the client sends; the member-action
	 * reading was a guess made before the search screen was tested, and because it registered first
	 * it was silently overwritten by this one and never ran.
	 */
	public static final int CLAN_SEARCH = 0x4b90;

	private static final int CLAN_SEARCH_START = 0x4b91;

	private static final int CLAN_SEARCH_ENTRIES = 0x4b92;

	private static final int CLAN_SEARCH_END = 0x4b93;

	/**
	 * One search result: {@code u32 id, name[16], u32 leader id, name[16], u32} — <b>44 bytes</b>.
	 * <p>
	 * Note this differs from the 48-byte record another server writes, which adds a flag byte and
	 * three pad bytes before the trailing u32. Our parser reads 44 and the id is the ELF's, so 44 it
	 * is; the two builds differ.
	 */
	private static final int SEARCH_RECORD_SIZE = 44;

	/** Disband the clan: no payload, leader only. */
	public static final int DISBAND = 0x4b04;

	private static final int DISBAND_RESULT = 0x4b05;

	/** Banish a member: {@code u32 target character id}. Leader only. */
	public static final int BANISH = 0x4b36;

	private static final int BANISH_RESULT = 0x4b37;

	/** Hand leadership to another member: {@code u32 target character id}. */
	public static final int TRANSFER_LEADERSHIP = 0x4b60;

	private static final int TRANSFER_LEADERSHIP_RESULT = 0x4b61;

	/** Assign emblem-editing rights: {@code u32 target character id}. */
	public static final int SET_EMBLEM_EDITOR = 0x4b62;

	private static final int SET_EMBLEM_EDITOR_RESULT = 0x4b63;

	/** Accept a join application: {@code u32 target character id}. Leader only. */
	public static final int ACCEPT_JOIN = 0x4b30;

	private static final int ACCEPT_JOIN_RESULT = 0x4b31;

	/** Decline a join application, same payload. */
	public static final int DECLINE_JOIN = 0x4b32;

	private static final int DECLINE_JOIN_RESULT = 0x4b33;

	/** The emblem display fetch: {@code u32 clan id} in, result + 768 bytes out. */
	public static final int CLAN_EMBLEM = 0x4b4a;

	private static final int CLAN_EMBLEM_RESULT = 0x4b4b;

	/** The upload mode that means "put this emblem on display" — the one the client commits. */
	private static final int EMBLEM_ON_DISPLAY = 3;

	/**
	 * Refusing an emblem re-display: {@code -1216}, which the client renders as
	 * <em>"A fixed amount of time must pass in order for the emblem to be updated."</em>
	 * <p>
	 * Found by dumping the client's error table at {@code 0x106D714} — 664 entries of
	 * {@code {u32 dialogId, i32 ordinal}} — and the dispatcher that feeds it
	 * ({@code 0xA7E410} for this op, {@code 0x885A08} raises the dialog, {@code 0xB8F988} resolves
	 * it, {@code 0x240708} fetches the string). The chain was verified against a case we already
	 * ship: {@code -260} on character creation resolves to "Desired PC name is already in use",
	 * which is exactly what the client shows.
	 * <p>
	 * Previously {@code -1202}, "Unable to update clan emblem" — true but vague. Other codes on this
	 * op: {@code -1215} "Use of the clan emblem is currently forbidden", {@code -1218} "You do not
	 * have emblem editing rights", {@code -1207} "Unable to locate designated clan".
	 * <p>
	 * <b>Caveat.</b> An earlier trace concluded only {@code -1207} and {@code -1202} reach a dialog
	 * and that every other value memsets the client's 768-byte emblem buffer. The later, deeper
	 * trace could not reproduce that: in this dispatcher every branch reaches a dialog and neither
	 * it nor the {@code 0x4b51} handler ({@code 0xD555D4}) contains a memset — so the wipe, if it
	 * happens, lives in the emblem screen's event-104 consumer, which nobody has located. If a
	 * refusal ever clears a work-in-progress emblem, revert this to {@code -1202}.
	 */
	private static final int EMBLEM_REFUSED = -1216;

	/**
	 * Refusing a clan creation on the requirements: {@code -1206} ->
	 * <em>"Conditions to create clan have not been met."</em> ({@code 0xA7E680}).
	 * <p>
	 * Neighbours on the same op, worth having when the checks they describe exist: {@code -1200} a
	 * clan by that name already exists, {@code -1230} banned from creating clans, {@code -1231}
	 * comment contains an invalid word, {@code -1233} clan name contains an invalid character,
	 * {@code -24} clan name is not long enough.
	 */
	private static final int CLAN_CONDITIONS_NOT_MET = -1206;

	/**
	 * Refusing a disband inside the cooldown: {@code -1205} ->
	 * <em>"A fixed amount of time must pass in order to disband the clan."</em> ({@code 0xA7E74C}).
	 * <p>
	 * This is the message the orphaned countdown strings (17312/17318) would have accompanied. The
	 * countdown itself is still unreachable — this says the same thing without the number.
	 */
	private static final int DISBAND_TOO_SOON = -1205;

	/**
	 * How long a clan must wait before putting another emblem on display.
	 * <p>
	 * <b>Operator policy, not protocol.</b> Emblem Edit warns about a spam filter and the client
	 * carries the countdown string ("You must wait another %d hours %d minutes", lobby 17247), but
	 * nothing client-side enforces it on this build: the emblem can be re-displayed immediately, and
	 * the one timestamp-shaped field the server sends that could have driven it, {@code 0x4b21}'s
	 * {@code T+0x48}, was tried and eliminated. So either the retail servers refused the upload
	 * themselves, or the countdown is fed by something not yet found.
	 * <p>
	 * The interval is a guess — the client computes its own from a constant we have not located.
	 * Tune with {@code MGO2SERVER_CLAN_EMBLEM_COOLDOWN_HOURS} in {@code server.env}; {@code 0}
	 * disables it. See {@link mgo2server.common.Policy}.
	 * <p>
	 * This defaulted to <b>sixty minutes</b> while the character-delete and clan-disband cooldowns
	 * defaulted to a week, for no reason beyond the order the three were written. It is a week now,
	 * like its siblings, and all three come from one place so they cannot drift apart again.
	 */
	private static final long EMBLEM_COOLDOWN_SECONDS =
		mgo2server.common.Policy.current().clanEmblemCooldown().toSeconds();

	/** The emblem upload: {@code u8 mode} then 768 bytes. */
	public static final int UPLOAD_EMBLEM = 0x4b50;

	private static final int UPLOAD_EMBLEM_RESULT = 0x4b51;

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

	/**
	 * What the client's date formatter takes as "no timestamp": any negative value. It prints
	 * {@code XXXX-XX-XX XX:XX:XX} rather than a date ({@code 0x884420} -> {@code 0x8844A0}).
	 */
	private static final int NO_TIMESTAMP = -1;

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
	//
	// There was a third table here, for requests answered with a bare success and nothing else. It
	// stopped the screens hanging, which was worth having, but it turned "unimplemented" into
	// "silently reports success" — banish, transfer leadership, disband and set-emblem-editor all
	// said they worked while doing nothing. Every one of them is implemented now and the table is
	// gone; do not reintroduce it. A command with no implementation should stall visibly, or return
	// an error, rather than lie.
	// ---------------------------------------------------------------------------------------------

	/** {@code {u32 result, byte[768]}}, the block opaque to the parser. */
	private static final int[][] BLOCK_768 = {
		{ 0x4b48, 0x4b49 },
		{ 0x4b4c, 0x4b4d },
	};

	/** Start/items/end triples. Items are never sent: the record layouts are not understood. */
	private static final int[][] LIST_TRIPLES = {
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

	/**
	 * Refusing an application inside the join cooldown.
	 * <p>
	 * <b>[ELF] The sentence we wanted cannot be shown, and the obvious guess was wrong.</b>
	 * <p>
	 * The client carries <em>"A fixed amount of time must pass in order to apply to join a
	 * clan.\nUnable to apply to join clan."</em> (dialogId 6458, string 24137). <b>No result code
	 * we can send will show it.</b> {@code li r3,6458} — the dialogId load every error path goes
	 * through — occurs nowhere in the binary, and the {@code 0x4b43} error block at
	 * {@code 0xA7E43C} is <em>total</em>, so every code lands on one of these five:
	 * <pre>
	 *   -1217 -> 6457  "This clan is already full."
	 *   -1201 -> 6459  "You are already a member of another clan."
	 *   -1207 -> 6461  "Unable to locate designated clan, or clan may be disbanded."
	 *   -160  -> 6453  "A network server error has occurred."
	 *   any other -> 6452  "Unable to apply to join clan."
	 * </pre>
	 * {@code -1217} was this constant's first value, picked by elimination on the theory that the
	 * other three had jobs and it did not. It has a job: the clan is full. Shipping it would have
	 * told a player on cooldown that the clan was at capacity — a confident, specific lie, which is
	 * the same failure the emblem refusal made three times before it was right.
	 * <p>
	 * So this deliberately takes the <b>default path</b>. "Unable to apply to join clan." is vague,
	 * but it is true, and vague-and-true beats specific-and-false. Four more dialogIds on this
	 * screen are absent from the result-code path the same way (6454, 6455, 6456, 6460), including
	 * the Block List one — so the generic refusal is the client's normal answer here, not a
	 * degraded one.
	 * <p>
	 * <b>[ELF] The elimination now holds by mechanism, not by absence.</b> It was first made on
	 * "{@code li r3,6458} occurs nowhere", which only covered the result-code path. The display
	 * path has since been inventoried end to end: every dialogId reaches the queue through one of
	 * <b>14 call sites</b> of {@code 0x7FA780}, and at every one of them the id is a
	 * <b>compile-time constant</b> — 167 direct {@code li}, 20 from a two-way {@code subfic}
	 * select, 9 set in the preceding block, and 2 memory loads whose only writers are themselves
	 * {@code li}. No dialogId in this binary is computed from data.
	 * <p>
	 * 6458 is installed only by the per-screen message-id constructor {@code 0x756F90} (with a dead
	 * identical twin at {@code 0x7550B0}, called from nowhere and absent from the OPD table), into
	 * field {@code 200(r31)} of a 384-byte object. Nothing reads that field into a raiser. The same
	 * mechanism accounts for 6454, 6455, 6456 and 6460 — all installed in that struct, none ever
	 * raised — which is the corroboration that makes this an explanation rather than a gap.
	 * <p>
	 * There is also no client-side pre-check to raise it: {@code 0xD585FC} refuses only with
	 * {@code -24} (name length and character class), {@code -36} (connectivity) and {@code -1201}
	 * (already in a clan). No time check exists on the apply path at all.
	 * <p>
	 * What would overturn it: a capture of a real server making this client print string 24137.
	 */
	private static final int APPLY_TOO_SOON = -1219;

	/** The applicant list, payload the clan id: {@code 0x4b75} records of 93 bytes. */
	public static final int APPLICANTS = 0x4b73;

	private static final int APPLICANTS_START = 0x4b74;

	private static final int APPLICANTS_ENTRIES = 0x4b75;

	private static final int APPLICANTS_END = 0x4b76;

	/** {@code u32 id, text[64], name[16], u8, s32, u32} — 93 bytes. */
	private static final int APPLICANT_RECORD_SIZE = 93;

	private static final int APPLICANT_TEXT_LENGTH = 64;

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
	private static final int STAT_PAGE = 2;

	/** The second half of the stats reply: {@code 0x4b72}, {@code 4 + 2 * 72 * 4} = 580 bytes. */
	private static final int CLAN_STAT_BLOCKS = 0x4b72;

	private static final int CLAN_STAT_BLOCKS_SIZE = 580;

	/**
	 * The clan privilege/notification word at {@code profile+6838}. <b>Bit 8 only, and only for a
	 * leader.</b>
	 *
	 * <p>[EXPERIMENT 2026-07-27] Emblem Edit offers no way to apply an emblem even though the commit
	 * gate is satisfied — {@code 0xAD409C} tests {@code ctx+788 & 4}, which is set purely from
	 * membership state 2, and we send that. So the missing piece is the menu row, not the
	 * permission, and the mask is what feeds the menu: {@code 0xACF188} and {@code 0xAD26A8} pass it
	 * verbatim to {@code 0xCFD0A0(ctx+876, 5, mask, 1)}, and {@code ctx+876} is the same widget queue
	 * whose last item selects the upload mode at {@code 0xAD4138}.
	 *
	 * <p><b>Why bit 8 specifically, and why this is safe when 0xFFFF was not.</b> The clan screen
	 * coroutine stalls on any bit it does not tolerate: {@code 0xAB0074} ands the word with
	 * {@code -1}, or with {@code -257} when the player is the leader ({@code 0xAB004C}), and returns
	 * without advancing its state machine if anything survives. {@code -257} is {@code ~0x0100}, so
	 * bit 8 is the one bit a leader may hold without the screen re-entering and re-sending
	 * {@code 0x4b46} forever — which is exactly what 0xFFFF caused. Every other bit still stalls,
	 * and a non-leader tolerates nothing, so this stays leader-only.
	 *
	 * <p><b>Answered 2026-07-27: bit 8 is NOT emblem-editing rights.</b> Set on its own for a leader
	 * it behaved exactly as the tolerance mask predicts — no stall and no poll loop, unlike 0xFFFF —
	 * but it produced only the saluting-soldier "!" badge and no new menu row anywhere, and emblem
	 * loading worked with or without it. So bit 8 is a pending-notification bit, the whole word is a
	 * notification mask the client drains to zero rather than a permission mask, and <b>no privilege
	 * bit gates applying an emblem</b>. Back to 0.
	 *
	 * <p>That also means the missing Apply row is not a permissions problem at all: the commit gate
	 * ({@code 0xAD409C}) reads membership state 2 and nothing else, and we already send it.
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

	private final CharacterService characterService;

	public ClanGameController(ClanService clanService, CharacterService characterService) {
		this.clanService = clanService;
		this.characterService = characterService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CLAN_INFO, this::clanInfo);
		handlers.put(CREATE_CLAN, this::createClan);
		handlers.put(CLAN_PROFILE, this::clanProfile);
		handlers.put(CLAN_MEMBERS, this::clanMembers);

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
		handlers.put(WITHDRAW, this::withdraw);
		handlers.put(DISBAND, this::disband);
		handlers.put(CLAN_SEARCH, this::clanSearch);
		handlers.put(CLAN_EMBLEM, this::clanEmblem);
		handlers.put(UPLOAD_EMBLEM, this::uploadEmblem);
		handlers.put(ACCEPT_JOIN, ctx -> judgeApplicant(ctx, true));
		handlers.put(DECLINE_JOIN, ctx -> judgeApplicant(ctx, false));
		handlers.put(BANISH, ctx -> leaderAction(ctx, BANISH_RESULT, "banish",
			(clan, target) -> clanService.banish(clan, target)));
		handlers.put(TRANSFER_LEADERSHIP, ctx -> leaderAction(ctx, TRANSFER_LEADERSHIP_RESULT,
			"transfer leadership to", (clan, target) -> false));
		handlers.put(SET_EMBLEM_EDITOR, ctx -> leaderAction(ctx, SET_EMBLEM_EDITOR_RESULT,
			"grant emblem-editing rights to", (clan, target) -> {
				clanService.setEmblemEditor(clan, target);
				return true;
			}));
		handlers.put(CLAN_STATS, ctx -> {
			// ONE 0x4b71, then 0x4b72 — not two pages. Sending 0x4b71 twice completed the request
			// slot on the first reply and the second arrived unexpected, which is the
			// "unable to acquire clan information (1931:FFFFFF60)" stall on Clan Affiliation.
			var grid = ctx.buffer(CLAN_STATS_SIZE);
			grid.writeInt(GameError.NONE.result()).writeInt(STAT_PAGE)
				.writeZero(CLAN_STATS_SIZE - 2 * Integer.BYTES);
			ctx.write(new GamePacket(CLAN_STATS_RESULT, grid));

			var blocks = ctx.buffer(CLAN_STAT_BLOCKS_SIZE);
			blocks.writeInt(GameError.NONE.result())
				.writeZero(CLAN_STAT_BLOCKS_SIZE - Integer.BYTES);
			ctx.write(new GamePacket(CLAN_STAT_BLOCKS, blocks));
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
				clanService.setNotice(membership.id(), notice, charaId);
				logger.info("Clan {} notice set by character {}.", membership.id(), charaId);
			}
		}
		writeResult(ctx, SET_NOTICE_RESULT);
	}

	/**
	 * {@code {u32 result, byte[768]}} — the <b>clan emblem</b>.
	 * <p>
	 * {@code 0x4b49}'s block is copied straight into {@code profile+6873} (parser {@code 0xD56F24},
	 * {@code addi r0,r27,57} off the clan record at {@code 0xD56EDC}), and {@code 0x4b4b}'s into the
	 * profile struct for display. Neither parser looks inside: both NUL-terminate at +768 into a
	 * 769-byte buffer, so the 768 bytes are opaque and are stored and returned verbatim.
	 * <p>
	 * This was briefly filled with pending applicant names on the theory that 768 = 48 x 16 made it
	 * a name table. It is not — that was writing text into the client's emblem buffer.
	 */
	private void writeBlock(GameControllerContext ctx, int command) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var membership = charaId == null ? ClanService.Membership.NONE
			: clanService.membershipOf(charaId);
		writeEmblem(ctx, command, membership.id());
	}

	/** {@code 0x4b4a}: the display fetch, which names the clan whose emblem is wanted. */
	private void clanEmblem(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;
		writeEmblem(ctx, CLAN_EMBLEM_RESULT, clanId);
	}

	/**
	 * The emblem flag for a clan: {@link ClanService#EMBLEM_ON_DISPLAY} or 0, never the raw stored
	 * mode.
	 * <p>
	 * Three commands write this byte and all three must agree, so the clamp lives in one place.
	 * {@code emblemFlagOf} returns the mode the emblem was uploaded with, and 2 and 4 mean stored
	 * but not shown — echoing one of those would put our record out of step with the client's own,
	 * which only ever holds 3.
	 */
	private int onDisplay(long clanId) {
		return clanService.emblemFlagOf(clanId) == ClanService.EMBLEM_ON_DISPLAY
			? ClanService.EMBLEM_ON_DISPLAY : 0;
	}

	private void writeEmblem(GameControllerContext ctx, int command, long clanId) {
		var emblem = clanId == 0L ? java.util.Optional.<byte[]>empty()
			: clanService.emblemOf(clanId);

		var buffer = ctx.buffer(Integer.BYTES + CLAN_DATA_BLOCK);
		buffer.writeInt(GameError.NONE.result());
		emblem.ifPresentOrElse(
			bytes -> buffer.writeBytes(bytes, 0, Math.min(bytes.length, CLAN_DATA_BLOCK)),
			() -> buffer.writeZero(CLAN_DATA_BLOCK));
		if (buffer.writerIndex() < Integer.BYTES + CLAN_DATA_BLOCK) {
			buffer.writeZero(Integer.BYTES + CLAN_DATA_BLOCK - buffer.writerIndex());
		}
		ctx.write(new GamePacket(command, buffer));
	}

	/**
	 * The emblem upload: {@code {u8 mode, byte[768]}} ({@code 0xD5804C}, reached from the emblem
	 * screen through task kind 25).
	 * <p>
	 * The mode is what the client will set its own emblem flag to. [ELF] 3 is "put on display" and
	 * the only value the client post-processes: the commit path at {@code 0xAD45A4} tests
	 * {@code cmpwi r29,3} and only that branch reaches both the store to {@code profile+6872} and
	 * the {@code memcpy} of the bitmap to {@code profile+6873}. Modes 2 and 4 also occur and touch
	 * neither — they read as "stored, not shown".
	 * <p>
	 * All three modes are stored, image and all, because a non-display mode looks like the editor's
	 * Save: work the player expects to keep. Only {@link ClanService#emblemOf} decides what may be
	 * <em>served</em>, and it serves nothing unless the mode is 3.
	 * <p>
	 * [OBSERVED 2026-07-27] This javadoc used to claim that storing every mode made "the server and
	 * the client end up agreeing about whether the clan has an emblem to show". It did not. The
	 * flag was clamped to 3-or-0 while the emblem fetch ignored the mode entirely, so a clan whose
	 * emblem had been deleted reported no emblem and then served one to any screen that asked —
	 * visible on Player Details -> More Details across a full logout and login.
	 * <p>
	 * Only the leader may commit: the client already enforces it ({@code 0xAD409C} tests
	 * {@code ctx+788 & 4}, which is set only when membership state is 2), and so do we.
	 */
	private void uploadEmblem(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();

		if (charaId != null && payload.readableBytes() >= 1 + CLAN_DATA_BLOCK) {
			var mode = payload.readUnsignedByte();
			var emblem = new byte[CLAN_DATA_BLOCK];
			payload.readBytes(emblem);

			var membership = clanService.membershipOf(charaId);
			if (membership.state() == ClanService.STATE_LEADER) {
				var since = clanService.secondsSinceEmblem(membership.id());
				if (mode == EMBLEM_ON_DISPLAY && since >= 0 && since < displayCooldownSeconds()) {
					logger.info("Clan {}: emblem re-display refused, {}s of {}s cooldown remaining.",
						membership.id(), displayCooldownSeconds() - since, displayCooldownSeconds());
					refuseEmblem(ctx);
					return;
				}
				clanService.setEmblem(membership.id(), emblem, mode);
				logger.info("Clan {}: emblem uploaded by character {}, mode {}.",
					membership.id(), charaId, mode);
			} else {
				logger.info("Character {} tried to set a clan emblem without leading one.", charaId);
				refuseEmblem(ctx);
				return;
			}
		}

		writeResult(ctx, UPLOAD_EMBLEM_RESULT);
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

		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var membership = charaId == null ? ClanService.Membership.NONE
			: clanService.membershipOf(charaId);
		var isLeader = membership.state() == ClanService.STATE_LEADER && membership.id() == clanId;

		// Members and applicants go out as ONE batch, with the isMember byte set per row.
		//
		// Sending them as two separate 0x4b54 packets — members then applicants, which is how the
		// list is built upstream — put both on the wire but the client rendered only the first, so
		// the applicant simply vanished. Before that, when applicants were mixed into the members
		// query, they appeared but as full members, because the flag was being set per batch rather
		// than per row. One list with an honest per-row flag is the combination not yet tried.
		var rows = new java.util.ArrayList<ClanService.Member>();
		if (clanId != 0L) {
			rows.addAll(clanService.membersOf(clanId));
			if (isLeader) {
				rows.addAll(clanService.applicantsFor(clanId));
			}
		}

		writeResult(ctx, CLAN_MEMBERS_START);
		writeRoster(ctx, rows);
		writeResult(ctx, CLAN_MEMBERS_END);
	}

	/**
	 * One batch of 68-byte roster rows: {@code u32 id, name[16], u8 isMember, u32, u32}, then the
	 * game-location fields (lobby id, lobby name, game id, host name, subtype) which stay zero until
	 * we look up where a member is playing.
	 */
	private void writeRoster(GameControllerContext ctx, java.util.List<ClanService.Member> rows) {
		if (rows.isEmpty()) {
			return;
		}
		var buffer = ctx.buffer(rows.size() * MEMBER_RECORD_SIZE);
		for (var row : rows) {
			var recordStart = buffer.writerIndex();
			buffer.writeInt((int) row.charaId());
			BufferUtil.writeString(buffer, row.name(), StandardCharsets.ISO_8859_1,
				CLAN_NAME_LENGTH);
			// Per row: joined members 1, pending applicants 0.
			buffer.writeByte(row.state() == ClanService.STATE_PENDING ? 0 : 1);
			buffer.writeInt(0);
			buffer.writeInt((int) row.charaId());
			buffer.writeZero(MEMBER_RECORD_SIZE - (buffer.writerIndex() - recordStart));
		}
		ctx.write(new GamePacket(CLAN_MEMBERS_ENTRIES, buffer));
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


	/** Records the application and acknowledges it. */
	private void applyToJoin(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		var clanId = payload.readableBytes() >= Integer.BYTES ? payload.readInt() & 0xFFFFFFFFL : 0L;

		if (charaId == null || clanId == 0 || clanService.clanById(clanId).isEmpty()) {
			ctx.write(APPLY_TO_JOIN_RESULT, GameError.GENERAL);
			return;
		}

		var wait = clanService.secondsUntilCanApply(charaId);
		if (wait > 0) {
			logger.info("Character {} may not apply to clan {} yet, {}s of {}s remaining.",
				charaId, clanId, wait,
				mgo2server.common.Policy.current().clanJoinCooldown().toSeconds());
			writeCode(ctx, APPLY_TO_JOIN_RESULT, APPLY_TOO_SOON);
			return;
		}

		clanService.apply(charaId, clanId);
		logger.info("Character {} applied to join clan {}.", charaId, clanId);
		writeResult(ctx, APPLY_TO_JOIN_RESULT);
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


	/** Searches clans by name, honouring the screen's exact-match and case-sensitivity toggles. */
	private void clanSearch(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var exactOnly = false;
		var caseSensitive = false;
		var name = "";
		if (payload.readableBytes() >= 2 + CLAN_NAME_LENGTH) {
			exactOnly = payload.readUnsignedByte() != 0;
			// 1 means IGNORE case. See SocialGameController.playerSearch — the same two bytes reach
			// both search screens and "bob" failing to find "Bob" is what settled the polarity.
			caseSensitive = payload.readUnsignedByte() == 0;
			name = readNulTerminated(payload, CLAN_NAME_LENGTH);
		}

		var matches = name.isEmpty() ? java.util.List.<ClanService.Clan>of()
			: clanService.searchClans(name, exactOnly, caseSensitive, CLAN_LIST_PAGE);
		logger.info("Clan search for '{}' ({}, {}): {} match(es).", name,
			exactOnly ? "exact" : "partial", caseSensitive ? "case-sensitive" : "case-insensitive",
			matches.size());

		writeResult(ctx, CLAN_SEARCH_START);
		if (!matches.isEmpty()) {
			var buffer = ctx.buffer(matches.size() * SEARCH_RECORD_SIZE);
			for (var clan : matches) {
				var recordStart = buffer.writerIndex();
				buffer.writeInt((int) clan.id());
				BufferUtil.writeString(buffer, clan.name(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				buffer.writeInt((int) clan.leaderCharaId());
				BufferUtil.writeString(buffer, clan.leaderName(), StandardCharsets.ISO_8859_1,
					CLAN_NAME_LENGTH);
				buffer.writeInt((int) clan.createdAt());
				buffer.writeZero(SEARCH_RECORD_SIZE - (buffer.writerIndex() - recordStart));
			}
			ctx.write(new GamePacket(CLAN_SEARCH_ENTRIES, buffer));
		}
		writeResult(ctx, CLAN_SEARCH_END);
	}

	/** Disbands the caller's clan, taking every membership with it. Leader only. */
	private void disband(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId == null) {
			ctx.write(DISBAND_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var membership = clanService.membershipOf(charaId);
		if (membership.state() != ClanService.STATE_LEADER) {
			logger.info("Character {} tried to disband a clan they do not lead.", charaId);
			ctx.write(DISBAND_RESULT, GameError.GENERAL);
			return;
		}

		var wait = clanService.secondsUntilDisbandable(membership.id());
		if (wait > 0) {
			logger.info("Clan {}: disband refused, {}s of the {}s cooldown remaining.",
				membership.id(), wait, ClanService.DISBAND_COOLDOWN.toSeconds());
			writeCode(ctx, DISBAND_RESULT, DISBAND_TOO_SOON);
			return;
		}

		if (clanService.disband(membership.id())) {
			logger.info("Clan {} disbanded by character {}.", membership.id(), charaId);
			writeResult(ctx, DISBAND_RESULT);
		} else {
			ctx.write(DISBAND_RESULT, GameError.GENERAL);
		}
	}

	/** Withdraws a pending application, or leaves the clan. */
	private void withdraw(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId != null && clanService.withdraw(charaId)) {
			logger.info("Character {} withdrew from their clan.", charaId);
		}
		writeResult(ctx, WITHDRAW_RESULT);
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
		// T+0x378 is the emblem-present flag, the same slot 0x4b21 carries it in. Zero here meant a
		// clan viewed from search or the clan list never had its emblem fetched, so it rendered
		// empty even when one was set.
		buffer.writeByte(onDisplay(clan.id()));    // T+0x378
		BufferUtil.writeString(buffer, clan.description(), StandardCharsets.ISO_8859_1,
			DESCRIPTION_LENGTH);                                              // T+0x67A
		buffer.writeZero(4);                                                  // T+0x1B34
		buffer.writeInt(clanService.memberCount(clan.id()));                  // T+0x58
		buffer.writeZero(CLAN_PROFILE_PART_SIZE - (buffer.writerIndex() - start));

		ctx.write(new GamePacket(CLAN_PROFILE_PART_RESULT, buffer));
	}

	/**
	 * A leader acting on one member, named by character id: banish, hand over leadership, grant
	 * emblem-editing rights. All three take the same {@code u32} payload and reply with a bare
	 * result, and all three were previously answered with a success the server never carried out —
	 * "it succeeded but nothing happened".
	 */
	private void leaderAction(GameControllerContext ctx, int reply, String what,
			java.util.function.BiPredicate<Long, Long> action) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		if (charaId == null || payload.readableBytes() < Integer.BYTES) {
			ctx.write(reply, GameError.INVALID_SESSION);
			return;
		}

		var targetId = payload.readInt() & 0xFFFFFFFFL;
		var membership = clanService.membershipOf(charaId);
		if (membership.state() != ClanService.STATE_LEADER) {
			logger.info("Character {} tried to {} {} without leading a clan.", charaId, what,
				targetId);
			ctx.write(reply, GameError.GENERAL);
			return;
		}

		var done = reply == TRANSFER_LEADERSHIP_RESULT
			? clanService.transferLeadership(membership.id(), charaId, targetId)
			: action.test(membership.id(), targetId);
		logger.info("Clan {}: character {} used {} on {}{}.", membership.id(), charaId, what,
			targetId, done ? "" : " (no matching member)");
		if (done) {
			writeResult(ctx, reply);
		} else {
			ctx.write(reply, GameError.GENERAL);
		}
	}

	/** Accepts or declines a pending applicant, named by character id. Leader only. */
	private void judgeApplicant(GameControllerContext ctx, boolean accept) {
		var reply = accept ? ACCEPT_JOIN_RESULT : DECLINE_JOIN_RESULT;
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		if (charaId == null || payload.readableBytes() < Integer.BYTES) {
			ctx.write(reply, GameError.INVALID_SESSION);
			return;
		}

		var targetId = payload.readInt() & 0xFFFFFFFFL;
		var membership = clanService.membershipOf(charaId);
		if (membership.state() != ClanService.STATE_LEADER) {
			logger.info("Character {} tried to judge an applicant without leading a clan.", charaId);
			ctx.write(reply, GameError.GENERAL);
			return;
		}

		var changed = accept ? clanService.approve(membership.id(), targetId)
			: clanService.decline(membership.id(), targetId);
		logger.info("Clan {}: character {} {} applicant {}{}.", membership.id(), charaId,
			accept ? "accepted" : "declined", targetId, changed ? "" : " (no pending application)");
		writeResult(ctx, reply);
	}

	/** Refuses an emblem upload. See {@link #EMBLEM_REFUSED}. */
	private void refuseEmblem(GameControllerContext ctx) {
		writeCode(ctx, UPLOAD_EMBLEM_RESULT, EMBLEM_REFUSED);
	}

	/**
	 * A bare result carrying a raw client error code.
	 * <p>
	 * These codes are not ours and are not masked: the client resolves them through its own table at
	 * {@code 0x106D714} ({@code dialogId -> ordinal -> string}), so each one selects a specific
	 * message. {@link GameError} exists for our masked codes; this is for the client's own.
	 */
	private void writeCode(GameControllerContext ctx, int command, int code) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(code);
		ctx.write(new GamePacket(command, buffer));
	}

	/** The re-display cooldown in seconds. See {@link #EMBLEM_COOLDOWN_SECONDS}. */
	private static long displayCooldownSeconds() {
		return EMBLEM_COOLDOWN_SECONDS;
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
		// T+0x48 is NOT the emblem re-display cooldown. [ELIMINATED 2026-07-27] It is the only
		// timestamp-shaped slot we send that the client never renders (u32 read, stored with `std`
		// as 64 bits at 0xD5899C), so it was the obvious candidate for the countdown behind lobby
		// string 17247. Sending the real display time changed nothing: the emblem could still be
		// re-displayed immediately, with a fresh 0x4b21 in hand. The confirming observation would
		// have been the countdown appearing, and it did not. Back to zero.
		buffer.writeZero(4);                                                  // T+0x48
		buffer.writeInt(clanService.memberCount(clan.id()));                  // T+0x58  members
		buffer.writeZero(4 + 4 + 4 + 4 + 4);                                  // T+0x5c .. T+0x6c
		buffer.writeZero(4 + 1);                                              // flags_word, T+0x74
		buffer.writeZero(1);                                                  // flags_byte
		// T+0x76 = 2 when a work-in-progress emblem exists (we do not model one yet);
		// T+0x378 = 3 when a published emblem exists. The client will not fetch or offer an emblem
		// while this is 0, which is why Emblem Edit had nothing to apply.
		buffer.writeByte(0);                                                  // T+0x76
		buffer.writeByte(onDisplay(clan.id()));    // T+0x378
		BufferUtil.writeString(buffer, clan.description(), StandardCharsets.ISO_8859_1,
			DESCRIPTION_LENGTH);                                              // T+0x67A
		// T+0x6FC is the EMBLEM EDITOR's character id — the client compares it against its own to
		// decide whether to offer "set as the clan's emblem". Nobody is assigned one yet, so it
		// falls back to the leader, who is the only person who can commit an emblem anyway.
		buffer.writeInt((int) clan.emblemEditorCharaId());                    // T+0x6FC
		BufferUtil.writeString(buffer, clan.notice(), StandardCharsets.ISO_8859_1,
			NOTICE_LENGTH);                                                   // T+0x700, the notice
		// The notice's timestamp and author, which the screen draws under the notice itself.
		//
		// T+0x904 was identified by probe as "the date Clan Affiliation displays" and labelled the
		// FOUNDING date, which was a guess about meaning layered on a real observation: the field is
		// right, the label was wrong. It is the notice's date, and the 16 bytes after it are the
		// name of whoever set it.
		//
		// NEVER SET: send -1, not 0. The renderer (0xAAB2D8) has no conditionals at all — it always
		// draws the date, the author and the notice body, so the line cannot be suppressed. But the
		// formatter 0x8843CC tests the value at 0x884420 and takes a fallback branch when it is
		// NEGATIVE, printing the literal "XXXX-XX-XX XX:XX:XX" instead of a date. Zero is not
		// special-cased — localtime(0) succeeds and yields 12-31-1969, which is the bug. -1 is this
		// binary's own convention for an absent timestamp; 0x91E4C0 tests another one the same way.
		buffer.writeInt(clan.noticeAt() == 0 ? NO_TIMESTAMP : (int) clan.noticeAt());  // T+0x904
		BufferUtil.writeString(buffer, clan.noticeWriter(), StandardCharsets.ISO_8859_1,
			CLAN_NAME_LENGTH);                                                // T+0x908
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

		// 20 hours of play time and level 3, which is the game's own rule — the client carries the
		// text for it (lobby 17193) and simply never gets to show it, because the refusal comes back
		// as a result code rather than that message.
		if (!characterService.meetsClanRequirements(charaId)) {
			logger.info("Character {} tried to create clan '{}' without 20 hours and level 3.",
				charaId, name);
			writeCode(ctx, CREATE_CLAN_RESULT, CLAN_CONDITIONS_NOT_MET);
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
			// 3 once an emblem is on display, 0 otherwise. Clamped like every other writer of this
			// byte: emblemFlagOf returns the raw stored upload mode, and modes 2 and 4 must not be
			// echoed — the client only ever stores 3 here (0xAD4724), so sending 2 would put our
			// record out of step with the one the client keeps for itself.
			.writeByte(onDisplay(membership.id()));
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
