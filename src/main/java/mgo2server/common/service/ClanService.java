package mgo2server.common.service;

import org.jdbi.v3.core.Jdbi;

import java.util.Optional;

/**
 * Clans, and a character's membership of one.
 * <p>
 * The vocabulary here is the client's, not ours. Membership state comes from the values the client
 * writes into {@code profile+6837} itself — 0 pending, 1 member, 2 leader, 99 none — so the server
 * stores the same numbers rather than inventing an enum that would need translating at the wire.
 */
public class ClanService {
	/** Membership state for a character in no clan. Never stored: it is the absence of a row. */
	public static final int STATE_NONE = 99;

	/** Applied, not yet approved — what {@code 0x4b42} writes locally after it sends. */
	public static final int STATE_PENDING = 0;

	/** An ordinary member. Written by the client at {@code 0xD56B68} on status {@code -1201}. */
	public static final int STATE_MEMBER = 1;

	/** The clan's leader — what creating one makes you ({@code 0xD56E90}). */
	public static final int STATE_LEADER = 2;

	/**
	 * How long a clan must exist before it can be disbanded — a week by default, the same interval
	 * as the character-delete and emblem-display cooldowns.
	 * <p>
	 * Operator policy in the sense that we enforce it, but not invented: it is the retail interval
	 * as players report it. The client cannot display it — the disband countdown strings (lobby
	 * 17312 / 17318) are orphaned in this build exactly like the emblem ones, referenced by no
	 * instruction and no string table — so a refusal shows a generic error rather than a countdown.
	 * <p>
	 * Tune with {@code MGO2SERVER_CLAN_DISBAND_COOLDOWN_HOURS} in {@code server.env}; see
	 * {@link mgo2server.common.Policy}.
	 */
	public static final java.time.Duration DISBAND_COOLDOWN =
		mgo2server.common.Policy.current().clanDisbandCooldown();

