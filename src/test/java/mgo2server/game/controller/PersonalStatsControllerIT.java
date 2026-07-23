package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The personal-stats burst and the outfit commit.
 * <p>
 * Sizes assert what the client's parsers consume, traced from the binary: {@code 0x4103} is a
 * 648-byte grid opening with a status u32, {@code 0x4105} 584, {@code 0x4107} 588 (the packet
 * that releases the client's wait state, so it must arrive last), and {@code 0x4133} is
 * {@code 4 + 5·count + 30} bytes — 34 for the empty readback we send.
 */
public class PersonalStatsControllerIT extends BaseGameClientServerIT {
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
					insert into account (username, password, session, slots, main_exp, alt_exp)
					values ('player', 'x', :session, 3, 1234, 99)
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
					assertThat(packet.getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
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

	private static GamePacket statsRequest(long charaId) {
		var payload = Unpooled.buffer();
		payload.writeInt((int) charaId);
		return new GamePacket(PersonalStatsController.GET_PERSONAL_STATS, payload);
	}

	/**
	 * The burst is four packets: info, the cumulative matrix (page 0), the weekly matrix
	 * (page 1), and the terminal tail — pages capture-proven as the cumulative/weekly toggle.
	 */
	@Test
	public void answersWithTheFourPacketBurst() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(statsRequest(charaId), PersonalStatsController.PERSONAL_STATS_TAIL);

		assertThat(replies).hasSize(4);

		var info = replies.get(0);
		assertThat(info.getCommand()).isEqualTo(PersonalStatsController.PERSONAL_STATS_INFO);
		assertThat(info.getPayload().readableBytes()).isEqualTo(0x288);
		assertThat(info.getPayload().getInt(0)).isEqualTo(0); // status
		assertThat(info.getPayload().getInt(4)).isEqualTo((int) charaId);
		var name = new byte[5];
		info.getPayload().getBytes(8, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1)).isEqualTo("Snake");
		// Main character, so the account's main experience.
		assertThat(info.getPayload().getInt(0x20)).isEqualTo(1234);

		for (var page = 0; page <= 1; page++) {
			var matrix = replies.get(1 + page);
			assertThat(matrix.getCommand())
				.isEqualTo(PersonalStatsController.PERSONAL_STATS_MATRIX);
			assertThat(matrix.getPayload().readableBytes()).isEqualTo(0x248);
			assertThat(matrix.getPayload().getInt(0)).isEqualTo(0); // status
			// The page selector: anything above 1 makes the client discard the matrix.
			assertThat(matrix.getPayload().getInt(4)).isEqualTo(page);
		}

		assertThat(replies.get(3).getCommand())
			.isEqualTo(PersonalStatsController.PERSONAL_STATS_TAIL);
		assertThat(replies.get(3).getPayload().readableBytes()).isEqualTo(0x24C);
	}

	/** A bad id gets 0x4103 alone with a nonzero status; the client error-completes on it. */
	@Test
	public void unknownCharacterGetsAnErrorStatus() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(statsRequest(9999), PersonalStatsController.PERSONAL_STATS_INFO);

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getPayload().readableBytes()).isEqualTo(4);
		assertThat(replies.get(0).getPayload().getInt(0)).isNotEqualTo(0);
	}

	@Test
	public void outfitCommitGetsTheEmptyReadback() {
		givenSelectedCharacter("Snake");

		var replies = loginThen(new GamePacket(PersonalInfoController.COMMIT_OUTFIT),
			PersonalInfoController.COMMIT_OUTFIT_RESULT);

		assertThat(replies).hasSize(1);
		var payload = replies.get(0).getPayload();
		assertThat(payload.readableBytes()).isEqualTo(34);
		assertThat(payload.getInt(0)).isEqualTo(0); // entry count, not a status
	}
}
