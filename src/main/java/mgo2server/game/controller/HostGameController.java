package mgo2server.game.controller;

import io.netty.buffer.ByteBufUtil;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.CharaSkill;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.AwardService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
import mgo2server.game.LoadoutWriter;
import mgo2server.game.PersonalInfoWriter;
import mgo2server.game.GameConnection;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.GameplaySettingsReader;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Hosting: turning a character's saved host settings into a live game, and the host-side commands
 * that run it once players connect.
 * <p>
 * Covers reading and pushing settings (0x4304/0x4310), create and quit (0x4316/0x4380), the
 * peer-registration round-trips (0x4340/0x4342/0x4344/0x4346), and the staging and round-lifecycle
 * admin commands (0x43c0 in-game info, 0x43ca start round, 0x4392 set game, 0x4390 stats, 0x43a2,
 * 0x43a0 pass host). The admin commands are acknowledged but their match state is not yet tracked.
 */
public class HostGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/**
	 * The host's saved game settings, asked for when the player opens Create Game so the screen can
	 * be pre-filled with whatever they hosted last time.
	 */
	public static final int GET_HOST_SETTINGS = 0x4304;

	/**
	 * The reply, and <b>the only payload this server encrypts on the way out</b> — see
	 * {@code GameCrypto.ENCRYPT_COMMANDS}. Until this command existed nothing exercised the
	 * Blowfish encrypt direction at all, so a fault there would have been invisible.
	 */
	public static final int HOST_SETTINGS_RESULT = 0x4305;

	/**
	 * Fixed reply size. A host with nothing saved gets this many zero bytes, which is what both
	 * references send and what the client reads as "no saved settings, use the defaults".
	 */
	private static final int HOST_SETTINGS_SIZE = 128;

	/**
	 * The settings the player just configured, pushed before the game is created.
	 * <p>
	 * Its payload arrives Blowfish-encrypted — see {@code GameCrypto.DECRYPT_COMMANDS}.
	 */
	public static final int CHECK_HOST_SETTINGS = 0x4310;

	public static final int CHECK_HOST_SETTINGS_RESULT = 0x4311;

	/**
	 * Byte offset of round 0's {@code [rule, map, flags]} triple in the {@code 0x4310} blob. The
	 * blob is name(16) + comment(128) + password(17) + dedicated(1) + a subtype byte, then the
	 * rotation.
	 * <p>
	 * <b>Resolved 2026-07-26 — 163 is right.</b> The one-byte ambiguity between the references
	 * (Model A = 162, Model B = 163) is settled from the binary: the {@code 0x4310} writer emits
	 * the lobby subtype as a standalone {@code u8} at wire {@code 0xA2} ({@code 0xd448fc}) and the
	 * rotation begins at {@code 0xA3}. See {@code dev/proto/inbound/mgo2_cmd_4310_c2s.ksy};
	 * no live experiment is needed.
	 */
	private static final int ROTATION_OFFSET = 163;

	/**
	 * Rotation entries in the {@code 0x4310} blob. Sixteen, not fifteen: the writer's loop bound is
	 * {@code cmpdi cr7,r27,16} at {@code 0xd44958} and it always emits all of them, and both the
	 * {@code 0x4305} and {@code 0x4313} parsers read sixteen. Fifteen is a reference-server figure.
	 */
	private static final int ROTATION_ROUNDS = 16;

	/**
	 * Host reports that a player's peer-to-peer connection to it succeeded — sent only once the
	 * P2P link actually forms, so its arrival is the first proof a join reached the host. The
	 * client blocks on the {@code 0x4341} ack; unanswered, the join hangs. Confirmed against a
	 * live client 2026-07-21 (mx1 joining a localhost-hosted game).
	 */
	public static final int PLAYER_CONNECTED = 0x4340;

	public static final int PLAYER_CONNECTED_RESULT = 0x4341;

	/** Host reports a player left. The disconnect pair of {@link #PLAYER_CONNECTED}. */
	public static final int PLAYER_DISCONNECTED = 0x4342;

	public static final int PLAYER_DISCONNECTED_RESULT = 0x4343;

	/**
	 * Second peer-registration round-trip. The host's per-peer P2P state machine (ELF
	 * {@code 0x276F60}) issues three blocking register-with-server round-trips —
	 * {@code 0x4340}, {@code 0x4344}, {@code 0x4346} — and its {@code 0x4345} reply parser
	 * ({@code 0xD42B40}) is byte-identical to {@code 0x4341}'s: it reads {@code {u32 result,
	 * u32 key}} and bails on a short read. An empty ack stalls the FSM here until its 30-second
	 * ({@code 0x7530}) deadline fires and it disconnects the peer ({@code 0x4342}). So this is
	 * <em>not</em> merely "set team" — the reply must carry {@code result + echoed key}. Handled
	 * by {@link #playerConnection}.
	 */
	public static final int SET_PLAYER_TEAM = 0x4344;

	public static final int SET_PLAYER_TEAM_RESULT = 0x4345;

	/**
	 * Third peer-registration round-trip (ELF FSM state {@code 0x217}, sender {@code 0xD42E64}).
	 * Reached only after {@code 0x4344} completes; unhandled, the FSM times out and disconnects.
	 * Its {@code 0x4347} parser ({@code 0xD42A34}) is the same {@code {result, key}} shape.
	 */
	public static final int PLAYER_CONNECT_FINISH = 0x4346;

	public static final int PLAYER_CONNECT_FINISH_RESULT = 0x4347;

	/** Host reports round-trip times for the players in its game. */
	public static final int UPDATE_PINGS = 0x4398;

	public static final int UPDATE_PINGS_RESULT = 0x4399;

	/**
	 * In-game host-settings edit: the host changing game name, comment and password lock from the
	 * in-match host menu (builder at ELF {@code 0xd41740}; the payload mirrors the {@code 0x4310}
	 * push — name[16] at 0x00, comment[128] at 0x10, password-enabled at 0x90, password[16] at 0x91).
	 * Arrives Blowfish-encrypted (in {@code GameCrypto.DECRYPT_COMMANDS}), so it is already decrypted
	 * here.
	 * <p>
	 * The client's {@code 0x43c1} parser ({@code 0xd4015c}) reads a {@code u32} result at offset 0
	 * and re-stalls on a short reply, so the ack must be 4 bytes {@code {result=0}} — <b>not</b> the
	 * empty reply the (different-build) references send. Handled by {@link #editHostSettings}, which
	 * parses those fields and updates the game this character hosts.
	 */
	public static final int IN_GAME_INFO = 0x43c0;

	public static final int IN_GAME_INFO_RESULT = 0x43c1;

	/**
	 * Host presses Start: begin the round. Request {@code {u32, u8}} (ELF builder {@code 0xD40CB4};
	 * the u32 reads as a round/rotation index, the u8 a flag). Reply {@code 0x43c9} must be
	 * {@code {u32 result, u32 token}}: the client's parser ({@code 0xD3FEAC}) gates the round on
	 * {@code result == 0}. <b>The second word is not a round handle</b> — corrected 2026-07-26. A
	 * nonzero value is written into {@code profile+0x32F8} and becomes the flag that suppresses the
	 * instructor recognition prompt; we send zero. See {@link #NO_INSTRUCTOR_TOKEN}.
	 * <p>
	 * <b>Renumbered from {@code 0x43ca}/{@code 0x43cb}</b> — the full send-site scan found no
	 * builder for {@code 0x43ca}; the client sends {@code 0x43c8} and parses {@code 0x43c9}. The
	 * old ids were a two-off transcription slip (and the reason the round snapshot never fired).
	 */
	public static final int START_ROUND = 0x43c8;

	/**
	 * A client settings write, pushed to the server rather than a host action despite the id.
	 * <p>
	 * The sender at {@code 0x27E0E4} reads client setting id <b>332</b> (4 bytes, from the settings
	 * group the caller selects) and puts that value straight on the wire, so the request is a
	 * single u32 whose meaning is whatever setting 332 is. First seen live 2026-07-26 carrying
	 * {@code 3}, moments after a training graduation.
	 * <p>
	 * Reply {@code 0x43a7} is a bare u32 result and nothing else: the parser at {@code 0xD3FFE0}
	 * reads one word and signals request-status 48 with it, taking no other branch. We do not
	 * persist the value — what setting 332 means is unknown, and storing an unidentified number
	 * against a character would be inventing a model.
	 */
	public static final int PUT_CLIENT_SETTING = 0x43a6;

	public static final int PUT_CLIENT_SETTING_RESULT = 0x43a7;

	public static final int START_ROUND_RESULT = 0x43c9;

	/** Host cycles the rule/map in the rotation while staging. Answered {@code result(0)}. */
	public static final int SET_GAME = 0x4392;

	public static final int SET_GAME_RESULT = 0x4393;

	/** End-of-round stat submission. Answered {@code result(0)}. */
	public static final int UPDATE_STATS = 0x4390;

	public static final int UPDATE_STATS_RESULT = 0x4391;

	/** End-of-round report (meaning unconfirmed). Answered {@code result(0)}. */
	/**
	 * The host-rating vote a player casts as they leave a game — a bare u32 of 1..5 stars.
	 * <p>
	 * IDENTIFIED 2026-07-28. It was an unhandled command dropped with a WARN, documented in
	 * PACKETS.md as "[UNKNOWN] In-match enumerated command". Two things settle it: the ELF accepts
	 * only the values 1..5 ({@code 0xD40E44} aborts otherwise), which rules out the character-id
	 * reading the rest of the {@code 0x43xx} family invites; and an operator who gave a host five
	 * stars produced exactly {@code 43c4 = 00000005}, sent right after the game-info screen and
	 * immediately before quitting.
	 */
	public static final int RATE_HOST = 0x43c4;

	public static final int ROUND_END = 0x43a2;

	/**
	 * One 0x43a2 weapon entry: {@code {u8 weapon, u16 kills, u16 headshots, u16 faints}}.
	 * The builder caps entries at 0x7f and the caller at 50.
	 */
	private static final int WEAPON_TALLY_BYTES = 7;

	/** The star range the client sends and the ELF enforces at {@code 0xD40E44}. */
	private static final int MIN_HOST_RATING = 1;

	private static final int MAX_HOST_RATING = 5;

	/** The caller-side cap on weapon entries; more than this is a mis-parse, not data. */
	private static final int MAX_WEAPON_TALLIES = 50;

	public static final int ROUND_END_RESULT = 0x43a3;

	/** Host hands hosting to another player. Answered {@code result(0)}. */
	public static final int HOST_MIGRATION = 0x43a0;

	public static final int HOST_MIGRATION_RESULT = 0x43a1;

	/**
	 * The client asking for its end-of-round results card (rank/exp/skill table), sent both on the
	 * post-round results screen and during the quit/leave teardown. Unanswered it is the
	 * "Unable to update character information (1031:FFFFFF60)" hang seen on quit.
	 * <p>
	 * The {@code 0x4129} parser ({@code 0xd3c9a8}) is fussy: an empty body re-stalls; a 4-byte
	 * {@code {result != 0}} clears the wait but the client renders the nonzero result as the error
	 * "1030:00000001"; and a 4-byte {@code {result = 0}} makes it read a full results blob that isn't
	 * there and fail. The only clean answer is {@code result = 0} <em>followed by the whole
	 * {@value #POST_GAME_INFO_SIZE}-byte results structure</em>, which the parser reads in full and
	 * accepts. Not Blowfish-encrypted. Confirmed against the ELF.
	 */
	public static final int GET_POST_GAME_INFO = 0x4128;

	public static final int POST_GAME_INFO_RESULT = 0x4129;

	/**
	 * The client saving its <b>personal gameplay options</b> — the write-back half of
	 * {@code 0x4120}, exactly as Nomad reads it. Identity settled live 2026-07-22: a <em>joiner</em>
	 * (who cannot set game rules) sent it as 304 bytes — the {@code 0x4120} layout minus its
	 * 32-byte trailer — in one burst with two {@code 0x4114} chat-macro write-backs. The earlier
	 * theory that its header carried the Common Settings toggles was wrong twice over: the toggles
	 * live in the {@code 0x4310} blob (capture-proven), and this command never appears in the
	 * hosting flow at all.
	 * <p>
	 * <b>The body is now parsed into {@code chara_settings}</b> (2026-07-29), so options persist.
	 * Before that it was acknowledged and discarded, which is why Lock-On — and in fact every
	 * Gameplay Option — reverted after each session. The reply must carry {@code u32 result == 0}.
	 */
	public static final int UPDATE_SETTINGS = 0x4110;

	public static final int UPDATE_SETTINGS_RESULT = 0x4111;

	/** Total bytes of the {@code 0x4129} results payload (result word included); echo's BUFFER_SIZE. */
	/**
	 * Everything in the reply that is not a skill record: a 14-byte head and a 25-byte tail. The
	 * whole packet is this plus {@code 4 * skills}, which is where the old fixed {@code 0x8b} came
	 * from — 39 + 25 records of 4 bytes, back when the table was hard-coded at 25 entries.
	 */
	private static final int POST_GAME_INFO_FIXED = 39;

	private static final int SKILL_RECORD_SIZE = 4;

	/**
	 * The second word of {@code 0x43c9}. Zero, always — a nonzero value is stored permanently into
	 * the character's profile and suppresses the instructor recognition prompt from then on. Named
	 * rather than inlined so nobody "restores" the game id thinking it is a round handle.
	 */
	private static final int NO_INSTRUCTOR_TOKEN = 0;

	/**
	 * The value of {@code 0x43c8}'s answer byte that means <b>the student recognised the
	 * instructor</b> — they were shown "Save current instructor, %s, as the instructor for your
	 * personal data?" ({@code n002a} string 3099) and chose yes.
	 * <p>
	 * The encoding, settled live 2026-07-27 with all three values observed:
	 * <ul>
	 *   <li>{@code 0x00} — prompt shown, answered <b>no</b></li>
	 *   <li>{@code 0x01} — prompt shown, answered <b>yes</b></li>
	 *   <li>{@code 0x21} — prompt never shown (bit {@code 0x20} = "not asked"), which is what every
	 *       graduation produced while {@code 0x4122} was suppressing the prompt</li>
	 * </ul>
	 * So bit {@code 0} is the answer and bit {@code 5} says whether it was asked. Exact equality is
	 * the right test and the tempting {@code (answer & 0x20) == 0} shorthand is <b>wrong</b>: it
	 * reads a declined prompt ({@code 0x00}) as a recognition, which would permanently record an
	 * instructor the player refused. That case is not hypothetical — it was the first "no" sample.
	 */
	private static final int RECOGNISED_ANSWER = 0x01;

	/** Stand-in when the answer byte is absent; distinct from any observed value. */
	private static final int NO_ANSWER = -1;

	/** Combat training. Basic training is 7; only 8 runs the instructor/student flow. */
	private static final int COMBAT_TRAINING_SUBTYPE = 8;

	/**
	 * Kill switch for the graduation branch: {@code MGO2SERVER_GRADUATION=off} sends every
	 * {@code 0x43c8} down the original round-start path instead.
	 * <p>
	 * It exists so a live session can be A/B'd without a rebuild. This branch changes behaviour
	 * inside a match — it answers a command differently and skips {@code markRoundPlayers} — so
	 * when something goes wrong in-game it has to be possible to take it out of the picture in one
	 * restart rather than by reasoning about logs.
	 */
	private static final boolean GRADUATION_ENABLED =
		!"off".equalsIgnoreCase(String.valueOf(System.getenv("MGO2SERVER_GRADUATION")));

	/** Skill-table entries the results parser reads: a fixed 25, each {id u8, exp u16, pad u8}. */

	/**
	 * The ADDLIST relationship command — <b>meaning not yet pinned</b>. Observed live 2026-07-22
	 * from BOTH roles: the host on executing a kick (payload {@code 00 00 00 00 02}, trailing
	 * bytes = the kicked character's id) and a joiner during ADDLIST toggling (payload
	 * {@code 00 00 00 00 01}, targeting the host). The client's ADDLIST is a single state toggle
	 * (friend → blocked → none), so this either sets or queries a relationship; mute/unmute and
	 * resetting to none send nothing. Unanswered it wedges the sender ("server unstable"), so it
	 * is acked {@code 0x4501 {result=0}} — but note the open suspicion recorded in BACKLOG: if
	 * this is a <em>query</em>, our constant result 0 may be why the target renders permanently
	 * as "friend" in the player list. Payload logged for mapping; nothing stored yet.
	 */
	public static final int ADD_LIST = 0x4500;

	/**
	 * Reply to {@link #ADD_LIST} — <b>one added entry</b>, 25 bytes: {@code u32 lead (0 to carry a
	 * body), u32 target id, u8 state, char[16] name}. Read from the ELF (parser {@code 0xD47110});
	 * an exhaustive immediate scan found <b>no</b> parser for {@code 0x4501}/{@code 0x4503}, so
	 * ADDLIST breaks the start/entries/end idiom — {@code 0x4502} alone carries the reply. A lead
	 * word {@code != 0} makes the client skip the body (an empty / count-only frame).
	 */
	public static final int ADD_LIST_ENTRY = 0x4502;

	/**
	 * The ADDLIST <b>remove</b> — sent when a relationship is cleared to "none", and sent right
	 * before {@link #ADD_LIST} when one is changed (remove-old-then-add-new). Payload
	 * {@code {u8 state, u32 target id}}, the state being the one <em>removed</em>. Silently
	 * dropping it (no handler) was the ADDLIST lock: the client blocks on the {@code 0x4512} reply.
	 * ELF send builder {@code 0xD46EB0}.
	 */
	public static final int REMOVE_LIST = 0x4510;

	/**
	 * Reply to {@link #REMOVE_LIST} — <b>one removed entry</b>, 9 bytes: {@code u32 lead (0),
	 * u8 state, u32 target id}. Note the field order differs from {@code 0x4502} (state before id,
	 * no name). ELF parser {@code 0xD46B60}; like ADDLIST there is no start/end, {@code 0x4512}
	 * alone is the reply.
	 */
	public static final int REMOVE_LIST_ENTRY = 0x4512;

	/**
	 * Bulk friend/blocked roster fetch — the standalone Friends/Blocked menu, distinct from the
	 * in-game ADDLIST. Request is a single {@code u8 state} (0 friends, 1 blocked); the reply is a
	 * triple, one list per state. Populated from {@code chara_relation}. Reply built from the ELF
	 * parsers ({@code 0x4581} start `0xD469C0`, {@code 0x4582} entries `0xD467C0`, {@code 0x4583}
	 * end `0xD465D4`); ELF send builder {@code 0xD4628C}.
	 * <p>
	 * <b>Observed live 2026-07-26, and it failed.</b> The start packet carried the entry
	 * <em>count</em>, so a character with one friend got
	 * <em>Unable to acquire Friend List.(1002:00000001)</em> — the dialog number was the count,
	 * stored verbatim as the transaction's failure code. It is a result code; see
	 * {@link #listRoster}. Two things were wrong at once: the records were also zero-filled, and
	 * {@code 0x4583} discards any record whose u16 at wire {@code 0x14} is zero, so fixing only
	 * the start would have produced an empty list with every record parsing correctly.
	 */
	public static final int LIST_ROSTER = 0x4580;

	public static final int LIST_ROSTER_START = 0x4581;

	public static final int LIST_ROSTER_ENTRIES = 0x4582;

	public static final int LIST_ROSTER_END = 0x4583;

	/**
	 * A {@code 0x4582} roster entry: {@code u32 id, char[16] name}, then five fields whose meaning
	 * the ELF trace could not pin (a u16, two more 16-byte strings, a u32, a trailing byte) — sent
	 * zero, the same unknown-as-zero convention the other list replies use. Total 59 bytes.
	 */
	private static final int ROSTER_ENTRY_SIZE = 59;

	/** Entries per {@code 0x4582} packet: the parser accumulates across packets, capped at 32 total. */
	private static final int ROSTER_PER_PACKET = 17; // 17 × 59 = 1003 ≤ the 1023 payload max

	private static final int ROSTER_MAX = 32;

	/** Fixed name width in a 0x4502 entry, as the ELF parser reads it. */
	private static final int RELATION_NAME_LENGTH = 16;

	/**
	 * The {@code 0x4582} u16 at wire {@code 0x14}, which decides whether the client keeps the
	 * record at all — see the write site in {@link #listRoster}. Any nonzero value passes the
	 * gate; 1 is chosen only because it is the smallest one, and it carries no claim about the
	 * field's meaning. If a value ever shows up on the roster screen, this is the field to
	 * fingerprint.
	 */
	private static final int ROSTER_ENTRY_VISIBLE = 1;

	/** Sent on leaving a game. Unanswered, the client sits on a black screen. */
	public static final int QUIT_GAME = 0x4380;

	public static final int QUIT_GAME_RESULT = 0x4381;

	public static final int CREATE_GAME = 0x4316;

	public static final int CREATE_GAME_RESULT = 0x4317;

	private final GameService gameService;

	private final CharacterService characterService;

	private final ClanService clanService;

	private final AwardService awardService;

	private final long lobbyId;

	private final int lobbySubtype;

	/**
	 * Told when a game has been created and its settings applied.
	 * <p>
	 * Exists for automatching, which must not release its joiners until the elected host's game is
	 * both committed <em>and</em> configured — {@code createGame} commits the row and
	 * {@code applyHostSettings} runs after it, so a matchmaker watching only for the row can hand
	 * joiners a game whose rule and map are still zero.
	 */
	@FunctionalInterface
	public interface GameCreatedListener {
		void gameCreated(long hostCharaId, long gameId);

		/** For every lobby that is not automatching. */
		GameCreatedListener NONE = (hostCharaId, gameId) -> { };
	}

	private final GameCreatedListener gameCreatedListener;

	public HostGameController(GameService gameService, CharacterService characterService,
			ClanService clanService, AwardService awardService, long lobbyId, int lobbySubtype) {
		this(gameService, characterService, clanService, awardService, lobbyId, lobbySubtype,
			GameCreatedListener.NONE);
	}

	public HostGameController(GameService gameService, CharacterService characterService,
			ClanService clanService, AwardService awardService, long lobbyId, int lobbySubtype,
			GameCreatedListener gameCreatedListener) {
		this.gameCreatedListener = gameCreatedListener;
		this.clanService = clanService;
		this.gameService = gameService;
		this.characterService = characterService;
		this.awardService = awardService;
		this.lobbyId = lobbyId;
		this.lobbySubtype = lobbySubtype;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(PUT_CLIENT_SETTING,
			ctx -> ctx.write(PUT_CLIENT_SETTING_RESULT, GameError.NONE));
		handlers.put(GET_HOST_SETTINGS, this::getHostSettings);
		handlers.put(CHECK_HOST_SETTINGS, this::checkHostSettings);
		handlers.put(CREATE_GAME, this::createGame);
		handlers.put(PLAYER_CONNECTED, this::playerConnection);
		handlers.put(PLAYER_DISCONNECTED, this::playerConnection);
		handlers.put(SET_PLAYER_TEAM, this::playerConnection);
		handlers.put(PLAYER_CONNECT_FINISH, this::playerConnection);
		handlers.put(UPDATE_PINGS, this::updatePings);
		handlers.put(QUIT_GAME, this::quitGame);
		handlers.put(IN_GAME_INFO, this::editHostSettings);
		handlers.put(START_ROUND, this::startRound);
		handlers.put(SET_GAME, this::setGame);
		handlers.put(UPDATE_STATS, this::updateStats);
		handlers.put(ROUND_END, this::roundEnd);
		handlers.put(RATE_HOST, this::rateHost);
		handlers.put(HOST_MIGRATION, this::hostMigration);
		handlers.put(GET_POST_GAME_INFO, this::postGameInfo);
		handlers.put(UPDATE_SETTINGS, this::updateSettings);
		handlers.put(ADD_LIST, this::addList);
		handlers.put(REMOVE_LIST, this::removeList);
		handlers.put(LIST_ROSTER, this::listRoster);
	}

	/**
	 * Acknowledges an ADDLIST relationship command ({@link #ADD_LIST}) so the sender does not
	 * wedge waiting — the payload is logged for mapping but nothing is stored or torn down here:
	 * on a kick the host reports the departure itself via {@code 0x4342}, and roster cleanup
	 * rides that as usual.
	 */
	/**
	 * Adds or changes a relationship ({@link #ADD_LIST}). Request {@code {u8 state, u32 target}} —
	 * state 0 friend, 1 blocked, confirmed live. Persists the relation (also replayed by the
	 * {@code 0x4101} login arrays) and replies with the single added entry as {@code 0x4502}, the
	 * ELF-confirmed reply. On a change the client sends {@link #REMOVE_LIST} for the old state
	 * first; both must be answered or the ADDLIST locks.
	 */
	private void addList(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();

		if (charaId == null || payload.readableBytes() < 5) {
			// Nothing to add: a count-only frame (nonzero lead, no body).
			var buffer = ctx.buffer(Integer.BYTES);
			buffer.writeInt(1);
			ctx.write(new GamePacket(ADD_LIST_ENTRY, buffer));
			return;
		}

		var base = payload.readerIndex();
		var state = payload.getByte(base) & 0xff;
		long targetId = payload.getInt(base + 1);
		characterService.setRelation(charaId, targetId, state);
		logger.info("Character {} set relation state {} on character {}.",
			charaId, state, targetId);

		var name = characterService.get(targetId).map(c -> c.getName()).orElse("");
		var buffer = ctx.buffer(2 * Integer.BYTES + 1 + RELATION_NAME_LENGTH);
		buffer.writeInt(0) // lead word 0: an entry body follows
			.writeInt((int) targetId)
			.writeByte(state);
		BufferUtil.writeString(buffer, name, StandardCharsets.ISO_8859_1, RELATION_NAME_LENGTH);
		ctx.write(new GamePacket(ADD_LIST_ENTRY, buffer));
	}

	/**
	 * Clears a relationship ({@link #REMOVE_LIST}) — ADDLIST set-to-none, or the first half of a
	 * change. Request {@code {u8 state, u32 target}} (the state being removed). Deletes the
	 * relation and replies with the removed entry as {@code 0x4512} ({@code u32 0, u8 state,
	 * u32 id} — note the order differs from {@code 0x4502}). Answering this is the fix for the
	 * ADDLIST lock; it was silently dropped before.
	 */
	private void removeList(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();

		var state = 0;
		long targetId = 0;
		if (charaId != null && payload.readableBytes() >= 5) {
			var base = payload.readerIndex();
			state = payload.getByte(base) & 0xff;
			targetId = payload.getInt(base + 1);
			characterService.removeRelation(charaId, targetId);
			logger.info("Character {} cleared its relation (was state {}) on character {}.",
				charaId, state, targetId);
		}

		var buffer = ctx.buffer(2 * Integer.BYTES + 1);
		buffer.writeInt(0) // lead word 0: an entry body follows
			.writeByte(state)
			.writeInt((int) targetId);
		ctx.write(new GamePacket(REMOVE_LIST_ENTRY, buffer));
	}

	/**
	 * The standalone Friends/Blocked roster fetch ({@link #LIST_ROSTER}). Reads the requested
	 * state ({@code u8}: 0 friends, 1 blocked) and replies with that state's relations from
	 * {@code chara_relation}: a {@code 0x4581} start <em>result code</em>, then {@code 0x4582}
	 * packets of up to {@value #ROSTER_PER_PACKET} entries each, then a {@code 0x4583} end.
	 * Capped at {@value #ROSTER_MAX}, the client's own limit.
	 * <p>
	 * <b>Corrected 2026-07-26, from a live failure.</b> The start used to carry the entry
	 * <em>count</em>. It is a result code: parser {@code 0xD469C0} reads one u32 and, when it is
	 * nonzero, completes the transaction as <em>failed</em> with the value stored verbatim
	 * ({@code 0xD46AB4}-{@code 0xD46B20}). A player with one friend therefore got
	 * <em>Unable to acquire Friend List.(1002:00000001)</em> — the dialog number was the count.
	 * Zero takes the other branch, which zeroes both list counters; the client counts the
	 * {@code 0x4582} records itself. This is the same mechanism as the recorded
	 * {@code 1032:00000005} for the {@code 0x4680} family, and it stayed hidden because an empty
	 * roster sends a count of 0, which is also the success code.
	 * <p>
	 * The subsystem index is not fixed: it is {@code 0x51 + state}, so Friends and Blocked are
	 * separate transactions.
	 */
	private void listRoster(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		var payload = ctx.packet().getPayload();
		var state = payload.readableBytes() >= 1 ? payload.getByte(payload.readerIndex()) & 0xff : 0;

		var entries = charaId == null ? java.util.List.<CharacterService.Relation>of()
			: characterService.relations(charaId).stream()
				.filter(relation -> relation.state() == state)
				.limit(ROSTER_MAX)
				.toList();

		// Start carries a RESULT CODE, never a count: nonzero fails the roster screen with that
		// value. See the javadoc above.
		var start = ctx.buffer(Integer.BYTES);
		start.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(LIST_ROSTER_START, start));

		for (var offset = 0; offset < entries.size(); offset += ROSTER_PER_PACKET) {
			var batch = entries.subList(offset, Math.min(offset + ROSTER_PER_PACKET, entries.size()));
			var buffer = ctx.buffer(batch.size() * ROSTER_ENTRY_SIZE);
			for (var relation : batch) {
				buffer.writeInt((int) relation.targetId());
				BufferUtil.writeString(buffer, relation.name(), StandardCharsets.ISO_8859_1,
					RELATION_NAME_LENGTH);
				// The u16 at wire 0x14 is a DISPLAY GATE, not decoration: the 0x4583 end handler
				// compacts the collected records and copies one into the display array only when
				// this field is nonzero (lhz +30, compare, branch — 0xD466D4..0xD46734). Zero here
				// means the roster screen comes up empty with every record having parsed
				// perfectly. What the value MEANS is unknown; only its nonzero-ness is evidenced.
				// Nomad puts 36 in the byte-identical 0x4602 record and guesses level or rank,
				// which is tier 4 and not a reason to copy it. If it turns out to render, this
				// must come from the character rather than being a constant.
				buffer.writeShort(ROSTER_ENTRY_VISIBLE);
				buffer.writeZero(ROSTER_ENTRY_SIZE - Integer.BYTES - RELATION_NAME_LENGTH
					- Short.BYTES);
			}
			ctx.write(new GamePacket(LIST_ROSTER_ENTRIES, buffer));
		}

		var end = ctx.buffer(Integer.BYTES);
		end.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(LIST_ROSTER_END, end));
	}

	/**
	 * Stores the client's gameplay options ({@link #UPDATE_SETTINGS}); the reply must carry
	 * a {@code u32} result of 0 or the enter-game flow stalls.
	 */
	private void updateSettings(GameControllerContext ctx) {
		// PERSIST THE OPTIONS. Acknowledging without storing is why every Gameplay Option reverted
		// after a session: 0x4120 was already sending the stored row correctly, so the round trip
		// was broken on exactly one side, and Lock-On was simply the setting people noticed.
		//
		// The payload is 0x4120's own layout truncated at 0x130 — the same 48-byte header and four
		// 64-byte codec names, minus the list-preferences trailer the client never returns. So the
		// reader is the writer backwards; see GameplaySettingsReader.
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId != null) {
			var settings = characterService.getOrCreateSettings(charaId);
			if (GameplaySettingsReader.apply(ctx.packet().getPayload(), settings)) {
				characterService.saveSettings(settings);
				logger.debug("Stored gameplay options for character {}.", charaId);
			} else {
				// Short payload: store nothing rather than half of it. The reply still goes out —
				// withholding it stalls the enter-game flow, which is a worse failure than one
				// unsaved options change.
				logger.warn("0x4110 from character {} was {} bytes, expected at least {}; options "
					+ "not stored.", charaId, ctx.packet().getPayload().readableBytes(),
					GameplaySettingsReader.PAYLOAD_SIZE);
			}
		}

		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(UPDATE_SETTINGS_RESULT, buffer));
	}

	/**
	 * Answers the end-of-round results request ({@link #GET_POST_GAME_INFO}) with the character's
	 * real rank and experience — both references source exactly these two fields from storage and
	 * fabricate the rest, so a populated card here is at parity with them. The skill experience
	 * repeats what the {@code 0x4125} catalogue advertises (skill progression does not exist), and
	 * grade points mirror experience, as in both references.
	 */
	private void postGameInfo(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null && account.getCurrentCharaId() != null
			? account.getCurrentCharaId() : 0L;

		// The WORN TITLE, not chara.rank — this byte lands in the SAME slot as 0x4122 wire 0xef
		// (charBlock+0x1EA5, via this parser at 0xD3CA30). Sending rank here would reset the
		// scorecard's animal-rank badge to nothing after the first match, undoing what the connect
		// burst set. Both packets must carry the same value.
		var wornTitle = 0;
		var experience = 0;
		if (account != null && charaId != 0L) {
			var chara = characterService.get(charaId).orElse(null);
			if (chara != null) {
				wornTitle = awardService.wornTitle(charaId);
				experience = chara.getExperience();
			}
		}

		// The same records 0x4125 sent at connect, from the same table: this parser writes into the
		// identical array and does not clear it first, so disagreeing here would half-update the
		// client's view of what the player owns.
		var skills = charaId == 0L ? List.<CharaSkill>of() : characterService.getSkills(charaId);
		var clan = charaId == 0L ? ClanService.Membership.NONE : clanService.membershipOf(charaId);

		var buffer = ctx.buffer(POST_GAME_INFO_FIXED + skills.size() * SKILL_RECORD_SIZE);
		buffer.writeInt(GameError.NONE.result()) // result
			.writeByte(wornTitle)
			.writeInt(experience)
			.writeByte(0)
			.writeInt(skills.size()); // skill count
		for (var skill : skills) {
			buffer.writeByte(skill.getSkillId())
				.writeShort(skill.getExperience())
				.writeByte(skill.getFlag());
		}
		buffer.writeInt(0)
			.writeInt(experience) // grade points mirror experience in both references
			.writeInt(0xffffff)
			// The same clan record 0x4122 carries, and this parser writes the same profile slots,
			// so disagreeing between the two would half-update the client's view.
			.writeInt((int) clan.id())
			.writeShort(0)        // privilege mask (profile+6838); nothing grants privileges yet
			.writeByte(clan.state())
			// The EMBLEM FLAG, and the same defect the worn title above had, three lines apart. This
			// parser writes the same profile slot as 0x4122 (+6872) and does not clear it first, so a
			// hardcoded 0 here CLEARS an emblem the connect burst had already switched on — the player
			// starts the session with their emblem and loses it the moment the first round ends.
			//
			// Sending 0 is not "no picture", it is "never ask": the fetch is skipped and the emblem is
			// silently absent (0x905A90 tests this byte for 3, after 0x905A8C checks the membership
			// state). So it must agree with 0x4122 and 0x4602, and it is computed the same way in all
			// three. Safe to set here: 0x4b48/0x4b4a are served by ClanGameController, which is
			// registered on the game servers as well as the lobby.
			.writeByte(clan.id() == 0 ? 0
				: (clanService.emblemFlagOf(clan.id()) == ClanService.EMBLEM_ON_DISPLAY
					? ClanService.EMBLEM_ON_DISPLAY : 0))
			.writeInt((int) charaId)
			.writeByte(0);

		ctx.write(new GamePacket(POST_GAME_INFO_RESULT, buffer));
	}

	/**
	 * Persists an in-game host-settings edit ({@link #IN_GAME_INFO}, {@code 0x43c0}): the host
	 * changing game name, comment and password lock from the in-match menu. The payload arrives
	 * Blowfish-decrypted and carries the same header as the {@code 0x4310} push — name[16] at 0x00,
	 * comment[128] at 0x10, a password-enabled byte at 0x90, password[16] at 0x91 — so we parse
	 * those and update the game this character hosts, then ack {@code 0x43c1 {result=0}}.
	 */
	/**
	 * {@code 0x43c0} wire {@code 0xA1}: the host stance, the screen's "Conditions" row.
	 * <p>
	 * [READ] Builder {@code 0xD4161C} emits exactly five values — name[16], comment[128], the
	 * password flag, password[16], then a {@code u8} from settings {@code +846}. The edit screen
	 * confirms it: it memsets a 968-byte stack copy and fills only those five, one per editable row.
	 */
	private static final int IN_GAME_STANCE = 0xA1;

	private void editHostSettings(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(IN_GAME_INFO_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId != null) {
			var payload = ctx.packet().getPayload();
			var base = payload.readerIndex();
			var bytes = new byte[payload.readableBytes()];
			payload.getBytes(base, bytes);

			var name = readField(bytes, 0x00, 16);
			var comment = readField(bytes, 0x10, 128);
			var passwordEnabled = bytes.length > 0x90 && bytes[0x90] != 0;
			var password = passwordEnabled ? readField(bytes, 0x91, 16) : null;

			// CONDITIONS — the host stance, and the field that would not save. This packet carries
			// exactly four editable values and we were reading three; byte 0xA1 was read by nobody,
			// so the client re-read the stale value on every refresh and the edit appeared to be
			// ignored.
			//
			// Note the offset is NOT the one 0x4310 uses. 0x43c0 is a strict subset of the same
			// 968-byte settings struct — name, comment, password flag, password, stance — and stops
			// there, so stance lands at 0xA1 here and at 0xF6 in 0x4310, where 0xA1 means
			// `dedicated`. Reusing the other packet's offset would have written the wrong field.
			var stance = bytes.length > IN_GAME_STANCE ? bytes[IN_GAME_STANCE] & 0xff : 0;

			gameService.updateGameSettings(lobbyId, charaId, name, comment, password, stance);
			logger.info("Character {} edited its game in place: name='{}', password={}, stance={}.",
				charaId, name, passwordEnabled ? "set" : "none", stance);
		}

		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(IN_GAME_INFO_RESULT, buffer));
	}

	/** Reads a fixed-width, NUL-terminated ISO-8859-1 field from a decoded payload. */
	private static String readField(byte[] bytes, int offset, int max) {
		if (offset >= bytes.length) {
			return "";
		}
		var limit = Math.min(offset + max, bytes.length);
		var end = offset;
		while (end < limit && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, offset, end - offset, StandardCharsets.ISO_8859_1);
	}

	/**
	 * Returns the host's saved settings, or an empty block when there are none.
	 * <p>
	 * The populated path re-maps the raw {@code 0x4310} blob the character pushed last time into
	 * the reply shape — see {@link mgo2server.game.HostSettingsReply} for the layout and its
	 * tier-4 provenance. A character that never pushed settings (or pushed a short blob) gets 128
	 * zero bytes. Provenance of that empty block, precisely: mgo2-server's empty path plus our own
	 * live verification (Create Game opens on it) — <b>not</b> Nomad, which has no empty path at
	 * all; it materialises a default settings blob and always answers populated.
	 */
	private void getHostSettings(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			// THE EMPTY BLOCK, NOT AN ERROR WORD. 0x4305 has no result field — it is the 128-byte
			// empty or 348-byte populated settings block — and it is the one payload we Blowfish
			// ENCRYPT outbound. A 4-byte reply here handed the Create Game screen four bytes of
			// ciphertext followed by stale receive buffer, parsed as saved host settings, because
			// the client's read primitives bound-check the 1023-byte buffer rather than the payload.
			//
			// The empty path is the correct refusal and already exists below: a character that never
			// pushed settings gets 128 zeros and the screen opens on defaults.
			writeEmptyHostSettings(ctx);
			return;
		}

		var charaId = account.getCurrentCharaId();
		var blob = charaId != null
			? gameService.getHostSettingsBlob(charaId, lobbySubtype).orElse(null)
			: null;

		if (mgo2server.game.HostSettingsReply.canWrite(blob)) {
			var buffer = ctx.buffer(mgo2server.game.HostSettingsReply.SIZE);
			mgo2server.game.HostSettingsReply.write(buffer, blob);
			ctx.write(new GamePacket(HOST_SETTINGS_RESULT, buffer));
			return;
		}

		writeEmptyHostSettings(ctx);
	}

	/**
	 * The 128-byte empty settings block — the only correct "nothing to pre-fill" answer.
	 * <p>
	 * {@code 0x4305} carries no result word, so there is no error to send here: a short reply is
	 * read as a settings block regardless, out of whatever the receive buffer held. The empty block
	 * is what the Create Game screen opens on when a character has never hosted.
	 */
	private void writeEmptyHostSettings(GameControllerContext ctx) {
		var buffer = ctx.buffer(HOST_SETTINGS_SIZE);
		buffer.writeZero(HOST_SETTINGS_SIZE);
		ctx.write(new GamePacket(HOST_SETTINGS_RESULT, buffer));
	}

	/**
	 * Accepts the host's configured settings. The reply carries no payload; the client only waits
	 * for the acknowledgement before moving on to create the game.
	 * <p>
	 * The blob is kept three ways: on the connection for the imminent create-game, parsed into
	 * the game row's columns by {@code applyHostSettings}, and decoded into columns per (character, lobby
	 * subtype) so {@link #getHostSettings} can pre-fill the Create Game screen next session.
	 */
	private void checkHostSettings(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
			return;
		}

		// The hosting half of the ban, and it belongs HERE rather than on create. 0x4311 is where
		// the client discriminates result codes; 0x4317's test has zero spans, so every code there
		// renders the same generic "unable to create game" and the ban would be invisible. Refusing
		// at the settings check also stops the create before it starts. [ELF 2026-07-29]
		if (account.isBannedAt(java.time.OffsetDateTime.now())) {
			logger.info("Host settings refused: account {} is banned until {}.",
				account.getId(), account.getBannedUntil());
			ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.GAME_BANNED_FROM_PLAY);
			return;
		}

		// The blob begins with the 16-byte game name at offset 0 — there is NO leading u32 "type".
		// (An earlier reading mistook name[0:4] for a type: PROTOCOL.md recorded 1399153006 =
		// 0x5365616E = "Sean", a game name read as an int.) We parse only round 0 of the rotation
		// for now — the rule/map/flags the client shows in the browser — and hand it to create-game.
		var payload = ctx.packet().getPayload();
		var base = payload.readerIndex();
		var bytes = new byte[payload.readableBytes()];
		payload.getBytes(base, bytes);

		// AN EMPTY ROTATION IS NOT A GAME. Confirm the host picked at least one rule and stage
		// before letting the create proceed: with every triple zeroed the client sails past the
		// Create Game screen and hangs on an infinite load, because there is no round to start.
		//
		// The client is meant to catch this itself — it ships the sentence for it, dialog 2944
		// "Game rules and map have not been set. / Please set game rules and map." — but the check
		// does not fire, and 2 of our 214 stored 0x4310 captures carry a completely empty rotation.
		// So it has been reaching us and we have been accepting it.
		//
		// The test is map, not rule. Rule 0 is Deathmatch and perfectly valid; map 0 is no stage at
		// all — across those 214 captures the maps actually used are 1, 2, 3, 4, 7 and 12, and a
		// zero map never once appears beside a real entry. This also matches the rotation's own
		// terminator convention, where rule == 0 && map == 0 ends the list.
		if (!hasAnyRound(bytes)) {
			logger.warn("Host settings refused: account {} sent an empty rotation — no rule or stage"
				+ " is selected in any of the {} rounds. Accepting it creates a game that cannot"
				+ " start and hangs the client on an infinite load.",
				account.getId(), ROTATION_ROUNDS);
			ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.GENERAL);
			return;
		}

		ctx.connection().setHostSettings(bytes);

		// Decode and persist per (character, subtype) so 0x4304 pre-fills next session. The
		// reference skips persisting clan-room rotations (rule 11); we have no clan rooms, so
		// nothing is special-cased. Stored raw: the parsed-column path stays applyHostSettings's.
		var charaId = account.getCurrentCharaId();
		if (charaId != null) {
			gameService.saveHostSettingsBlob(charaId, lobbySubtype, bytes);
		}

		if (bytes.length >= ROTATION_OFFSET + 3) {
			logger.info("Host settings from account {}: round 0 rule={} map={} flags={} ({} bytes).",
				account.getId(), bytes[ROTATION_OFFSET] & 0xff, bytes[ROTATION_OFFSET + 1] & 0xff,
				bytes[ROTATION_OFFSET + 2] & 0xff, bytes.length);
		} else {
			logger.warn("Host settings from account {}: {} bytes, too short to read the rotation.",
				account.getId(), bytes.length);
		}

		// Explicit 4-byte zero, not an empty payload (corrected 2026-07-26). The parser reads a
		// u32 unconditionally and hands it to the waiting request slot; an empty payload only
		// "worked" because the read primitives bound-check the 1023-byte receive buffer rather
		// than the payload length, so the client consumed four bytes of stale buffer as its
		// result code. See dev/proto/outbound/mgo2_cmd_4311_s2c.ksy.
		ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.NONE);
	}

	/**
	 * Whether a {@code 0x4310} blob selects at least one round.
	 *
	 * <p>A round counts when its <b>map</b> is nonzero. Rule 0 is Deathmatch and is a real choice,
	 * so a zero rule proves nothing; map 0 is not a stage this disc ships. A blob too short to hold
	 * the rotation is treated as having no rounds — it cannot describe a startable game either way.
	 */
	static boolean hasAnyRound(byte[] blob) {
		if (blob.length < ROTATION_OFFSET + ROTATION_ROUNDS * 3) {
			return false;
		}
		for (var round = 0; round < ROTATION_ROUNDS; round++) {
			if (blob[ROTATION_OFFSET + round * 3 + 1] != 0) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Stores a host-rating vote ({@link #RATE_HOST}) and acknowledges.
	 * <p>
	 * The vote comes from a PLAYER, not the host, so the game is resolved by membership
	 * ({@code gameContaining}) rather than by {@code hostedGame}. The rating applies to whoever
	 * hosts that game. Out-of-range values are dropped rather than clamped — the client will not
	 * send them, so one that arrives means the reading is wrong and should be visible.
	 */
	private void rateHost(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var account = ctx.connection().account();
		var voterId = account != null ? account.getCurrentCharaId() : null;

		if (voterId != null && payload.readableBytes() >= Integer.BYTES) {
			var rating = payload.readInt();
			var game = gameService.gameContaining(voterId).orElse(null);
			if (rating < MIN_HOST_RATING || rating > MAX_HOST_RATING) {
				logger.warn("0x43c4 host rating {} is outside 1..5 — dropped. The ELF rejects "
					+ "these too, so this means our reading of the command is wrong.", rating);
			} else if (game == null) {
				logger.warn("0x43c4 host rating {} from character {}, who is in no game; dropped.",
					rating, voterId);
			} else if (gameService.recordHostVote(game.getId(), game.getHostCharaId(), voterId,
					rating)) {
				logger.info("Game {}: character {} rated host {} at {} stars.",
					game.getId(), voterId, game.getHostCharaId(), rating);
			}
		}

		acknowledgeResult(ctx);
	}

	/**
	 * Stores one player's per-weapon round tallies ({@code 0x43a2}) and acknowledges.
	 * <p>
	 * Layout is {@code {u32 chara_id, u32 count, count × {u8 weapon, u16 kills, u16 headshots,
	 * u16 faints}}} (dev/proto/inbound/mgo2_cmd_43a2_c2s.ksy). The host sends one of these per scoring player,
	 * immediately after that player's {@code 0x4390}; players with no entries are skipped
	 * entirely, so a zero count is normal.
	 * <p>
	 * <b>The ack is unconditional.</b> An unanswered command stalls the client into
	 * {@code FFFFFF60}, so a malformed payload is logged and still acknowledged — losing a weapon
	 * tally is a stat gap, losing the ack is a hung screen.
	 */
	private void roundEnd(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		// Same reporting-model tripwire as 0x4390: 0x43a2 rides immediately behind it from the
		// same host connection, so a non-host one is the same deviation and wants the same noise.
		if (game == null) {
			logger.warn("0x43a2 from a NON-HOST connection — reporting-model deviation. Payload: {}",
				ByteBufUtil.hexDump(payload));
		}

		try {
			if (game != null && payload.readableBytes() >= 2 * Integer.BYTES) {
				var charaId = payload.readUnsignedInt();
				var count = payload.readUnsignedInt();

				// The ELF's caller caps entries at 50. A larger count is a mis-parse rather than
				// data, so drop the frame instead of storing whatever the loop happens to read.
				if (count > MAX_WEAPON_TALLIES) {
					logger.warn("Game {}: 0x43a2 for character {} declared {} weapon entries, past "
						+ "the client's own cap of {}; dropped as a mis-parse.",
						game.getId(), charaId, count, MAX_WEAPON_TALLIES);
				} else if (payload.readableBytes() < count * WEAPON_TALLY_BYTES) {
					logger.warn("Game {}: 0x43a2 for character {} declared {} weapon entries but "
						+ "carries {} bytes; dropped rather than stored in part.",
						game.getId(), charaId, count, payload.readableBytes());
				} else if (!playedThisRound(game, charaId)) {
					// Mirrors the 0x4390 participation check. Without it a host could attribute
					// weapon tallies to any character id it liked.
					logger.warn("Game {}: weapon tallies for character {} who neither is in the "
						+ "game nor played the round; dropped.", game.getId(), charaId);
				} else {
					var tallies = new java.util.ArrayList<GameService.WeaponTally>();
					for (var i = 0; i < count; i++) {
						tallies.add(new GameService.WeaponTally(payload.readUnsignedByte(),
							payload.readUnsignedShort(), payload.readUnsignedShort(),
							payload.readUnsignedShort()));
					}
					gameService.insertWeaponTallies(game.getId(), charaId, tallies);
				}
			}
		}
		catch (RuntimeException e) {
			logger.warn("0x43a2 weapon tallies could not be stored; acknowledging anyway.", e);
		}
		acknowledgeResult(ctx);
	}

	/** The 0x4390 participation test, reused: in the game now, or named in the round snapshot. */
	private boolean playedThisRound(mgo2server.common.model.Game game, long charaId) {
		var inGame = gameService.getPlayers(game.getId(), game.getHostCharaId()).stream()
			.anyMatch(player -> player.charaId() == charaId);
		return inGame || gameService.playedLastRound(game.getId(), charaId);
	}

	/**
	 * Acknowledges a host-admin command with a {@code result(0)} word, the four-byte "OK" both
	 * references send for the round-lifecycle commands. Their parsers read a result and block on
	 * it.
	 */
	private void acknowledgeResult(GameControllerContext ctx) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(ctx.packet().getCommand() + 1, buffer));
	}

	/** The game this character hosts here, or null — the guard every in-match command shares. */
	private mgo2server.common.model.Game hostedGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null ? account.getCurrentCharaId() : null;
		if (charaId == null) {
			return null;
		}
		return gameService.getHostedGame(lobbyId, charaId).orElse(null);
	}

	/**
	 * The host cycling the rotation while staging ({@link #SET_GAME}). Request is a single byte:
	 * the index into the rotation pushed via {@code 0x4310} (reference layout — Nomad reads one
	 * byte and stores it as {@code currentGame}). The rule/map/flags the index resolves to come
	 * from the game's stored rotation columns, so the browser reflects the round being staged.
	 */
	private void setGame(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		if (game != null && payload.readableBytes() >= 1) {
			var index = payload.readByte() & 0xff;
			// The rotation is three typed arrays now, not an offset into a stored blob. The
			// bounds check that used to guard a raw index into bytes is the arrays' own length.
			//
			// 16, not 15, corrected 2026-07-26: the 0x4310 writer emits sixteen triples
			// (cmpdi cr7,r27,16 at 0xd44958) and the 0x4305/0x4313 parsers read sixteen. At 15 a
			// host advancing to its last rotation entry was logged as "no stored rotation entry"
			// and the browser kept showing the previous round.
			var rules = game.getRotationRules();
			var maps = game.getRotationMaps();
			var flags = game.getRotationFlags();
			if (index < ROTATION_ROUNDS && rules != null && index < rules.length) {
				gameService.setCurrentGame(game.getId(), index,
					rules[index] & 0xff, maps[index] & 0xff, flags[index] & 0xff);
				logger.info("Game {} advanced to rotation entry {} (rule={} map={}).",
					game.getId(), index, rules[index] & 0xff, maps[index] & 0xff);
			} else {
				logger.warn("Game {}: set-game index {} has no stored rotation entry; ignoring.",
					game.getId(), index);
			}
		}

		acknowledgeResult(ctx);
	}

	/**
	 * The host's latency report ({@link #UPDATE_PINGS}): a u32 of its own ping, then
	 * {@code {u32 chara id, u32 ping}} pairs for everyone in its game (reference layout; a zero
	 * id is skipped, as Nomad does). Applied to the game row and the roster so the browser and
	 * player list show real latencies. Also the game's heartbeat in the reference; we track
	 * {@code last_update} the same way without yet reaping on it.
	 * <p>
	 * The reply stays the live-verified empty {@code 0x4399} — reshaping a working ack on
	 * reference evidence is how this project has been burned before.
	 */
	private void updatePings(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		if (game != null && payload.readableBytes() >= Integer.BYTES) {
			var hostPing = payload.readInt();
			var pings = new java.util.HashMap<Long, Integer>();
			while (payload.readableBytes() >= 2 * Integer.BYTES) {
				var charaId = payload.readInt();
				var ping = payload.readInt();
				if (charaId != 0) {
					pings.put((long) charaId, ping);
				}
			}
			gameService.updatePings(game.getId(), hostPing, pings);
		}

		// Explicit 4-byte zero, not an empty payload (corrected 2026-07-26). The parser reads a
		// u32 unconditionally and hands it to the waiting request slot; an empty payload only
		// "worked" because the read primitives bound-check the 1023-byte receive buffer rather
		// than the payload length, so the client consumed four bytes of stale buffer as its
		// result code. See dev/proto/outbound/mgo2_cmd_4399_s2c.ksy.
		ctx.write(UPDATE_PINGS_RESULT, GameError.NONE);
	}

	/**
	 * Host presses Start ({@link #START_ROUND}). The request carries nothing the reference reads;
	 * the work is the roster snapshot — everyone in the game now "played this round", which is
	 * what {@link #updateStats} checks before applying a stat report to a character.
	 */
	private void startRound(GameControllerContext ctx) {
		if (gradedInstructor(ctx)) {
			return;
		}

		var game = hostedGame(ctx);
		if (game != null) {
			gameService.markRoundPlayers(game.getId());
			logger.info("Game {} started a round.", game.getId());
		}
		// {u32 result, u32 token}: result 0 lets the client proceed. The second word must be ZERO.
		//
		// It is not a round handle. The parser (0xD3FEAC) stores a nonzero second word into
		// profile+0x32F8 (0xD3FF6C, guarded by `!= 0`), and that field has exactly three accesses
		// in the whole binary: its initialiser (0x414898), that write, and one read at 0x8842AC —
		// the packer that builds a player's join announcement, where it becomes struct+12, then
		// replicated player variable 352, then P2P opcode 0x24 to every peer. On the receiving
		// client it lands in G->0x1C0 and gates the instructor recognition prompt at 0xA359A4:
		// non-zero means "an instructor is already saved", and the prompt is skipped.
		//
		// So sending the game id here permanently stamped every character who ever started a round
		// or graduated, and their console then told every future training host to suppress the
		// prompt. Zero leaves the field untouched, which is what we want; the client never reads
		// the token for anything else.
		var buffer = ctx.buffer(2 * Integer.BYTES);
		buffer.writeInt(GameError.NONE.result()).writeInt(NO_INSTRUCTOR_TOKEN);
		ctx.write(new GamePacket(START_ROUND_RESULT, buffer));
	}

	/**
	 * The same id, sent by a <em>student</em> in a combat-training lobby, is the instructor review
	 * that ends a graduation — not a round start.
	 * <p>
	 * Evidence, three live sessions with the star rating as the only variable: 5, 3 and 1 stars
	 * produced {@code 00000005}, {@code 00000003} and {@code 00000001} in the u32, with the
	 * trailing byte constant at {@code 0x21}. Connection attribution puts it on the student's
	 * socket, while the host's own packets around it ({@code 0x43a6}, {@code 0x43c0},
	 * {@code 0x4390}, {@code 0x4342}) arrive on the other. The student then checks its mailbox
	 * within seconds, which is why the award has to be granted here and now rather than deferred.
	 * <p>
	 * The distinction is narrow on purpose: only a subtype-8 lobby, and only from someone who is
	 * not the game's host. Anything else falls through to the round start, because a single caller
	 * in the client builds both and this id may legitimately do both jobs.
	 *
	 * @return whether this was a review, and has been answered
	 */
	private boolean gradedInstructor(GameControllerContext ctx) {
		if (!GRADUATION_ENABLED || lobbySubtype != COMBAT_TRAINING_SUBTYPE) {
			return false;
		}

		var account = ctx.connection().account();
		var studentId = account != null ? account.getCurrentCharaId() : null;
		if (studentId == null) {
			return false;
		}

		var game = gameService.gameContaining(studentId).orElse(null);
		if (game == null || game.getHostCharaId() == studentId) {
			return false;
		}

		// {u32 rating, u8 answer}: both are bytes of the same dialog result buffer in the client
		// (0xA35B0C/0xA35B14 -> 0xA36160/0xA36164), so the rating arrives widened into a u32.
		var payload = ctx.packet().getPayload();
		var rating = payload.readableBytes() >= Integer.BYTES
			? payload.getInt(payload.readerIndex()) : 0;
		var answer = payload.readableBytes() > Integer.BYTES
			? payload.getUnsignedByte(payload.readerIndex() + Integer.BYTES) : NO_ANSWER;
		var recognised = answer == RECOGNISED_ANSWER;

		var graduation = characterService.recordGraduation(studentId, game.getHostCharaId(),
			rating, recognised, answer);
		logger.info("Character {} reviewed {} — rating {}, answer 0x{} ({}); {}.",
			studentId, game.getHostCharaId(), rating, Integer.toHexString(answer),
			recognised ? "recognised" : "not recognised",
			recognised
				? "generation " + graduation.generation() + ", skill follows on the stats report"
				: "rating recorded only");

		// Answered exactly as a round start is: the client is waiting on the same reply shape — and
		// with the same zero second word, for the same reason. See startRound.
		var buffer = ctx.buffer(2 * Integer.BYTES);
		buffer.writeInt(GameError.NONE.result()).writeInt(NO_INSTRUCTOR_TOKEN);
		ctx.write(new GamePacket(START_ROUND_RESULT, buffer));
		return true;
	}

	/**
	 * <b>The host quitting</b> ({@link #HOST_MIGRATION}) — not a player choosing to hand the game on.
	 *
	 * <p>[ELF 2026-07-29] There is exactly one builder, `0xD40F28`, called from the host's leave-game
	 * routine `0x273C38`. Its three callers are UI leave handlers that first ask {@code 0x26E958}
	 * ("am I the host") and branch: <b>host sends this, everyone else sends {@code 0x4380}</b>. They
	 * are mutually exclusive, so a migrating host does not also send a quit.
	 *
	 * <p><b>The successor is elected by the client, silently.</b> `0x273CF4`-`0x273D48` walks the
	 * 24-slot roster reading per-player property 343 — a 0-100 connection-quality score refreshed
	 * round-robin — and keeps the maximum. A laxer second pass drops the liveness check if the strict
	 * one finds nobody. The player is never asked and never sees a prompt.
	 *
	 * <p>Payload is {@code {sender's own chara id, elected successor's chara id}}. The first word is
	 * ignored here because the session already identifies the sender; it is the sender's id read from
	 * {@code session+0x57D8}, not a "current host" field.
	 *
	 * <p><b>The old name was wrong and cost real time.</b> As {@code PASS_HOST} with a log line
	 * reading "host passed from X to Y", this looked twice like a player performing a deliberate
	 * transfer — once in an automatch game and once in a Free Battle game — and was twice explained
	 * away as the client asking on the player's behalf. It is simply what quitting looks like. The
	 * reading came from a reference server, and its own comment admitted the first field was "unused,
	 * as in the reference".
	 *
	 * <p>The game is re-keyed to the target and the sender leaves the roster; joins pick up the new
	 * host's endpoint automatically because {@code 0x4320} reads {@code chara_connection} by the
	 * game's host id at join time.
	 */
	private void hostMigration(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		if (game != null && payload.readableBytes() >= 2 * Integer.BYTES) {
			payload.readInt(); // the sender's own chara id; the session already proves it
			long targetId = payload.readInt();
			var isPlayer = gameService.getPlayers(game.getId(), game.getHostCharaId()).stream()
				.anyMatch(player -> player.charaId() == targetId);
			if (isPlayer && targetId != game.getHostCharaId()) {
				gameService.migrateHost(game.getId(), game.getHostCharaId(), targetId);
				logger.info("Game {}: host {} quit; the client elected character {} as successor.",
					game.getId(), game.getHostCharaId(), targetId);
			} else {
				// THE SUCCESSOR IS ALREADY GONE. The client elects by connection score and its
				// fallback pass drops the liveness check, so it can nominate a roster entry that
				// has since left. Dropping the command here left the game keyed to a host who had
				// just quit — a ghost row the browser still lists and nobody can join.
				//
				// The sender has left either way, so treat it as the plain quit it is.
				logger.info("Game {}: host {} quit and its elected successor {} is no longer in the"
					+ " game; tearing down as an ordinary quit.",
					game.getId(), game.getHostCharaId(), targetId);
				gameService.deleteGame(game.getId());
			}
		}

		acknowledgeResult(ctx);
	}

	/**
	 * End-of-round stat submission from the host ({@link #UPDATE_STATS}), one player per packet.
	 * <p>
	 * The 167-byte frame layout is capture-confirmed and documented in PROTOCOL.md
	 * (`0x4390 — update stats`). The report is applied only when the target verifiably played: a
	 * current roster member, or a member of the round snapshot taken at round start — the
	 * snapshot is what keeps a report for a player who <em>quit mid-round</em> applicable.
	 * Experience (absolute total at {@code 0x27}) goes to the account pool; the whole decoded
	 * frame is stored as a {@code round_report} row, from which stats and history screens derive.
	 * The aborted byte at {@code 0xB7} is Nomad's longer build layout, read only when the report
	 * reaches it (this client's 167-byte frame does not).
	 */
	private void updateStats(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();
		var readable = payload.readableBytes();

		// Reporting-model tripwire (PROTOCOL.md, "two established truths"): only hosts have
		// ever sent reports. A non-host report means the model needs revisiting — flag it
		// loudly, then ack as before.
		if (game == null) {
			logger.warn("0x4390 from a NON-HOST connection — reporting-model deviation. Payload: {}",
				ByteBufUtil.hexDump(payload));
		}

		// This client sends 167-byte reports (observed live 2026-07-22: exp at 0x27 matched the
		// account total to the byte, and 0x23 held seconds-in-game), so Nomad's 0xB8 minimum was
		// a different build's; its aborted byte at 0xB7 is read only when the report reaches it.
		if (game != null && readable >= 0x2B) {
			var base = payload.readerIndex();
			long targetId = payload.getInt(base);
			var experience = payload.getInt(base + 0x27);
			var aborted = readable > 0xB7 && payload.getByte(base + 0xB7) == 1;

			// Current members are accepted unconditionally (the reference's first branch); the
			// round snapshot rescues a target who already left the game mid-round.
			var inGame = gameService.getPlayers(game.getId(), game.getHostCharaId()).stream()
				.anyMatch(player -> player.charaId() == targetId);
			var played = inGame || gameService.playedLastRound(game.getId(), targetId);
			if (played) {
				gameService.applyRoundExperience(targetId, experience, aborted);
				// The whole frame is stored, one round_report row per report — every stats and
				// history screen derives from these rows. Struct A is the 15 s16 counters at
				// 0x05 + 2*i; the capture-confirmed labels (kills A0, deaths A1, score A3, stun
				// A4, headshots A6, headshot-deaths A7) live at fixed indices, the rest are kept
				// by offset rather than guessed. Struct B (58 s16 at 0x2f) and the trailing word
				// only exist in the long form; the short ~51-byte form ends after 0x2b's zero.
				var structA = new short[15];
				for (var i = 0; i < structA.length; i++) {
					structA[i] = payload.getShort(base + 0x05 + 2 * i);
				}
				var detailPresent = readable >= 0x2F ? payload.getInt(base + 0x2B) : 0;
				var detail = new short[readable >= 0xA3 ? 58 : 0];
				for (var i = 0; i < detail.length; i++) {
					detail[i] = payload.getShort(base + 0x2F + 2 * i);
				}
				long trailing = 0;
				if (readable >= 0xA7) {
					trailing = payload.getInt(base + 0xA3) & 0xFFFFFFFFL;
				} else if (detail.length == 0 && readable >= 0x33) {
					trailing = payload.getInt(base + 0x2F) & 0xFFFFFFFFL;
				}
				// Second tripwire: the trailing word has been 0 in every observed report; a
				// nonzero value would be the in-frame identifier the model says does not exist.
				if (trailing != 0) {
					logger.warn("0x4390 trailing word nonzero ({}) — possible identifier echo, "
						+ "reporting-model deviation.", trailing);
				}
				gameService.insertRoundReport(new GameService.RoundReport(
					game.getId(), game.getHostCharaId(), targetId,
					payload.getByte(base + 0x04) & 0xFF, structA,
					// Wire 0x23 is {u16 team-win flag, u16 seconds}, not a u32. The split is from
					// OBSERVED.md; the high half's meaning was corrected 2026-07-27 (V41) — it is
					// a TEAM WIN flag, not the team slot index it was read as for four days.
					payload.getUnsignedShort(base + 0x23), payload.getUnsignedShort(base + 0x25),
					experience & 0xFFFFFFFFL,
					detailPresent & 0xFFFFFFFFL, detail, trailing, aborted,
					// Stamped from this instance's configuration: the game row is deleted on
					// teardown, so the report cannot be joined back to its lobby afterwards.
					lobbySubtype));
				logger.info("Game {}: stats for character {} — {} kills, {} deaths, score {}, "
						+ "experience {}{}{}.",
					game.getId(), targetId, structA[0], structA[1], structA[3],
					experience, aborted ? " (aborted round)" : "",
					inGame ? "" : " (left mid-round; accepted from the round snapshot)");

				// A recognised graduation earns the instructor skill here rather than at 0x43c8:
				// the host reports every player as they leave, combat training included, so the
				// award rides the session ending and a missed one is picked up next report. The
				// letter still beats the student's mailbox fetch — leaving sends 0x4390 first.
				if (characterService.awardPendingInstructorSkill(targetId)) {
					logger.info("Character {} awarded the instructor skill and its announcement.",
						targetId);
				}
			} else {
				logger.warn("Game {}: stat report for character {} who neither is in the game nor "
					+ "played the round; dropped.", game.getId(), targetId);
			}
		} else if (game != null) {
			logger.warn("Game {}: stat report of {} bytes, shorter than the reference layout; dropped.",
				game.getId(), readable);
		}

		acknowledgeResult(ctx);
	}

	/**
	 * The host's peer-registration round-trips: player connected ({@code 0x4340}), disconnected
	 * ({@code 0x4342}), and the two follow-up phases ({@code 0x4344}, {@code 0x4346}) its per-peer
	 * P2P state machine (ELF {@code 0x276F60}) issues while establishing a peer.
	 * <p>
	 * All four share one reply shape and one trap: the client's parsers ({@code 0xD42D58},
	 * {@code 0xD42C4C}, {@code 0xD42B40}, {@code 0xD42A34}) each read a u32 result <em>and a second
	 * u32 key</em>, and bail the whole handler if either read is short — only registering the peer
	 * (state → 2, cancelling the FSM's 30s {@code 0x7530} timeout) after both reads. An empty ack
	 * therefore stalls the FSM in that phase until it times out and disconnects the peer
	 * ({@code 0x4342}) — the ~28s connect/retry loop observed against two clients. Replying
	 * {@code result(0)} then echoing the key the host sent lets each phase complete. The second u32
	 * must be the host's own key (used to index its peer table), which is the leading u32 of the
	 * request — so echoing the request's first word is correct for every phase.
	 */
	private void playerConnection(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		var value = payload.readableBytes() >= Integer.BYTES ? payload.readInt() : 0;

		var buffer = ctx.buffer(2 * Integer.BYTES);
		buffer.writeInt(GameError.NONE.result())
			.writeInt(value);
		ctx.write(new GamePacket(ctx.packet().getCommand() + 1, buffer));
	}

	/**
	 * Leaves a game, and tears it down if the leaver was hosting it.
	 * <p>
	 * Without a reply the client sits on a black screen after Quit Game — it has already left as
	 * far as it is concerned and is waiting for the server to agree.
	 * <p>
	 * A host leaving deletes the game, which matches both references: the match cannot continue
	 * without the peer everyone else connects to. Players other than the host are not tracked, so
	 * for them this is only an acknowledgement.
	 */
	private void quitGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(QUIT_GAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		tearDownCharacter(account.getCurrentCharaId(), "on quit");
		// Explicit 4-byte zero, not an empty payload (corrected 2026-07-26). The parser reads a
		// u32 unconditionally and hands it to the waiting request slot; an empty payload only
		// "worked" because the read primitives bound-check the 1023-byte receive buffer rather
		// than the payload length, so the client consumed four bytes of stale buffer as its
		// result code. See dev/proto/outbound/mgo2_cmd_4381_s2c.ksy.
		ctx.write(QUIT_GAME_RESULT, GameError.NONE);
	}

	/**
	 * Tears down whatever a character was holding in this lobby: any game it hosts is deleted (its
	 * {@code game_player} rows cascade), and the character is removed from any game it had merely
	 * joined. Shared by the explicit Quit Game command and {@link #onDisconnect}.
	 */
	private void tearDownCharacter(Long charaId, String reason) {
		if (charaId == null) {
			return;
		}
		for (var game : gameService.getGames(lobbyId)) {
			if (game.getHostCharaId() == charaId) {
				logger.info("Character {} left game {} ({}), which it hosted; removing it.",
					charaId, game.getId(), reason);
				gameService.deleteGame(game.getId());
			}
		}
		gameService.removePlayerFromGames(charaId);
	}

	/**
	 * A dropped connection sends no Quit Game, so the same teardown runs here — otherwise a host that
	 * crashes or loses the network leaves a ghost game in the browser until the next startup purge.
	 * <p>
	 * <b>Suspect this first if hosting breaks</b> (the host loses its controls mid-session): this
	 * client reconnects periodically, and if a reconnect closes an authenticated socket it lands here
	 * and would delete a live game. The teardown log says "on disconnect" here versus "on quit" for
	 * the explicit {@code 0x4380} path, so the two are distinguishable in the log rather than guessed
	 * at. If it turns out to fire on ordinary reconnects, this needs a reconnect grace period instead
	 * of an immediate delete.
	 */
	@Override
	public void onDisconnect(GameConnection connection) {
		var account = connection.account();
		if (account != null) {
			tearDownCharacter(account.getCurrentCharaId(), "on disconnect");
		}
	}

	private void createGame(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		var chara = characterService.get(charaId).orElse(null);
		if (chara == null) {
			ctx.write(CREATE_GAME_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		// Defaults are named after the host, which is what a player sees if they never edit them.
		var settings = gameService.getOrCreateHostSettings(charaId, lobbySubtype, chara.getName());

		long gameId;
		try {
			gameId = gameService.createGame(lobbyId, charaId, settings);
		} catch (RuntimeException e) {
			logger.warn("Failed to create game for character {}.", charaId, e);
			ctx.write(CREATE_GAME_RESULT, GameError.GENERAL);
			return;
		}

		// Apply the settings the host pushed via 0x4310 just before this, so the game the browser
		// shows matches what the host configured (not the rule=0/map=0/timers=0 default): round 0's
		// rule/map/flags into columns, and the whole blob stored so the details reply can replay the
		// per-mode timers/rounds/tickets and uniques.
		// The game already exists; a failure applying the pushed settings must not hang the create
		// reply, so it is caught and logged rather than propagated (the game keeps the defaults).
		try {
			gameService.applyHostSettings(gameId, ctx.connection().hostSettings());
		} catch (RuntimeException e) {
			logger.warn("Failed to apply host settings to game {}; keeping defaults.", gameId, e);
		}

		// After the settings, not merely after the row: a listener told at createGame time could act
		// on a game whose rule and map are still zero.
		try {
			gameCreatedListener.gameCreated(charaId, gameId);
		} catch (RuntimeException e) {
			// A listener must never cost the host their game — the reply below is what unblocks them.
			logger.warn("Game-created listener threw for game {}.", gameId, e);
		}

		logger.info("Character {} created game {} in lobby {}.", charaId, gameId, lobbyId);

		var buffer = ctx.buffer(8);
		buffer.writeInt(GameError.NONE.result()).writeInt((int) gameId);
		ctx.write(new GamePacket(CREATE_GAME_RESULT, buffer));
	}
}