	/** Seconds until this clan may be disbanded, or 0 when it already may be. */
	public long secondsUntilDisbandable(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select greatest(0, :cooldown - extract(epoch from now() - created_at))::bigint
				from clan where id = :clan
				""")
			.bind("cooldown", DISBAND_COOLDOWN.toSeconds())
			.bind("clan", clanId)
			.mapTo(Long.class)
			.findOne()
			.orElse(0L));
	}

	/** Name bounds the client enforces before it will even send {@code 0x4b00}. */
	public static final int NAME_MIN_LENGTH = 3;

	public static final int NAME_MAX_LENGTH = 16;

	public static final int DESCRIPTION_MAX_LENGTH = 128;

	/**
	 * A character's clan as the client's profile record wants it.
	 *
	 * @param state 1 member or 2 leader; {@link #STATE_NONE} when the character has no clan, in
	 *     which case {@code id} is 0 and {@code name} empty
	 */
	public record Membership(long id, String name, int state) {
		public static final Membership NONE = new Membership(0, "", STATE_NONE);
	}

	/** A pending application, as the clan-applications mailbox shows it. */
	public record Applicant(long charaId, String name, long appliedAt) {
	}

	/** One row of the member roster. */
	public record Member(long charaId, String name, int state) {
	}

	/** A clan itself, for the profile screen. */
	public record Clan(long id, String name, String description, String notice, String noticeWriter,
			long noticeAt, String leaderName, long leaderCharaId, long emblemEditorCharaId,
			long emblemAt, long createdAt) {
	}

	private final Jdbi jdbi;

	public ClanService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/** The character's clan record, or {@link Membership#NONE} — never empty, since 99 is a state. */
	public Membership membershipOf(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select c.id, c.name, m.state
				from clan_member m
				join clan c on c.id = m.clan_id
				where m.chara_id = :chara
				""")
			.bind("chara", charaId)
			.map((rs, ctx) -> new Membership(rs.getLong("id"), rs.getString("name"),
				rs.getInt("state")))
			.findOne()
			.orElse(Membership.NONE));
	}

	/** One clan by id, for the profile block {@code 0x4b21} returns. */
	public Optional<Clan> clanById(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select c.id, c.name, c.description, c.notice, coalesce(l.name, '') as leader_name,
					coalesce(c.leader_chara_id, 0) as leader_chara_id,
					coalesce(c.emblem_editor_chara_id, c.leader_chara_id, 0) as emblem_editor,
					coalesce(w.name, '') as notice_writer,
					coalesce(extract(epoch from c.notice_at)::bigint, 0) as notice_at,
					coalesce(extract(epoch from c.emblem_at)::bigint, 0) as emblem_at,
					extract(epoch from c.created_at)::bigint as created_at
				from clan c
				left join chara l on l.id = c.leader_chara_id
				left join chara w on w.id = c.notice_writer_chara_id
				where c.id = :clan
				""")
			.bind("clan", clanId)
			.map((rs, ctx) -> new Clan(rs.getLong("id"), rs.getString("name"),
				rs.getString("description"), rs.getString("notice"), rs.getString("notice_writer"),
				rs.getLong("notice_at"), rs.getString("leader_name"), rs.getLong("leader_chara_id"),
				rs.getLong("emblem_editor"), rs.getLong("emblem_at"), rs.getLong("created_at")))
			.findOne());
	}

	/**
	 * The roster: leader first, then members. <b>Joined members only</b> — applicants ride the same
	 * list as a separate second batch with the {@code isMember} byte clear, so including them here
	 * made a pending applicant appear twice, the first time as a full member.
	 */
	public java.util.List<Member> membersOf(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select m.chara_id, c.name, m.state
				from clan_member m
				join chara c on c.id = m.chara_id
				where m.clan_id = :clan and m.state != :pending
				order by m.state desc, m.joined_at
				""")
			.bind("pending", STATE_PENDING)
			.bind("clan", clanId)
			.map((rs, ctx) -> new Member(rs.getLong("chara_id"), rs.getString("name"),
				rs.getInt("state")))
			.list());
	}

	/**
	 * Records an application to join. State 0 is the client's own "pending" value — the same one
	 * {@code 0x4b42} writes into its session record after sending — so an applicant is a
	 * {@code clan_member} row that has not been approved yet, not a separate kind of thing.
	 */
	public void apply(long charaId, long clanId) {
		jdbi.useHandle(handle -> handle
			.createUpdate("""
				insert into clan_member (chara_id, clan_id, state)
				values (:chara, :clan, :state)
				on conflict (chara_id) do update set
					clan_id = excluded.clan_id,
					state = excluded.state,
					joined_at = now()
				""")
			.bind("chara", charaId)
			.bind("clan", clanId)
			.bind("state", STATE_PENDING)
			.execute());
	}

	/** Applicants awaiting approval — state 0 rows. */
	public java.util.List<Member> applicantsFor(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select m.chara_id, c.name, m.state
				from clan_member m
				join chara c on c.id = m.chara_id
				where m.clan_id = :clan and m.state = :state
				order by m.joined_at
				""")
			.bind("clan", clanId)
			.bind("state", STATE_PENDING)
			.map((rs, ctx) -> new Member(rs.getLong("chara_id"), rs.getString("name"),
				rs.getInt("state")))
			.list());
	}

	/** Pending applications with their timestamps, for the clan-applications mailbox. */
	public java.util.List<Applicant> applicationsFor(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select m.chara_id, c.name, extract(epoch from m.joined_at)::bigint as applied_at
				from clan_member m
				join chara c on c.id = m.chara_id
				where m.clan_id = :clan and m.state = :pending
				order by m.joined_at
				""")
			.bind("clan", clanId)
			.bind("pending", STATE_PENDING)
			.map((rs, ctx) -> new Applicant(rs.getLong("chara_id"), rs.getString("name"),
				rs.getLong("applied_at")))
			.list());
	}

	/** Approves a pending applicant by character id — what {@code 0x4b30} names. */
	public boolean approve(long clanId, long charaId) {
		return jdbi.withHandle(handle -> handle
			.createUpdate("""
				update clan_member set state = :member
				where clan_id = :clan and chara_id = :chara and state = :pending
				""")
			.bind("member", STATE_MEMBER)
			.bind("pending", STATE_PENDING)
			.bind("clan", clanId)
			.bind("chara", charaId)
			.execute() > 0);
	}

	/** Declines a pending applicant by character id — {@code 0x4b32}. */
	public boolean decline(long clanId, long charaId) {
		return jdbi.withHandle(handle -> handle
			.createUpdate("""
				delete from clan_member
				where clan_id = :clan and chara_id = :chara and state = :pending
				""")
			.bind("pending", STATE_PENDING)
			.bind("clan", clanId)
			.bind("chara", charaId)
			.execute() > 0);
	}

	/** Approves a pending applicant by name. Returns whether a pending row was actually promoted. */
	public boolean approveByName(long clanId, String name) {
		return jdbi.withHandle(handle -> handle
			.createUpdate("""
				update clan_member set state = :member
				where clan_id = :clan and state = :pending
				  and chara_id = (select id from chara where name = :name)
				""")
			.bind("member", STATE_MEMBER)
			.bind("pending", STATE_PENDING)
			.bind("clan", clanId)
			.bind("name", name)
			.execute() > 0);
	}

	/**
	 * Withdraws a character from their clan — cancelling a pending application or leaving outright.
	 * A leader cannot: the clan would be left without one. Returns whether a row was removed.
	 */
	public boolean withdraw(long charaId) {
		return jdbi.inTransaction(handle -> {
			// Whether this was a real membership or only a pending application, read before the row
			// goes. Cancelling an application must NOT start the join cooldown: the same command
			// backs "Cancel Join", and charging a week for pressing it would lock a player out of
			// clans for having changed their mind on a screen that offers exactly that button.
			var wasMember = handle
				.createQuery("select state from clan_member where chara_id = :chara")
				.bind("chara", charaId)
				.mapTo(Integer.class)
				.findOne()
				.filter(state -> state != STATE_PENDING)
				.isPresent();

			var removed = handle
				.createUpdate("delete from clan_member where chara_id = :chara and state != :leader")
				.bind("chara", charaId)
				.bind("leader", STATE_LEADER)
				.execute() > 0;

			if (removed && wasMember) {
				stampDeparture(handle, charaId);
			}
			return removed;
		});
	}

	/** Records that a character has stopped being in a clan, starting the apply-to-join cooldown. */
	private static void stampDeparture(org.jdbi.v3.core.Handle handle, long charaId) {
		handle.createUpdate("update chara set clan_left_at = now() where id = :chara")
			.bind("chara", charaId)
			.execute();
	}

	/**
	 * Seconds until this character may apply to join a clan again, or 0 when they may now.
	 *
	 * <p><b>Operator policy, and policy twice over.</b> That the wait exists is the game's own — it
	 * carries the sentence and has a result code for it. Both the length and the decision to
	 * measure it from leaving a clan rather than from the last application are ours; nothing in the
	 * binary states which, because nothing in the binary checks it. A character who has never been
	 * in a clan has no departure and is never held.
	 */
	public long secondsUntilCanApply(long charaId) {
		var cooldown = mgo2server.common.Policy.current().clanJoinCooldown().toSeconds();
		if (cooldown <= 0) {
			return 0;
		}
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select greatest(0, :cooldown - extract(epoch from now() - clan_left_at))::bigint
				from chara where id = :chara and clan_left_at is not null
				""")
			.bind("cooldown", cooldown)
			.bind("chara", charaId)
			.mapTo(Long.class)
			.findOne()
			.orElse(0L));
	}

	/** Removes a member from a clan outright — {@code 0x4b36}, banish. The leader cannot be. */
	public boolean banish(long clanId, long charaId) {
		return jdbi.inTransaction(handle -> {
			var removed = handle
				.createUpdate("""
					delete from clan_member
					where clan_id = :clan and chara_id = :chara and state != :leader
					""")
				.bind("leader", STATE_LEADER)
				.bind("clan", clanId)
				.bind("chara", charaId)
				.execute() > 0;

			// A banished member left a clan, however involuntarily, so the cooldown applies. Whether
			// it should is a policy question we cannot answer from the binary: it is defensible that
			// being thrown out shouldn't cost you a week. Change it here if it plays badly.
			if (removed) {
				stampDeparture(handle, charaId);
			}
			return removed;
		});
	}

	/**
	 * Hands leadership to another member — {@code 0x4b60}. The outgoing leader stays as an ordinary
	 * member, and the clan's own leader pointer moves too, since that is what names the leader on
	 * every list screen.
	 */
	public boolean transferLeadership(long clanId, long fromCharaId, long toCharaId) {
		return jdbi.inTransaction(handle -> {
			var promoted = handle
				.createUpdate("""
					update clan_member set state = :leader
					where clan_id = :clan and chara_id = :chara and state = :member
					""")
				.bind("leader", STATE_LEADER)
				.bind("member", STATE_MEMBER)
				.bind("clan", clanId)
				.bind("chara", toCharaId)
				.execute() > 0;
			if (!promoted) {
				return false;
			}
			handle.createUpdate("""
					update clan_member set state = :member
					where clan_id = :clan and chara_id = :chara
					""")
				.bind("member", STATE_MEMBER)
				.bind("clan", clanId)
				.bind("chara", fromCharaId)
				.execute();
			handle.createUpdate("update clan set leader_chara_id = :chara where id = :clan")
				.bind("chara", toCharaId)
				.bind("clan", clanId)
				.execute();
			return true;
		});
	}

	/** Assigns emblem-editing rights — {@code 0x4b62}. */
	public void setEmblemEditor(long clanId, long charaId) {
		jdbi.useHandle(handle -> handle
			.createUpdate("update clan set emblem_editor_chara_id = :chara where id = :clan")
			.bind("chara", charaId)
			.bind("clan", clanId)
			.execute());
	}

	/**
	 * Disbands a clan — {@code 0x4b04}, leader only. Members go with it: {@code clan_member} rows
	 * cascade on the clan's deletion, so everyone lands back at state 99, no clan.
	 */
	public boolean disband(long clanId) {
		return jdbi.inTransaction(handle -> {
			// Everyone who was actually in the clan leaves at once. Stamped before the delete,
			// because clan_member cascades away with the clan row. Pending applicants are excluded:
			// they were never members, and an application that was never answered should not cost
			// them anything.
			handle.createUpdate("""
					update chara set clan_left_at = now()
					where id in (
						select chara_id from clan_member where clan_id = :clan and state != :pending
					)
					""")
				.bind("clan", clanId)
				.bind("pending", STATE_PENDING)
				.execute();

			return handle
				.createUpdate("delete from clan where id = :clan")
				.bind("clan", clanId)
				.execute() > 0;
		});
	}

	/**
	 * The emblem block to serve for a clan, or empty when it has none <b>on display</b>.
	 *
	 * <p>The mode test is the point of this method. Storage and display are different things: an
	 * emblem uploaded with mode 2 or 4 is kept but is not on display, and only mode 3 is. This used
	 * to select on {@code emblem is not null} alone, which made the server contradict itself — the
	 * flag at {@code profile+6872} said "nothing to show", and then any screen that asked for the
	 * picture was handed 768 bytes of it regardless.
	 *
	 * <p>[OBSERVED 2026-07-27] That is what kept a deleted emblem on Player Details -> More
	 * Details after a full logout and login, while the clan screen — which believes the flag —
	 * correctly showed nothing. One source of truth: if we would not set the flag to
	 * {@link #EMBLEM_ON_DISPLAY}, we do not serve the bytes either.
	 *
	 * <p>The bytes are deliberately <b>not</b> deleted with the mode. A non-display mode looks like
	 * "saved, not shown" — the emblem editor has Save and Load — so discarding the image on a mode
	 * change would destroy work the player expects to keep.
	 */
	public Optional<byte[]> emblemOf(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select emblem from clan
				where id = :clan and emblem is not null and emblem_mode = :displayed
				""")
			.bind("clan", clanId)
			.bind("displayed", EMBLEM_ON_DISPLAY)
			.mapTo(byte[].class)
			.findOne());
	}

	/**
	 * The upload mode that means "on display". [ELF] The client's own constant: the upload path
	 * stores it to {@code profile+6872} at {@code 0xAD4724}, and every reader tests it with an
	 * exact {@code cmpwi r0,3}, so 2 and 4 read identically to 0.
	 */
	public static final int EMBLEM_ON_DISPLAY = 3;

	/** Seconds since the clan's emblem last went on display, or -1 if it never has. */
	public long secondsSinceEmblem(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select coalesce(extract(epoch from now() - emblem_at)::bigint, -1)
				from clan where id = :clan
				""")
			.bind("clan", clanId)
			.mapTo(Long.class)
			.findOne()
			.orElse(-1L));
	}

	/** The emblem flag the client expects at {@code profile+6872}: the upload's mode, or 0. */
	public int emblemFlagOf(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("select coalesce(emblem_mode, 0) from clan where id = :clan")
			.bind("clan", clanId)
			.mapTo(Integer.class)
			.findOne()
			.orElse(0));
	}

	/** Stores an uploaded emblem, the mode it was uploaded with, and when it went on display. */
	public void setEmblem(long clanId, byte[] emblem, int mode) {
		jdbi.useHandle(handle -> handle
			.createUpdate("""
				update clan set emblem = :emblem, emblem_mode = :mode, emblem_at = now()
				where id = :clan
				""")
			.bind("emblem", emblem)
			.bind("mode", mode)
			.bind("clan", clanId)
			.execute());
	}

	/** How many clans exist, for the list header's total. */
	public int countClans() {
		return jdbi.withHandle(handle ->
			handle.createQuery("select count(*) from clan").mapTo(Integer.class).one());
	}

	/** How many members a clan has — joined only, not applicants awaiting approval. */
	public int memberCount(long clanId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("select count(*) from clan_member where clan_id = :clan and state != :pending")
			.bind("clan", clanId)
			.bind("pending", STATE_PENDING)
			.mapTo(Integer.class)
			.one());
	}

	/**
	 * Clan search — {@code 0x4b90}. The request carries the screen's two toggles: exact-only versus
	 * partial, and case-sensitive versus not.
	 */
	public java.util.List<Clan> searchClans(String name, boolean exactOnly, boolean caseSensitive,
			int limit) {
		var pattern = exactOnly ? name : "%" + name + "%";
		// Spaces are part of the fragment on purpose. This clause is concatenated between two text
		// blocks, and a text block strips trailing whitespace from every line — so "where " became
		// "where" and produced `wherec.name`, while the block after it began "order by" and produced
		// `:nameorder`. Carrying its own padding makes the join independent of that stripping.
		var comparison = caseSensitive ? " c.name like :name " : " lower(c.name) like lower(:name) ";
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select c.id, c.name, c.description, c.notice, coalesce(l.name, '') as leader_name,
					coalesce(c.leader_chara_id, 0) as leader_chara_id,
					coalesce(c.emblem_editor_chara_id, c.leader_chara_id, 0) as emblem_editor,
					coalesce(w.name, '') as notice_writer,
					coalesce(extract(epoch from c.notice_at)::bigint, 0) as notice_at,
					coalesce(extract(epoch from c.emblem_at)::bigint, 0) as emblem_at,
					extract(epoch from c.created_at)::bigint as created_at
				from clan c
				left join chara l on l.id = c.leader_chara_id
				left join chara w on w.id = c.notice_writer_chara_id
				where """ + comparison + """

				order by c.id
				limit :limit
				""")
			.bind("name", pattern)
			.bind("limit", limit)
			.map((rs, ctx) -> new Clan(rs.getLong("id"), rs.getString("name"),
				rs.getString("description"), rs.getString("notice"), rs.getString("notice_writer"),
				rs.getLong("notice_at"), rs.getString("leader_name"), rs.getLong("leader_chara_id"),
				rs.getLong("emblem_editor"), rs.getLong("emblem_at"), rs.getLong("created_at")))
			.list());
	}

	/** A page of the clan list. The client's array holds 100, so that is the page size. */
	public java.util.List<Clan> listClans(int offset, int limit) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select c.id, c.name, c.description, c.notice, coalesce(l.name, '') as leader_name,
					coalesce(c.leader_chara_id, 0) as leader_chara_id,
					coalesce(c.emblem_editor_chara_id, c.leader_chara_id, 0) as emblem_editor,
					coalesce(w.name, '') as notice_writer,
					coalesce(extract(epoch from c.notice_at)::bigint, 0) as notice_at,
					coalesce(extract(epoch from c.emblem_at)::bigint, 0) as emblem_at,
					extract(epoch from c.created_at)::bigint as created_at
				from clan c
				left join chara l on l.id = c.leader_chara_id
				left join chara w on w.id = c.notice_writer_chara_id
				order by c.id
				offset :offset limit :limit
				""")
			.bind("offset", Math.max(0, offset))
			.bind("limit", limit)
			.map((rs, ctx) -> new Clan(rs.getLong("id"), rs.getString("name"),
				rs.getString("description"), rs.getString("notice"), rs.getString("notice_writer"),
				rs.getLong("notice_at"), rs.getString("leader_name"), rs.getLong("leader_chara_id"),
				rs.getLong("emblem_editor"), rs.getLong("emblem_at"), rs.getLong("created_at")))
			.list());
	}

	/**
	 * Replaces a clan's notice — the 512-byte text, {@code 0x4b66} on the wire — and records who
	 * wrote it and when, which the screen shows beneath it.
	 */
	public void setNotice(long clanId, String notice, long writerCharaId) {
		jdbi.useHandle(handle -> handle
			.createUpdate("""
				update clan
				set notice = :notice, notice_writer_chara_id = :writer, notice_at = now()
				where id = :clan
				""")
			.bind("notice", notice)
			.bind("writer", writerCharaId)
			.bind("clan", clanId)
			.execute());
	}

	/** Replaces a clan's description. Only the leader is allowed to, and the caller checks that. */
	public void setDescription(long clanId, String description) {
		jdbi.useHandle(handle -> handle
			.createUpdate("update clan set description = :description where id = :clan")
			.bind("description", description)
			.bind("clan", clanId)
			.execute());
	}

	/**
	 * Creates a clan and makes the character its leader, or returns empty when the name is taken.
	 * <p>
	 * The client has already checked the name's length and character class before sending
	 * {@code 0x4b00} ({@code 0xD579AC} rejects anything outside 3..16 or failing {@code 0xD32DD0}),
	 * so the only failure left to us is a collision — names are unique because the client identifies
	 * a clan by name in its lists.
	 */
	public Optional<Long> createClan(long leaderCharaId, String name, String description) {
		return jdbi.inTransaction(handle -> {
			var taken = handle
				.createQuery("select count(*) from clan where lower(name) = lower(:name)")
				.bind("name", name)
				.mapTo(Integer.class)
				.one() > 0;
			if (taken) {
				return Optional.<Long>empty();
			}

			var clanId = handle
				.createUpdate("""
					insert into clan (name, description, leader_chara_id)
					values (:name, :description, :leader)
					""")
				.bind("name", name)
				.bind("description", description)
				.bind("leader", leaderCharaId)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one();

			handle.createUpdate("""
					insert into clan_member (chara_id, clan_id, state)
					values (:chara, :clan, :state)
					on conflict (chara_id) do update set
						clan_id = excluded.clan_id,
						state = excluded.state,
						joined_at = now()
					""")
				.bind("chara", leaderCharaId)
				.bind("clan", clanId)
				.bind("state", STATE_LEADER)
				.execute();

			return Optional.of(clanId);
		});
	}
}
