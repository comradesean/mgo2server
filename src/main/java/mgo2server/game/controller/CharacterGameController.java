package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import mgo2server.common.BufferUtil;
import mgo2server.common.CharacterNames;
import mgo2server.common.model.Chara;
import mgo2server.common.model.Account;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.service.AccountService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
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

	/**
	 * Name availability, asked before the client will submit a character for creation.
	 * <p>
	 * This is <em>not</em> optional, however it may look elsewhere. savemgo's Nomad names the
	 * command in a commented-out case and ships without it, but this client blocks on the reply:
	 * with nothing sent back it waits about forty seconds, never sends {@link #CREATE_CHARACTER},
	 * and fails with <em>Unable to register character (0A41:FFFFFF60)</em>.
	 */
	public static final int CHECK_CHARACTER_NAME = 0x3107;

	public static final int CHECK_CHARACTER_NAME_RESULT = 0x3108;

	private static final int NAME_LENGTH = 16;

	/** The 23-byte header: result, slot count, character count, selected slot, selected name. */
	private static final int LIST_HEADER_SIZE = 23;

	/** One character: slot index, id, name, appearance. */
	private static final int LIST_ENTRY_SIZE = 52;

	/**
	 * The client's parser (0xD3732C) consumes a fixed grid regardless of how many characters are in
	 * it: the header, then <b>eight</b> 52-byte slots, then a trailing block. Slots beyond the
	 * character count are zero-filled.
	 */
	private static final int LIST_SLOTS = 8;

	/** Where the eight slots end and the trailing block begins: 23 + 8*52 = 439. */
	private static final int LIST_TRAILER_OFFSET = LIST_HEADER_SIZE + LIST_SLOTS * LIST_ENTRY_SIZE;

	private static final int LIST_PAYLOAD_SIZE = 0x1d7;

	/**
	 * The trailing block, 32 bytes, so the whole payload is 0x1d7.
	 * <p>
	 * This was written as a 35-byte constant zero-filled to offset 0x1b4, on the reading that the
	 * first three bytes "complete the eighth slot". The totals are identical and it is wrong: the
	 * slots end at 0x1b7, and the three bytes belong to the zero fill. That is invisible while the
	 * grid is short — but at eight characters the writer index passes 0x1b4 and the zero-fill length
	 * goes negative. Slots are capped at four by policy, so it was not reachable; a policy number is
	 * a poor thing to have load-bearing under a framing error, hence {@link #LIST_SLOTS} and the
	 * length assertion below.
	 * <p>
	 * This packet has already cost one live break from arithmetic that happened to add up — a
	 * three-byte-short appearance block cancelling a four-byte slot index — which is the argument
	 * for asserting the total rather than trusting that it works out.
	 */
	/**
	 * <b>Index 3 bit 0 grants the 32 CODEC / preset messages — the day-one paid MGO Codec Pack.</b>
	 * <p>
	 * Two readers, both of the same byte at {@code ctx+22455} — trailer index 3. {@code 0x9B9E30}
	 * computes {@code (byte & 1) << 4}, i.e. 0 or 16, and {@code 0x9BADA4} tests {@code byte & 1} to
	 * choose between two list-builders. The 16 is a threshold: the predicate {@code 0x9B9DF0} walks
	 * the preset-message catalogue at {@code 0xE1812C} and refuses any phrase whose gate exceeds it.
	 * Of the 82 populated rows, <b>32 gate on exactly 16</b> — matched 32/32 to the published product
	 * list, in order — 23 gate on 0 and are always available, and 27 are the Combat Training
	 * instructor commands, which no server field controls.
	 * <p>
	 * <b>It has nothing to do with gear.</b> {@code 0x9B9DF0} has 17 call sites binary-wide, none in
	 * loadout code, and this byte has no third reader. An earlier note here said the bit unlocked
	 * "32 of the 91 selectable loadout items" and that clearing it emptied the loadout screen; both
	 * were wrong, and a live test showed gear entirely unaffected.
	 * <p>
	 * We send bit 1 clear. It is read by nothing here and is most likely the second codec pack,
	 * which needed a client update — see {@code dev/docs/POST_LAUNCH.md}.
	 * <p>
	 * <b>32 bytes, not 35</b> — independently confirmed from the parser side: {@code 0xD3732C} copies
	 * exactly 32 (`li r5,32` at {@code 0xD3774C}). Subtracting the phantom three from the old
	 * "35-byte trailer with 07 at +4 and 03 at +6" lands them on indices 1 and 3, which is exactly
	 * where they sit here.
	 */
	/** [ELF 0xD3774C] The parser copies exactly 32 bytes; 35 was a phantom. */
	private static final int TRAILER_SIZE = 32;

	/**
	 * The trailer's entitlement byte — index 3, and the only byte in the 32 with any reader.
	 *
	 * <p>Sourced from {@code account.entitlements_byte3} (V62, renamed V65) rather than a constant, so it is
	 * <b>per account and editable live</b>: an {@code UPDATE} takes effect on the next
	 * character-list fetch, with no restart and without touching anyone else.
	 *
	 * <p>[ELF] only bit 0 is read, by two sites on the same byte at {@code ctx+22455}:
	 * {@code 0x9B9E30} computes {@code (byte & 1) << 4} — 0 or 16 — and {@code 0x9BADA4} tests
	 * {@code byte & 1} to pick between two list-builders. The 16 is a threshold: the availability
	 * predicate {@code 0x9B9DF0} walks an 85-entry table at {@code 0xE1812C} and refuses any entry
	 * whose gate exceeds it. <b>32 entries gate on exactly 16</b>, so clearing bit 0 removes them.
	 *
	 * <p><b>RESOLVED LIVE 2026-07-29.</b> The first trace called these "32 of the 91 selectable
	 * loadout items"; that is wrong. Clearing the bit on one account removed the <b>codec / preset
	 * message</b> list and left gear and outfits <em>entirely unchanged</em>. So the 85-entry table
	 * at {@code 0xE1812C} is a preset-message table. The 32 are almost certainly the day-one paid
	 * "MGO Codec Pack" — 32 additional voice tracks, bound to the Konami ID, which is consistent
	 * with this being per-account. See {@code dev/docs/POST_LAUNCH.md}.
	 */
	private static final int TRAILER_ENTITLEMENT_INDEX = 3;

	/**
	 * Index 1 carries {@code 0x07}, and <b>none of its three set bits is understood</b>.
	 *
	 * <p>Per account since V63, so they can be isolated live. <b>Nobody has actually looked for a
	 * reader of this byte.</b> The search that reported "no reader" looked for {@code lbz r0,487(r3)},
	 * which is <em>index 3</em>'s offset ({@code ctx+21968 + 487}); index 1 is {@code 485}. So the
	 * negative does not cover this byte at all — see {@code dev/docs/POST_LAUNCH.md}.
	 */
	private static final int TRAILER_INDEX1 = 1;

	/**
	 * Builds the trailer for one account.
	 *
	 * <p><b>Provenance, and why every set bit is per-account.</b> The values {@code 0x07} at index 1
	 * and {@code 0x03} at index 3 are <b>tier 4</b>: `PROTOCOL.md` lists them under "fixed constants
	 * we emit without knowing why", noting only that "both Nomad upstreams and mgo2-server send
	 * these exact bytes". They were never derived from the binary or from a Konami capture.
	 *
	 * <p>That mattered more than it looked. Of the five bits we set, exactly one is now understood —
	 * index 3 bit 0 — and it grants the <b>MGO Codec Pack, a day-one PAID item</b>. We were handing
	 * out purchased content because a reference server did. The remaining four bits are unexamined
	 * and could be doing the same thing.
	 *
	 * <p><b>Bit 1 does nothing on this build.</b> The byte is read at exactly two addresses
	 * binary-wide — {@code 0x9B9E30} and {@code 0x9BADA4}, both in the preset-message subsystem —
	 * and both test bit 0 only. The store sold a <em>second</em> codec pack which reportedly needed
	 * a client update, and bit 1 being inert here is consistent with that: the content would not
	 * exist for a flag to unlock. Ten phrase ids are shipped on the disc but absent from the
	 * catalogue (27, 34, 35 and 58..64) — that is what a later pack would extend.
	 */
	private static byte[] trailerFor(Account account) {
		var trailer = new byte[TRAILER_SIZE];
		trailer[TRAILER_INDEX1] = (byte) (account.getEntitlementsByte1() & 0xff);
		trailer[TRAILER_ENTITLEMENT_INDEX] = (byte) (account.getEntitlementsByte3() & 0xff);
		return trailer;
	}

	private final AccountService accountService;

	private final CharacterService characterService;

	private final ClanService clanService;

	public CharacterGameController(AccountService accountService, CharacterService characterService,
			ClanService clanService) {
		this.accountService = accountService;
		this.characterService = characterService;
		this.clanService = clanService;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(GET_CHARACTER_LIST, this::getCharacterList);
		handlers.put(CREATE_CHARACTER, this::createCharacter);
		handlers.put(CHECK_CHARACTER_NAME, this::checkCharacterName);
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

		// The grid has eight slots and no more. Slot counts are policy and could be raised past the
		// current maximum of four by an operator edit; the packet's shape cannot follow them.
		var shown = Math.min(characters.size(), LIST_SLOTS);

		// Header: result, slot count, character count, the selected slot, then that character's
		// name. Then one FIXED 52-byte entry per character.
		//
		// This used to introduce the first entry with its name and every later one with a 4-byte
		// index, which is not the layout — it happened to total 52 bytes only because the appearance
		// block was three bytes short at the same time. The two errors cancelled for a
		// single-character account and stopped cancelling the moment a second character existed,
		// which is what corrupted the character-select screen.
		// The selected slot is the character this account last chose — NOT always the first.
		//
		// Hardcoding slot 0 quietly undid every selection. The client sends 0x3103 with the slot it
		// picked, we record it, and then the client re-fetches this list and takes its selection
		// back from this header: with slot 0 and the first character's name in it, choosing the
		// second character and entering the lobby logged the player in as the first.
		var selectedSlot = 0;
		for (var i = 0; i < characters.size(); i++) {
			if (account.getCurrentCharaId() != null
					&& characters.get(i).getId() == account.getCurrentCharaId()) {
				selectedSlot = i;
				break;
			}
		}
		var selectedName = characters.isEmpty() ? ""
			: displayName(characters.get(selectedSlot), account.getMainCharaId());

		var buffer = ctx.buffer(LIST_PAYLOAD_SIZE);
		buffer.writeInt(GameError.NONE.result())
			.writeByte(account.getSlots())
			.writeByte(shown)
			.writeByte(selectedSlot);
		BufferUtil.writeString(buffer, selectedName, StandardCharsets.ISO_8859_1, NAME_LENGTH);

		for (var i = 0; i < shown; i++) {
			var chara = characters.get(i);
			var name = displayName(chara, account.getMainCharaId());

			buffer.writeByte(i);
			buffer.writeInt((int) chara.getId());
			BufferUtil.writeString(buffer, name, StandardCharsets.ISO_8859_1, NAME_LENGTH);
			writeAppearance(buffer, characterService.getAppearance(chara.getId()).orElseGet(CharaAppearance::new),
				characterService.secondsUntilDeletable(chara, OffsetDateTime.now()));
		}

		buffer.writeZero(LIST_TRAILER_OFFSET - buffer.writerIndex());
		buffer.writeBytes(trailerFor(account));

		assert buffer.readableBytes() == LIST_PAYLOAD_SIZE
			: "Character list must be " + LIST_PAYLOAD_SIZE + " bytes, was " + buffer.readableBytes();

		ctx.write(new GamePacket(CHARACTER_LIST_RESULT, buffer));
	}

	/** The main character is shown with a leading asterisk. */
	private static String displayName(Chara chara, Long mainCharaId) {
		if (mainCharaId != null && chara.getId() == mainCharaId) {
			return "*" + chara.getName();
		}
		return chara.getName();
	}

	/**
	 * The appearance block and the entry's trailing {@code u32}, which is the <b>delete cooldown in
	 * seconds</b> — how long until this character may be deleted.
	 * <p>
	 * The client reads it at wire {@code +0x30} of each 52-byte entry (parser {@code 0xD372F8},
	 * stored to {@code sess+0x55D4+60*slot+56}) and the character-management screen formats it at
	 * {@code 0x9510B4}: non-zero rounds up to whole minutes and produces "Characters cannot be
	 * deleted for a fixed amount of time after being registered. You must wait %d hours %d minutes"
	 * (lobby strings 11848 / 11854); zero lets the deletion proceed.
	 * <p>
	 * This also corrects the entry's size. The block was written as 28 bytes — nine appearance
	 * bytes, four zero, fourteen appearance bytes and a single pad — where the layout is 31, the pad
	 * standing in for this u32. Every entry was three bytes short, which the trailer padding hid
	 * because only the first entry is ever populated for a one-character account.
	 */
	private static void writeAppearance(ByteBuf buffer, CharaAppearance a, long deleteCooldown) {
		buffer.writeByte(a.getGender()).writeByte(a.getFace()).writeByte(a.getUpper())
			.writeByte(a.getLower()).writeByte(a.getFacePaint()).writeByte(a.getUpperColor())
			.writeByte(a.getLowerColor()).writeByte(a.getVoice()).writeByte(a.getPitch())
			.writeZero(4)
			.writeByte(a.getHead()).writeByte(a.getChest()).writeByte(a.getHands())
			.writeByte(a.getWaist()).writeByte(a.getFeet()).writeByte(a.getAccessory1())
			.writeByte(a.getAccessory2()).writeByte(a.getHeadColor()).writeByte(a.getChestColor())
			.writeByte(a.getHandsColor()).writeByte(a.getWaistColor()).writeByte(a.getFeetColor())
			.writeByte(a.getAccessory1Color()).writeByte(a.getAccessory2Color())
			.writeInt((int) deleteCooldown);
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

		var rejection = rejectionFor(name);
		if (rejection != null) {
			ctx.write(CREATE_CHARACTER_RESULT, rejection);
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
	 * Answers whether a name may be registered, before the client will offer one for creation.
	 * <p>
	 * Shares {@link #rejectionFor} with {@link #createCharacter} deliberately. A pre-check that
	 * answered more leniently than the create it precedes would only move the failure one screen
	 * later, which is worse than not having one.
	 */
	private void checkCharacterName(GameControllerContext ctx) {
		if (ctx.connection().account() == null) {
			ctx.write(CHECK_CHARACTER_NAME_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < NAME_LENGTH) {
			ctx.write(CHECK_CHARACTER_NAME_RESULT, GameError.GENERAL);
			return;
		}

		var name = readString(payload, NAME_LENGTH);
		var rejection = rejectionFor(name);

		ctx.write(CHECK_CHARACTER_NAME_RESULT, rejection == null ? GameError.NONE : rejection);
	}

	/** The error a name should be refused with, or null if it is free to register. */
	private GameError rejectionFor(String name) {
		var check = CharacterNames.check(name);
		if (check != CharacterNames.Result.OK) {
			logger.info("Rejected character name {}: {}", name, check);
			return switch (check) {
				case RESERVED_PREFIX -> GameError.CHARACTER_NAME_PREFIX;
				case RESERVED_NAME -> GameError.CHARACTER_NAME_RESERVED;
				default -> GameError.CHARACTER_NAME_INVALID;
			};
		}

		return characterService.isNameTaken(name) ? GameError.CHARACTER_NAME_TAKEN : null;
	}

	/**
	 * Reads the appearance block.
	 * <p>
	 * Two bytes here were long skipped, on an inherited claim that the original server discarded
	 * them. That was wrong. The wardrobe update (0x4130) carries the same fields in the same order
	 * and names them: the byte after {@code upper} is {@code lower}, and the byte after
	 * {@code chestColor} is {@code handsColor}. Both were verified against a live client, whose
	 * stored {@code lower} went from 0 to a real value the moment 0x4130 was implemented — so
	 * creation had been silently dropping the player's choices.
	 */
	private static CharaAppearance readAppearance(ByteBuf payload) {
		var a = new CharaAppearance();
		if (payload.readableBytes() < 27) {
			return a;
		}

		a.setGender(payload.readByte());
		a.setFace(payload.readByte());
		a.setUpper(payload.readByte());
		a.setLower(payload.readByte());
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
		a.setHandsColor(payload.readByte());
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

		// A LEADER CANNOT DELETE THEMSELVES, and the client says exactly why: "You are the leader of
		// a clan. Either disband the clan or assign another character as leader." Both routes already
		// exist in game — 0x4b04 disband and 0x4b60 transfer leadership.
		//
		// This REPLACES an auto-succession policy written earlier the same day, which promoted the
		// longest-standing member (or disbanded a one-member clan) and let the delete proceed. That
		// was chosen because -1212 was thought unestablished, so refusing would have shown a generic
		// sentence and left the player stuck. -1212 is established (sweep of all 4353 codes, chain
		// 0x94F60C), and it does more than refuse — it names the two ways out. Picking a successor on
		// the player's behalf is a decision the game itself declines to make.
		//
		// The check is still load-bearing beyond the sentence: the delete is a SOFT delete, so
		// clan.leader_chara_id's "on delete set null" never fires and a leader who got through left
		// the clan pointing at somebody who could never log in again.
		var membership = clanService.membershipOf(chara.getId());
		if (membership.id() != 0 && membership.state() == ClanService.STATE_LEADER) {
			logger.info("Delete of character {} refused: it leads clan {}.",
				chara.getId(), membership.id());
			ctx.write(DELETE_CHARACTER_RESULT, GameError.CHARACTER_IS_CLAN_LEADER);
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
