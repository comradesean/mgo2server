package mgo2server.game.controller;

import mgo2server.common.BufferUtil;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.GameService;
import mgo2server.game.LoadoutWriter;
import mgo2server.game.GameConnection;
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
	 * rotation. The exact start is ambiguous by one byte between the references (Model A = 162,
	 * Model B = 163); this uses <b>Model B</b> — savemgo's push parser {@code Hosts.checkSettings}
	 * plus our own tier-1 {@code 0x4313} layout, which has a {@code u8} immediately before its
	 * rotation. <b>Unresolved:</b> host a game changing <em>only</em> the map to confirm whether map
	 * is at {@code +1} (Model B) or {@code +0} (Model A) of this offset.
	 */
	private static final int ROTATION_OFFSET = 163;

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
	 * {@code result == 0}, then retains a nonzero second word as a round handle (stored at
	 * {@code ctx+0x32F8}). We send {@code result = 0} and the game id as the token.
	 * <p>
	 * <b>Renumbered from {@code 0x43ca}/{@code 0x43cb}</b> — the full send-site scan found no
	 * builder for {@code 0x43ca}; the client sends {@code 0x43c8} and parses {@code 0x43c9}. The
	 * old ids were a two-off transcription slip (and the reason the round snapshot never fired).
	 */
	public static final int START_ROUND = 0x43c8;

	public static final int START_ROUND_RESULT = 0x43c9;

	/** Host cycles the rule/map in the rotation while staging. Answered {@code result(0)}. */
	public static final int SET_GAME = 0x4392;

	public static final int SET_GAME_RESULT = 0x4393;

	/** End-of-round stat submission. Answered {@code result(0)}. */
	public static final int UPDATE_STATS = 0x4390;

	public static final int UPDATE_STATS_RESULT = 0x4391;

	/** End-of-round report (meaning unconfirmed). Answered {@code result(0)}. */
	public static final int ROUND_END = 0x43a2;

	public static final int ROUND_END_RESULT = 0x43a3;

	/** Host hands hosting to another player. Answered {@code result(0)}. */
	public static final int PASS_HOST = 0x43a0;

	public static final int PASS_HOST_RESULT = 0x43a1;

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
	 * hosting flow at all. The body is not yet parsed into {@code chara_settings}, so options do
	 * not persist across sessions — see BACKLOG. The reply must carry {@code u32 result == 0}.
	 */
	public static final int UPDATE_SETTINGS = 0x4110;

	public static final int UPDATE_SETTINGS_RESULT = 0x4111;

	/** Total bytes of the {@code 0x4129} results payload (result word included); echo's BUFFER_SIZE. */
	private static final int POST_GAME_INFO_SIZE = 0x8b;

	/** Skill-table entries the results parser reads: a fixed 25, each {id u8, exp u16, pad u8}. */
	private static final int POST_GAME_SKILLS = 25;

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
	 * triple, one list per state. Populated from {@code chara_relation}. <b>Not observed live</b>
	 * (the in-game path uses {@link #ADD_LIST}/{@link #REMOVE_LIST} plus the {@code 0x4101} login
	 * arrays), so the reply is built from the ELF parser ({@code 0x4581} start `0xD469C0`,
	 * {@code 0x4582} entries `0xD467C0`, {@code 0x4583} end `0xD465D4`) and unverified against a
	 * client — if the Friends menu ever misbehaves, this is the suspect; the empty form was the
	 * prior known-safe fallback. ELF send builder {@code 0xD4628C}.
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

	/** Sent on leaving a game. Unanswered, the client sits on a black screen. */
	public static final int QUIT_GAME = 0x4380;

	public static final int QUIT_GAME_RESULT = 0x4381;

	public static final int CREATE_GAME = 0x4316;

	public static final int CREATE_GAME_RESULT = 0x4317;

	private final GameService gameService;

	private final CharacterService characterService;

	private final long lobbyId;

	private final int lobbySubtype;

	public HostGameController(GameService gameService, CharacterService characterService,
			long lobbyId, int lobbySubtype) {
		this.gameService = gameService;
		this.characterService = characterService;
		this.lobbyId = lobbyId;
		this.lobbySubtype = lobbySubtype;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
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
		handlers.put(ROUND_END, this::acknowledgeResult);
		handlers.put(PASS_HOST, this::passHost);
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
	 * {@code chara_relation}: a {@code 0x4581} start carrying the entry <em>count</em> (the parser
	 * treats 0 as an empty list), then {@code 0x4582} packets of up to {@value #ROSTER_PER_PACKET}
	 * entries each (id + name, the five unmapped trailing fields zeroed), then a {@code 0x4583}
	 * end. Capped at {@value #ROSTER_MAX}, the client's own limit.
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

		// Start carries the count — the parser reads 0 as "empty list", nonzero as the number of
		// entries that follow.
		var start = ctx.buffer(Integer.BYTES);
		start.writeInt(entries.size());
		ctx.write(new GamePacket(LIST_ROSTER_START, start));

		for (var offset = 0; offset < entries.size(); offset += ROSTER_PER_PACKET) {
			var batch = entries.subList(offset, Math.min(offset + ROSTER_PER_PACKET, entries.size()));
			var buffer = ctx.buffer(batch.size() * ROSTER_ENTRY_SIZE);
			for (var relation : batch) {
				buffer.writeInt((int) relation.targetId());
				BufferUtil.writeString(buffer, relation.name(), StandardCharsets.ISO_8859_1,
					RELATION_NAME_LENGTH);
				buffer.writeZero(ROSTER_ENTRY_SIZE - Integer.BYTES - RELATION_NAME_LENGTH);
			}
			ctx.write(new GamePacket(LIST_ROSTER_ENTRIES, buffer));
		}

		var end = ctx.buffer(Integer.BYTES);
		end.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(LIST_ROSTER_END, end));
	}

	/**
	 * Acknowledges the post-entry game-rules update ({@link #UPDATE_SETTINGS}); the reply must carry
	 * a {@code u32} result of 0 or the enter-game flow stalls. Its 48-byte header carries the Common
	 * Settings toggles, which are not decoded yet — the reply is all the client needs for now.
	 */
	private void updateSettings(GameControllerContext ctx) {
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

		var rank = 0;
		var experience = 0;
		if (account != null && charaId != 0L) {
			var chara = characterService.get(charaId).orElse(null);
			if (chara != null) {
				rank = chara.getRank();
				experience = charaId == (account.getMainCharaId() != null
					? account.getMainCharaId() : 0L)
					? account.getMainExp() : account.getAltExp();
			}
		}

		var buffer = ctx.buffer(POST_GAME_INFO_SIZE);
		buffer.writeInt(GameError.NONE.result()) // result
			.writeByte(rank)
			.writeInt(experience)
			.writeByte(0)
			.writeInt(POST_GAME_SKILLS); // skill count
		for (var i = 0; i < POST_GAME_SKILLS; i++) {
			buffer.writeByte(i + 1) // skill id
				.writeShort(LoadoutWriter.advertisedSkillExperience(i + 1))
				.writeByte(0);
		}
		buffer.writeInt(0)
			.writeInt(experience) // grade points mirror experience in both references
			.writeInt(0xffffff)
			.writeInt(0)          // clan id — clans are not modelled
			.writeShort(0)
			.writeByte(1)
			.writeByte(0)         // emblem — no clans, no emblem
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

			gameService.updateGameSettings(lobbyId, charaId, name, comment, password);
			logger.info("Character {} edited its game in place: name='{}', password={}.",
				charaId, name, passwordEnabled ? "set" : "none");
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
			ctx.write(HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
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

		var buffer = ctx.buffer(HOST_SETTINGS_SIZE);
		buffer.writeZero(HOST_SETTINGS_SIZE);
		ctx.write(new GamePacket(HOST_SETTINGS_RESULT, buffer));
	}

	/**
	 * Accepts the host's configured settings. The reply carries no payload; the client only waits
	 * for the acknowledgement before moving on to create the game.
	 * <p>
	 * The blob is kept three ways: on the connection for the imminent create-game, parsed into
	 * the game row's columns by {@code applyHostSettings}, and stored raw per (character, lobby
	 * subtype) so {@link #getHostSettings} can pre-fill the Create Game screen next session.
	 */
	private void checkHostSettings(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CHECK_HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
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
		ctx.connection().setHostSettings(bytes);

		// Persist the raw blob per (character, subtype) so 0x4304 pre-fills next session. The
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

		ctx.write(new GamePacket(CHECK_HOST_SETTINGS_RESULT, ctx.buffer(0)));
	}

	/**
	 * Acknowledges a host-admin command with a {@code result(0)} word, the four-byte "OK" both
	 * references send for the round-lifecycle commands. Their parsers read a result and block on
	 * it. Still used for {@code 0x43a2} (round end), whose payload no reference parses — its
	 * meaning is unconfirmed everywhere, so the data is dropped knowingly.
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
	 * from the game's stored blob, so the browser reflects the round actually being staged.
	 */
	private void setGame(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		if (game != null && payload.readableBytes() >= 1) {
			var index = payload.readByte() & 0xff;
			var blob = game.getHostSettings();
			var offset = ROTATION_OFFSET + index * 3;
			if (index < 15 && blob != null && blob.length >= offset + 3) {
				gameService.setCurrentGame(game.getId(), index,
					blob[offset] & 0xff, blob[offset + 1] & 0xff, blob[offset + 2] & 0xff);
				logger.info("Game {} advanced to rotation entry {} (rule={} map={}).",
					game.getId(), index, blob[offset] & 0xff, blob[offset + 1] & 0xff);
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

		ctx.write(new GamePacket(UPDATE_PINGS_RESULT, ctx.buffer(0)));
	}

	/**
	 * Host presses Start ({@link #START_ROUND}). The request carries nothing the reference reads;
	 * the work is the roster snapshot — everyone in the game now "played this round", which is
	 * what {@link #updateStats} checks before applying a stat report to a character.
	 */
	private void startRound(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var token = game != null ? (int) game.getId() : 0;
		if (game != null) {
			gameService.markRoundPlayers(game.getId());
			logger.info("Game {} started a round.", game.getId());
		}
		// {u32 result, u32 token}: result 0 lets the client proceed; the token is the round
		// handle it retains (0xD3FEAC stores a nonzero second word). The game id serves.
		var buffer = ctx.buffer(2 * Integer.BYTES);
		buffer.writeInt(GameError.NONE.result()).writeInt(token);
		ctx.write(new GamePacket(START_ROUND_RESULT, buffer));
	}

	/**
	 * Host hands the game to another player ({@link #PASS_HOST}). Request is two u32s — the
	 * current host's chara id (unused, as in the reference) then the new host's. The game is
	 * re-keyed to the target and the old host leaves the roster; joins pick up the new host's
	 * endpoint automatically because {@code 0x4320} reads {@code chara_connection} by the game's
	 * host id at join time.
	 */
	private void passHost(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();

		if (game != null && payload.readableBytes() >= 2 * Integer.BYTES) {
			payload.readInt(); // the sender's own chara id; the session already proves it
			long targetId = payload.readInt();
			var isPlayer = gameService.getPlayers(game.getId(), game.getHostCharaId()).stream()
				.anyMatch(player -> player.charaId() == targetId);
			if (isPlayer && targetId != game.getHostCharaId()) {
				gameService.passHost(game.getId(), game.getHostCharaId(), targetId);
				logger.info("Game {} host passed from character {} to {}.",
					game.getId(), game.getHostCharaId(), targetId);
			} else {
				logger.warn("Game {}: pass-host target {} is not another player in the game.",
					game.getId(), targetId);
			}
		}

		acknowledgeResult(ctx);
	}

	/**
	 * End-of-round stat submission from the host ({@link #UPDATE_STATS}), one player per packet.
	 * <p>
	 * <b>Reference layout (tier 4), and the references disagree</b>: Nomad reads
	 * {@code u32 target chara id} at 0, {@code u32 experience} (absolute total) at {@code 0x27}
	 * and an aborted byte at {@code 0xB7}, skipping everything else; mgo2-server reads a
	 * completely different single-byte stat struct with no target id at all. Nomad served retail
	 * clients, so its read is implemented — but only the experience is applied, and only when the
	 * target verifiably played: a current roster member, or a member of the round snapshot taken
	 * at {@code 0x43ca} — the snapshot is what keeps a report for a player who <em>quit
	 * mid-round</em> applicable, which is the case the reference's own list exists for. Per-stat
	 * fields (kills, deaths…) are deliberately not parsed: no trusted layout exists. Verify live
	 * by comparing a host's results-screen total to the stored value after one round.
	 */
	private void updateStats(GameControllerContext ctx) {
		var game = hostedGame(ctx);
		var payload = ctx.packet().getPayload();
		var readable = payload.readableBytes();

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
				// Scoreboard: the stat-struct-A slots confirmed by the 2026-07-22 capture (signed
				// u16 at 0x05 + 2*i). kills A0, deaths A1, score A3, stun A4, headshots A6,
				// headshot-deaths A7. The rest of the report is not yet labelled — see PROTOCOL.md.
				var stats = new GameService.RoundStats(
					payload.getShort(base + 0x05), payload.getShort(base + 0x07),
					payload.getShort(base + 0x0b), payload.getShort(base + 0x11),
					payload.getShort(base + 0x13), payload.getShort(base + 0x0d));
				gameService.accumulateStats(targetId, stats);
				logger.info("Game {}: stats for character {} — {} kills, {} deaths, score {}, "
						+ "experience {}{}{}.",
					game.getId(), targetId, stats.kills(), stats.deaths(), stats.score(),
					experience, aborted ? " (aborted round)" : "",
					inGame ? "" : " (left mid-round; accepted from the round snapshot)");
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
		ctx.write(new GamePacket(QUIT_GAME_RESULT, ctx.buffer(0)));
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

		logger.info("Character {} created game {} in lobby {}.", charaId, gameId, lobbyId);

		var buffer = ctx.buffer(8);
		buffer.writeInt(GameError.NONE.result()).writeInt((int) gameId);
		ctx.write(new GamePacket(CREATE_GAME_RESULT, buffer));
	}
}
