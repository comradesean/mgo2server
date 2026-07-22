package mgo2server.game.controller;

import mgo2server.common.service.CharacterService;
import mgo2server.common.service.GameService;
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

	/** Host presses Start: begin the round. Answered {@code result(0)}; without it no match starts. */
	public static final int START_ROUND = 0x43ca;

	public static final int START_ROUND_RESULT = 0x43cb;

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
	 * The game-rules update the client sends right after entering a hosted game — <b>this is where
	 * the Common Settings toggles live</b> (friendly fire, ghost, nametags, silent, auto-assign,
	 * teams-switch, voice, level-limit/kick enables), in its 48-byte header (payload {@code
	 * 0x00–0x2F}), verified against serializer {@code 0xD3BFB8}. The {@code 0x4310} push does
	 * <b>not</b> carry them. Plaintext. Its reply parser ({@code 0xD3B20C}) requires a {@code u32}
	 * result {@code == 0}; unanswered it stalls the enter-game flow. The header bits are not decoded
	 * yet — see {@code dev/docs/BACKLOG.md} for the capture plan that would map them.
	 */
	public static final int UPDATE_SETTINGS = 0x4110;

	public static final int UPDATE_SETTINGS_RESULT = 0x4111;

	/** Total bytes of the {@code 0x4129} results payload (result word included); echo's BUFFER_SIZE. */
	private static final int POST_GAME_INFO_SIZE = 0x8b;

	/** Skill-table entries the results parser reads: a fixed 25, each {id u8, exp u16, pad u8}. */
	private static final int POST_GAME_SKILLS = 25;

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
		handlers.put(UPDATE_PINGS, this::acknowledge);
		handlers.put(QUIT_GAME, this::quitGame);
		handlers.put(IN_GAME_INFO, this::editHostSettings);
		handlers.put(START_ROUND, this::acknowledgeResult);
		handlers.put(SET_GAME, this::acknowledgeResult);
		handlers.put(UPDATE_STATS, this::acknowledgeResult);
		handlers.put(ROUND_END, this::acknowledgeResult);
		handlers.put(PASS_HOST, this::acknowledgeResult);
		handlers.put(GET_POST_GAME_INFO, this::postGameInfo);
		handlers.put(UPDATE_SETTINGS, this::updateSettings);
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
	 * Answers the end-of-round results request ({@link #GET_POST_GAME_INFO}) with a nonzero result,
	 * the one reply shape that clears the client's wait without a stall — see the constant's note.
	 * We do not track match results, so no card is rendered.
	 */
	private void postGameInfo(GameControllerContext ctx) {
		var account = ctx.connection().account();
		var charaId = account != null && account.getCurrentCharaId() != null
			? account.getCurrentCharaId() : 0L;

		// result=0 then the full fixed-size results structure the parser reads: rank, exp, a
		// 25-entry skill table, grade/clan/emblem fields. We track no match stats, so everything is
		// zeroed except the fixed counts and the character id the client expects echoed back.
		var buffer = ctx.buffer(POST_GAME_INFO_SIZE);
		buffer.writeInt(GameError.NONE.result()) // result
			.writeByte(0)   // rank
			.writeInt(0)    // experience
			.writeByte(0)
			.writeInt(POST_GAME_SKILLS); // skill count
		for (var i = 0; i < POST_GAME_SKILLS; i++) {
			buffer.writeByte(i + 1) // skill id
				.writeShort(0)      // skill exp
				.writeByte(0);
		}
		buffer.writeInt(0)
			.writeInt(0)          // grade points
			.writeInt(0xffffff)
			.writeInt(0)          // clan id
			.writeShort(0)
			.writeByte(1)
			.writeByte(0)         // emblem
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
	 * Nothing is persisted here yet: {@code chara_host_settings} exists but is never written, so
	 * this always takes the empty path. That is correct rather than a stub — a player who has not
	 * hosted has no settings to restore — but it means the populated path is untested.
	 */
	private void getHostSettings(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(HOST_SETTINGS_RESULT, GameError.INVALID_SESSION);
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
	 * The settings are read but <b>not stored</b>. Our {@code chara_host_settings} table is
	 * structured per field, while the client sends an opaque blob whose layout is not decoded here,
	 * so there is nowhere faithful to put it. The consequence is visible but small: the Create Game
	 * screen will not remember these settings next time, because {@link #getHostSettings} has
	 * nothing to return. Hosting itself is unaffected.
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
	 * Acknowledges an in-match report the host sends but which nothing here consumes yet.
	 * <p>
	 * {@link #SET_PLAYER_TEAM} and {@link #UPDATE_PINGS} both carry real information — team
	 * assignments and per-player latency — that a server tracking a live match would use. We track
	 * neither, so the data is dropped. They are answered because the client blocks on the reply,
	 * not because the work is done: implementing the match state is what makes them meaningful.
	 */
	private void acknowledge(GameControllerContext ctx) {
		var reply = ctx.packet().getCommand() + 1;
		ctx.write(new GamePacket(reply, ctx.buffer(0)));
	}

	/**
	 * Acknowledges a host-admin command with a {@code result(0)} word, the four-byte "OK" both
	 * references send for the staging and round-lifecycle commands ({@code 0x43ca} start round,
	 * {@code 0x4392} set game, {@code 0x4390} stats, {@code 0x43a2}, {@code 0x43a0}). Their parsers
	 * read a result and block on it, so unlike {@link #acknowledge}'s empty reply these must carry
	 * the word. The match state they describe is not tracked yet, so the payload is dropped.
	 */
	private void acknowledgeResult(GameControllerContext ctx) {
		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(ctx.packet().getCommand() + 1, buffer));
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
