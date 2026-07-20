package nomad.game.controller;

import io.netty.buffer.ByteBuf;
import nomad.common.BufferUtil;
import nomad.common.model.Account;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.model.ChatMacro;
import nomad.common.service.CharacterService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.GameplaySettingsWriter;
import nomad.game.IGameController;
import nomad.game.LoadoutWriter;
import nomad.game.PersonalInfoWriter;
import nomad.game.packet.GamePacket;
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

	public static final int CHARACTER_INFO = 0x4101;

	public static final int GAMEPLAY_SETTINGS = 0x4120;

	public static final int CHAT_MACROS = 0x4121;

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
	private static final byte[] INFO_PREFIX = {
		(byte) 0x16, (byte) 0xAE, (byte) 0x03, (byte) 0x38,
		(byte) 0x01, (byte) 0x3E, (byte) 0x01, (byte) 0x50,
	};

	private final CharacterService characterService;

	public CharacterConnectController(CharacterService characterService) {
		this.characterService = characterService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(CONNECT, this::connect);
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

		// Order matches the original's burst.
		writeCharacterInfo(ctx, account, chara);
		writeGameplaySettings(ctx, charaId);
		writeChatMacros(ctx, charaId);
		writePersonalInfo(ctx, chara);
		writeGear(ctx);
		writeSkills(ctx);
		writeSkillSets(ctx, charaId);
		writeGearSets(ctx, charaId);
	}

	private void writeGear(GameControllerContext ctx) {
		var buffer = ctx.buffer(LoadoutWriter.gearPayloadSize());
		LoadoutWriter.writeGear(buffer);
		ctx.write(new GamePacket(GEAR, buffer));
	}

	private void writeSkills(GameControllerContext ctx) {
		var buffer = ctx.buffer(LoadoutWriter.skillsPayloadSize());
		LoadoutWriter.writeSkills(buffer);
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

		var buffer = ctx.buffer(PersonalInfoWriter.PAYLOAD_SIZE);
		PersonalInfoWriter.write(buffer, chara, appearance, skills);

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

		// Friend and blocked lists are fixed-width regions of 4-byte ids. Neither is modelled
		// yet, so both are left empty and the regions are zero-filled, as is the tail — which
		// is what the client actually received from the original server.
		padTo(buffer, FRIENDS_END);
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
