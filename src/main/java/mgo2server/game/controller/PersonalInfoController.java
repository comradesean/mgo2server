package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.service.CharacterService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.PersonalInfoWriter;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.LoadoutWriter;
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

	private static final int COMMENT_LENGTH = 128;

	/** Nineteen clothing bytes, four skills, a pad, four levels, two pads, then the comment. */
	private static final int REQUEST_SIZE = 19 + 4 + 1 + 4 + 2 + COMMENT_LENGTH;

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
	 * loadout entries, then the fixed sixteen-pair trailer; a nonzero first u32 would be read as
	 * a count, not an error.
	 * <p>
	 * <strong>This is the same table {@code 0x4124} fills, and sending zero entries wiped it.</strong>
	 * [ELF] Both parsers address it with the identical {@code addi r9,r9,9888} ({@code +0x26a0}) —
	 * {@code 0xD3CF10}/{@code 0xD3CFC0} in the {@code 0x4124} parser, {@code 0xD3C85C}/{@code
	 * 0xD3C90C} in this one — and the shapes agree: {@code 4 + 5·count + 32} at 123 items is 651
	 * bytes, exactly what {@code 0x4124} sends. The parser <em>zeroes the whole {@code 0x60c}-byte
	 * table before applying entries</em>, so a count of 0 did not mean "no change", it meant
	 * "forget every item you own". A character logged in with the full catalogue, opened the
	 * outfit screen, and closed it with nothing unlocked — not even starter gear.
	 * <p>
	 * So the reply reads the character's gear back, from the same
	 * {@link CharacterService#ownedGear} the {@code 0x4124} writer uses. That shared source is the
	 * point: while the catalogue was a constant only one of the two writers held, the two could
	 * disagree, and the client keeps whichever spoke last. Any future narrowing — a starter set,
	 * an unlock — now narrows both at once by construction.
	 */
	private void commitOutfit(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			// The reply is a table, not a result code, so there is no error shape to send: a
			// nonzero first word would be read as an entry count. Staying silent stalls the
			// screen, but a session with no character cannot have reached it.
			logger.warn("Outfit commit with no selected character; ignoring.");
			return;
		}

		var gear = characterService.ownedGear(account.getCurrentCharaId());
		var buffer = ctx.buffer(LoadoutWriter.gearPayloadSize(gear.size()));
		LoadoutWriter.writeGear(buffer, gear);
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

		ctx.write(new GamePacket(UPDATE_PERSONAL_INFO_RESULT,
			reply(ctx, charaId, a, skills, levels, comment)));
	}

	/**
	 * Echoes the accepted change back. The client wants its own values returned rather than a bare
	 * result code, which is why this is not a four-byte reply like its neighbours.
	 */
	private ByteBuf reply(GameControllerContext ctx, long charaId, CharaAppearance a, byte[] skills,
			byte[] levels, String comment) {
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

		// REAL PER-SKILL EXPERIENCE, from chara_skill. This echoed a fixed 0x600000 until
		// 2026-07-29 — inherited from a reference server and never explained. That value is
		// 0x6000 << 8, i.e. 256x the client's own legal maximum of 24576, and the validator at
		// 0x93E418 ZEROES any record above that rather than clamping. It survived only because
		// 0x600000 >> 13 still clamps to level 3, so every equipped skill rendered as maxed.
		//
		// It has to match what 0x4122 sends for the same slots, or the skill screen disagrees with
		// itself between the connect burst and a wardrobe change — hence the shared helper.
		var experience = characterService.skillExperience(charaId);
		for (var slot = 0; slot < 4; slot++) {
			buffer.writeInt(PersonalInfoWriter.reportedExperience(
				experience.applyAsInt(skills[slot] & 0xFF), levels[slot] & 0xFF));
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
