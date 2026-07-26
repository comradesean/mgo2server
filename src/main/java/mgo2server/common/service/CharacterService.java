package mgo2server.common.service;

import mgo2server.common.CharacterNames;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.CharaSettings;
import mgo2server.common.model.ChatMacro;
import mgo2server.common.model.EquippedSkills;
import mgo2server.common.model.GearSet;
import mgo2server.common.model.SkillSet;
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
	 * Accumulated training seconds for one character, split the three ways {@code 0x4107} reports
	 * them.
	 * <p>
	 * The source is {@code round_report.seconds_in_game}, which is the <b>host's</b> measurement of
	 * how long that player was present — CONFIRMED in {@code mgo2_cmd_4390.ksy} and observed live
	 * 2026-07-26 as 1987 seconds for a 33-minute lecture. Summing it is therefore the same number
	 * the original would have accumulated, not an invention.
	 * <p>
	 * The split is ours, not the game's: reports stamped with subtype 7 count as training mode,
	 * subtype 8 as combat training, with the instructor being whoever hosted
	 * ({@code host_chara_id = chara_id}) and everyone else the student. The slot <em>labels</em>
	 * are CONFIRMED; this mapping of our lobby subtypes onto them is operator policy and is the
	 * first thing to revisit if the totals read wrong on screen.
	 * <p>
	 * Written with {@code !=} rather than {@code <>} on purpose: Jdbi runs statements through the
	 * StringTemplate engine, which parses {@code <...>} as a template expression and fails to
	 * compile the query.
	 * <p>
	 * Reads {@code round_report.lobby_subtype} rather than joining through {@code game}: game rows
	 * are deleted on teardown and carry no foreign key, so a join loses every report the moment
	 * its host leaves — which is every historical report. Rows written before V19 hold 0 and are
	 * counted nowhere.
	 */
	public TrainingSeconds trainingSeconds(long charaId) {
		return jdbi.withHandle(handle -> handle.createQuery("""
					select
						coalesce(sum(seconds_in_game) filter (where lobby_subtype = 7), 0)
							as training,
						coalesce(sum(seconds_in_game) filter (
							where lobby_subtype = 8 and host_chara_id = chara_id), 0) as instructor,
						coalesce(sum(seconds_in_game) filter (
							where lobby_subtype = 8 and host_chara_id != chara_id), 0) as student
					from round_report
					where chara_id = :chara
					""")
			.bind("chara", charaId)
			.map((rs, c) -> new TrainingSeconds(
				rs.getLong("training"), rs.getLong("instructor"), rs.getLong("student")))
			.one());
	}

	/** Seconds, as {@code 0x4107} slots 46, 47 and 48 want them. */
	public record TrainingSeconds(long trainingMode, long instructor, long student) {
	}

	/** Wire value the ADDLIST uses for a friend; see {@code V14__chara_relations.sql}. */
	public static final int RELATION_FRIEND = 0;

	/** Wire value the ADDLIST uses for a blocked player. */
	public static final int RELATION_BLOCKED = 1;

	/**
	 * Records an ADDLIST relationship change ({@code 0x4500}): the state a character assigned to
	 * another player. Upserts — the client sends one change per target and expects the stored
	 * lists back at next login via the {@code 0x4101} arrays.
	 */
	public void setRelation(long charaId, long targetCharaId, int state) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					insert into chara_relation (chara_id, target_chara_id, state)
					values (:chara, :target, :state)
					on conflict (chara_id, target_chara_id) do update
						set state = excluded.state, updated_at = now()
					""")
				.bind("chara", charaId)
				.bind("target", targetCharaId)
				.bind("state", state)
				.execute());
	}

	/** Character ids holding the given relation state, oldest first, capped for the 0x4101 grid. */
	public java.util.List<Long> relationIds(long charaId, int state, int limit) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select target_chara_id from chara_relation
					where chara_id=:chara and state=:state
					order by updated_at
					limit :limit
					""")
				.bind("chara", charaId)
				.bind("state", state)
				.bind("limit", limit)
				.mapTo(Long.class)
				.list());
	}

	/** Clears a relationship — the ADDLIST "set to none" ({@code 0x4510}), keyed by the pair. */
	public void removeRelation(long charaId, long targetCharaId) {
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					delete from chara_relation where chara_id=:chara and target_chara_id=:target
					""")
				.bind("chara", charaId)
				.bind("target", targetCharaId)
				.execute());
	}

	/** One ADDLIST entry as the {@code 0x4502} reply needs it: target id, name, and state. */
	public record Relation(long targetId, String name, int state) {
	}

	/** A character's whole relationship list, friends then blocked, oldest first within each. */
	public java.util.List<Relation> relations(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select r.target_chara_id, c.name, r.state
					from chara_relation r
					join chara c on c.id = r.target_chara_id
					where r.chara_id = :chara
					order by r.state, r.updated_at
					""")
				.bind("chara", charaId)
				.map((rs, ctx) -> new Relation(rs.getLong("target_chara_id"),
					rs.getString("name"), rs.getInt("state")))
				.list());
	}

	/**
	 * Saves one type's macro grid, as pushed by the client's write-back ({@code 0x4114}) — all
	 * twelve slots arrive every time, so this upserts the full row set for the type.
	 */
	public void saveChatMacros(long charaId, int type, java.util.List<String> texts) {
		jdbi.useHandle(handle -> {
			var batch = handle.prepareBatch("""
					insert into chara_chat_macro (chara_id, type, index, text)
					values (:chara, :type, :index, :text)
					on conflict (chara_id, type, index) do update set text = excluded.text
					""");
			for (var index = 0; index < texts.size() && index < ChatMacro.PER_TYPE; index++) {
				batch.bind("chara", charaId).bind("type", type)
					.bind("index", index).bind("text", texts.get(index)).add();
			}
			batch.execute();
		});
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
	 * Persists the four equipped skill slots and their levels, as sent by the wardrobe update
	 * ({@code 0x4130}). Until 2026-07-23 these were echoed but never stored, so an equipped
	 * skill survived the session and vanished on the next connect burst.
	 */
	public void updateEquippedSkills(long charaId, byte[] skills, byte[] levels) {
		getOrCreateEquippedSkills(charaId);
		jdbi.useHandle(handle ->
			handle.createUpdate("""
					update chara_equipped_skills set
						skill1=:s1, skill2=:s2, skill3=:s3, skill4=:s4,
						level1=:l1, level2=:l2, level3=:l3, level4=:l4
					where chara_id=:id
					""")
				.bind("id", charaId)
				.bind("s1", skills[0]).bind("s2", skills[1])
				.bind("s3", skills[2]).bind("s4", skills[3])
				.bind("l1", levels[0]).bind("l2", levels[1])
				.bind("l3", levels[2]).bind("l4", levels[3])
				.execute());
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

	/**
	 * Player search ({@code 0x4600}). The client sends only the raw name and the two toggles; the
	 * binary does no matching of its own, so the semantics of "partial" are operator policy —
	 * implemented here as a substring match. Full match with wildcards escaped degenerates to
	 * equality, which keeps the four combinations in one query.
	 */
	public List<Chara> search(String name, boolean fullMatch, boolean caseSensitive, int limit) {
		var escaped = name.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
		var pattern = fullMatch ? escaped : "%" + escaped + "%";
		var operator = caseSensitive ? "like" : "ilike";
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara where active=true and name " + operator
					+ " :pattern escape '\\' order by name, id limit :limit")
				.bind("pattern", pattern)
				.bind("limit", limit)
				.mapTo(Chara.class)
				.list());
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
