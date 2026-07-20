package nomad.common.service;

import nomad.common.CharacterNames;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.model.CharaSettings;
import nomad.common.model.ChatMacro;
import nomad.common.model.EquippedSkills;
import nomad.common.model.GearSet;
import nomad.common.model.SkillSet;
import org.jdbi.v3.core.Jdbi;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class CharacterService {
	/** A character cannot be deleted until it has existed this long. */
	public static final Duration DELETE_COOLDOWN = Duration.ofDays(7);

	private final Jdbi jdbi;

	public CharacterService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/**
	 * Live characters for an account, with the account's main character first.
	 * <p>
	 * The client addresses characters by their position in this list, so every command that takes
	 * an index must order them identically — hence the single method rather than each caller
	 * sorting for itself.
	 */
	public List<Chara> listForAccount(long accountId, Long mainCharaId) {
		var characters = jdbi.withHandle(handle ->
			handle.createQuery("select * from chara where account_id=:id and active=true order by id")
				.bind("id", accountId)
				.mapTo(Chara.class)
				.list());

		var ordered = new ArrayList<>(characters);
		if (mainCharaId != null) {
			for (var i = 0; i < ordered.size(); i++) {
				if (ordered.get(i).getId() == mainCharaId) {
					ordered.add(0, ordered.remove(i));
					break;
				}
			}
		}
		return ordered;
	}

	public Optional<Chara> get(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara where id=:id")
				.bind("id", charaId)
				.mapTo(Chara.class)
				.findOne());
	}

	/**
	 * Chat macros as a dense grid, filling in blanks for any the character has never set. The
	 * client always expects a full set, so absent rows become empty text rather than gaps.
	 */
	public List<ChatMacro> getChatMacros(long charaId) {
		var stored = jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_chat_macro where chara_id=:id")
				.bind("id", charaId)
				.mapTo(ChatMacro.class)
				.list());

		var grid = new ArrayList<ChatMacro>();
		for (var type = 0; type < ChatMacro.TYPES; type++) {
			for (var index = 0; index < ChatMacro.PER_TYPE; index++) {
				var macro = new ChatMacro();
				macro.setCharaId(charaId);
				macro.setType(type);
				macro.setIndex(index);
				for (var candidate : stored) {
					if (candidate.getType() == type && candidate.getIndex() == index) {
						macro.setText(candidate.getText());
						break;
					}
				}
				grid.add(macro);
			}
		}
		return grid;
	}

	/**
	 * Gameplay and interface settings, materialised with defaults on first use. The original does
	 * the same, handing back a default blob for a character that has never saved any.
	 */
	public CharaSettings getOrCreateSettings(long charaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("insert into chara_settings (chara_id) values (:id) on conflict do nothing")
				.bind("id", charaId)
				.execute());

		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_settings where chara_id=:id")
				.bind("id", charaId)
				.mapTo(CharaSettings.class)
				.one());
	}

	public EquippedSkills getOrCreateEquippedSkills(long charaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("insert into chara_equipped_skills (chara_id) values (:id) on conflict do nothing")
				.bind("id", charaId)
				.execute());

		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_equipped_skills where chara_id=:id")
				.bind("id", charaId)
				.mapTo(EquippedSkills.class)
				.one());
	}

	/**
	 * The character's three skill loadouts, created empty on first use. The client always expects
	 * three, so absent rows are materialised rather than returned as gaps.
	 */
	public List<SkillSet> getOrCreateSkillSets(long charaId) {
		createSets(charaId, "chara_skill_set");

		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_skill_set where chara_id=:id order by index")
				.bind("id", charaId)
				.mapTo(SkillSet.class)
				.list());
	}

	public List<GearSet> getOrCreateGearSets(long charaId) {
		createSets(charaId, "chara_gear_set");

		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_gear_set where chara_id=:id order by index")
				.bind("id", charaId)
				.mapTo(GearSet.class)
				.list());
	}

	private void createSets(long charaId, String table) {
		jdbi.useHandle(handle -> {
			for (var index = 0; index < SkillSet.PER_CHARACTER; index++) {
				handle.createUpdate("insert into " + table + " (chara_id, index) values (:id, :index)"
						+ " on conflict do nothing")
					.bind("id", charaId)
					.bind("index", index)
					.execute();
			}
		});
	}

	public Optional<CharaAppearance> getAppearance(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_appearance where chara_id=:id")
				.bind("id", charaId)
				.mapTo(CharaAppearance.class)
				.findOne());
	}

	public boolean isNameTaken(String name) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select count(*) from chara where name=:name")
				.bind("name", name)
				.mapTo(Long.class)
				.one()) > 0;
	}

	/**
	 * Creates a character and its appearance, and points the account at it. The first character an
	 * account creates also becomes its main.
	 *
	 * @return the new character's id
	 */
	public long create(long accountId, String name, CharaAppearance appearance) {
		return jdbi.inTransaction(handle -> {
			var charaId = handle
				.createUpdate("insert into chara (account_id, name) values (:accountId, :name)")
				.bind("accountId", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one();

			appearance.setCharaId(charaId);
			insertAppearance(handle, appearance);

			handle.createUpdate("""
					update account
					set current_chara_id = :charaId,
						main_chara_id = coalesce(main_chara_id, :charaId)
					where id = :accountId
					""")
				.bind("charaId", charaId)
				.bind("accountId", accountId)
				.execute();

			return charaId;
		});
	}

	private static void insertAppearance(org.jdbi.v3.core.Handle handle, CharaAppearance a) {
		handle.createUpdate("""
				insert into chara_appearance (chara_id, gender, face, face_paint, voice, pitch,
					upper, upper_color, lower, lower_color,
					head, head_color, chest, chest_color, hands, hands_color,
					waist, waist_color, feet, feet_color,
					accessory1, accessory1_color, accessory2, accessory2_color)
				values (:charaId, :gender, :face, :facePaint, :voice, :pitch,
					:upper, :upperColor, :lower, :lowerColor,
					:head, :headColor, :chest, :chestColor, :hands, :handsColor,
					:waist, :waistColor, :feet, :feetColor,
					:accessory1, :accessory1Color, :accessory2, :accessory2Color)
				""")
			.bindBean(a)
			.execute();
	}

	/**
	 * Applies a wardrobe change made from the lobby.
	 * <p>
	 * Only the clothing fields are written. Gender, face, voice and pitch are fixed at creation and
	 * the client does not send them here, so they are left alone rather than overwritten with
	 * whatever a partially populated object happens to hold.
	 */
	public void updateAppearance(long charaId, CharaAppearance a) {
		jdbi.useHandle(handle -> handle.createUpdate("""
				update chara_appearance set
					face_paint = :facePaint,
					upper = :upper, upper_color = :upperColor,
					lower = :lower, lower_color = :lowerColor,
					head = :head, head_color = :headColor,
					chest = :chest, chest_color = :chestColor,
					hands = :hands, hands_color = :handsColor,
					waist = :waist, waist_color = :waistColor,
					feet = :feet, feet_color = :feetColor,
					accessory1 = :accessory1, accessory1_color = :accessory1Color,
					accessory2 = :accessory2, accessory2_color = :accessory2Color
				where chara_id = :charaId
				""")
			.bindBean(a)
			.bind("charaId", charaId)
			.execute());
	}

	/** The free-text comment shown on a character's card. */
	public void updateComment(long charaId, String comment) {
		jdbi.useHandle(handle -> handle
			.createUpdate("update chara set comment = :comment where id = :charaId")
			.bind("comment", comment)
			.bind("charaId", charaId)
			.execute());
	}

	public void setCurrentCharacter(long accountId, long charaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("update account set current_chara_id=:charaId where id=:id")
				.bind("charaId", charaId)
				.bind("id", accountId)
				.execute());
	}

	public boolean canDelete(Chara chara, OffsetDateTime now) {
		if (chara.getCreatedAt() == null) {
			return true;
		}
		return !now.isBefore(chara.getCreatedAt().plus(DELETE_COOLDOWN));
	}

	/**
	 * Soft-deletes a character: it stays in the database, but is hidden and renamed so the name
	 * becomes available again. The original name is kept in {@code old_name}.
	 */
	public void delete(long accountId, long charaId) {
		jdbi.useTransaction(handle -> {
			handle.createUpdate("""
					update chara
					set active = false,
						old_name = name,
						name = :placeholder
					where id = :id
					""")
				.bind("placeholder", CharacterNames.deletedName(charaId))
				.bind("id", charaId)
				.execute();

			// Clear the references so the account does not point at a deleted character.
			handle.createUpdate("""
					update account
					set main_chara_id = case when main_chara_id = :charaId then null else main_chara_id end,
						current_chara_id = case when current_chara_id = :charaId then null else current_chara_id end
					where id = :accountId
					""")
				.bind("charaId", charaId)
				.bind("accountId", accountId)
				.execute();
		});
	}
}
