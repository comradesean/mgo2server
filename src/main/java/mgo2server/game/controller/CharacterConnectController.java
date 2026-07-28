package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.Account;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.ChatMacro;
import mgo2server.common.model.ConnectionInfo;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.AwardService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.GameplaySettingsWriter;
import mgo2server.game.IGameController;
import mgo2server.game.LoadoutWriter;
import mgo2server.game.PersonalInfoWriter;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.function.Consumer;

/**
 * The burst a client asks for on entering a game lobby.
 * <p>
 * A single request, 0x4100, is answered with everything the client needs about the character it
 * arrived with. All eight of the original's responses are implemented: the character record
 * (0x4101), gameplay and interface settings (0x4120), chat macros (0x4121, one packet per type),
 * personal info (0x4122), the gear and skill catalogues (0x4124, 0x4125) and the saved skill and
 * gear loadouts (0x4140, 0x4142).
 */
public class CharacterConnectController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int CONNECT = 0x4100;

	/** The client's peer-to-peer endpoint, registered on joining a game lobby. */
	public static final int UPDATE_CONNECTION_INFO = 0x4700;

	public static final int UPDATE_CONNECTION_INFO_RESULT = 0x4701;

	/**
	 * Private port, private address, public port, then a <b>u16 the client populates</b> — not
	 * padding (corrected 2026-07-26). The sender writes it from its fourth argument
	 * ({@code 0xD5C918} at {@code 0xD38708}), so the request is exactly 22 bytes, not "at least
	 * 20". Its meaning is [UNKNOWN] and we do not read it; the constant below is only a minimum
	 * length check. See {@code dev/proto/blanks/inbound/mgo2_cmd_4700_c2s.ksy}.
	 */
	private static final int PRIVATE_IP_LENGTH = 16;

	private static final int CONNECTION_INFO_SIZE = 2 + PRIVATE_IP_LENGTH + 2;

	public static final int CHARACTER_INFO = 0x4101;

	/**
	 * A 32-byte write-back from the connect family, contents unidentified — and the client
	 * <b>blocks on it</b> (wait slot {@code 0x18}, {@code li r4,24} at {@code 0xD3BEDC}).
	 * <p>
	 * Observed live 2026-07-27 after a player search, payload
	 * {@code 0000 1000 0000 0000 1110 0000 0000 0000 0000}, and unanswered it stalls the screen.
	 * The reply {@code 0x4113} is a bare {@code u32} result ({@code 0xD3B148}), so acknowledging it
	 * costs nothing; the body is stored nowhere because nothing is known about it. Whatever setting
	 * this carries will not persist until someone identifies the 32 bytes.
	 */
	public static final int UNKNOWN_WRITE_BACK = 0x4112;

	private static final int UNKNOWN_WRITE_BACK_RESULT = 0x4113;

	public static final int GAMEPLAY_SETTINGS = 0x4120;

	public static final int CHAT_MACROS = 0x4121;

	/**
	 * The write-back half of {@link #CHAT_MACROS}: the client saving its macros. First observed
	 * live 2026-07-22 — the joiner flushed its options as {@code 0x4110} + two of these in one
	 * burst, 769 bytes each, the exact {@code 0x4121} layout (u8 type, then 12 × 64-byte texts).
	 * The {@code 0x4115} reply shape is inferred from the sibling result packets, not read from
	 * the binary; observed accepted by a live client since.
	 */
	public static final int UPDATE_CHAT_MACROS = 0x4114;

	public static final int UPDATE_CHAT_MACROS_RESULT = 0x4115;

	/** Fixed width of one macro text on the wire, same as the 0x4121 read side. */
	private static final int MACRO_TEXT_LENGTH = 64;

	/** Each 0x4101 list region holds at most this many 4-byte ids. */
	private static final int MAX_LIST_IDS = 32;

	public static final int PERSONAL_INFO = 0x4122;

	public static final int GEAR = 0x4124;

	public static final int SKILLS = 0x4125;

	public static final int SKILL_SETS = 0x4140;

	public static final int GEAR_SETS = 0x4142;

	private static final int NAME_LENGTH = 16;

	/**
	 * The client's 0x4101 parser (0xD3C120) consumes a fixed 0x142-byte grid: the 0x29-byte
	 * header, 32 friend ids, 32 blocked ids, then a 25-byte tail (u8, 16 bytes, two u32s).
	 * Anything past 0x142 is never read. The reference servers all send 0x243 with 256-byte
	 * friend and blocked regions — under them the client's blocked list was actually friend
	 * ids 33-64, and its tail was read out of the blocked region, which was zeros in practice.
	 */
	private static final int INFO_PAYLOAD_SIZE = 0x142;

	/** 32 friend ids run from the end of the header up to this offset. */
	private static final int FRIENDS_END = 0xa9;

	/** 32 blocked ids follow, up to here; the remaining 25 bytes are the tail, zeroed. */
	private static final int BLOCKED_END = 0x129;


	/**
	 * Four u16 values the client stores from the header (0x16AE, 0x0338, 0x013E, 0x0150).
	 * Their meaning is undocumented; they are reproduced from the original server byte for
	 * byte.
	 */
	static final byte[] INFO_PREFIX = {
		(byte) 0x16, (byte) 0xAE, (byte) 0x03, (byte) 0x38,
		(byte) 0x01, (byte) 0x3E, (byte) 0x01, (byte) 0x50,
	};

	private final CharacterService characterService;

	private final ClanService clanService;

	private final AwardService awardService;

	private final GameService gameService;

	public CharacterConnectController(CharacterService characterService, ClanService clanService,
			GameService gameService, AwardService awardService) {
		this.clanService = clanService;
		this.characterService = characterService;
		this.gameService = gameService;
		this.awardService = awardService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CONNECT, this::connect);
		handlers.put(UPDATE_CONNECTION_INFO, this::updateConnectionInfo);
		handlers.put(UPDATE_CHAT_MACROS, this::updateChatMacros);
		handlers.put(UNKNOWN_WRITE_BACK, ctx -> ctx.write(UNKNOWN_WRITE_BACK_RESULT, GameError.NONE));
	}

	/**
	 * The endpoint the client wants other players to reach it on, sent right after it joins a game
	 * lobby. Matches are peer to peer, so this is what a joining client is eventually handed.
	 * <p>
	 * The client blocks on the reply: with nothing sent back it waits and then fails with
	 * <em>Unable to connect to lobby (092E:FFFFFF60)</em>, the same timeout shape as an unanswered
	 * name check.
	 * <p>
	 * The values are persisted against the character so a joining player can be handed them by
	 * command 0x4321. The public address is taken from the socket rather than trusted from the
	 * payload, which is what the reference servers do — a client cannot lie about where its
	 * packets come from.
	 */
	/**
	 * Saves a macro-type's grid pushed by the client ({@link #UPDATE_CHAT_MACROS}). The payload
	 * mirrors what {@code 0x4121} sends down: one type byte, then twelve 64-byte texts. A type
	 * outside 0/1 is logged and dropped (the table's check constraint would reject it anyway),
	 * but still acknowledged — an unanswered command is this client's signature failure.
	 */
	private void updateChatMacros(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(UPDATE_CHAT_MACROS_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		var charaId = account.getCurrentCharaId();
		if (charaId != null && payload.readableBytes() >= 1) {
			var type = payload.readByte() & 0xff;
			if (type < ChatMacro.TYPES) {
				var texts = new java.util.ArrayList<String>(ChatMacro.PER_TYPE);
				while (payload.readableBytes() >= MACRO_TEXT_LENGTH
						&& texts.size() < ChatMacro.PER_TYPE) {
					texts.add(readNulTerminated(payload, MACRO_TEXT_LENGTH));
				}
				characterService.saveChatMacros(charaId, type, texts);
				logger.info("Character {} saved {} chat macros of type {}.",
					charaId, texts.size(), type);
			} else {
				logger.warn("Chat-macro save with unknown type {}; dropped.", type);
			}
		}

		var buffer = ctx.buffer(Integer.BYTES);
		buffer.writeInt(GameError.NONE.result());
		ctx.write(new GamePacket(UPDATE_CHAT_MACROS_RESULT, buffer));
	}

	private void updateConnectionInfo(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(UPDATE_CONNECTION_INFO_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < CONNECTION_INFO_SIZE) {
			logger.warn("Connection info: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(UPDATE_CONNECTION_INFO_RESULT, GameError.GENERAL);
			return;
		}

		var privatePort = payload.readUnsignedShort();
		var privateIp = readNulTerminated(payload, PRIVATE_IP_LENGTH);
		var publicPort = payload.readUnsignedShort();

		var charaId = account.getCurrentCharaId();
		var publicIp = ctx.remoteIp();
		if (charaId == null || publicIp == null) {
			// Nothing to key the endpoint to, or no socket address — register nothing but still
			// acknowledge, since the client blocks on the reply.
			logger.warn("Connection info from account {} could not be stored (chara {}, ip {}).",
				account.getId(), charaId, publicIp);
			ctx.write(UPDATE_CONNECTION_INFO_RESULT, GameError.NONE);
			return;
		}

		var info = new ConnectionInfo();
		info.setCharaId(charaId);
		info.setPublicIp(publicIp);
		info.setPublicPort(publicPort);
		info.setPrivateIp(privateIp);
		info.setPrivatePort(privatePort);
		gameService.saveConnectionInfo(info);

		logger.info("Character {} reachable at {}:{} (private {}:{}).",
			charaId, publicIp, publicPort, privateIp, privatePort);

		ctx.write(UPDATE_CONNECTION_INFO_RESULT, GameError.NONE);
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

	private void connect(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CHARACTER_INFO, GameError.INVALID_SESSION);
			return;
		}

		var charaId = account.getCurrentCharaId();
		if (charaId == null) {
			logger.warn("Account {} entered a game lobby with no character selected.", account.getId());
			ctx.write(CHARACTER_INFO, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		var chara = characterService.get(charaId).orElse(null);
		if (chara == null) {
			logger.warn("Account {} has a selected character {} that no longer exists.",
				account.getId(), charaId);
			ctx.write(CHARACTER_INFO, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		// Stamping the visit also re-tests the titles, and does so BEFORE the stamp lands so an
		// absence-based requirement can still see the gap it is measuring. Doing it here as well as
		// at round end means a character who qualifies purely by staying away can still be told.
		var titles = awardService.seen(charaId);
		if (!titles.isEmpty()) {
			logger.info("Character {} unlocked title bits {} on entering the lobby.", charaId, titles);
		}

		// Order matches the original's burst.
		writeCharacterInfo(ctx, account, chara);
		writeGameplaySettings(ctx, charaId);
		writeChatMacros(ctx, charaId);
		writePersonalInfo(ctx, chara);
		writeGear(ctx, charaId);
		writeSkills(ctx, charaId);
		writeSkillSets(ctx, charaId);
		writeGearSets(ctx, charaId);
	}

	private void writeGear(GameControllerContext ctx, long charaId) {
		var gear = characterService.ownedGear(charaId);
		var buffer = ctx.buffer(LoadoutWriter.gearPayloadSize(gear.size()));
		LoadoutWriter.writeGear(buffer, gear);
		ctx.write(new GamePacket(GEAR, buffer));
	}

	private void writeSkills(GameControllerContext ctx, long charaId) {
		var skills = characterService.getSkills(charaId);

		var buffer = ctx.buffer(LoadoutWriter.skillsPayloadSize(skills.size()));
		LoadoutWriter.writeSkills(buffer, skills);
		ctx.write(new GamePacket(SKILLS, buffer));
	}

	private void writeSkillSets(GameControllerContext ctx, long charaId) {
		var sets = characterService.getOrCreateSkillSets(charaId);

		var buffer = ctx.buffer(sets.size() * LoadoutWriter.SKILL_SET_SIZE);
		LoadoutWriter.writeSkillSets(buffer, sets);
		ctx.write(new GamePacket(SKILL_SETS, buffer));
	}

	private void writeGearSets(GameControllerContext ctx, long charaId) {
		var sets = characterService.getOrCreateGearSets(charaId);

		var buffer = ctx.buffer(sets.size() * LoadoutWriter.GEAR_SET_SIZE);
		LoadoutWriter.writeGearSets(buffer, sets);
		ctx.write(new GamePacket(GEAR_SETS, buffer));
	}

	private void writeGameplaySettings(GameControllerContext ctx, long charaId) {
		var settings = characterService.getOrCreateSettings(charaId);

		var buffer = ctx.buffer(GameplaySettingsWriter.PAYLOAD_SIZE);
		GameplaySettingsWriter.write(buffer, settings);

		ctx.write(new GamePacket(GAMEPLAY_SETTINGS, buffer));
	}

	private void writePersonalInfo(GameControllerContext ctx, Chara chara) {
		var appearance = characterService.getAppearance(chara.getId()).orElseGet(CharaAppearance::new);
		var skills = characterService.getOrCreateEquippedSkills(chara.getId());

		// A saved instructor is announced to peers; without it the client re-offers the recognition
		// prompt every session and no "your instructor" tag can appear.
		var savedInstructor = characterService.instructorOf(chara.getId())
			.map(instructor -> (int) instructor.instructorCharaId())
			.orElse(PersonalInfoWriter.NO_SAVED_INSTRUCTOR);

		var membership = clanService.membershipOf(chara.getId());

		// Only a clan we can actually serve an emblem for: the flag makes the client send 0x4b48
		// during connect and wait on the reply, so claiming an emblem we do not have would hand it
		// an empty one. emblemFlagOf returns the raw stored upload mode; 3 is the only mode the
		// client itself records as "on display".
		var clanHasEmblem = membership.id() != 0
			&& clanService.emblemFlagOf(membership.id()) == PersonalInfoWriter.EMBLEM_ON_DISPLAY;

		var buffer = ctx.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara, appearance, skills, savedInstructor, membership,
			clanHasEmblem, characterService.skillExperience(chara.getId()));

		ctx.write(new GamePacket(PERSONAL_INFO, buffer));
	}

	private void writeCharacterInfo(GameControllerContext ctx, Account account, Chara chara) {
		var now = (int) Instant.now().getEpochSecond();

		var buffer = ctx.buffer(INFO_PAYLOAD_SIZE);
		buffer.writeInt((int) chara.getId());
		BufferUtil.writeString(buffer, chara.getName(), StandardCharsets.ISO_8859_1, NAME_LENGTH);
		buffer.writeBytes(INFO_PREFIX);

		buffer.writeInt(experienceFor(account, chara))
			// The client shows the previous login alongside the current one.
			.writeInt(now - 1)
			.writeInt(now)
			.writeZero(1);

		// Friend and blocked lists: fixed-width regions of 4-byte ids, filled from the stored
		// ADDLIST relations (0x4500) and zero-padded. These arrays are how the client learns its
		// authoritative list state at login — leaving them zero is why relationships could never
		// be changed twice in a session or survive one (observed live 2026-07-22).
		for (var id : characterService.relationIds(chara.getId(),
				CharacterService.RELATION_FRIEND, MAX_LIST_IDS)) {
			buffer.writeInt(id.intValue());
		}
		padTo(buffer, FRIENDS_END);
		for (var id : characterService.relationIds(chara.getId(),
				CharacterService.RELATION_BLOCKED, MAX_LIST_IDS)) {
			buffer.writeInt(id.intValue());
		}
		padTo(buffer, BLOCKED_END);
		padTo(buffer, INFO_PAYLOAD_SIZE);

		ctx.write(new GamePacket(CHARACTER_INFO, buffer));
	}

	/** Experience is per account, split between the main character and the alts. */
	private static int experienceFor(Account account, Chara chara) {
		var main = account.getMainCharaId();
		return main != null && main == chara.getId() ? account.getMainExp() : account.getAltExp();
	}

	private void writeChatMacros(GameControllerContext ctx, long charaId) {
		var macros = characterService.getChatMacros(charaId);

		// One packet per type, each carrying its type byte then its twelve entries.
		for (var type = 0; type < ChatMacro.TYPES; type++) {
			var buffer = ctx.buffer(1 + ChatMacro.PER_TYPE * ChatMacro.TEXT_LENGTH);
			buffer.writeByte(type);

			for (var macro : macros) {
				if (macro.getType() == type) {
					BufferUtil.writeString(buffer, macro.getText(), StandardCharsets.ISO_8859_1,
						ChatMacro.TEXT_LENGTH);
				}
			}

			ctx.write(new GamePacket(CHAT_MACROS, buffer));
		}
	}

	private static void padTo(ByteBuf buffer, int offset) {
		var padding = offset - buffer.writerIndex();
		if (padding > 0) {
			buffer.writeZero(padding);
		}
	}
}
