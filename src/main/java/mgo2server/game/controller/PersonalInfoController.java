package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.service.CharacterService;
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
 * Wardrobe and comment changes made from inside a game lobby.
 * <p>
 * The client sends this whenever the player changes clothes or edits their comment, and it blocks
 * on the reply: with nothing sent back it stalls and fails with <em>Unable to update character
 * information (1031:FFFFFF60)</em>.
 * <p>
 * Note that this command carries {@code lower} and {@code hands_color}, which character creation
 * (0x3101) skips over. That makes the creation-time skip look more like a bug than a deliberate
 * choice — see the note in {@code dev/docs/OBSERVED.md}. Here the fields are read and stored.
 */
public class PersonalInfoController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	public static final int UPDATE_PERSONAL_INFO = 0x4130;

	public static final int UPDATE_PERSONAL_INFO_RESULT = 0x4131;

	public static final int COMMIT_OUTFIT = 0x4132;

	public static final int COMMIT_OUTFIT_RESULT = 0x4133;

	/**
	 * The fixed tail of the {@code 0x4133} reply: fifteen {@code {u8 slot, u8 bit}} pairs the
	 * parser at {@code 0xd3c77c} always reads, setting equipped bits in the loadout table it has
	 * just zeroed. All-zero pairs redundantly touch bit 0 of slot 0 — no distinct no-op encoding
	 * is known, and what the original filled these with awaits a capture.
	 */
	private static final int COMMIT_TRAILER_PAIRS = 15;

	private static final int COMMENT_LENGTH = 128;

	/** Nineteen clothing bytes, four skills, a pad, four levels, two pads, then the comment. */
	private static final int REQUEST_SIZE = 19 + 4 + 1 + 4 + 2 + COMMENT_LENGTH;

	/**
	 * Per-skill experience echoed back. The same fixed value the personal-info packet (0x4122)
	 * sends; why it is constant is not understood, only that both references send it.
	 */
	private static final int SKILL_EXPERIENCE = 0x600000;

	/**
	 * Face-paint colour unlock bitmask, one bit per colour. Both references send all-ones, so
	 * every colour is offered; no source of a narrower value has been found.
	 */
	private static final int FACE_PAINT_UNLOCKED = 0xffffffff;

	private final CharacterService characterService;

	public PersonalInfoController(CharacterService characterService) {
		this.characterService = characterService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(UPDATE_PERSONAL_INFO, this::updatePersonalInfo);
		handlers.put(COMMIT_OUTFIT, this::commitOutfit);
	}

	/**
	 * Outfit commit ({@code 0x4132}, empty payload): fired after the {@code 0x4130} updates when
	 * the outfit screen closes, and blocked on. The reply is not a result code — the parser at
	 * {@code 0xd3c77c} reads a u32 <em>entry count</em>, {@code count × {u8 slot, u32 value}}
	 * loadout entries, then the fixed fifteen-pair trailer; a nonzero first u32 would be read as
	 * a count, not an error. Zero entries is the honest reply until the entry semantics are
	 * captured: the client zeroes its loadout table first either way.
	 */
	private void commitOutfit(GameControllerContext ctx) {
		var buffer = ctx.buffer(Integer.BYTES + COMMIT_TRAILER_PAIRS * 2);
		buffer.writeInt(0);
		buffer.writeZero(COMMIT_TRAILER_PAIRS * 2);
		ctx.write(new GamePacket(COMMIT_OUTFIT_RESULT, buffer));
	}

	private void updatePersonalInfo(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(UPDATE_PERSONAL_INFO_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < REQUEST_SIZE) {
			logger.warn("Update personal info: payload too short ({} bytes).", payload.readableBytes());
			ctx.write(UPDATE_PERSONAL_INFO_RESULT, GameError.GENERAL);
			return;
		}

		var charaId = account.getCurrentCharaId();
		var a = new CharaAppearance();

		a.setUpper(payload.readByte());
		a.setLower(payload.readByte());
		a.setFacePaint(payload.readByte());
		a.setUpperColor(payload.readByte());
		a.setLowerColor(payload.readByte());
		a.setHead(payload.readByte());
		a.setChest(payload.readByte());
		a.setHands(payload.readByte());
		a.setWaist(payload.readByte());
		a.setFeet(payload.readByte());
		a.setAccessory1(payload.readByte());
		a.setAccessory2(payload.readByte());
		a.setHeadColor(payload.readByte());
		a.setChestColor(payload.readByte());
		a.setHandsColor(payload.readByte());
		a.setWaistColor(payload.readByte());
		a.setFeetColor(payload.readByte());
		a.setAccessory1Color(payload.readByte());
		a.setAccessory2Color(payload.readByte());

		var skills = new byte[4];
		payload.readBytes(skills);

		payload.skipBytes(1);
		var levels = new byte[4];
		payload.readBytes(levels);

		payload.skipBytes(2);
		var comment = readNulTerminated(payload, COMMENT_LENGTH);

		characterService.updateAppearance(charaId, a);
		characterService.updateComment(charaId, comment);
		// Live 2026-07-23: without this, an equipped skill survives the session (the echo below
		// keeps the menu populated) but vanishes on the next connect burst, whose 0x4122 reads
		// chara_equipped_skills.
		characterService.updateEquippedSkills(charaId, skills, levels);

		ctx.write(new GamePacket(UPDATE_PERSONAL_INFO_RESULT, reply(ctx, a, skills, levels, comment)));
	}

	/**
	 * Echoes the accepted change back. The client wants its own values returned rather than a bare
	 * result code, which is why this is not a four-byte reply like its neighbours.
	 */
	private ByteBuf reply(GameControllerContext ctx, CharaAppearance a, byte[] skills, byte[] levels,
			String comment) {
		var buffer = ctx.buffer(4 + 19 + 4 + 1 + 4 + 1 + 16 + 5 + COMMENT_LENGTH + 4);

		buffer.writeZero(4);
		buffer.writeByte(a.getUpper()).writeByte(a.getLower()).writeByte(a.getFacePaint())
			.writeByte(a.getUpperColor()).writeByte(a.getLowerColor())
			.writeByte(a.getHead()).writeByte(a.getChest()).writeByte(a.getHands())
			.writeByte(a.getWaist()).writeByte(a.getFeet())
			.writeByte(a.getAccessory1()).writeByte(a.getAccessory2())
			.writeByte(a.getHeadColor()).writeByte(a.getChestColor()).writeByte(a.getHandsColor())
			.writeByte(a.getWaistColor()).writeByte(a.getFeetColor())
			.writeByte(a.getAccessory1Color()).writeByte(a.getAccessory2Color());

		buffer.writeBytes(skills).writeZero(1).writeBytes(levels).writeZero(1);

		for (var i = 0; i < 4; i++) {
			buffer.writeInt(SKILL_EXPERIENCE);
		}

		buffer.writeZero(5);
		BufferUtil.writeString(buffer, comment, StandardCharsets.ISO_8859_1, COMMENT_LENGTH);
		buffer.writeInt(FACE_PAINT_UNLOCKED);

		return buffer;
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
