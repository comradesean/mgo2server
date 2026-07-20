package nomad.game.controller;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.TestDatabase;
import nomad.common.crypto.SessionField;
import nomad.game.BaseGameClientServerIT;
import nomad.game.GameError;
import nomad.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;

/**
 * The character selection screen, end to end.
 * <p>
 * Every exchange logs in first, because these commands all depend on the connection having an
 * authenticated account.
 */
public class CharacterGameControllerIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	private long accountId;

	private long createAccount() {
		return TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("""
					insert into account (username, password, session, slots)
					values ('player', 'x', :session, 3)
					""")
				.bind("session", SessionField.stored(TOKEN))
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());
	}

	/** Inserts a character directly, optionally backdated so the delete cooldown has elapsed. */
	private long insertCharacter(String name, boolean backdate) {
		var charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", charaId).execute();
			if (backdate) {
				handle.createUpdate("update chara set created_at = :when where id = :id")
					.bind("when", OffsetDateTime.now().minusDays(30))
					.bind("id", charaId)
					.execute();
			}
		});
		return charaId;
	}

	private void setMain(long charaId) {
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set main_chara_id=:chara where id=:id")
				.bind("chara", charaId).bind("id", accountId).execute());
	}

	private Optional<Long> currentCharacter() {
		return TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select current_chara_id from account where id=:id")
				.bind("id", accountId).mapTo(Long.class).findOne());
	}

	/**
	 * Logs in, then sends {@code request}, collecting replies until one carries {@code untilCommand}.
	 */
	private List<GamePacket> loginThen(GamePacket request, int untilCommand) {
		accountId = createAccount();
		return loginThenNoAccount(request, untilCommand);
	}

	private List<GamePacket> loginThenNoAccount(GamePacket request, int untilCommand) {
		var login = Unpooled.buffer();
		login.writeInt((int) accountId);
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

	private static GamePacket withIndex(int command, int index) {
		return new GamePacket(command, Unpooled.wrappedBuffer(new byte[] { (byte) index }));
	}

	private static int resultOf(GamePacket packet) {
		return packet.getPayload().getInt(0);
	}

	private static String nameAt(ByteBuf payload, int offset) {
		var bytes = new byte[16];
		payload.getBytes(offset, bytes);
		var end = 0;
		while (end < bytes.length && bytes[end] != 0) {
			end++;
		}
		return new String(bytes, 0, end, StandardCharsets.ISO_8859_1);
	}

	// ---------- list ----------

	@Test
	public void listsNoCharactersForNewAccount() {
		var replies = loginThen(new GamePacket(CharacterGameController.GET_CHARACTER_LIST),
			CharacterGameController.CHARACTER_LIST_RESULT);

		assertThat(replies).hasSize(1);
		var payload = replies.get(0).getPayload();
		// The client parses a fixed 0x1d7-byte grid with no length check; anything shorter makes
		// it read stale buffer bytes.
		assertThat(payload.readableBytes()).isEqualTo(0x1d7);
		assertThat(payload.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(payload.getByte(4)).isEqualTo((byte) 3);   // slots
		assertThat(payload.getByte(5)).isEqualTo((byte) 0);   // character count
	}

	@Test
	public void listsCharacters() {
		accountId = createAccount();
		insertCharacter("Snake", false);
		insertCharacter("Raiden", false);

		var replies = loginThenNoAccount(new GamePacket(CharacterGameController.GET_CHARACTER_LIST),
			CharacterGameController.CHARACTER_LIST_RESULT);

		var payload = replies.get(0).getPayload();
		assertThat(payload.getByte(5)).isEqualTo((byte) 2);
		// The first entry leads with its name at offset 7.
		assertThat(nameAt(payload, 7)).isEqualTo("Snake");
	}

	/** The main character is floated to the front and marked with an asterisk. */
	@Test
	public void listsMainCharacterFirst() {
		accountId = createAccount();
		insertCharacter("Snake", false);
		var raiden = insertCharacter("Raiden", false);
		setMain(raiden);

		var replies = loginThenNoAccount(new GamePacket(CharacterGameController.GET_CHARACTER_LIST),
			CharacterGameController.CHARACTER_LIST_RESULT);

		assertThat(nameAt(replies.get(0).getPayload(), 7)).isEqualTo("*Raiden");
	}

	// ---------- create ----------

	private static GamePacket createRequest(String name) {
		var payload = Unpooled.buffer(48);
		var bytes = name.getBytes(StandardCharsets.ISO_8859_1);
		for (var i = 0; i < 16; i++) {
			payload.writeByte(i < bytes.length ? bytes[i] : 0);
		}
		// Appearance block; values are asset indices and arbitrary here.
		for (var i = 0; i < 27; i++) {
			payload.writeByte(i + 1);
		}
		return new GamePacket(CharacterGameController.CREATE_CHARACTER, payload);
	}

	@Test
	public void createsCharacter() {
		var replies = loginThen(createRequest("Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);

		assertThat(replies).hasSize(1);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());

		var charaId = replies.get(0).getPayload().getInt(4);
		assertThat(charaId).isPositive();

		var stored = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select name from chara where id=:id")
				.bind("id", charaId).mapTo(String.class).one());
		assertThat(stored).isEqualTo("Snake");
	}

	/** The first character created becomes the account's main, and is selected. */
	@Test
	public void firstCharacterBecomesMainAndCurrent() {
		var replies = loginThen(createRequest("Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);
		var charaId = (long) replies.get(0).getPayload().getInt(4);

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select main_chara_id, current_chara_id from account where id=:id")
				.bind("id", accountId)
				.mapToMap()
				.one());

		assertThat(row.get("main_chara_id")).isEqualTo(charaId);
		assertThat(row.get("current_chara_id")).isEqualTo(charaId);
	}

	@Test
	public void storesAppearance() {
		var replies = loginThen(createRequest("Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);
		var charaId = replies.get(0).getPayload().getInt(4);

		var gender = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select gender from chara_appearance where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());

		assertThat(gender).isEqualTo(1);
	}

	@Test
	public void rejectsReservedPrefix() {
		var replies = loginThen(createRequest("GM_Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.CHARACTER_NAME_PREFIX.result());
	}

	@Test
	public void rejectsReservedName() {
		var replies = loginThen(createRequest("SaveMGO"),
			CharacterGameController.CREATE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.CHARACTER_NAME_RESERVED.result());
	}

	@Test
	public void rejectsDuplicateName() {
		accountId = createAccount();
		insertCharacter("Snake", false);

		var replies = loginThenNoAccount(createRequest("Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.CHARACTER_NAME_TAKEN.result());
	}

	// ---------- select ----------

	@Test
	public void selectsCharacterByIndex() {
		accountId = createAccount();
		insertCharacter("Snake", false);
		var raiden = insertCharacter("Raiden", false);

		var replies = loginThenNoAccount(
			withIndex(CharacterGameController.SELECT_CHARACTER, 1),
			CharacterGameController.SELECT_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());
		assertThat(currentCharacter()).contains(raiden);
	}

	/** An index the client should not have sent falls back to the first character. */
	@Test
	public void selectingOutOfRangeIndexFallsBackToFirst() {
		accountId = createAccount();
		var snake = insertCharacter("Snake", false);
		insertCharacter("Raiden", false);

		loginThenNoAccount(withIndex(CharacterGameController.SELECT_CHARACTER, 99),
			CharacterGameController.SELECT_CHARACTER_RESULT);

		assertThat(currentCharacter()).contains(snake);
	}

	@Test
	public void selectingWithNoCharactersReportsMissing() {
		var replies = loginThen(withIndex(CharacterGameController.SELECT_CHARACTER, 0),
			CharacterGameController.SELECT_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0)))
			.isEqualTo(GameError.CHARACTER_DOES_NOT_EXIST.result());
	}

	// ---------- delete ----------

	@Test
	public void deletesCharacterPastCooldown() {
		accountId = createAccount();
		var snake = insertCharacter("Snake", true);

		var replies = loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select active, name, old_name from chara where id=:id")
				.bind("id", snake).mapToMap().one());

		assertThat(row.get("active")).isEqualTo(false);
		assertThat(row.get("old_name")).isEqualTo("Snake");
		assertThat(row.get("name")).isEqualTo(":#" + snake);
	}

	/** Freshly created characters are protected by the cooldown. */
	@Test
	public void refusesToDeleteWithinCooldown() {
		accountId = createAccount();
		insertCharacter("Snake", false);

		var replies = loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0)))
			.isEqualTo(GameError.CHARACTER_CANNOT_DELETE_YET.result());
	}

	/** Deleting frees the name for reuse, which is the point of the rename. */
	@Test
	public void deletedNameCanBeReused() {
		accountId = createAccount();
		insertCharacter("Snake", true);

		loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		var replies = loginThenNoAccount(createRequest("Snake"),
			CharacterGameController.CREATE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());
	}

	@Test
	public void deletingClearsMainAndCurrentReferences() {
		accountId = createAccount();
		var snake = insertCharacter("Snake", true);
		setMain(snake);
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set current_chara_id=:chara where id=:id")
				.bind("chara", snake).bind("id", accountId).execute());

		loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		var row = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select main_chara_id, current_chara_id from account where id=:id")
				.bind("id", accountId).mapToMap().one());

		assertThat(row.get("main_chara_id")).isNull();
		assertThat(row.get("current_chara_id")).isNull();
	}

	/** A deleted character no longer appears in the list. */
	@Test
	public void deletedCharacterIsHiddenFromList() {
		accountId = createAccount();
		insertCharacter("Snake", true);
		insertCharacter("Raiden", true);

		loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		var replies = loginThenNoAccount(new GamePacket(CharacterGameController.GET_CHARACTER_LIST),
			CharacterGameController.CHARACTER_LIST_RESULT);

		assertThat(replies.get(0).getPayload().getByte(5)).isEqualTo((byte) 1);
	}

	// ---------- authentication ----------

	/** None of these commands may be served to a connection that has not checked in. */
	@Test
	public void refusesCommandsBeforeLogin() {
		var replies = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CharacterGameController.GET_CHARACTER_LIST));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
					ctx.close();
				}
			}
		});

		assertThat(replies).hasSize(1);
		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.INVALID_SESSION.result());
	}
}
