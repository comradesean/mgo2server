package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.GameClient;
import mgo2server.TestDatabase;
import mgo2server.common.AutomatchPolicy;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.AutomatchPackets;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.GameServerFactory;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiConsumer;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Starting and cancelling an automatch search — {@code 0x43e0}/{@code 0x43e2} and their replies.
 * <p>
 * Two things here are read from the binary and everything else is policy. The <b>reply lengths</b>
 * are protocol: the parser at {@code 0xD5BF98} reads the two trailing u8s of {@code 0x43e1} only
 * when the result is zero, so success is six bytes and failure is four, and {@code 0x43e3}'s parser
 * at {@code 0xD5BB04} reads a u32 unconditionally — an empty payload there leaves it reading stale
 * receive buffer as the result, which is the trap {@code 0x4399} fell into. The <b>result codes</b>
 * are protocol too: the client matches −970 and −950 against literals and prints Konami's own
 * sentences ({@code 0x93D224}, {@code 0x93CF50}), so a wrong code is a wrong sentence rather than a
 * silent pass. Whether a given search is accepted at all is ours. See {@code AUTOMATCH.md} §3 and §6.
 * <p>
 * A separate class rather than more tests on {@code HubGameControllerIT} because the commands moved
 * out of that controller on 2026-07-28, and because this class needs its own automatch policy — the
 * window has to be open for anything but a refusal to be observable.
 */
