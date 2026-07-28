package mgo2server.game.controller;

import mgo2server.common.AutomatchPolicy;
import mgo2server.common.model.Account;
import mgo2server.game.Automatch;
import mgo2server.game.GameControllerContext;
import mgo2server.game.GameError;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.time.ZonedDateTime;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/**
 * Automatching: starting and cancelling a search.
 *
 * <p>Moved out of {@code HubGameController} on 2026-07-28, and the move was forced rather than
 * tidy — {@code GameServerHandler} throws at construction if two controllers claim the same command,
 * so these two ids can live in exactly one place. The full wire spec is
 * {@code dev/docs/AUTOMATCH.md}; this class is its front door.
 *
 * <h2>What the previous implementation got wrong</h2>
 * Both commands were answered, and both were misunderstood:
 * <ul>
 * <li>{@code 0x43e0} was documented as a "status fetch sent on entry to the automatching lobby". It
 * is <b>start automatching</b>, sent on <b>confirm</b> from state 4 of the screen's state machine
 * ({@code 0x93CD58}); the constructor at {@code 0x93B4D0} makes no network call at all. The client's
 * own error table settles it — a timeout on this slot prints "Unable to <b>start</b> automatching"
 * ({@code 0x93CDD4}) where {@code 0x43e2}'s prints "Unable to <b>cancel</b>" ({@code 0x93D178}).</li>
 * <li>Its u8 argument was "unidentified, observed 11". It is a <b>rule filter</b>, and 11 is the
 * "Do not specify rules" sentinel — deliberately outside the 0–10 range the label mapper accepts
 * ({@code 0x93B610}).</li>
 * <li>The two bytes of the reply were "unidentified and zero is the only defensible placeholder".
 * They are a <b>level band half-width</b> and <b>players needed</b>, the latter printed through disc
 * string 917.</li>
 * </ul>
 *
 * <h2>Answering result 0 is a commitment</h2>
 * A zero result is not an acknowledgement. It sets the client's "loaded" flag and <b>registers push
 * channel 60</b> ({@code 0x93CF04}), after which the client sends nothing whatsoever and waits for
 * us — for about twenty minutes, then gives up. So we say zero only when a matchmaker is actually
 * going to look at this player. Otherwise we say {@link GameError#AUTOMATCH_NOT_OPEN} and the client
 * prints the sentence Konami wrote for it.
 */
public class AutomatchGameController implements IGameController {
	private static final Logger logger = LogManager.getLogger();

	/** Start automatching. One u8: the rule filter. */
	public static final int START_AUTOMATCH = 0x43e0;

	/** Reply to {@code 0x43e0}. */
	public static final int START_AUTOMATCH_RESULT = 0x43e1;

	/** Cancel the search. Empty payload. */
	public static final int CANCEL_AUTOMATCH = 0x43e2;

	/** Reply to {@code 0x43e2}. */
	public static final int CANCEL_AUTOMATCH_RESULT = 0x43e3;

	/** "Do not specify rules" — disc string 925, and the default selection. */
	public static final int ANY_RULE = 11;

	/**
	 * The rule filter values the client can send.
	 * <p>
	 * Rows 1–6 of the menu carry rule ids 0–5 and row 0 carries {@code 11}
	 * ({@code 0x93B60C}–{@code 0x93B828}). Rule 6 (BOMB) has no row, and rule 7 (Team Sneaking) is
	 * behind the feature bit we clear — so neither is expected, and both are refused rather than
	 * queued under a rule nobody selected. The disc corroborates the set independently:
	 * {@code lobby/scenerio.gcl} carries {@code -rule_bit 191}, bits 0–5 and 7.
	 */
	private static final Set<Integer> RULE_FILTERS = Set.of(0, 1, 2, 3, 4, 5, ANY_RULE);

	/**
	 * Bytes in a successful {@code 0x43e1}: the result, then band and players-needed.
	 * <p>
	 * A <b>failure is four bytes, not six</b>. The parser reads the two trailing u8s only when the
	 * result is zero ({@code 0xD5BF98}), so sending them anyway is not harmful but is not the shape
	 * the client expects, and the short form is what every other error path here uses.
	 */
	private static final int SUCCESS_SIZE = 4 + 1 + 1;

	private final AutomatchPolicy policy;

	private final Automatch automatch;

