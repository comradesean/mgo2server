package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.common.service.CharacterService;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.*;

/**
 * A beginners-only lobby refuses a character above level 3, at the session check.
 * <p>
 * Enforced server-side because the client demonstrably does not enforce it. The whole client
 * mechanism exists — {@code 0x884300} matches the gate list's restriction bit and its callers raise
 * dialog 2355 — and on 2026-07-28 a character joined a marked lobby with the bit confirmed on the
 * wire and no refusal at all. So the refusal is made where it cannot be ignored.
 * <p>
 * {@code -404} is the client's own code for this: the lobby-connect state machine maps it to dialog
 * 2355, <em>"You cannot login to this lobby."</em> ({@code 0x9471E0}).
 */
public class BeginnerLobbyIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private long givenCharacterWithExperience(int experience, boolean isMain) {
		var accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots, main_exp, alt_exp)
					values ('player', 'x', :session, 3, :main, :alt)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.bind("main", isMain ? experience : 0)
				.bind("alt", isMain ? 0 : experience)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		var charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:a, 'Snake')")
				.bind("a", accountId)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("update account set current_chara_id = :c, main_chara_id = :m where id = :a")
			.bind("c", charaId)
			.bind("m", isMain ? charaId : null)
			.bind("a", accountId)
			.execute());

		return charaId;
	}

	private void givenBeginnersOnlyLobby(boolean beginnersOnly) {
		TestDatabase.get().jdbi().useHandle(handle -> handle
			.createUpdate("update lobby set beginners_only = :b where id = :id")
			.bind("b", beginnersOnly)
			.bind("id", lobbyId)
			.execute());
	}

	/** Sends the session check for {@code charaId} and returns the result word of 0x3004. */
	private int checkSession(long charaId) {
		var payload = Unpooled.buffer();
		payload.writeInt((int) charaId);
		payload.writeBytes(SessionField.of(TOKEN));

		var result = new AtomicReference<Integer>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, payload));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet
						&& packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					result.set(packet.getPayload().getInt(0));
					ctx.close();
				}
			}
		});

		assertThat(result.get()).as("0x3004 result").isNotNull();
		return result.get();
	}

	/** 500 is the measured level-4 threshold: 499 displays as level 3, 500 as level 4. */
	@Test
	public void refusesACharacterAboveLevelThree() {
		givenBeginnersOnlyLobby(true);
		var charaId = givenCharacterWithExperience(CharacterService.LEVEL_4_EXPERIENCE, true);

		assertThat(checkSession(charaId)).isEqualTo(GameError.LOBBY_ENTRY_REFUSED.result());
	}

	/** One experience point below the threshold is still level 3, and still welcome. */
	@Test
	public void admitsACharacterAtLevelThree() {
		givenBeginnersOnlyLobby(true);
		var charaId = givenCharacterWithExperience(CharacterService.LEVEL_4_EXPERIENCE - 1, true);

		assertThat(checkSession(charaId)).isEqualTo(GameError.NONE.result());
	}

	/** An unmarked lobby takes anyone, however experienced. */
	@Test
	public void anOrdinaryLobbyAdmitsAnyone() {
		givenBeginnersOnlyLobby(false);
		var charaId = givenCharacterWithExperience(49250, true);

		assertThat(checkSession(charaId)).isEqualTo(GameError.NONE.result());
	}

	/**
	 * Experience splits main from alt, and the refusal must read the same pool every other screen
	 * does — otherwise a veteran's alt walks in on the main's total, or the reverse.
	 */
	@Test
	public void readsTheAltPoolForANonMainCharacter() {
		givenBeginnersOnlyLobby(true);
		var charaId = givenCharacterWithExperience(CharacterService.LEVEL_4_EXPERIENCE, false);

		assertThat(checkSession(charaId)).isEqualTo(GameError.LOBBY_ENTRY_REFUSED.result());
	}
}