public class AutomatchGameControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	/** {@code u32 result}, then band and players-needed. */
	private static final int SUCCESS_SIZE = 6;

	/** {@code u32 result} alone — every failure, and both cancel outcomes. */
	private static final int RESULT_ONLY_SIZE = 4;

	/**
	 * A tick short enough to test against. The deployed default is five seconds, which is chosen for
	 * a client whose search runs twenty minutes; a test that waited for it would spend most of its
	 * life asleep. Nothing here asserts the interval itself — {@code GameServerSchedulerTest} owns
	 * that — only that a push happens at all.
	 */
	private static final Duration TICK = Duration.ofSeconds(1);

	/** Long enough for three ticks, which is what "no push arrived" is worth asserting over. */
	private static final long WATCH_MS = 3500;

	/**
	 * A push already handed to the event loop when a cancel is processed is legitimately in flight —
	 * the tick runs on the scheduler thread and the cancel on the channel's — so one tick is allowed
	 * to drain before the absence of pushes starts counting.
	 */
	private static final long DRAIN_MS = 1500;

	/**
	 * Open at every instant a wall clock can actually hold.
	 * <p>
	 * Built directly rather than parsed from a window string so the test does not depend on the
	 * midnight-wrapping rule it would otherwise have to exploit; that rule is pinned in
	 * {@code AutomatchPolicyTest}. The exclusive end excludes only {@code 23:59:59.999999999}
	 * exactly, which no {@code now()} has ever landed on.
	 */
	private static final AutomatchPolicy ALWAYS_OPEN = new AutomatchPolicy(true,
		List.of(new AutomatchPolicy.Window(LocalTime.MIN, LocalTime.MAX)), ZoneId.of("UTC"),
		AutomatchPolicy.Mode.BOTH, 2, TICK, Set.of(),
		// The widest band from the outset, so level never decides whether these tests match. Level
		// windowing has its own coverage; here it would only make the outcome depend on whatever
		// experience the fixtures happen to give a character.
		AutomatchPolicy.DEFAULT_BAND_MAX, Duration.ofSeconds(30), AutomatchPolicy.DEFAULT_BAND_MAX,
		// Zero relaxation: every searcher accepts any mode immediately, so rule filters never decide
		// whether these tests match. Mode grouping has its own coverage; here it would only make the
		// outcome depend on which filter a fixture happened to send.
		Duration.ZERO,
		// No decay: the requirement is MIN_PLAYERS from the outset, so these tests match as soon as
		// enough clients are queued rather than waiting out a countdown. The decay has its own
		// coverage.
		2, Duration.ZERO);

	/**
	 * What an operator who has configured nothing gets, and therefore the default deployment — with
	 * the tick shortened, which is the only deviation and cannot change any answer. A closed window
	 * refuses before anything is queued, so the matchmaker has nothing to look at however often it
	 * runs; the short interval only means a test asserting that it pushes nothing does not have to
	 * wait fifteen seconds to have watched three ticks.
	 */
	private static final AutomatchPolicy CLOSED = AutomatchPolicy.from(
		Map.of("MGO2SERVER_AUTOMATCH_TICK_SECONDS", String.valueOf(TICK.toSeconds()))::get);

	private long charaId;

	/** The automatch commands are only registered for a game lobby. */
	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	@Override
	protected AutomatchPolicy automatchPolicy() {
		return ALWAYS_OPEN;
	}

	/**
	 * Rebuilds the server under test with a different policy.
	 * <p>
	 * The policy is fixed when the server is constructed, which the base class does in
	 * {@code @BeforeEach} — so a class cannot hold both an open and a closed window. Rebuilding is
	 * cheaper than a second test class that would have to duplicate this file's fixtures.
	 */
	private void restartWith(AutomatchPolicy policy) {
		server.stop(0L, 0L, TimeUnit.SECONDS).join();
		server = GameServerFactory.createGameServer(services, 0, lobbyType(), lobbyId, 0, policy);
		server.start().join();
	}

	private void givenSelectedCharacter() {
		var accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, main_exp)
					values ('automatch', 'x', :session, 3, 0)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, 'Snake')")
				.bind("account", accountId)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle -> handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara
					where id = :id
					""")
			.bind("chara", charaId).bind("id", accountId).execute());
	}

	/**
	 * Logs in, sends one request and returns the single reply.
	 * <p>
	 * A fresh {@link GameClient} per exchange, shut down on the way out, because several tests here
	 * send more than one request and {@code GameClient.run} allocates an event loop group each time.
	 */
	private GamePacket exchange(GamePacket request) {
		return exchange(request, true);
	}

	private GamePacket exchange(GamePacket request, boolean login) {
		var replies = new ArrayList<GamePacket>();

		var session = Unpooled.buffer();
		session.writeInt((int) charaId);
		session.writeBytes(SessionField.of(TOKEN));

		client = new GameClient(server.boundPort());
		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(login
					? new GamePacket(AccountGameController.CHECK_SESSION, session)
					: request);
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}

				if (login && packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(request);
					return;
				}

				// An accepted 0x43e0 queues this character, so the matchmaker may push a panel into
				// the gap between the reply and this connection closing. It is not the reply this
				// method is waiting for; the tests that care about it are the ones that stay open.
				if (packet.getCommand() == AutomatchPackets.SEARCH_PANEL) {
					return;
				}

				replies.add(packet);
				ctx.close();
			}
		});
		client.disconnect(0L, 0L, TimeUnit.SECONDS).join();

		assertThat(replies).hasSize(1);
		return replies.get(0);
	}

	/**
	 * Logs in, sends one request and then <b>stays connected</b>, handing every later packet to
	 * {@code onPacket} until that closes the channel.
	 * <p>
	 * This is the shape a searching client actually has, and {@link #exchange} cannot express it: from
	 * state 6 the client sends nothing whatsoever — no heartbeat, no poll — and everything that
	 * reaches it after {@code 0x43e1} is unsolicited. A test that closes on the first reply can never
	 * see a push. {@code GameClient.run} blocking until the handler closes is exactly the right
	 * primitive, and the timeout is a failure rather than an end condition: if the handler never
	 * closes, the push never came.
	 */
	private void searching(long timeoutSeconds, GamePacket request,
			BiConsumer<ChannelHandlerContext, GamePacket> onPacket) {
		var session = Unpooled.buffer();
		session.writeInt((int) charaId);
		session.writeBytes(SessionField.of(TOKEN));

		client = new GameClient(server.boundPort());
		client.run(timeoutSeconds, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, session));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
					ctx.writeAndFlush(request);
					return;
				}
				onPacket.accept(ctx, packet);
			}
		});
		client.disconnect(0L, 0L, TimeUnit.SECONDS).join();
	}

	/**
	 * The first push the server has ever sent unprompted, and the one that cannot go wrong quietly.
	 * <p>
	 * Nothing solicits it: after {@code 0x43e1} result 0 the client registers push channel 60
	 * ({@code 0x93CF04}) and then sends nothing at all, so if the matchmaker does not push, the panel
	 * never changes and the player watches a twenty-minute stopwatch. The 36 bytes are the parser's
	 * fixed read at {@code 0xD5BDCC}; the contents are pinned in {@code AutomatchPacketsTest}.
	 */
	@Test
	public void aSearchPanelIsPushedWithoutBeingAskedFor() {
		givenSelectedCharacter();

		var panels = new ArrayList<GamePacket>();
		searching(15, start(AutomatchGameController.ANY_RULE), (ctx, packet) -> {
			if (packet.getCommand() == AutomatchGameController.START_AUTOMATCH_RESULT) {
				assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
				// And then nothing is sent back, exactly as the client does in state 6.
				return;
			}
			assertThat(packet.getCommand()).isEqualTo(AutomatchPackets.SEARCH_PANEL);
			panels.add(packet);
			ctx.close();
		});

		assertThat(panels).hasSize(1);
		assertThat(panels.get(0).getPayload().readableBytes())
			.isEqualTo(AutomatchPackets.SEARCH_PANEL_SIZE);
	}

	/**
	 * Cancelling leaves the queue, observed the only way this end of the socket can observe it: the
	 * pushes stop.
	 * <p>
	 * The first panel is waited for deliberately, so that the silence afterwards is evidence rather
	 * than a coincidence — without it, a server that never pushed at all would pass. One tick is
	 * allowed to drain first, because a panel handed to the event loop before the cancel was
	 * processed is in flight through no fault of the queue.
	 */
	@Test
	public void cancellingStopsTheSearchAndThePushes() {
		givenSelectedCharacter();

		var cancelReplies = new ArrayList<GamePacket>();
		var panelsBeforeCancel = new AtomicInteger();
		var panelsAfterDrain = new AtomicInteger();
		var counting = new AtomicBoolean();
		var cancelSent = new AtomicBoolean();
		var unexpected = new ArrayList<String>();

		searching(30, start(AutomatchGameController.ANY_RULE), (ctx, packet) -> {
			switch (packet.getCommand()) {
				case AutomatchGameController.START_AUTOMATCH_RESULT ->
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
				case AutomatchPackets.SEARCH_PANEL -> {
					if (counting.get()) {
						panelsAfterDrain.incrementAndGet();
					} else if (cancelSent.compareAndSet(false, true)) {
						panelsBeforeCancel.incrementAndGet();
						ctx.writeAndFlush(new GamePacket(AutomatchGameController.CANCEL_AUTOMATCH));
					}
				}
				case AutomatchGameController.CANCEL_AUTOMATCH_RESULT -> {
					cancelReplies.add(packet);
					ctx.executor().schedule(() -> counting.set(true), DRAIN_MS, TimeUnit.MILLISECONDS);
					ctx.executor().schedule((Runnable) ctx::close, DRAIN_MS + WATCH_MS,
						TimeUnit.MILLISECONDS);
				}
				// Collected rather than thrown: an exception on the event loop goes to exceptionCaught
				// and would hang the run rather than fail it.
				default -> unexpected.add(Integer.toHexString(packet.getCommand()));
			}
		});

		assertThat(unexpected).as("nothing else is sent to a searching client").isEmpty();
		assertThat(panelsBeforeCancel.get()).as("the queue must have been pushing to begin with")
			.isEqualTo(1);
		assertThat(cancelReplies).hasSize(1);
		assertThat(cancelReplies.get(0).getPayload().readableBytes()).isEqualTo(RESULT_ONLY_SIZE);
		assertThat(cancelReplies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(panelsAfterDrain.get())
			.as("a cancelled searcher is out of the queue, so nothing more is pushed to it")
			.isZero();
	}

	/**
	 * A refusal must be the end of it. Pushing after a nonzero {@code 0x43e1} is not merely useless —
	 * the client only registers push channel 60 on a zero result, so anything sent afterwards is
	 * parsed into memory and dropped ({@code AUTOMATCH.md} §7 rule 4). A server that queued the
	 * searcher anyway would be holding a seat for a player who was told the feature is closed.
	 */
	@Test
	public void aRefusedStartIsNeverFollowedByAPush() {
		restartWith(CLOSED);
		givenSelectedCharacter();

		var refusals = new ArrayList<GamePacket>();
		var panels = new AtomicInteger();

		searching(30, start(AutomatchGameController.ANY_RULE), (ctx, packet) -> {
			if (packet.getCommand() == AutomatchPackets.SEARCH_PANEL) {
				panels.incrementAndGet();
				return;
			}
			refusals.add(packet);
			if (refusals.size() == 1) {
				ctx.executor().schedule((Runnable) ctx::close, WATCH_MS, TimeUnit.MILLISECONDS);
			}
		});

		assertThat(refusals).hasSize(1);
		assertThat(refusals.get(0).getCommand())
			.isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
		assertThat(refusals.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.AUTOMATCH_NOT_OPEN.result());
		assertThat(panels.get()).as("a refused searcher was never queued").isZero();
	}

	private static GamePacket start(int ruleFilter) {
		var payload = Unpooled.buffer();
		payload.writeByte(ruleFilter);
		return new GamePacket(AutomatchGameController.START_AUTOMATCH, payload);
	}

	/**
	 * The default deployment, and the headline of step 2. Four bytes, not six: the client reads the
	 * band and players-needed only on a zero result, so the error form is short.
	 * <p>
	 * −970 is what makes the client print "Automatching is currently not open" (4929) rather than
	 * the generic "Unable to start". Answering zero here instead would register push channel 60 and
	 * commit us to a match we have no queue to make, which is the twenty-minute stall this replaced.
	 */
	@Test
	public void aClosedWindowRefusesWithFourBytes() {
		restartWith(CLOSED);
		givenSelectedCharacter();

		var reply = exchange(start(AutomatchGameController.ANY_RULE));

		assertThat(reply.getCommand()).isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(RESULT_ONLY_SIZE);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(GameError.AUTOMATCH_NOT_OPEN.result());
		// Unmasked: the client compares against the literal −970, and a masked 0xC0FFEExx would fall
		// through its table to the wrong sentence.
		assertThat(reply.getPayload().getInt(0)).isEqualTo(-970);
	}

	/** An open window accepts, and only then are the two trailing bytes present. */
	@Test
	public void anOpenWindowAcceptsWithSixBytes() {
		givenSelectedCharacter();

		var reply = exchange(start(AutomatchGameController.ANY_RULE));

		assertThat(reply.getCommand()).isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(SUCCESS_SIZE);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		// The band is this searcher's own level window at the moment they started — the client lights
		// [myLevel - band, myLevel + band] around a centre it computes itself, and the same byte is
		// re-sent widened on every 0x43e4. Asserted against the policy rather than a literal so it
		// keeps testing the relationship if the default changes; ALWAYS_OPEN deliberately starts at
		// maximum so level never decides whether these tests match.
		assertThat(reply.getPayload().getUnsignedByte(4))
			.isEqualTo((short) ALWAYS_OPEN.bandAfter(Duration.ZERO));
		// Players-needed was zero while there was no queue to count. There is one now, and this
		// caller is in it — two wanted, nobody else found yet — so the answer is 2, which the client
		// prints through disc string 917. Zero would select the placeholder 48 instead and say
		// nothing at all. Policy, not protocol: the 2 is MIN_PLAYERS on ALWAYS_OPEN.
		//
		// The recipient is COUNTED here: a lone searcher sees the whole requirement, not the
		// requirement minus themselves. That is how the original renders it — reference footage
		// shows a lone searcher on 12 against a 12-player start. [Tier 2: video of the original
		// service, not read from the binary.]
		assertThat(reply.getPayload().getUnsignedByte(5)).isEqualTo((short) 2);
	}

	/**
	 * The whole selectable set. Rows 1–6 of the menu carry rule ids 0–5 and row 0 carries 11, the
	 * "Do not specify rules" sentinel, which is deliberately outside the 0–10 range the label mapper
	 * accepts ({@code 0x93B610}). Every one of them has to be a search the client can start.
	 */
	@Test
	public void everySelectableRuleFilterIsAccepted() {
		givenSelectedCharacter();

		for (var rule : List.of(0, 1, 2, 3, 4, 5, AutomatchGameController.ANY_RULE)) {
			var reply = exchange(start(rule));

			assertThat(reply.getPayload().readableBytes())
				.as("rule filter %s", rule).isEqualTo(SUCCESS_SIZE);
			assertThat(reply.getPayload().getInt(0))
				.as("rule filter %s", rule).isEqualTo(GameError.NONE.result());
		}
	}

	/**
	 * 6 is BOMB, which has no menu row on this build, and 7 is Team Sneaking, which is behind the
	 * feature bit we clear — release-day scope, see {@code CLAUDE.md}. Neither can come from a
	 * selection, so both are refused rather than queued under a rule nobody chose.
	 * <p>
	 * −950 is "Unable to start automatching" (4930). The window is open here, so this also pins the
	 * ordering: an unusable rule filter is refused on its own terms rather than being excused as
	 * "not open".
	 */
	@Test
	public void bombAndTeamSneakingAreRefused() {
		givenSelectedCharacter();

		for (var rule : List.of(6, 7)) {
			var reply = exchange(start(rule));

			assertThat(reply.getCommand())
				.isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
			assertThat(reply.getPayload().readableBytes())
				.as("rule filter %s", rule).isEqualTo(RESULT_ONLY_SIZE);
			assertThat(reply.getPayload().getInt(0))
				.as("rule filter %s", rule).isEqualTo(GameError.AUTOMATCH_CANNOT_START.result());
		}
	}

	/**
	 * The rule filter is the entire request, so an empty {@code 0x43e0} is not something the client
	 * sends — but reading byte 0 of an empty buffer would throw, and a handler that throws answers
	 * nothing. An unanswered {@code 0x43e0} does not even produce the usual {@code FFFFFF60}: it
	 * produces "network error / unable to start" after a 6000-tick wait ({@code 0x93CDD4}).
	 */
	@Test
	public void anEmptyStartPayloadIsRefusedRatherThanThrowing() {
		givenSelectedCharacter();

		var reply = exchange(new GamePacket(AutomatchGameController.START_AUTOMATCH));

		assertThat(reply.getCommand()).isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(RESULT_ONLY_SIZE);
		assertThat(reply.getPayload().getInt(0))
			.isEqualTo(GameError.AUTOMATCH_CANNOT_START.result());
	}

	/**
	 * Cancel, answered with an explicit four-byte zero. The parser at {@code 0xD5BB04} reads a u32
	 * whether or not we sent one, so an empty payload here would have the client read whatever was
	 * left in its receive buffer as the result.
	 * <p>
	 * A successful cancel is also the only route to "Unable to find opponent" (4934) — the client
	 * raises it on a zero result whose own search timer had already expired ({@code 0x93D1D4}).
	 */
	@Test
	public void cancelAnswersAnExplicitFourByteZero() {
		givenSelectedCharacter();

		var reply = exchange(new GamePacket(AutomatchGameController.CANCEL_AUTOMATCH));

		assertThat(reply.getCommand()).isEqualTo(AutomatchGameController.CANCEL_AUTOMATCH_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(RESULT_ONLY_SIZE);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(0);
	}

	/**
	 * No {@code 0x4110} on this connection, so there is no character to queue. Refusing beats
	 * dereferencing a null account, which would answer nothing at all.
	 */
	@Test
	public void aStartWithoutASessionIsRefused() {
		var reply = exchange(start(AutomatchGameController.ANY_RULE), false);

		assertThat(reply.getCommand()).isEqualTo(AutomatchGameController.START_AUTOMATCH_RESULT);
		assertThat(reply.getPayload().readableBytes()).isEqualTo(RESULT_ONLY_SIZE);
		assertThat(reply.getPayload().getInt(0)).isEqualTo(GameError.INVALID_SESSION.result());
	}
}
