package mgo2server.game.controller;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.TestDatabase;
import mgo2server.common.crypto.SessionField;
import mgo2server.common.model.ChatMacro;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.GameplaySettingsWriter;
import mgo2server.common.model.CharaSkill;
import mgo2server.game.LoadoutWriter;
import mgo2server.game.PersonalInfoWriter;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Entering a game lobby: check in with a character id, then ask for the connect burst.
 */
public class GameLobbyConnectIT extends BaseGameClientServerIT {
	private static final String TOKEN = "abcd1234abcd1234";

	/**
	 * Check-session reply plus the burst. The burst is nine packets from eight responses: chat
	 * macros are sent as one packet per type.
	 */
	private static final int BURST_REPLIES = 10;

	private long accountId;

	private long charaId;

	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GAME;
	}

	/** An account that has already selected a character, as it would be on arriving here. */
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

		// Identity sequences restart between tests, so without this the account and character ids
		// both come out as 1 and a test that confuses the two would pass by coincidence.
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, 'Filler')")
				.bind("account", accountId).execute());

		charaId = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createUpdate("insert into chara (account_id, name) values (:account, :name)")
				.bind("account", accountId)
				.bind("name", name)
				.executeAndReturnGeneratedKeys("id")
				.mapTo(Long.class)
				.one());

		grantStartingSkills(charaId);
		grantStartingGear(charaId);

		assertThat(charaId).isNotEqualTo(accountId);

		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("insert into chara_appearance (chara_id) values (:id)")
				.bind("id", charaId).execute();
			handle.createUpdate("""
					update account set current_chara_id = :chara, main_chara_id = :chara where id = :id
					""")
				.bind("chara", charaId).bind("id", accountId).execute();
		});
	}

	/** Checks in with {@code claimedId}, then sends 0x4100 and collects the burst. */
	private List<GamePacket> connect(long claimedId, int expectedPackets) {
		var login = Unpooled.buffer();
		login.writeInt((int) claimedId);
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
				replies.add(packet);

				if (packet.getCommand() == AccountGameController.CHECK_SESSION_RESULT) {
					if (packet.getPayload().getInt(0) != GameError.NONE.result()) {
						ctx.close();
						return;
					}
					ctx.writeAndFlush(new GamePacket(CharacterConnectController.CONNECT));
					return;
				}

				if (replies.size() >= expectedPackets) {
					ctx.close();
				}
			}
		});

		return replies;
	}

	/** A game lobby identifies the player by character, not by account. */
	@Test
	public void checksInWithCharacterId() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, BURST_REPLIES);

		assertThat(replies.get(0).getCommand())
			.isEqualTo(AccountGameController.CHECK_SESSION_RESULT);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
	}

	/**
	 * Claiming a character this account does not own must be refused.
	 * <p>
	 * This used to send the account id, on the reasoning that an account lobby expects one and a
	 * game lobby must not. That worked by accident: both identity sequences start at 1 in a fresh
	 * test database, so the "account id" was frequently a character id this account really owned,
	 * and the test only passed because check-in compared against the selected character rather than
	 * ownership. It now claims an id that exists nowhere.
	 */
	@Test
	public void rejectsCharacterTheAccountDoesNotOwn() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId + 9999, 1);

		assertThat(replies).hasSize(1);
		// A GAME lobby says "You must login again to connect to the lobby." rather than the masked
		// generic — the instruction the player can actually act on. Gated on lobby type: the same
		// handler serves account lobbies, where -240 reads as "Unable to connect to server." and is
		// worse than that chain's default, so those keep INVALID_SESSION.
		assertThat(replies.get(0).getPayload().getInt(0))
			.isEqualTo(GameError.LOBBY_LOGIN_AGAIN.result());
	}

	/**
	 * A stale or absent selection is not a reason to refuse: the client names the character it is
	 * entering with, and check-in adopts it.
	 * <p>
	 * The old rule demanded that the claim equal {@code current_chara_id}, which broke a real login
	 * — creating a character points the selection at the new one, so entering the lobby as any other
	 * character failed with "Unable to connect to lobby.(0925:C0FFEE02)".
	 */
	@Test
	public void adoptsTheClaimedCharacterWhenTheSelectionIsStale() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set current_chara_id = null where id = :id")
				.bind("id", accountId).execute());

		var replies = connect(charaId, BURST_REPLIES);

		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());

		var current = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select current_chara_id from account where id=:id")
				.bind("id", accountId).mapTo(Long.class).findOne());
		assertThat(current).contains(charaId);
	}

	/** Check-in must not clear the selection here, unlike in an account lobby. */
	@Test
	public void keepsSelectedCharacter() {
		givenSelectedCharacter("Snake");

		connect(charaId, BURST_REPLIES);

		var current = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select current_chara_id from account where id=:id")
				.bind("id", accountId).mapTo(Long.class).findOne());

		assertThat(current).contains(charaId);
	}

	@Test
	public void connectBurstSendsAllEightResponsesInOrder() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, BURST_REPLIES);

		assertThat(replies).hasSize(10);
		assertThat(replies.get(1).getCommand()).isEqualTo(CharacterConnectController.CHARACTER_INFO);
		assertThat(replies.get(2).getCommand()).isEqualTo(CharacterConnectController.GAMEPLAY_SETTINGS);
		assertThat(replies.get(3).getCommand()).isEqualTo(CharacterConnectController.CHAT_MACROS);
		assertThat(replies.get(4).getCommand()).isEqualTo(CharacterConnectController.CHAT_MACROS);
		assertThat(replies.get(5).getCommand()).isEqualTo(CharacterConnectController.PERSONAL_INFO);
		assertThat(replies.get(6).getCommand()).isEqualTo(CharacterConnectController.GEAR);
		assertThat(replies.get(7).getCommand()).isEqualTo(CharacterConnectController.SKILLS);
		assertThat(replies.get(8).getCommand()).isEqualTo(CharacterConnectController.SKILL_SETS);
		assertThat(replies.get(9).getCommand()).isEqualTo(CharacterConnectController.GEAR_SETS);
	}

	@Test
	public void gameplaySettingsPayloadIsFullSize() {
		givenSelectedCharacter("Snake");

		var settings = connect(charaId, BURST_REPLIES).get(2).getPayload();

		assertThat(settings.readableBytes()).isEqualTo(GameplaySettingsWriter.PAYLOAD_SIZE);
	}

	/** Settings materialise with defaults, so a fresh character gets a usable options screen. */
	@Test
	public void gameplaySettingsDefaultForANewCharacter() {
		givenSelectedCharacter("Snake");

		var settings = connect(charaId, BURST_REPLIES).get(2).getPayload();

		// View speeds default to 5 and go out one lower.
		assertThat(settings.getByte(1) >>> 4 & 0b1111).isEqualTo(4);
		// Music volume defaults to 10 and goes out one higher.
		assertThat(settings.getByte(20) >>> 4 & 0b1111).isEqualTo(11);

		var rows = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_settings where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());
		assertThat(rows).isEqualTo(1);
	}

	@Test
	public void gameplaySettingsReflectStoredValues() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("""
					insert into chara_settings (chara_id, normal_view_speed, bgm_volume, radar_lock_north)
					values (:id, 1, 0, true)
					""")
				.bind("id", charaId).execute());

		var settings = connect(charaId, BURST_REPLIES).get(2).getPayload();

		assertThat(settings.getByte(1) >>> 4 & 0b1111).isZero();      // speed 1 -> 0
		assertThat(settings.getByte(20) >>> 4 & 0b1111).isEqualTo(1); // volume 0 -> 1
		assertThat(settings.getByte(21) & 0b1).isEqualTo(1);          // radar lock north
	}

	@Test
	public void personalInfoPayloadIsFullSize() {
		givenSelectedCharacter("Snake");

		var info = connect(charaId, BURST_REPLIES).get(5).getPayload();

		assertThat(info.readableBytes()).isEqualTo(PersonalInfoWriter.PAYLOAD_SIZE);
		// No clan.
		assertThat(info.getInt(0)).isZero();
	}

	/**
	 * Wire {@code 0xef} of {@code 0x4122} carries the worn title — the animal-rank badge the in-game
	 * scorecard draws — and it has to arrive in the <b>connect burst</b>, not only when the player
	 * opens Personal Stats.
	 * <p>
	 * That is the whole bug this pins. The byte used to carry {@code chara.rank}, which is dead
	 * (always 0), so the badge never appeared in a session while the stats screen showed the title
	 * correctly: {@code 0x4103} fills a scratch block, this fills the local character record at
	 * charBlock+{@code 0x1EA5}, and only the local one is published to peers as record slot+1 key
	 * 358. Asserting a title the character actually holds is what makes this test able to catch a
	 * regression rather than just observe a zero.
	 */
	@Test
	public void personalInfoCarriesCommentAndWornTitle() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle -> {
			handle.createUpdate("update chara set comment = 'Hello' where id = :id")
				.bind("id", charaId).execute();
			// Bit 0 is the lowest-ranked title in awards.json, so it is the one worn, and the wire
			// value is 1-based — bit 0 goes out as 1.
			handle.createUpdate("insert into chara_title (chara_id, title_bit) values (:id, 0)")
				.bind("id", charaId).execute();
		});

		var info = connect(charaId, BURST_REPLIES).get(5).getPayload();

		var comment = new byte[128];
		info.getBytes(111, comment);
		assertThat(new String(comment, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Hello");
		assertThat(info.getByte(239)).as("wire 0xef, the worn title, 1-based").isEqualTo((byte) 1);
	}

	@Test
	public void characterInfoCarriesIdNameAndExperience() {
		givenSelectedCharacter("Snake");

		var info = connect(charaId, BURST_REPLIES).get(1).getPayload();

		assertThat(info.getInt(0)).isEqualTo((int) charaId);

		var name = new byte[16];
		info.getBytes(4, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Snake");

		// This character is the account's main, so it draws on the main experience pool.
		assertThat(info.getInt(28)).isEqualTo(1234);
		// The client's parser consumes exactly this much: header, 32+32 ids, 25-byte tail.
		assertThat(info.readableBytes()).isEqualTo(0x142);
	}

	/** An alt draws on the other pool. */
	@Test
	public void alternateCharacterUsesAltExperience() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("update account set main_chara_id = null where id = :id")
				.bind("id", accountId).execute());

		var info = connect(charaId, BURST_REPLIES).get(1).getPayload();

		assertThat(info.getInt(28)).isEqualTo(99);
	}

	/** Both macro packets are full-width, with the type byte leading each. */
	/** Both macro sets arrive in one packet each, type byte leading. */
	@Test
	public void chatMacrosAreSentAsTwoFullSets() {
		givenSelectedCharacter("Snake");

		var macros = connect(charaId, BURST_REPLIES).stream()
			.filter(p -> p.getCommand() == CharacterConnectController.CHAT_MACROS)
			.toList();
		var expectedSize = 1 + ChatMacro.PER_TYPE * ChatMacro.TEXT_LENGTH;

		assertThat(macros).hasSize(2);
		assertThat(macros.get(0).getPayload().readableBytes()).isEqualTo(expectedSize);
		assertThat(macros.get(1).getPayload().readableBytes()).isEqualTo(expectedSize);
		assertThat(macros.get(0).getPayload().getByte(0)).isEqualTo((byte) 0);
		assertThat(macros.get(1).getPayload().getByte(0)).isEqualTo((byte) 1);
	}

	@Test
	public void chatMacrosReturnStoredText() {
		givenSelectedCharacter("Snake");
		TestDatabase.get().jdbi().useHandle(handle ->
			handle.createUpdate("""
					insert into chara_chat_macro (chara_id, type, index, text)
					values (:id, 0, 1, 'Enemy spotted')
					""")
				.bind("id", charaId).execute());

		var macros = connect(charaId, BURST_REPLIES).stream()
			.filter(p -> p.getCommand() == CharacterConnectController.CHAT_MACROS)
			.toList().get(0).getPayload();

		var entry = new byte[ChatMacro.TEXT_LENGTH];
		macros.getBytes(1 + ChatMacro.TEXT_LENGTH, entry);
		assertThat(new String(entry, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("Enemy spotted");
	}

	/**
	 * The connect burst is only served to an authenticated connection — and an unauthenticated one
	 * is answered with <b>nothing</b>.
	 * <p>
	 * This used to assert a 4-byte {@code 0x4101} carrying {@code INVALID_SESSION}. That reply was
	 * worse than silence: {@code 0x4101} has no result field, its first field is the character id,
	 * and no read primitive consults the payload length — so the masked code landed in the id and
	 * the client entered the lobby as character {@code 0xC0FFEE02}, carrying it in every subsequent
	 * packet. A zero id is no better.
	 * <p>
	 * There is no way to refuse this command; the refusal belongs to {@code 0x3003}/{@code 0x3004},
	 * which discriminates properly and already rejects all of these conditions. Reaching here at all
	 * means a race, so the server logs and drops, and the client times out with
	 * {@code 1037:FFFFFF60}.
	 */
	@Test
	public void refusesConnectBurstBeforeCheckInBySayingNothing() {
		givenSelectedCharacter("Snake");

		var replies = new ArrayList<GamePacket>();
		client.run(3, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CharacterConnectController.CONNECT));
				// Nothing will close this channel for us, because the whole point is that no reply
				// arrives. Give the server long enough to have sent one, then close.
				ctx.executor().schedule((Runnable) ctx::close, 1, java.util.concurrent.TimeUnit.SECONDS);
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
				}
			}
		});

		assertThat(replies)
			.as("a malformed 0x4101 would be parsed as a character record, not as an error")
			.isEmpty();
	}

	/** A game lobby must not answer commands that belong to other lobby types. */
	@Test
	public void doesNotServeAccountLobbyCommands() {
		givenSelectedCharacter("Snake");

		var replies = new ArrayList<GamePacket>();
		client.run(3, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CharacterGameController.GET_CHARACTER_LIST));
				ctx.executor().schedule((Runnable) ctx::close, 1, java.util.concurrent.TimeUnit.SECONDS);
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
				}
			}
		});

		assertThat(replies).isEmpty();
	}

	/** The three saved loadouts of each kind materialise on first connect. */
	@Test
	public void loadoutSetsAreCreatedOnFirstConnect() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, BURST_REPLIES);

		assertThat(replies.get(8).getPayload().readableBytes())
			.isEqualTo(3 * LoadoutWriter.SKILL_SET_SIZE);
		assertThat(replies.get(9).getPayload().readableBytes())
			.isEqualTo(3 * LoadoutWriter.GEAR_SET_SIZE);

		var skillSets = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_skill_set where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());
		var gearSets = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_gear_set where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());

		assertThat(skillSets).isEqualTo(3);
		assertThat(gearSets).isEqualTo(3);
	}

	/** Connecting twice must not duplicate the loadout rows. */
	@Test
	public void reconnectingDoesNotDuplicateLoadoutSets() {
		givenSelectedCharacter("Snake");

		connect(charaId, BURST_REPLIES);
		connect(charaId, BURST_REPLIES);

		var skillSets = TestDatabase.get().jdbi().withHandle(handle ->
			handle.createQuery("select count(*) from chara_skill_set where chara_id=:id")
				.bind("id", charaId).mapTo(Integer.class).one());

		assertThat(skillSets).isEqualTo(3);
	}

	/** Rows in gear_item, seeded by V44. 0x86 appears twice, so 123 rows and 122 distinct ids. */
	private static final int GEAR_CATALOGUE_ROWS = 123;

	@Test
	public void gearAndSkillCataloguesAreAdvertised() {
		givenSelectedCharacter("Snake");

		var replies = connect(charaId, BURST_REPLIES);

		// 123 catalogue rows for a new character, which is the known-good 651 bytes. The count is
		// the character's row count now, not a constant: gear comes from chara_gear as of V44, and
		// creation grants the whole catalogue.
		var gear = replies.get(6).getPayload();
		assertThat(gear.getInt(0)).isEqualTo(GEAR_CATALOGUE_ROWS);
		assertThat(gear.readableBytes()).isEqualTo(LoadoutWriter.gearPayloadSize(GEAR_CATALOGUE_ROWS));
		assertThat(gear.readableBytes()).isEqualTo(651);
		// The count is the character's row count now, not a constant in the writer. A new character
		// is granted 1..16; skill 17 is withheld to be earned.
		assertThat(replies.get(7).getPayload().getInt(0)).isEqualTo(CharaSkill.STARTING_MAX_ID);
	}
}
