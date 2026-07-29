package mgo2server.game.controller;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.common.service.ClanService;
import mgo2server.game.GameError;
import mgo2server.game.packet.GamePacket;
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
		// The client's parser at 0xD3732C (MGO2.elf) consumes a fixed 0x1d7-byte grid with no
		// length check -- a 23-byte header, eight 52-byte slots, then 32 trailing bytes -- so
		// anything shorter makes it read stale buffer bytes rather than fail.
		assertThat(payload.readableBytes()).isEqualTo(0x1d7);
		assertThat(payload.getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(payload.getByte(4)).isEqualTo((byte) 3);   // slots
		assertThat(payload.getByte(5)).isEqualTo((byte) 0);   // character count
	}

	/**
	 * The entitlement trailer: 32 bytes at the end of the grid, with bit 0 of index 3 set.
	 * <p>
	 * [ELF] the parser at {@code 0xD3732C} copies exactly 32 bytes ({@code li r5,32} at
	 * {@code 0xD3774C}). Index 3 bit 0 is the only byte in it with any reader: {@code 0x9B9E30}
	 * computes {@code (byte & 1) << 4} and the availability predicate {@code 0x9B9DF0} refuses any
	 * entry whose gate exceeds that, so clearing it removes 32 gated entries from the client.
	 * <p>
	 * <b>What those 32 entries are is unresolved.</b> "Loadout items" is the label from the first
	 * trace, but the day-one MGO Codec Pack adds exactly 32 preset-message phrases, so one bit may
	 * be the whole shop. {@code MGO2SERVER_ENTITLEMENT_BYTE} flips it in one restart to settle
	 * which screens shrink. This test pins the default; it is not a claim about what is unlocked.
	 */
	@Test
	public void theEntitlementTrailerHasBitZeroSetAtIndexThree() {
		var payload = loginThen(new GamePacket(CharacterGameController.GET_CHARACTER_LIST),
			CharacterGameController.CHARACTER_LIST_RESULT).get(0).getPayload();

		var trailer = 0x1d7 - 32;
		assertThat(payload.getUnsignedByte(trailer + 3) & 1)
			.as("index 3 bit 0 — clearing it removes 32 gated entries from the client")
			.isEqualTo(1);
		assertThat(payload.getUnsignedByte(trailer + 1))
			.as("index 1 carries 0x07, which has no reader at all")
			.isEqualTo((short) 0x07);
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

	// There is deliberately no reserved-name case here. The reserved-name list is operator policy
	// and is empty: it used to hold "SaveMGO", another server's branding inherited from their name
	// checker. Asserting a rejection would mean re-adding an entry purely to satisfy the test.
	// CharacterNames.check still maps the case, so populating the list stays supported.

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

	/**
	 * A clan leader is refused the delete, and told the two ways out.
	 * <p>
	 * {@code -1212} renders as "You are the leader of a clan. Either disband the clan or assign
	 * another character as leader." — both of which the client can already do ({@code 0x4b04},
	 * {@code 0x4b60}).
	 * <p>
	 * The refusal matters beyond the sentence. The delete is a <b>soft</b> delete, so
	 * {@code clan.leader_chara_id}'s {@code on delete set null} never fires; a leader who got
	 * through left the clan pointing at a character nobody could log in as, with no in-game way to
	 * repair it.
	 * <p>
	 * <b>This replaces an auto-succession test written earlier the same day</b>, which asserted that
	 * the longest-standing member was promoted. That behaviour was a policy invention adopted while
	 * {@code -1212} was believed unestablished; it is established, so the game's own answer wins.
	 */
	@Test
	public void refusesToDeleteACharacterThatLeadsAClan() {
		accountId = createAccount();
		var leader = insertCharacter("Snake", true);

		var clans = services.getClanService();
		var clanId = clans.createClan(leader, "Rat Patrol", "").orElseThrow();

		var replies = loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 0),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0)))
			.isEqualTo(GameError.CHARACTER_IS_CLAN_LEADER.result());

		// Still there, still active, still leading — the refusal left nothing half-done.
		var active = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select active from chara where id=:id")
				.bind("id", leader).mapTo(Boolean.class).one());
		assertThat(active).isTrue();
		assertThat(clans.membershipOf(leader).state()).isEqualTo(ClanService.STATE_LEADER);
		assertThat(clans.clanById(clanId)).isPresent();
	}

	/** An ordinary member is not a leader, so nothing blocks their delete. */
	@Test
	public void aPlainClanMemberCanStillBeDeleted() {
		accountId = createAccount();
		var leader = insertCharacter("Snake", true);
		var member = insertCharacter("Otacon", true);

		var clans = services.getClanService();
		var clanId = clans.createClan(leader, "Rat Patrol", "").orElseThrow();
		clans.apply(member, clanId);
		clans.approve(clanId, member);

		// Index 1 — delete clamps to the last character, and this asserts we refuse on LEADERSHIP
		// rather than on clan membership.
		var replies = loginThenNoAccount(withIndex(CharacterGameController.DELETE_CHARACTER, 1),
			CharacterGameController.DELETE_CHARACTER_RESULT);

		assertThat(resultOf(replies.get(0))).isEqualTo(GameError.NONE.result());
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
