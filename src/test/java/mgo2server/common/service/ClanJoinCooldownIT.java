package mgo2server.common.service;

import mgo2server.TestDatabase;
import mgo2server.common.Policy;
import mgo2server.common.ServicesFactory;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The apply-to-join cooldown.
 * <p>
 * <b>Operator policy, and policy twice over.</b> That a wait exists is the game's own — it carries
 * the sentence (dialog 24137) and has a result code for it. Both the length and the decision to
 * measure it from leaving a clan rather than from the last application are ours, because nothing
 * in the binary checks either. So these are regression guards on our own rules, not correctness
 * checks against the client.
 */
public class ClanJoinCooldownIT {
	private static ClanService clanService;

	@BeforeAll
	public static void setUp() {
		clanService = ServicesFactory.createServices(TestDatabase.get().jdbi()).getClanService();
	}

	@Test
	public void aCharacterThatNeverLeftAClanIsNeverHeld() {
		assertThat(clanService.secondsUntilCanApply(999999L)).isZero();
	}

	@Test
	public void leavingStartsTheCooldown() {
		var fixture = ClanFixture.create("leaver");
		clanService.apply(fixture.member(), fixture.clan());
		clanService.approve(fixture.clan(), fixture.member());

		assertThat(clanService.secondsUntilCanApply(fixture.member())).isZero();

		assertThat(clanService.withdraw(fixture.member())).isTrue();
		assertThat(clanService.secondsUntilCanApply(fixture.member()))
			.isCloseTo(Policy.current().clanJoinCooldown().toSeconds(), within(5L));
	}

	/**
	 * The case that would have hurt. "Cancel Join" is the same command as leaving, so charging the
	 * cooldown for it would lock a player out of clans for a week for changing their mind on a
	 * screen whose whole purpose is to let them.
	 */
	@Test
	public void cancellingAPendingApplicationIsFree() {
		var fixture = ClanFixture.create("canceller");
		clanService.apply(fixture.member(), fixture.clan());

		assertThat(clanService.withdraw(fixture.member())).isTrue();
		assertThat(clanService.secondsUntilCanApply(fixture.member())).isZero();
	}

	@Test
	public void banishingStartsTheCooldownForTheBanished() {
		var fixture = ClanFixture.create("banished");
		clanService.apply(fixture.member(), fixture.clan());
		clanService.approve(fixture.clan(), fixture.member());

		assertThat(clanService.banish(fixture.clan(), fixture.member())).isTrue();
		assertThat(clanService.secondsUntilCanApply(fixture.member())).isPositive();
	}

	/** Disbanding turns every member out at once, so every member starts waiting. */
	@Test
	public void disbandingStartsTheCooldownForTheMembers() {
		var fixture = ClanFixture.create("disbanded");
		clanService.apply(fixture.member(), fixture.clan());
		clanService.approve(fixture.clan(), fixture.member());

		assertThat(clanService.disband(fixture.clan())).isTrue();
		assertThat(clanService.secondsUntilCanApply(fixture.member())).isPositive();
	}

	/** A pending applicant was never a member, so an unanswered application costs them nothing. */
	@Test
	public void disbandingIsFreeForPendingApplicants() {
		var fixture = ClanFixture.create("stillpending");
		clanService.apply(fixture.member(), fixture.clan());

		assertThat(clanService.disband(fixture.clan())).isTrue();
		assertThat(clanService.secondsUntilCanApply(fixture.member())).isZero();
	}

	private static org.assertj.core.data.Offset<Long> within(long value) {
		return org.assertj.core.data.Offset.offset(value);
	}

	/** A clan with a leader and one other character available to join it. */
	private record ClanFixture(long clan, long leader, long member) {
		static ClanFixture create(String tag) {
			var suffix = String.valueOf(System.nanoTime() % 100000000L);
			var leader = character(tag + "L" + suffix);
			var member = character(tag + "M" + suffix);
			var clan = clanService.createClan(leader, "c" + suffix, "").orElseThrow();
			return new ClanFixture(clan, leader, member);
		}

		private static long character(String name) {
			return TestDatabase.get().jdbi().withHandle(handle -> {
				var accountId = handle
					.createUpdate("insert into account (username, password) values (:n, 'x')")
					.bind("n", name)
					.executeAndReturnGeneratedKeys("id")
					.mapTo(Long.class)
					.one();
				return handle
					.createUpdate("insert into chara (account_id, name) values (:a, :n)")
					.bind("a", accountId)
					.bind("n", name.substring(0, Math.min(16, name.length())))
					.executeAndReturnGeneratedKeys("id")
					.mapTo(Long.class)
					.one();
			});
		}
	}
}
