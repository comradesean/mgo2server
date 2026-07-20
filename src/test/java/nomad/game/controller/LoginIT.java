package nomad.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.TestDatabase;
import nomad.common.crypto.SessionField;
import nomad.game.BaseGameClientServerIT;
import nomad.game.GameError;
import nomad.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * The check-session handshake, end to end over a socket.
 * <p>
 * Command 0x3003 is one of the commands whose payload is Blowfish-encrypted, so these also
 * exercise the encrypted path of the codec rather than just the plaintext framing.
 */
public class LoginIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private long createAccount(String username, String session) {
		return TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values (:username, 'x', :session, 3)
					""")
				.bind("username", username)
				.bind("session", SessionField.stored(session))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());
	}

	/** Sends a check-session packet and returns the reply packets. */
	private List<GamePacket> checkSession(long accountId, byte[] sessionField) {
		var payload = Unpooled.buffer(Integer.BYTES + SessionField.FIELD_LENGTH);
		payload.writeInt((int) accountId);
		payload.writeBytes(sessionField);

		var received = new ArrayList<GamePacket>();
		var results = new ArrayList<Integer>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(AccountGameController.CHECK_SESSION, payload));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					received.add(packet);
					results.add(packet.getPayload().getInt(0));
					ctx.close();
				}
			}
		});

		return received;
	}

	private static int resultOf(GamePacket packet) {
		return packet.getPayload().getInt(0);
	}

	@Test
	public void acceptsValidSession() {
		var accountId = createAccount("player", TOKEN);

		var replies = checkSession(accountId, SessionField.of(TOKEN));

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(AccountGameController.CHECK_SESSION_RESULT);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());
	}

	/** Checking in clears any previously selected character. */
	@Test
	public void clearsCurrentCharacterOnCheckIn() {
		var accountId = createAccount("player", TOKEN);

		var charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, 'Snake')")
				.bind("account", accountId)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set current_chara_id=:chara where id=:id")
				.bind("chara", charaId)
				.bind("id", accountId)
				.execute());

		checkSession(accountId, SessionField.of(TOKEN));

		var current = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select current_chara_id from account where id=:id")
				.bind("id", accountId)
				.mapTo(Long.class)
				.findOne());

		assertThat(current).isEmpty();
	}

	@Test
	public void rejectsUnknownSession() {
		createAccount("player", TOKEN);

		var replies = checkSession(1, SessionField.of("zzzzzzzzzzzzzzzz"));

		assertThat(replies).hasSize(1);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.INVALID_SESSION.result());
	}

	/** A valid session presented alongside somebody else's account id must not be honoured. */
	@Test
	public void rejectsSessionBelongingToAnotherAccount() {
		var accountId = createAccount("player", TOKEN);
		var otherId = createAccount("other", "wxyz9876wxyz9876");

		var replies = checkSession(otherId, SessionField.of(TOKEN));

		assertThat(accountId).isNotEqualTo(otherId);
		assertThat(replies).hasSize(1);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.INVALID_SESSION.result());
	}

	@Test
	public void rejectsAccountWithNoSession() {
		var accountId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into account (username, password, slots) values ('nosession', 'x', 3)")
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		var replies = checkSession(accountId, SessionField.of("0000000000000000"));

		assertThat(replies).hasSize(1);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.INVALID_SESSION.result());
	}
}
