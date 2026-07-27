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

	/** One row of the member roster. */
	public record Member(long charaId, String name, int state) {
	}

	/** A clan itself, for the profile screen. */
	public record Clan(long id, String name, String description, String notice, String leaderName,
			long createdAt) {
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
					extract(epoch from c.created_at)::bigint as created_at
				from clan c
				left join chara l on l.id = c.leader_chara_id
				where c.id = :clan
				""")
			.bind("clan", clanId)
			.map((rs, ctx) -> new Clan(rs.getLong("id"), rs.getString("name"),
				rs.getString("description"), rs.getString("notice"), rs.getString("leader_name"),
				rs.getLong("created_at")))
			.findOne());
	}

	/**
	 * The roster, leaders first then by seniority. <b>Actual members only</b> — a pending applicant
	 * is a {@code clan_member} row with state 0, and including them made Clan Info count an
	 * applicant as a member.
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
		return jdbi.withHandle(handle -> handle
			.createUpdate("delete from clan_member where chara_id = :chara and state != :leader")
			.bind("chara", charaId)
			.bind("leader", STATE_LEADER)
			.execute() > 0);
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

	/** A page of the clan list. The client's array holds 100, so that is the page size. */
	public java.util.List<Clan> listClans(int offset, int limit) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select c.id, c.name, c.description, c.notice, coalesce(l.name, '') as leader_name,
					extract(epoch from c.created_at)::bigint as created_at
				from clan c
				left join chara l on l.id = c.leader_chara_id
				order by c.id
				offset :offset limit :limit
				""")
			.bind("offset", Math.max(0, offset))
			.bind("limit", limit)
			.map((rs, ctx) -> new Clan(rs.getLong("id"), rs.getString("name"),
				rs.getString("description"), rs.getString("notice"), rs.getString("leader_name"),
				rs.getLong("created_at")))
			.list());
	}

	/** Replaces a clan's notice — the 512-byte text, {@code 0x4b66} on the wire. */
	public void setNotice(long clanId, String notice) {
		jdbi.useHandle(handle -> handle
			.createUpdate("update clan set notice = :notice where id = :clan")
			.bind("notice", notice)
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
