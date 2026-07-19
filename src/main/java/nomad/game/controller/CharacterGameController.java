package nomad.game.controller;

import io.netty.buffer.ByteBuf;
import nomad.common.BufferUtil;
import nomad.common.CharacterNames;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.service.AccountService;
import nomad.common.service.CharacterService;
import nomad.game.GameControllerContext;
import nomad.game.GameError;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Character selection screen: listing, creating, selecting and deleting characters.
 * <p>
 * The client refers to characters by their index in the list it was last sent, so every command
 * here resolves that index through {@link CharacterService#listForAccount}, which applies one
 * ordering rule in one place.
 */
public class CharacterGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int GET_CHARACTER_LIST = 0x3048;

	public static final int CHARACTER_LIST_RESULT = 0x3049;

	public static final int CREATE_CHARACTER = 0x3101;

	public static final int CREATE_CHARACTER_RESULT = 0x3102;

	public static final int SELECT_CHARACTER = 0x3103;

	public static final int SELECT_CHARACTER_RESULT = 0x3104;

	public static final int DELETE_CHARACTER = 0x3105;

	public static final int DELETE_CHARACTER_RESULT = 0x3106;

	private static final int NAME_LENGTH = 16;

	/** Total size of the character list payload, zero-filled up to the trailer. */
	private static final int LIST_TRAILER_OFFSET = 0x1b4;

	private static final int LIST_PAYLOAD_SIZE = 0x1d7;

	/**
	 * Fixed trailer the client expects after the character entries. Its meaning is not documented;
	 * it is reproduced from the original server byte for byte.
	 */
	private static final byte[] LIST_TRAILER = {
		0x00, 0x00, 0x00, 0x00, 0x07, 0x00, 0x03, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	};

	private final AccountService accountService;

	private final CharacterService characterService;

	public CharacterGameController(AccountService accountService, CharacterService characterService) {
		this.accountService = accountService;
		this.characterService = characterService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_CHARACTER_LIST, this::getCharacterList);
		handlers.put(CREATE_CHARACTER, this::createCharacter);
		handlers.put(SELECT_CHARACTER, this::selectCharacter);
		handlers.put(DELETE_CHARACTER, this::deleteCharacter);
	}

	private void getCharacterList(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CHARACTER_LIST_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var characters = characterService.listForAccount(account.getId(), account.getMainCharaId());

		var buffer = ctx.buffer(LIST_PAYLOAD_SIZE);
		buffer.writeInt(GameError.NONE.result())
			.writeByte(account.getSlots())
			.writeByte(characters.size())
			.writeZero(1);

		for (var i = 0; i < characters.size(); i++) {
			var chara = characters.get(i);
			var name = displayName(chara, account.getMainCharaId());

			// The first entry is introduced by its name; later ones by their index.
			if (i == 0) {
				BufferUtil.writeString(buffer, name, StandardCharsets.ISO_8859_1, NAME_LENGTH);
				buffer.writeZero(1);
			} else {
				buffer.writeInt(i);
			}

			buffer.writeInt((int) chara.getId());
			BufferUtil.writeString(buffer, name, StandardCharsets.ISO_8859_1, NAME_LENGTH);
			writeAppearance(buffer, characterService.getAppearance(chara.getId()).orElseGet(CharaAppearance::new));
		}

		buffer.writeZero(LIST_TRAILER_OFFSET - buffer.writerIndex());
		buffer.writeBytes(LIST_TRAILER);

		ctx.write(new GamePacket(CHARACTER_LIST_RESULT, buffer));
	}

	/** The main character is shown with a leading asterisk. */
	private static String displayName(Chara chara, Long mainCharaId) {
		if (mainCharaId != null && chara.getId() == mainCharaId) {
			return "*" + chara.getName();
		}
		return chara.getName();
	}

	private static void writeAppearance(ByteBuf buffer, CharaAppearance a) {
		buffer.writeByte(a.getGender()).writeByte(a.getFace()).writeByte(a.getUpper())
			.writeByte(a.getLower()).writeByte(a.getFacePaint()).writeByte(a.getUpperColor())
			.writeByte(a.getLowerColor()).writeByte(a.getVoice()).writeByte(a.getPitch())
			.writeZero(4)
			.writeByte(a.getHead()).writeByte(a.getChest()).writeByte(a.getHands())
			.writeByte(a.getWaist()).writeByte(a.getFeet()).writeByte(a.getAccessory1())
			.writeByte(a.getAccessory2()).writeByte(a.getHeadColor()).writeByte(a.getChestColor())
			.writeByte(a.getHandsColor()).writeByte(a.getWaistColor()).writeByte(a.getFeetColor())
			.writeByte(a.getAccessory1Color()).writeByte(a.getAccessory2Color())
			.writeZero(1);
	}

	private void createCharacter(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(CREATE_CHARACTER_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < NAME_LENGTH) {
			ctx.write(CREATE_CHARACTER_RESULT, GameError.GENERAL);
			return;
		}

		var name = readString(payload, NAME_LENGTH);

		var check = CharacterNames.check(name);
		if (check != CharacterNames.Result.OK) {
			logger.info("Rejected character name {}: {}", name, check);
			ctx.write(CREATE_CHARACTER_RESULT, switch (check) {
				case RESERVED_PREFIX -> GameError.CHARACTER_NAME_PREFIX;
				case RESERVED_NAME -> GameError.CHARACTER_NAME_RESERVED;
				default -> GameError.CHARACTER_NAME_INVALID;
			});
			return;
		}

		if (characterService.isNameTaken(name)) {
			ctx.write(CREATE_CHARACTER_RESULT, GameError.CHARACTER_NAME_TAKEN);
			return;
		}

		var appearance = readAppearance(payload);

		long charaId;
		try {
			charaId = characterService.create(account.getId(), name, appearance);
		} catch (RuntimeException e) {
			// Most likely the unique name constraint, if two clients raced for the same name.
			logger.warn("Failed to create character {}.", name, e);
			ctx.write(CREATE_CHARACTER_RESULT, GameError.CHARACTER_NAME_TAKEN);
			return;
		}

		// The account now points at the new character, and gained a main if it had none.
		account.setCurrentCharaId(charaId);
		if (account.getMainCharaId() == null) {
			account.setMainCharaId(charaId);
		}

		var buffer = ctx.buffer(8);
		buffer.writeInt(GameError.NONE.result()).writeInt((int) charaId);
		ctx.write(new GamePacket(CREATE_CHARACTER_RESULT, buffer));
	}

	/**
	 * Reads the appearance block. The skipped bytes are fields the client sends but the original
	 * server discarded, so lower and hands colour are always stored as zero.
	 */
	private static CharaAppearance readAppearance(ByteBuf payload) {
		var a = new CharaAppearance();
		if (payload.readableBytes() < 27) {
			return a;
		}

		a.setGender(payload.readByte());
		a.setFace(payload.readByte());
		a.setUpper(payload.readByte());
		payload.skipBytes(1);
		a.setFacePaint(payload.readByte());
		a.setUpperColor(payload.readByte());
		a.setLowerColor(payload.readByte());
		a.setVoice(payload.readByte());
		a.setPitch(payload.readByte());
		payload.skipBytes(4);
		a.setHead(payload.readByte());
		a.setChest(payload.readByte());
		a.setHands(payload.readByte());
		a.setWaist(payload.readByte());
		a.setFeet(payload.readByte());
		a.setAccessory1(payload.readByte());
		a.setAccessory2(payload.readByte());
		a.setHeadColor(payload.readByte());
		a.setChestColor(payload.readByte());
		payload.skipBytes(1);
		a.setWaistColor(payload.readByte());
		a.setFeetColor(payload.readByte());
		a.setAccessory1Color(payload.readByte());
		a.setAccessory2Color(payload.readByte());
		return a;
	}

	private void selectCharacter(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(SELECT_CHARACTER_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var characters = characterService.listForAccount(account.getId(), account.getMainCharaId());
		if (characters.isEmpty()) {
			ctx.write(SELECT_CHARACTER_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		var index = clampIndex(readIndex(ctx), characters.size(), 0);
		var chara = characters.get(index);

		characterService.setCurrentCharacter(account.getId(), chara.getId());
		account.setCurrentCharaId(chara.getId());

		ctx.write(SELECT_CHARACTER_RESULT, GameError.NONE);
	}

	private void deleteCharacter(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null) {
			ctx.write(DELETE_CHARACTER_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var characters = characterService.listForAccount(account.getId(), account.getMainCharaId());
		if (characters.isEmpty()) {
			ctx.write(DELETE_CHARACTER_RESULT, GameError.CHARACTER_DOES_NOT_EXIST);
			return;
		}

		// Delete clamps to the last character rather than the first, matching the original.
		var index = clampIndex(readIndex(ctx), characters.size(), characters.size() - 1);
		var chara = characters.get(index);

		if (!characterService.canDelete(chara, OffsetDateTime.now())) {
			ctx.write(DELETE_CHARACTER_RESULT, GameError.CHARACTER_CANNOT_DELETE_YET);
			return;
		}

		characterService.delete(account.getId(), chara.getId());

		if (account.getMainCharaId() != null && account.getMainCharaId() == chara.getId()) {
			account.setMainCharaId(null);
		}
		if (account.getCurrentCharaId() != null && account.getCurrentCharaId() == chara.getId()) {
			account.setCurrentCharaId(null);
		}

		ctx.write(DELETE_CHARACTER_RESULT, GameError.NONE);
	}

	private static int readIndex(GameControllerContext ctx) {
		var payload = ctx.packet().getPayload();
		return payload.readableBytes() > 0 ? payload.readByte() : 0;
	}

	private static int clampIndex(int index, int size, int fallback) {
		return index < 0 || index >= size ? fallback : index;
	}

	static List<Chara> ordered(CharacterService service, long accountId, Long mainCharaId) {
		return service.listForAccount(accountId, mainCharaId);
	}

	private static String readString(ByteBuf buffer, int length) {
		var bytes = new byte[Math.min(length, buffer.readableBytes())];
		buffer.readBytes(bytes);

		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, 0, end, StandardCharsets.ISO_8859_1);
	}
}
