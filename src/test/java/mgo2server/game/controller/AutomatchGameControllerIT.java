package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.GameClient;
import mgo2server.TestDatabase;
import mgo2server.common.AutomatchPolicy;
import mgo2server.common.crypto.SessionField;
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
	 * Open at every instant a wall clock can actually hold.
	 * <p>
	 * Built directly rather than parsed from a window string so the test does not depend on the
	 * midnight-wrapping rule it would otherwise have to exploit; that rule is pinned in
	 * {@code AutomatchPolicyTest}. The exclusive end excludes only {@code 23:59:59.999999999}
	 * exactly, which no {@code now()} has ever landed on.
	 */
	private static final AutomatchPolicy ALWAYS_OPEN = new AutomatchPolicy(true,
		List.of(new AutomatchPolicy.Window(LocalTime.MIN, LocalTime.MAX)), ZoneId.of("UTC"),
		AutomatchPolicy.Mode.BOTH, 2, Duration.ofSeconds(5), Set.of());

	/** What an operator who has configured nothing gets, and therefore the default deployment. */
	private static final AutomatchPolicy CLOSED = AutomatchPolicy.from(Map.<String, String>of()::get);

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

				replies.add(packet);
				ctx.close();
			}
		});
		client.disconnect(0L, 0L, TimeUnit.SECONDS).join();

		assertThat(replies).hasSize(1);
		return replies.get(0);
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
		// Band and players-needed. Zero is a flat graph and the placeholder string, which is honest
		// while there is no queue to count — not a value read from the binary.
		assertThat(reply.getPayload().getUnsignedByte(4)).isEqualTo((short) 0);
		assertThat(reply.getPayload().getUnsignedByte(5)).isEqualTo((short) 0);
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
