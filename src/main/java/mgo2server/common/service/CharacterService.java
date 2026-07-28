package mgo2server.common.service;

import mgo2server.common.CharacterNames;
import mgo2server.common.Level;
import mgo2server.common.Policy;
import mgo2server.common.model.Chara;
import mgo2server.common.model.CharaAppearance;
import mgo2server.common.model.CharaSkill;
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
	/**
	 * A character cannot be deleted until it has existed this long — a week by default.
	 * <p>
	 * Operator policy. Tune with {@code MGO2SERVER_CHARACTER_DELETE_COOLDOWN_HOURS} in
	 * {@code server.env}; see {@link mgo2server.common.Policy}.
	 */
	public static final Duration DELETE_COOLDOWN = Policy.current().characterDeleteCooldown();

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
	 * The source is {@code chara_training_time}, which the server accumulates from presence:
	 * {@code game_player.joined_at} to the moment the row is removed. It replaced a derivation from
	 * {@code round_report.seconds_in_game} — the host's own measurement — because the host only
	 * reports when a player leaves early, so a host who quits first reports nobody and a whole
	 * session was lost. The host's numbers remain in {@code round_report}; when both exist they
	 * should agree, and a live 33-minute lecture reported 1987 seconds against the same presence.
	 * <p>
	 * The split is ours, not the game's: reports stamped with subtype 7 count as training mode,
	 * subtype 8 as combat training, with the instructor being whoever hosted
	 * ({@code host_chara_id = chara_id}) and everyone else the student. The slot <em>labels</em>
	 * are CONFIRMED; this mapping of our lobby subtypes onto them is operator policy and is the
	 * first thing to revisit if the totals read wrong on screen.
	 * <p>
	 * <b>Not</b> the graduation gate. That requirement is client-side and per session — the student
	 * must be present for the full 30 minutes in one sitting — and no value here shortens it.
	 * These are the career totals the stats screen renders.
	 */
	/**
	 * Grants the instructor skill and its announcement to a character who has a recognised
	 * graduation on file, meets the eligibility rule, and does not hold the skill yet. Returns
	 * whether anything was granted.
	 * <p>
	 * <b>The rule is Konami's, documented on the official MGO2 site: "Level 3 or above and 20 or
	 * more hours of gameplay".</b> It is service policy, not protocol — the client enforces neither
	 * half, proven live on 2026-07-27 when a character with zero accumulated play time was shown the
	 * recognition prompt and answered it. Konami's servers withheld the reward instead, which is
	 * exactly what happens here. An earlier version of this used level <em>4</em>, taken from player
	 * accounts rather than the source; the official wording says 3, which is
	 * {@link #LEVEL_3_EXPERIENCE} = 375 experience in the client's own threshold table.
	 * <p>
	 * This is deliberately <b>not</b> done when {@code 0x43c8} arrives. It is driven by the
	 * end-of-round stats report ({@code 0x4390}), which the host sends for every player as they
	 * leave — including leaving combat training — so the award is a consequence of the session
	 * ending rather than of one packet, and a graduation that somehow misses its award is picked up
	 * by the next report instead of being lost.
	 * <p>
	 * The ordering that makes this safe was checked against a live capture: leaving produces
	 * {@code 0x4390} at 02:41:26 and the student's mailbox fetch ({@code 0x4820}) at 02:41:29, so
	 * the letter exists before it is read. That was the original reason for granting inline, and it
	 * still holds here.
	 * <p>
	 * Idempotent by construction: the insert is {@code on conflict do nothing} and the letter is
	 * sent only when the insert actually granted the skill, so repeated reports — and repeated
	 * graduations — never duplicate either.
	 */
	public boolean awardPendingInstructorSkill(long charaId) {
		return jdbi.inTransaction(handle -> {
			// Experience follows the same main/alt split the stats screen uses: a character that is
			// its account's main spends the main pool, everyone else the alt pool.
			var eligible = handle.createQuery("""
					select count(*) from chara c
					join account a on a.id = c.account_id
					join chara_instructor i on i.chara_id = c.id
					where c.id = :student
					  and (select coalesce(sum(r.seconds_in_game), 0) from round_report r
						   where r.chara_id = c.id and r.rule between 0 and :lastMode) >= :seconds
					  and case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end
						  >= :experience
					""")
				.bind("student", charaId)
				.bind("seconds", INSTRUCTOR_MIN_SECONDS)
				.bind("lastMode", PLAYABLE_MODES - 1)
				.bind("experience", LEVEL_3_EXPERIENCE)
				.mapTo(Integer.class)
				.one() > 0;
			if (!eligible) {
				return false;
			}

			var granted = handle.createUpdate("""
					insert into chara_skill (chara_id, skill_id, experience, flag)
					values (:student, :skill, :experience, 0)
					on conflict (chara_id, skill_id) do nothing
					""")
				.bind("student", charaId)
				.bind("skill", INSTRUCTOR_SKILL_ID)
				.bind("experience", CharaSkill.MINIMUM_VISIBLE_EXPERIENCE)
				.execute() > 0;

			if (granted) {
				handle.createUpdate("""
						insert into mail (recipient_chara_id, sender_chara_id, sender_name,
							subject, body)
						values (:student, null, :sender, :subject, :body)
						""")
					.bind("student", charaId)
					.bind("sender", GRADUATION_SENDER)
					.bind("subject", GRADUATION_SUBJECT)
					.bind("body", GRADUATION_BODY)
					.execute();
			}
			return granted;
		});
	}

	public TrainingSeconds trainingSeconds(long charaId) {
		return jdbi.withHandle(handle -> handle.createQuery("""
					select
						coalesce(max(training_mode_seconds), 0) as training,
						coalesce(max(instructor_seconds), 0) as instructor,
						coalesce(max(student_seconds), 0) as student
					from chara_training_time
					where chara_id = :chara
					""")
			.bind("chara", charaId)
			.map((rs, c) -> new TrainingSeconds(
				rs.getLong("training"), rs.getLong("instructor"), rs.getLong("student")))
			.one());
	}

	/**
	 * Seconds spent in the training lobbies, for {@code 0x4107} slots 46, 47 and 48.
	 *
	 * <p><b>These are presence figures — {@code now() - joined_at} at teardown — and that is not a
	 * shortcut, it is the only signal that exists.</b> Verified live on 2026-07-28 across two Solo
	 * Training sessions: the client's entire inbound vocabulary in that lobby is
	 * {@code 0003, 0005, 4128, 4150, 4310, 4316, 4344, 4380, 4398, 43d0, 4440, 4820}, it sends
	 * <b>no {@code 0x4390} at all</b>, no round-report row appears for any rule, and nothing goes
	 * unhandled. The mode simply does not report what happened in it.
	 *
	 * <p>That is why this table survives while its {@code total_seconds} column did not: total play
	 * time <em>is</em> derivable from {@code round_report} and now is, but training time is not
	 * derivable from anything.
	 */
	public record TrainingSeconds(long trainingMode, long instructor, long student) {
	}

	/**
	 * Play time a character must have accumulated before the instructor skill is awarded — Konami's
	 * documented "20 or more hours of gameplay".
	 * <p>
	 * Measured against {@code sum(round_report.seconds_in_game)} over the playable modes, which is
	 * <b>exactly the number the personal-stats screen shows</b>. That equality is the point: a gate
	 * the player can see themselves approaching is one we can explain, and until 2026-07-28 this read
	 * a hidden presence counter that disagreed with the screen.
	 * <p>
	 * It also means training time no longer counts toward it. Only the six playable modes do — which
	 * matches the requirement's wording, since twenty hours of sitting in a training lobby is not
	 * twenty hours of gameplay.
	 */
	public static final long INSTRUCTOR_MIN_SECONDS = 20 * 60 * 60;

	/**
	 * Experience for character level 3 — Konami's documented instructor requirement, "Level 3 or
	 * above".
	 * <p>
	 * <b>Provenance resolved 2026-07-28, and the numbers were right all along.</b> This used to say
	 * the value was "recovered from the client's own threshold table", which cannot have been true —
	 * the table is not in the binary. It is a GCX script argument on the disc, and it has now been
	 * read from there; the whole table lives in {@link mgo2server.common.Level}, which this defers to.
	 * <p>
	 * The old comment's figures — {@code 125, 250, 375, 500, 650}, 22 entries capped at 4,600 — are
	 * <b>all correct</b>. Only the claimed source was wrong. An intermediate correction here also
	 * asserted that 4,600 was contradicted by the 49,250 → 22 reading; <b>that was itself wrong</b>,
	 * because 49,250 exceeds every threshold and so simply yields the maximum.
	 * <p>
	 * One thing the disassembly did correct: the level is the <b>count</b> of thresholds at or below
	 * the experience, not one more than it. {@code 499} displays as 3 and {@code 500} as 4, with
	 * {@code T[3] = 500}.
	 */
	public static final int LEVEL_3_EXPERIENCE = Level.experienceFor(3);

	/**
	 * The measured experience threshold for character level 4 — {@code T[3]} of that same table.
	 * <p>
	 * This was {@code GRADUATION_MIN_EXPERIENCE} and gated the award at level <em>4</em> until
	 * 2026-07-27, when the official requirement turned out to be level 3. Kept because the
	 * measurement is worth having, not because anything enforces it.
	 * <p>
	 * The client shows a <em>level</em>, and that level comes from experience, not from
	 * {@code chara.rank} — five live readings on 2026-07-26, all at rank 0: 214 showed level 1,
	 * 499 level 3, 500 level 4, 1,600 level 10, and 49,250 level 22.
	 * <p>
	 * <b>500 is the exact threshold, bracketed to one experience point:</b> 499 displays as level 3
	 * and 500 as level 4 on the live client. Not derived — measured.
	 * <p>
	 * Do not try to compute it. A {@code 100 * level^2} curve fitted the first two readings and
	 * predicted level 4 at 1,600; the next reading falsified it — 1,600 is level 10. The thresholds
	 * are a table, and it has since been read from a <b>stage script on the disc</b>: see
	 * {@link Level}.
	 * <p>
	 * This comment also used to claim levels 10 to 22 cost "over 47,000" experience between them.
	 * <b>That was wrong</b>, and it came from reading the 49,250 → 22 observation as a threshold when
	 * it is merely a value above the cap. The real span is level 10 at 1,450 to level 22 at 4,600 —
	 * 3,150, not 47,000.
	 */
	public static final int LEVEL_4_EXPERIENCE = Level.experienceFor(4);

	/**
	 * Game modes that carry a play-time figure — modes 0..5 in the {@code 0x4105} grid.
	 * <p>
	 * Play time is stored as one aggregate and written into every one of these rows, so the total
	 * the client derives is that aggregate times this count. Both screens that show a play time have
	 * to agree about that, which is why the arithmetic lives here rather than in either controller.
	 */
	public static final int PLAYABLE_MODES = 6;

	/**
	 * The play time the client displays: the sum across game modes, which is what both the personal
	 * stats screen and player details show.
	 * <p>
	 * <b>The {@value #PLAYABLE_MODES}× multiplication is gone (2026-07-28).</b> It existed because
	 * {@code 0x4105} had no per-mode breakdown and wrote one aggregate into every mode row, so the
	 * client's own total — which sums the column over rows 0..6 — counted it six times; multiplying
	 * here kept the player card telling the same (inflated) story. {@link StatsService} now derives
	 * real per-mode play time from {@code round_report}, so the client's sum is correct on its own
	 * and this must not pre-multiply.
	 * <p>
	 * Note the source change that comes with it: this is now {@code sum(seconds_in_game)} over the
	 * playable modes, the same figure the stats grid sums, rather than the presence total. The
	 * presence total is the <em>more complete</em> number — it covers sessions where the host quit
	 * first and reported nobody — but two screens showing different play times for one character is
	 * a defect a player notices and we cannot explain, while one consistent slightly-low number is
	 * explainable. Consistency wins; the coverage hole is documented where the query lives.
	 */
	/**
	 * A character's instructor score: how many students reviewed them, and the average rating in
	 * 8.8 fixed point.
	 * <p>
	 * The vote count is what the Personal Data screen renders as the denominator of "N stars /
	 * M votes" ({@code 0x4103} wire 636). It sends 0 for someone never reviewed, which is honest,
	 * where the fingerprint that used to sit there quoted 4034 votes for ratings nobody had cast.
	 * <p>
	 * {@code ratingSum} is the star NUMERATOR at wire 632. The client draws
	 * {@code clamp(ceil(2 * numerator / denominator), 0, 10)} half-stars ({@code 0x94258C}), so
	 * sending the rating SUM over the vote COUNT makes the ratio the average and the gauge lands on
	 * the real star count — four reviews averaging 3.00 send 12/4 and draw three stars.
	 */
	public record InstructorScore(int votes, int ratingSum) {
	}

	/**
	 * A character's host rating: how many players have voted on their hosting, and the sum of
	 * those votes. Same shape and the same gauge maths as {@link #instructorScore} — wire 571 is
	 * the numerator and 575 the denominator on {@code 0x4103}.
	 * <p>
	 * Source is {@code host_review}, filled from {@code 0x43c4}. Before 2026-07-28 nothing stored
	 * these votes, which is why this gauge could only read zero and why the ranking board's
	 * host-rating row was empty.
	 */
	public InstructorScore hostScore(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
					select count(*) as votes, coalesce(sum(rating), 0)::bigint as rating_sum
					from host_review
					where host_chara_id = :chara
					""")
			.bind("chara", charaId)
			.map((rs, ctx) -> new InstructorScore(rs.getInt("votes"),
				(int) rs.getLong("rating_sum")))
			.one());
	}

	public InstructorScore instructorScore(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
					select count(*) as votes, coalesce(sum(rating), 0)::bigint as rating_sum
					from instructor_review
					where instructor_chara_id = :chara
					""")
			.bind("chara", charaId)
			.map((rs, ctx) -> new InstructorScore(rs.getInt("votes"),
				(int) rs.getLong("rating_sum")))
			.one());
	}

	/**
	 * Play time across the six playable modes: {@code sum(round_report.seconds_in_game)}.
	 *
	 * <h2>Why this and not presence</h2>
	 * A presence counter — {@code now() - joined_at} at teardown — is the more <em>complete</em>
	 * measurement, since it also covers sessions where the host quit first and reported nobody. It is
	 * nevertheless the wrong one here, for three reasons:
	 *
	 * <ul>
	 * <li><b>Presence cannot be attributed to a mode.</b> A game rotates: one session can play Team
	 * Deathmatch, then Sneaking, then Base under a single {@code joined_at}. There is no way to split
	 * that. A round report carries {@code seconds_in_game} <em>with its rule</em>, which is exactly
	 * what {@code 0x4105} column 17 needs, since the client renders a figure per mode row and sums
	 * them for the header.</li>
	 * <li><b>Presence counts time nobody was playing</b> — briefing, the pre-round wait, the results
	 * screen. {@code seconds_in_game} is the host's measurement of the round itself.</li>
	 * <li><b>Two measures would diverge.</b> {@code RankingService} already sums
	 * {@code seconds_in_game} for its play-time boards, and the gates now read this. One number,
	 * everywhere, is worth more than a better number in one place.</li>
	 * </ul>
	 *
	 * <p>The training lobbies are the mirror image and that is why they keep a presence counter: a
	 * training lobby is one mode for its whole life, so session time and mode time are the same
	 * number — and those modes send no round report at all, verified live 2026-07-28.
	 */
	public long displayedPlaySeconds(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
					select coalesce(sum(r.seconds_in_game), 0)
					from round_report r
					where r.chara_id = :chara and r.rule between 0 and :lastMode
					""")
			.bind("chara", charaId)
			.bind("lastMode", PLAYABLE_MODES - 1)
			.mapTo(Long.class)
			.one());
	}

	/**
	 * The character's experience, which is what every screen showing a <em>level</em> is really
	 * reading — the client walks its own threshold table (125, 250, {@link #LEVEL_3_EXPERIENCE},
	 * {@link #LEVEL_4_EXPERIENCE}, 650, ...) and displays one more than the number of thresholds
	 * cleared.
	 * <p>
	 * Experience belongs to the account, not the character, and splits main from alt: a character
	 * that is its account's main spends the main pool, everyone else the alt pool. Same expression
	 * the eligibility checks and the ranking queries use.
	 */
	public long experienceOf(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select coalesce(
					case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end, 0)
				from chara c
				join account a on a.id = c.account_id
				where c.id = :chara
				""")
			.bind("chara", charaId)
			.mapTo(Long.class)
			.findOne()
			.orElse(0L));
	}

	/**
	 * Play time a clan founder needs — 20 hours. Operator policy on community report; see
	 * {@link #meetsClanRequirements} for why the string that states it is not evidence, and why
	 * the 5-hour tier beside it cannot be ruled out.
	 */
	public static final long CLAN_MIN_SECONDS = 20 * 60 * 60;

	/** The skill graduation awards. */
	public static final int INSTRUCTOR_SKILL_ID = 17;

	/**
	 * What a graduation did, so the caller can log it without re-querying.
	 *
	 * @param generation which generation of instructor the student now belongs to
	 * @param recognised whether the student answered yes to the recognition prompt; a review
	 *     without it is only a star rating, and changes no relationship
	 */
	public record Graduation(int generation, boolean recognised) {
	}

	/**
	 * Records an instructor review, and — only when the student <em>recognised</em> the instructor —
	 * writes the relationship. The skill and the announcement follow separately; see
	 * {@link #awardPendingInstructorSkill}.
	 * <p>
	 * {@code 0x43c8} carries two answers. The star rating is always given. The recognition decision
	 * comes from the prompt "Save current instructor, %s, as the instructor for your personal data?
	 * (Instructor name cannot be erased once saved)" ({@code n002a} string 3099), which the client
	 * shows before the rating screen ({@code n002a} string 3105) — and which it suppresses entirely
	 * unless {@code 0x4122}'s saved-instructor field is zero. That prompt is the moment the player
	 * chooses to make the relationship permanent, so it, not the bare arrival of the packet, is what
	 * this keys on.
	 * <p>
	 * Every review is stored regardless, so a rating without recognition is not lost and the
	 * instructor score has a source. Without recognition nothing else happens: no relationship, no
	 * skill, no letter.
	 * <p>
	 * There is <b>no level or play-time requirement</b>. There used to be one here — level 4 and 20
	 * hours, taken from player accounts of retail behaviour — and it was our invention. Falsified
	 * twice on 2026-07-27: a character with 428 experience (level 3) and zero accumulated play time
	 * was shown the recognition prompt, answered yes, and was then refused the award by our own
	 * rule; and the client's eligibility logic contains no read of level, experience, skill
	 * ownership or instructor generation anywhere ({@code 0x6D8B10}, {@code 0x6D8BB0},
	 * {@code 0x6D97E0}, {@code 0x27DF38}, {@code 0x27E050}).
	 * <p>
	 * What the client does gate on is a timer, and it is not ours to enforce: {@code 0x6D8BB0} scans
	 * the roster each tick on the <em>instructor's</em> machine and approves a student once a
	 * per-slot accumulator passes {@code 5,400,000} ({@code 0x6D8C10}), resetting to zero the moment
	 * the slot empties ({@code 0x6D8CA8}). It is session-accumulated, never sent to us, and the
	 * server is never consulted — by the time {@code 0x43c8} arrives the client has already decided.
	 * <p>
	 * Idempotent on the award: a student who already holds the skill gets the relationship updated
	 * and no second letter, so re-graduating with a different instructor re-parents them without
	 * spamming the mailbox.
	 */
	public Graduation recordGraduation(long studentId, long instructorId, int rating,
			boolean recognised, int answerByte) {
		return jdbi.inTransaction(handle -> {
			var instructorName = handle
				.createQuery("select name from chara where id = :id")
				.bind("id", instructorId)
				.mapTo(String.class)
				.findOne()
				.orElse("");

			handle.createUpdate("""
					insert into instructor_review (instructor_chara_id, student_chara_id, rating,
						recognised, answer_byte)
					values (:instructor, :student, :rating, :recognised, :answer)
					""")
				.bind("instructor", instructorId)
				.bind("student", studentId)
				.bind("rating", rating)
				.bind("recognised", recognised)
				.bind("answer", answerByte)
				.execute();

			// An instructor with no record of their own is first generation.
			var generation = handle
				.createQuery("select generation from chara_instructor where chara_id = :id")
				.bind("id", instructorId)
				.mapTo(Integer.class)
				.findOne()
				.orElse(1) + 1;

			// Rated but not recognised: the review is on file and that is all the player asked for.
			if (!recognised) {
				return new Graduation(generation, false);
			}

			handle.createUpdate("""
					insert into chara_instructor as ci
						(chara_id, instructor_chara_id, instructor_name, generation, rating,
						 graduated_at)
					values (:student, :instructor, :name, :generation, :rating, now())
					on conflict (chara_id) do update set
						instructor_chara_id = excluded.instructor_chara_id,
						instructor_name = excluded.instructor_name,
						generation = excluded.generation,
						rating = excluded.rating,
						graduated_at = excluded.graduated_at
					""")
				.bind("student", studentId)
				.bind("instructor", instructorId)
				.bind("name", instructorName)
				.bind("generation", generation)
				.bind("rating", rating)
				.execute();

			return new Graduation(generation, true);
		});
	}

	private static final String GRADUATION_SENDER = "GameMaster";

	private static final String GRADUATION_SUBJECT = "You've been awarded the Instructor Skill";

	/**
	 * The announcement body, reproduced verbatim from a live client's letter — including the
	 * Konami URL, which no longer resolves.
	 * <p>
	 * An earlier version dropped the URL and the sign-off on the grounds that pointing players at a
	 * dead domain was unhelpful. That was the wrong call: this is a reproduction of what the
	 * original service sent, and silently shortening it makes the letter a paraphrase. The line
	 * break inside the URL is the client's own wrapping at the field width, not ours.
	 */
	private static final String GRADUATION_BODY = """
			Congratulations!

			You've been approved for graduation by
			your instructor and have accumulated
			ample experience on the battlefield.
			As a result, you are now certified as an
			"Instructor" and have been awarded
			the "Instructor Skill".

			You can now create your own Combat
			Training sessions to train others, just
			as your instructor did for you.
			For more info on Combat Training, see
			the Combat Training Manual.

			Combat Training Manual:
			http://www.konami.jp/mgo/en/instructor.html

			From:
			the MGO staff at Kojima Productions""";

	/** Who trained a character, as the stats screen shows it. */
	public record Instructor(long instructorCharaId, String instructorName, int generation,
			int rating) {
	}

	public java.util.Optional<Instructor> instructorOf(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select instructor_chara_id, instructor_name, generation, rating
					from chara_instructor where chara_id = :id
					""")
				.bind("id", charaId)
				.map((rs, c) -> new Instructor(rs.getLong("instructor_chara_id"),
					rs.getString("instructor_name"), rs.getInt("generation"), rs.getInt("rating")))
				.findOne());
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
	/** Whether {@code charaId} has blocked {@code otherId}. */
	public boolean hasBlocked(long charaId, long otherId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select count(*) from chara_relation
				where chara_id = :chara and target_chara_id = :other and state = :blocked
				""")
			.bind("chara", charaId)
			.bind("other", otherId)
			.bind("blocked", RELATION_BLOCKED)
			.mapTo(Long.class)
			.one()) > 0;
	}

	/**
	 * Whether a character may found a clan: <b>20 hours of play time and level 3</b>.
	 * <p>
	 * <b>This is operator policy on community report, not a value read from the binary.</b> The
	 * text exists — "You must have 20 hours of playing time and a Level of at least 3 to create a
	 * clan", ordinal 81 of string group {@code 0x333C8E} — but so does ordinal 82 beside it, which
	 * says <b>5 hours and Level 2</b>. Two tiers shipped and nothing in {@code MGO2.elf} chooses
	 * between them: neither item hash ({@code 0xE5EEC8}, {@code 0x3E91BB}) is referenced anywhere
	 * in the binary or in {@code scenerio.gcl}, and there is no selector table.
	 * <p>
	 * That absence proves nothing either way, which is the point worth remembering. Only 24 of that
	 * group's 153 strings are referenced by literal hash, and the unreferenced 129 include "Create
	 * Clan", "Clan List" and "Disband" — strings that unquestionably render. The group is addressed
	 * through an indirection in the packed UI resources that nobody has decoded, so "no reference
	 * found" is not an elimination here, unlike in the error table where the same test is decisive.
	 * <p>
	 * [ELF] What <em>is</em> settled: <b>the client never checks either rule.</b> The create-clan
	 * sender {@code 0xD579AC} reads no play time and no level — it validates name length, character
	 * class, comment length, connectivity, and whether you are already in a clan, then sends. The
	 * constants are absent too: 18000 and 72000 (5h and 20h in seconds) occur as no immediate
	 * anywhere in the binary, and the two {@code {20,3}} comparison adjacencies that exist are
	 * unrelated switch dispatches. So whichever tier is right, <b>the server is the only thing that
	 * can enforce it</b>, and picking the stricter one is a choice rather than a reading.
	 * <p>
	 * The same numbers as the instructor award, which is coincidence rather than a shared rule: the
	 * two are separate policies that happen to agree, so they are checked separately.
	 */
	public boolean meetsClanRequirements(long charaId) {
		return jdbi.withHandle(handle -> handle
			.createQuery("""
				select count(*) from chara c
				join account a on a.id = c.account_id
				where c.id = :chara
				  -- Play time from round_report, the same sum the stats screen shows. Was
				  -- chara_training_time.total_seconds x PLAYABLE_MODES, which made the real bar
				  -- about 3h20m rather than the 20 hours the requirement claims -- an artefact of
				  -- an old display hack that multiplied play time six times over. Both the hack
				  -- and the column are gone; see V50 and the commit that dropped them.
				  and (select coalesce(sum(r.seconds_in_game), 0) from round_report r
					   where r.chara_id = c.id and r.rule between 0 and :lastMode) >= :seconds
				  and case when a.main_chara_id = c.id then a.main_exp else a.alt_exp end
					  >= :experience
				""")
			.bind("chara", charaId)
			.bind("lastMode", PLAYABLE_MODES - 1)
			.bind("seconds", CLAN_MIN_SECONDS)
			.bind("experience", LEVEL_3_EXPERIENCE)
			.mapTo(Long.class)
			.one()) > 0;
	}

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
	 * One stored letter, as the mailbox replies need it.
	 * <p>
	 * {@code counterparty} is the name the list entry shows: the <em>sender</em> for a received
	 * letter, the <em>recipient</em> for a sent one. The 0x4822 entry has exactly one 128-byte
	 * name field, so which end it names depends on which list the entry belongs to.
	 * <p>
	 * {@code index} is the position within its own list, newest first — what the 0x4822 index byte
	 * carries and what 0x4840 sends back to open a letter.
	 */
	/**
	 * @param systemSender true when no character sent this — a GameMaster announcement rather than
	 *                     player mail, which the client files under a different tab
	 */
	public record Mail(long id, int index, String counterparty, String subject, String body,
		java.time.Instant sentAt, boolean read, boolean systemSender) {
	}

	/**
	 * Delivers one letter, resolving the recipient by name. Returns false when no character owns
	 * that name — the client lets the player type a recipient freely, so an unknown name is an
	 * ordinary outcome rather than an error.
	 * <p>
	 * The sender's name is stored alongside the id: the id is the honest link, but a list entry
	 * has to render a name even if that character is later deleted or renamed.
	 */
	/** An active character by name, case-insensitively — names are unique that way. */
	public Optional<Long> findByName(String name) {
		return jdbi.withHandle(handle -> handle
			.createQuery("select id from chara where lower(name) = lower(:name) and active")
			.bind("name", name)
			.mapTo(Long.class)
			.findOne());
	}

	public boolean sendMail(long senderCharaId, String senderName, String recipientName,
		String subject, String body) {
		return jdbi.withHandle(handle -> handle.createUpdate("""
					insert into mail (recipient_chara_id, sender_chara_id, sender_name, subject, body)
					select c.id, :sender, :senderName, :subject, :body
					from chara c where c.name = :recipient
					""")
			.bind("sender", senderCharaId)
			.bind("senderName", senderName)
			.bind("recipient", recipientName)
			.bind("subject", subject)
			.bind("body", body)
			.execute()) > 0;
	}

	/**
	 * Letters a character has received, newest first. Counterparty is the sender.
	 * <p>
	 * The ordering has to be stable: the 0x4822 index byte is a position in it, and 0x4840 sends
	 * that position back to choose which letter to open.
	 */
	public java.util.List<Mail> mailbox(long charaId, int limit) {
		return mail("""
				select id, sender_name as counterparty, subject, body, sent_at, is_read,
					sender_chara_id
				from mail where recipient_chara_id = :chara and not recipient_deleted
				order by sent_at desc, id desc
				limit :limit
				""", charaId, limit);
	}

	/**
	 * Letters a character has sent, newest first. Counterparty is the recipient.
	 * <p>
	 * Read from the same rows as {@link #mailbox}, from the other end — one row per delivery,
	 * never a duplicate "sent copy". A letter to eight recipients is eight rows and therefore
	 * eight entries here, which is what the wire format can express: the 0x4822 entry has one
	 * name field, so a single row naming all eight is not representable.
	 */
	public java.util.List<Mail> sentMail(long charaId, int limit) {
		return mail("""
				select m.id, c.name as counterparty, m.subject, m.body, m.sent_at,
					m.sender_read as is_read, m.sender_chara_id
				from mail m join chara c on c.id = m.recipient_chara_id
				where m.sender_chara_id = :chara and not m.sender_deleted
				order by m.sent_at desc, m.id desc
				limit :limit
				""", charaId, limit);
	}

	/**
	 * Marks one letter read for the end that opened it — what the client cannot do for us.
	 * <p>
	 * The client sets its own copy's read byte on open ({@code 0x8E2CD8}), but that is local
	 * state: the next {@code 0x4821} zeroes all four category counters and the lists are rebuilt
	 * entirely from the {@code 0x4822} entries we send, so an unrecorded read comes back as new.
	 * There is no "mark as read" command — opening ({@code 0x4840}) is the only signal, which is
	 * why this is called from the read handler rather than a command of its own.
	 * <p>
	 * Per-side, like deletion: a sender opening their own letter in Sent must not clear the
	 * recipient's unread badge for mail they have never seen.
	 */
	public void markMailRead(long charaId, long mailId, boolean sent) {
		jdbi.useHandle(handle ->
			handle.createUpdate(sent
					? """
						update mail set sender_read = true
						where id = :id and sender_chara_id = :chara
						"""
					: """
						update mail set is_read = true
						where id = :id and recipient_chara_id = :chara
						""")
				.bind("id", mailId)
				.bind("chara", charaId)
				.execute());
	}

	/**
	 * Removes one letter from the asking end's list only.
	 * <p>
	 * A row is one delivery seen from both ends, so a recipient deleting a letter must not remove
	 * it from the sender's Sent list. Each end has its own flag; the row goes when neither end can
	 * see it any more.
	 */
	public void deleteMail(long charaId, long mailId, boolean sent) {
		jdbi.useHandle(handle -> {
			handle.createUpdate(sent
					? """
						update mail set sender_deleted = true
						where id = :id and sender_chara_id = :chara
						"""
					: """
						update mail set recipient_deleted = true
						where id = :id and recipient_chara_id = :chara
						""")
				.bind("id", mailId)
				.bind("chara", charaId)
				.execute();
			handle.createUpdate("""
					delete from mail
					where id = :id and recipient_deleted and (sender_deleted or sender_chara_id is null)
					""")
				.bind("id", mailId)
				.execute();
		});
	}

	/** Shared body of {@link #mailbox} and {@link #sentMail}: the index is the row's position. */
	private java.util.List<Mail> mail(String sql, long charaId, int limit) {
		return jdbi.withHandle(handle -> {
			var rows = handle.createQuery(sql)
				.bind("chara", charaId)
				.bind("limit", limit)
				.map((rs, ctx) -> new Object[] { rs.getLong("id"), rs.getString("counterparty"),
					rs.getString("subject"), rs.getString("body"),
					rs.getTimestamp("sent_at").toInstant(), rs.getBoolean("is_read"),
					rs.getObject("sender_chara_id") == null })
				.list();
			var mail = new java.util.ArrayList<Mail>(rows.size());
			for (var index = 0; index < rows.size(); index++) {
				var row = rows.get(index);
				mail.add(new Mail((long) row[0], index, (String) row[1], (String) row[2],
					(String) row[3], (java.time.Instant) row[4], (boolean) row[5],
					(boolean) row[6]));
			}
			return mail;
		});
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

	/**
	 * The skills a character owns — exactly what the table holds, with no top-up.
	 * <p>
	 * The starting set is granted once, at character creation, and V20 backfilled the characters
	 * that predate the table. Nothing re-seeds afterwards, deliberately: a character with a subset
	 * keeps that subset, and a character with no rows sends an empty {@code 0x4125}, which is the
	 * only way "does not have this skill" can be expressed at all.
	 * <p>
	 * Which skills a character starts with is <em>policy</em>, not protocol. A server that wanted
	 * them earned would seed nothing at creation and insert on whatever grants one.
	 */
	public List<CharaSkill> getSkills(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select * from chara_skill where chara_id=:id order by skill_id")
				.bind("id", charaId)
				.mapTo(CharaSkill.class)
				.list());
	}

	/**
	 * One gear record as {@code 0x4124} and {@code 0x4133} carry it: an item id and its colour
	 * mask. Emitted once per <em>catalogue row</em>, so the duplicated {@code 0x86} yields two.
	 */
	public record OwnedGear(int itemId, long colours) {
	}

	/**
	 * The gear a character owns, in the catalogue's wire order — exactly what the table holds.
	 * <p>
	 * The join is against {@code gear_item} rather than a constant, so the order and the record
	 * count come from the catalogue and ownership comes from {@code chara_gear}. An item the
	 * character does not own is <em>omitted</em>, not sent with a zero mask: the client memsets
	 * the whole loadout table before applying records, so an absent record is the only way "does
	 * not have this" can be expressed. Same mechanism as {@link #getSkills}.
	 * <p>
	 * Both writers must use this. {@code 0x4124} fills the table at login and {@code 0x4133}
	 * refills it after the outfit screen zeroes it, and if the two ever disagree the client keeps
	 * whichever spoke last — which is exactly the bug that made a character lose everything by
	 * opening the outfit screen.
	 * <p>
	 * Which items a character starts with is <em>policy</em>, not protocol. V44 backfilled
	 * everyone with everything, preserving the behaviour that predates the table; a server that
	 * wanted gear earned would grant a starter set at creation and insert on whatever unlocks one.
	 */
	public List<OwnedGear> ownedGear(long charaId) {
		return jdbi.withHandle(handle ->
			handle.createQuery("""
					select g.item_id, cg.colours
					from gear_item g
					join chara_gear cg
						on cg.item_id = g.item_id and cg.chara_id = :id
					order by g.ordinal
					""")
				.bind("id", charaId)
				.map((rs, sctx) -> new OwnedGear(rs.getInt("item_id"), rs.getLong("colours")))
				.list());
	}

	/**
	 * Stored experience per skill id, for the packets that report it alongside an equipped level.
	 * <p>
	 * Returns a lookup rather than the list because the callers need it keyed by skill id and a
	 * character has at most eighteen rows; building a map once beats scanning the list per slot.
	 * A skill with no row reads as 0, which is the truth — nothing has been earned toward it.
	 */
	public java.util.function.IntUnaryOperator skillExperience(long charaId) {
		var byId = new java.util.HashMap<Integer, Integer>();
		for (var skill : getSkills(charaId)) {
			byId.put(skill.getSkillId(), skill.getExperience());
		}
		return skillId -> byId.getOrDefault(skillId, 0);
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

	/**
	 * Whether a character name is already in use, <b>ignoring case</b>.
	 *
	 * <p>It was case-sensitive, so "sean" was accepted alongside "Sean". Two characters whose names
	 * differ only in case are indistinguishable everywhere the game shows a name — rosters, friend
	 * lists, the instructor badge — and the client's own error for this,
	 * {@code CHARACTER_NAME_TAKEN} (-260, "Desired PC name is already in use"), exists precisely so
	 * the server can refuse it.
	 *
	 * <p>Deleted characters keep their row but release the name (it moves to {@code old_name}), so
	 * only active ones count.
	 */
	public boolean isNameTaken(String name) {
		return jdbi.withHandle(handle ->
			handle.createQuery("select count(*) from chara where lower(name) = lower(:name) and active")
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

			// The starting gear: every catalogue item, in every colour.
			//
			// This is POLICY, and it is the permissive one — it matches what every character had
			// before V44, so creating a character is unchanged by the table existing. Granting a
			// real starter set means narrowing this insert (and the V44 backfill); nothing in the
			// binary says which items a character should begin with, because the client never
			// checks — it renders whatever the two gear writers agree on.
			//
			// DISTINCT because the catalogue holds 0x86 twice: ownership is per item, and the
			// duplicate is a quirk of the wire order that the writer reproduces from gear_item.
			handle.createUpdate("""
					insert into chara_gear (chara_id, item_id)
					select :charaId, distinct_items.item_id
					from (select distinct item_id from gear_item) distinct_items
					on conflict (chara_id, item_id) do nothing
					""")
				.bind("charaId", charaId)
				.execute();

			// The starting skill set: ids 1..16 at level 1, and no skill 17.
			//
			// Seeded here rather than on read so that a character's skills are afterwards whatever
			// the table says — including none. A read that top-up-seeded could not express "this
			// character has lost, or never had, skill N".
			//
			// Level 1 rather than 0 because 0 is not a thing the client can show: its list builder
			// rejects any record at or below 8191 experience (0x8DD5F0), so a zero-experience skill
			// is invisible and a gameplay check reads it as level 0 anyway. Skill 17 is withheld —
			// see CharaSkill.STARTING_MAX_ID.
			//
			// The bound reads ":maxId >= id" rather than the natural way round, and this note lives
			// out here rather than in the SQL, for the same reason: Jdbi renders statements through
			// StringTemplate, which treats a less-than sign as the start of an expression and fails
			// to compile — in the statement text or in a comment inside it.
			handle.createUpdate("""
					insert into chara_skill (chara_id, skill_id, experience, flag)
					select :chara, id, :experience, 0
					from skill
					where :maxId >= id
					""")
				.bind("chara", charaId)
				.bind("experience", CharaSkill.MINIMUM_VISIBLE_EXPERIENCE)
				.bind("maxId", CharaSkill.STARTING_MAX_ID)
				.execute();

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

	/**
	 * Seconds until a character may be deleted, or 0 when it already may be.
	 * <p>
	 * The client enforces this itself and shows the countdown, given the value in {@code 0x3049}'s
	 * per-entry trailing u32 — so this is what makes "You must wait %d hours %d minutes" appear with
	 * real numbers instead of the deletion simply being refused.
	 */
	public long secondsUntilDeletable(Chara chara, OffsetDateTime now) {
		if (chara.getCreatedAt() == null) {
			return 0;
		}
		var ready = chara.getCreatedAt().plus(DELETE_COOLDOWN);
		return now.isBefore(ready) ? java.time.Duration.between(now, ready).toSeconds() : 0;
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
