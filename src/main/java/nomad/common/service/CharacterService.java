package nomad.common.service;

import nomad.common.CharacterNames;
import nomad.common.model.Chara;
import nomad.common.model.CharaAppearance;
import nomad.common.model.ChatMacro;
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
