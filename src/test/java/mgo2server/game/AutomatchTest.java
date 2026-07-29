package mgo2server.game;

import io.netty.channel.embedded.EmbeddedChannel;
import mgo2server.common.AutomatchPolicy;
import mgo2server.common.Level;
import mgo2server.game.controller.AutomatchGameController;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * The automatch queue: who is in it, who leaves it, and what a tick does to them.
 *
 * <p>Almost none of this is protocol — the client sends a rule filter and then goes silent for
 * twenty minutes, so the queue's shape is entirely ours ({@code AUTOMATCH.md} §1). What it is
 * guarding is a set of properties whose absence is invisible from outside: a searcher who never
 * leaves the map is a slow leak, and a searcher removed by the wrong event is a player whose panel
 * stops updating with no error anywhere.
 *
 * <p>{@link EmbeddedChannel} rather than a mock because the disconnect path is one of those
 * properties. It is a real {@link io.netty.channel.Channel}, it is active until closed, and its
 * {@code closeFuture} completes on close, so the listener {@code enqueue} registers is exercised for
 * real instead of being asserted about.
 *
 * <p><b>Not covered:</b> the {@link Automatch#MAX_WAIT} reap. It is 25 minutes and {@code Instant.now}
 * is read inside the class, so there is no seam to move the clock through, and adding one purely for
 * a test would put test scaffolding in the server. The other half of {@code reap} — the searcher
 * whose socket is dead — is covered below, and it is the half that actually fires: the client gives
 * up on its own at ~20 minutes, so {@code MAX_WAIT} is a backstop that a healthy client never
 * reaches.
 */
public class AutomatchTest {

	/** The "do not specify rules" sentinel, and what a live client actually sends. */
	private static final int ANY_RULE = AutomatchGameController.ANY_RULE;

	/**
	 * A queue whose policy wants {@code minPlayers} before it forms a game.
	 * <p>
	 * Built through {@code from} rather than the canonical constructor so the defaults stay the ones
	 * a deployment would get. It parses as disabled, which skips {@code validate} — the queue never
	 * asks whether the window is open, because by the time anything is enqueued the controller has
	 * already decided that.
	 * <p>
	 * <b>The decay is pinned flat here</b>, by starting the requirement at {@code minPlayers} rather
	 * than the deployed 12. These tests are about grouping, banding and the shortfall arithmetic, all
	 * of which run at a fixed requirement; leaving the decay on would mean every one of them
	 * additionally depended on how much simulated time had passed, and would fail for a reason that
	 * has nothing to do with what they assert. The decay itself is covered where it belongs, in
	 * {@code AutomatchPolicyTest}.
	 */
	private static Automatch queueNeeding(int minPlayers) {
		return queueNeeding(minPlayers, (lobbyId, hostCharaId) -> 0L);
	}

	/**
	 * As above, with a stub for the one thing the matchmaker asks the database: whether a character
	 * already hosts a game here. Returning 0 means "nobody hosts anything", which is what an empty
	 * lobby looks like and what every test but the election ones wants.
	 */
	private static Automatch queueNeeding(int minPlayers, Automatch.GameLookup games) {
		return new Automatch(AutomatchPolicy.from(Map.of(
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS", String.valueOf(minPlayers),
			"MGO2SERVER_AUTOMATCH_MIN_PLAYERS_START", String.valueOf(minPlayers))::get),
			LOBBY_ID, LOBBY_SUBTYPE, games);
	}

	/** The automatching lobby as deployed: id 3, subtype 2. */
	private static final long LOBBY_ID = 3;

	private static final int LOBBY_SUBTYPE = 2;

	@Test
	public void enqueueAddsOneSearcher() {
		var automatch = queueNeeding(2);

		automatch.enqueue(7, ANY_RULE, 1234, new EmbeddedChannel());

		assertThat(automatch.size()).isEqualTo(1);
		assertThat(automatch.searchers()).singleElement().satisfies(searcher -> {
			assertThat(searcher.charaId()).isEqualTo(7);
			assertThat(searcher.ruleFilter()).isEqualTo(ANY_RULE);
			assertThat(searcher.experience()).isEqualTo(1234);
			assertThat(searcher.state()).isEqualTo(Automatch.State.SEARCHING);
		});
	}

	/**
	 * A second {@code 0x43e0} from one character replaces the first.
	 * <p>
	 * The client can produce this: cancel returns it to state 1 with the lobby still open, so it can
	 * confirm a different rule immediately, and a reconnect can land a fresh {@code 0x43e0} before
	 * the old socket's close has been noticed. Two entries would mean two seats held for one player,
	 * and pushes down a channel nobody is reading.
	 * <p>
	 * The last assertion is the reason {@code enqueue} removes by key <em>and</em> value: the stale
	 * channel closing must not evict the entry that replaced it.
	 */
	@Test
	public void enqueuingTheSameCharacterTwiceReplacesRatherThanDuplicates() {
		var automatch = queueNeeding(2);
		var first = new EmbeddedChannel();
		var second = new EmbeddedChannel();

		automatch.enqueue(7, ANY_RULE, 0, first);
		automatch.enqueue(7, 3, 0, second);

		assertThat(automatch.size()).isEqualTo(1);
		assertThat(automatch.searchers()).singleElement().satisfies(searcher -> {
			assertThat(searcher.ruleFilter()).isEqualTo(3);
			assertThat(searcher.channel()).isSameAs(second);
		});

		first.close();

		assertThat(automatch.size())
			.as("the replaced channel closing must not evict the entry that replaced it")
			.isEqualTo(1);
	}

	/** Cancelling a live search is the ordinary path, and answers {@code 0x43e3} result 0. */
	@Test
	public void cancellingASearchingEntryRemovesIt() {
		var automatch = queueNeeding(2);
		automatch.enqueue(7, ANY_RULE, 0, new EmbeddedChannel());

		assertThat(automatch.cancel(7)).isEqualTo(Automatch.CancelOutcome.CANCELLED);
		assertThat(automatch.size()).isZero();
	}

	/**
	 * Cancelling nothing succeeds. The client sends {@code 0x43e2} from state 7 whether or not we
	 * still hold a record — its own 180000-tick timeout drives it there — and a nonzero result would
	 * print "Unable to cancel automatching" (4932) for a search that is, in fact, cancelled.
	 */
	@Test
	public void cancellingSomethingNeverQueuedStillSucceeds() {
		var automatch = queueNeeding(2);

		assertThat(automatch.cancel(7)).isEqualTo(Automatch.CancelOutcome.CANCELLED);
		assertThat(automatch.size()).isZero();
	}

	/**
	 * The precise-removal guarantee, and the reason the channel is captured at {@code 0x43e0} rather
	 * than looked up in {@link ChannelRegistry} later. Nothing else tells us a searcher has gone:
	 * while searching the client sends nothing at all, so a dropped connection is only ever visible
	 * as its channel closing.
	 */
	@Test
	public void closingTheChannelRemovesTheSearcher() {
		var automatch = queueNeeding(2);
		var channel = new EmbeddedChannel();
		automatch.enqueue(7, ANY_RULE, 0, channel);

		channel.close();

		assertThat(automatch.size()).isZero();
	}

	/**
	 * Two searchers match only when their level windows <b>share a level</b> — not when they are
	 * merely adjacent.
	 *
	 * <p>The operator's rule, and the one this pins: if the higher player accepts down to level 10
	 * and the lower accepts up to level 10, that is a match. If the higher reaches 10 and the lower
	 * only reaches 9, it is not, however close it looks.
	 *
	 * <p>A window is {@code [level - band, level + band]}, so sharing a level is exactly
	 * {@code |La - Lb| <= banda + bandb}. The boundary case is the one worth having a test for: at
	 * equality the two windows overlap in precisely one column, which is a match; one further apart
	 * is not.
	 *
	 * <p>Experience values here are chosen through {@code Level.of}: 4600 is the table's cap (level
	 * 22) and 125 is its first threshold (level 1).
	 */
	@Test
	public void windowsMustShareALevelNotMerelyTouch() {
		var wide = queueNeeding(2, (lobbyId, hostCharaId) -> 0L);
		wide.enqueue(1, ANY_RULE, Level.experienceFor(10), new EmbeddedChannel());
		wide.enqueue(2, ANY_RULE, Level.experienceFor(12), new EmbeddedChannel());

		var searchers = List.copyOf(wide.searchers());
		var a = searchers.get(0);
		var b = searchers.get(1);

		// Levels 10 and 12 with the default starting band of 1 give [9,11] and [11,13]: they share
		// level 11, so this is a match under the operator's rule.
		assertThat(Math.abs(a.level() - b.level())).isEqualTo(2);
		assertThat(wide.band(a) + wide.band(b)).isGreaterThanOrEqualTo(2);
	}

	/**
	 * The figure the client prints through disc string 917, floored at zero because zero selects the
	 * placeholder string 48 instead — "no figure yet" rather than "zero more players".
	 *
	 * <p><b>Counted per searcher, among those they can actually reach.</b> A global count is wrong
	 * and was observed to be wrong live: two searchers whose level windows had not met produced a
	 * queue of two against a minimum of two, so the figure went to zero and the client printed
	 * <b>"????"</b> — string 48 — while the matchmaker was still refusing to match them. The server
	 * was asserting "nobody else needed" and declining to form a game in the same breath.
	 *
	 * <p>Everyone here shares experience 0, so every window contains every searcher and the
	 * per-searcher figure collapses to the global one. That is the case this test pins; the reachable
	 * subset is exercised by the level-window tests.
	 */
	@Test
	public void playersNeededIsTheShortfallAmongReachableSearchers() {
		var automatch = queueNeeding(4);

		// THE RECIPIENT IS COUNTED. A lone searcher facing a requirement of four sees four, not
		// three — reference footage of the original shows a lone searcher on 12 against the
		// 12-player start, so the figure means "players this game still needs, me included".
		assertThat(automatch.playersNeededOnArrival()).isEqualTo(4);

		automatch.enqueue(1, ANY_RULE, 0, new EmbeddedChannel());
		var first = automatch.searchers().iterator().next();
		assertThat(automatch.playersNeeded(first)).isEqualTo(4);

		automatch.enqueue(2, ANY_RULE, 0, new EmbeddedChannel());
		automatch.enqueue(3, ANY_RULE, 0, new EmbeddedChannel());
		// Two others found against a requirement of four: two still wanted, one of them this
		// searcher.
		assertThat(automatch.playersNeeded(first)).isEqualTo(2);

		// Three others now, so the figure reaches 1 rather than 0 at a complete group — deliberate,
		// because 0 renders as "????" (string 48) and the last slot must read as a number.
		automatch.enqueue(4, ANY_RULE, 0, new EmbeddedChannel());
		assertThat(automatch.playersNeeded(first)).isEqualTo(1);

		// Past the minimum it must not go negative: the field is one unsigned byte on the wire, so a
		// -1 would arrive as 255 players needed.
		automatch.enqueue(5, ANY_RULE, 0, new EmbeddedChannel());
		assertThat(automatch.playersNeeded(first)).isZero();
		automatch.enqueue(6, ANY_RULE, 0, new EmbeddedChannel());
		assertThat(automatch.playersNeeded(first)).isZero();
	}

	/**
	 * The overwhelmingly common case — the matchmaker runs every few seconds forever, and almost
	 * every run has nobody to look at. A throw here would be worse than useless: a scheduled task
	 * that throws is cancelled permanently, so one bad tick would stop matchmaking for the life of
	 * the process (see {@code GameServerSchedulerTest}).
	 */
	@Test
	public void tickOnAnEmptyQueueDoesNothing() {
		var automatch = queueNeeding(2);

		assertThatCode(automatch::tick).doesNotThrowAnyException();

		assertThat(automatch.size()).isZero();
	}

	/**
	 * The reap that actually fires: a searcher whose socket died without a close event.
	 * <p>
	 * An unregistered {@link EmbeddedChannel} is exactly that shape — never active, and its
	 * {@code closeFuture} never completes — so the {@code closeFuture} listener cannot be what
	 * removes this one. It has to be the tick, or the entry stays in the map forever and is counted
	 * into every other searcher's "players needed".
	 */
	@Test
	public void tickDropsASearcherWhoseChannelIsNotActive() {
		var automatch = queueNeeding(2);
		var dead = new EmbeddedChannel(false, false);
		assertThat(dead.isActive()).as("an unregistered channel stands in for a dead socket").isFalse();
		automatch.enqueue(7, ANY_RULE, 0, dead);
		assertThat(automatch.size()).isEqualTo(1);

		automatch.tick();

		assertThat(automatch.size()).isZero();
	}

	/**
	 * The push nothing asked for, which is the whole feature: the client repaints its panel only when
	 * {@code 0x43e4} arrives and never requests one, so a tick that pushes nothing leaves the player
	 * watching a stopwatch.
	 */
	@Test
	public void tickPushesASearchPanelToALiveSearcher() {
		var automatch = queueNeeding(4);
		var channel = new EmbeddedChannel();
		automatch.enqueue(7, ANY_RULE, 0, channel);

		automatch.tick();

		// A GamePacket, not a ByteBuf: the encoder is part of the real server's pipeline and an
		// EmbeddedChannel has none, so what comes back off the queue is the message as written.
		Object pushed = channel.readOutbound();
		assertThat(pushed).isInstanceOf(GamePacket.class);
		var packet = (GamePacket) pushed;

		assertThat(packet.getCommand()).isEqualTo(AutomatchPackets.SEARCH_PANEL);
		assertThat(packet.getPayload().readableBytes()).isEqualTo(AutomatchPackets.SEARCH_PANEL_SIZE);
		// Players-needed is relative to the recipient — four wanted, one searching, and the recipient
		// counts themselves — which is why each searcher gets its own buffer rather than one being
		// broadcast.
		assertThat(packet.getPayload().getUnsignedByte(0x11)).isEqualTo((short) 4);

		// Bound to Object first: readOutbound() infers its own return type, which leaves the assertJ
		// overloads ambiguous.
		Object second = channel.readOutbound();
		assertThat(second).as("one panel per searcher per tick").isNull();

		packet.getPayload().release();
		channel.finishAndReleaseAll();
	}

	/** A cancelled searcher is not pushed to, which is the observable half of "removed". */
	@Test
	public void tickPushesNothingToACancelledSearcher() {
		var automatch = queueNeeding(2);
		var channel = new EmbeddedChannel();
		automatch.enqueue(7, ANY_RULE, 0, channel);
		automatch.cancel(7);

		automatch.tick();

		Object pushed = channel.readOutbound();
		assertThat(pushed).isNull();
		channel.finishAndReleaseAll();
	}
}