	public AutomatchGameController(AutomatchPolicy policy, Automatch automatch) {
		this.policy = policy;
		this.automatch = automatch;
	}

	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(START_AUTOMATCH, this::startAutomatch);
		handlers.put(CANCEL_AUTOMATCH, this::cancelAutomatch);
	}

	/**
	 * Starts a search, or refuses it with a sentence the player can act on.
	 * <p>
	 * There is no queue yet, so every accepted search will end in the client's own "Unable to find
	 * opponent" once it cancels. That is still an improvement on what this replaced: the old handler
	 * always answered zero and then never spoke again, which the player experienced as a
	 * twenty-minute stopwatch and no explanation.
	 */
	private void startAutomatch(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(START_AUTOMATCH_RESULT, GameError.INVALID_SESSION);
			return;
		}

		var payload = ctx.packet().getPayload();
		if (payload.readableBytes() < 1) {
			// The rule filter is the whole request; without it there is nothing to search for.
			logger.warn("0x43e0 with no rule filter from chara {}; refused.",
				account.getCurrentCharaId());
			ctx.write(START_AUTOMATCH_RESULT, GameError.AUTOMATCH_CANNOT_START);
			return;
		}

		var rule = payload.getUnsignedByte(0);
		if (!RULE_FILTERS.contains((int) rule)) {
			// Not a value any menu row can produce. Queueing it would search for a rule the player
			// did not choose, so refuse and say which sentence they will see.
			logger.warn("0x43e0 rule filter {} from chara {} is outside the selectable set {}; "
				+ "refused.", rule, account.getCurrentCharaId(), RULE_FILTERS);
			ctx.write(START_AUTOMATCH_RESULT, GameError.AUTOMATCH_CANNOT_START);
			return;
		}

		if (!policy.openAt(ZonedDateTime.now())) {
			logger.info("Automatching is closed; refused a search from chara {} (windows {}, zone {}"
				+ ", enabled {}).", account.getCurrentCharaId(), policy.windows(), policy.zone(),
				policy.enabled());
			ctx.write(START_AUTOMATCH_RESULT, GameError.AUTOMATCH_NOT_OPEN);
			return;
		}

		// The channel is captured here on purpose rather than resolved from ChannelRegistry later:
		// answering result 0 below is the very thing that registers the client's push channel 60, so
		// taking the channel at this moment makes our record and its record the same event.
		automatch.enqueue(account.getCurrentCharaId(), rule, experience(account), ctx.channel());

		var buffer = ctx.buffer(SUCCESS_SIZE);
		buffer.writeInt(GameError.NONE.result())
			// The level band. Zero until grouping exists to define one — the client lights only the
			// player's own column, which is honest about a search that is not yet spanning levels.
			.writeByte(0)
			.writeByte(automatch.playersNeeded());
		ctx.write(new GamePacket(START_AUTOMATCH_RESULT, buffer));
	}

	/**
	 * The experience this character's level is derived from.
	 * <p>
	 * The main/alt split is the same one the stats screen uses: a character that is its account's
	 * main spends and shows the main pool, everyone else the alt pool. The client computes its own
	 * level from the u32 we send at {@code 0x4101 + 0x1C}, which is this number, so grouping
	 * searchers on it groups them the way the client will draw them.
	 */
	private static int experience(Account account) {
		var charaId = account.getCurrentCharaId();
		return charaId != null && charaId.equals(account.getMainCharaId())
			? account.getMainExp() : account.getAltExp();
	}

	/**
	 * Cancels the search.
	 * <p>
	 * Answering this is also the only way the player ever sees <em>"Unable to find opponent"</em>:
	 * the client raises 4934 on a <b>successful</b> cancel whose own search timer had already expired
	 * ({@code 0x93D1D4}). A silent cancel would rob them of the one message that explains the wait.
	 * <p>
	 * Explicit four-byte zero rather than an empty payload — an empty one leaves the client reading
	 * four bytes of stale receive buffer as its result, the trap {@code 0x4399} fell into.
	 */
	private void cancelAutomatch(GameControllerContext ctx) {
		var account = ctx.connection().account();
		if (account == null || account.getCurrentCharaId() == null) {
			ctx.write(CANCEL_AUTOMATCH_RESULT, GameError.INVALID_SESSION);
			return;
		}
		var outcome = automatch.cancel(account.getCurrentCharaId());
		ctx.write(CANCEL_AUTOMATCH_RESULT, outcome == Automatch.CancelOutcome.TOO_LATE
			? GameError.AUTOMATCH_CANCEL_TOO_LATE : GameError.NONE);
	}
}
