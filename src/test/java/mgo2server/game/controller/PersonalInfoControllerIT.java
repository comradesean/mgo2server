package mgo2server.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.buffer.Unpooled;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The wardrobe/personal-info update ({@code 0x4130}) must PERSIST what it acknowledges.
 * Regression test for the 2026-07-23 live find: equipped skills were echoed back (so the menu
 * kept them for the session) but never written, so they vanished on the next connect burst.
 */
public class PersonalInfoControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private long accountId;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	private void givenSelectedCharacter(String name) {
		accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values ('player', 'x', :session, 3)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());
		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", charaId).execute();
			handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
				.bind("chara", charaId).bind("id", accountId).execute();
		});
	}

	private List<GamePacket> loginThen(GamePacket request, int untilCommand) {
		var login = Unpooled.buffer();
		login.writeInt((int) charaId);
		login.writeBytes(SessionField.of(TOKEN));

		var replies = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, login));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (!(msg instanceof GamePacket packet)) {
					return;
				}
				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					ctx.writeAndFlush(request);
					return;
				}
				replies.add(packet);
				if (packet.getCommand() == untilCommand) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	/** 158-byte 0x4130: 19 appearance bytes, 4 skills, pad, 4 levels, 2 pads, 128B comment. */
	@Test
	public void updatePersistsEquippedSkills() {
		givenSelectedCharacter("Snake");

		var payload = Unpooled.buffer();
		payload.writeZero(19);              // appearance, not under test
		payload.writeByte(0).writeByte(0x0a).writeByte(0).writeByte(0); // skills: CQC in slot 2
		payload.writeZero(1);
		payload.writeByte(0).writeByte(3).writeByte(0).writeByte(0);    // levels: tier 3
		payload.writeZero(2);
		payload.writeZero(128);             // comment

		var replies = loginThen(
			new GamePacket(PersonalInfoController.UPDATE_PERSONAL_INFO, payload),
			PersonalInfoController.UPDATE_PERSONAL_INFO_RESULT);

		assertThat(replies).hasSize(1);
		// The echo keeps the in-session menu populated…
		assertThat(replies.get(0).getPayload().getByte(4 + 19 + 1)).isEqualTo((byte) 0x0a);

		// …and the row is what the next connect burst's 0x4122 reads: it must match.
		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select * from chara_equipped_skills where chara_id=:c")
				.bind("c", charaId).mapToMap().one());
		assertThat(((Number) row.get("skill2")).intValue()).isEqualTo(0x0a);
		assertThat(((Number) row.get("level2")).intValue()).isEqualTo(3);
		assertThat(((Number) row.get("skill1")).intValue()).isEqualTo(0);
	}
}
