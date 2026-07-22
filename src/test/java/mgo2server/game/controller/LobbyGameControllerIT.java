package mgo2server.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.common.model.Lobby;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.GameError;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

public class LobbyGameControllerIT extends BaseGameClientServerIT {
	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GATE;
	}

	private static final int ENTRY_SIZE = 0x2e;

	private void addLobby(String name, int type, String ip, int port) {
		var lobby = new Lobby();
		lobby.setType(type);
		lobby.setName(name);
		lobby.setIp(ip);
		lobby.setPort(port);
		services.getLobbyService().addLobby(lobby);
	}

	/** Requests the lobby list and collects packets up to and including the end marker. */
	private List<GamePacket> requestLobbyList() {
		var received = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(LobbyGameController.GET_LOBBY_LIST));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					received.add(packet);
					if (packet.getCommand() == LobbyGameController.LOBBY_LIST_END) {
						ctx.close();
					}
				}
			}
		});

		return received;
	}

	@Test
	public void emptyListStillSendsStartAndEnd() {
		var replies = requestLobbyList();

		assertThat(replies).hasSize(2);
		assertThat(replies.get(0).getCommand()).isEqualTo(LobbyGameController.LOBBY_LIST_START);
		assertThat(replies.get(0).getPayload().getInt(0)).isEqualTo(GameError.NONE.result());
		assertThat(replies.get(1).getCommand()).isEqualTo(LobbyGameController.LOBBY_LIST_END);
	}

	@Test
	public void sendsOneEntryPacketForASmallList() {
		addLobby("Gate", 0, "127.0.0.1", 5730);
		addLobby("Account", 1, "127.0.0.1", 5731);

		var replies = requestLobbyList();

		assertThat(replies).hasSize(3);
		assertThat(replies.get(1).getCommand()).isEqualTo(LobbyGameController.LOBBY_LIST_ENTRIES);
		assertThat(replies.get(1).getPayload().readableBytes()).isEqualTo(2 * ENTRY_SIZE);
	}

	@Test
	public void writesLobbyFieldsInWireOrder() {
		addLobby("Gate", 2, "10.0.0.5", 5730);

		var entries = requestLobbyList().get(1).getPayload();

		assertThat(entries.getInt(0)).isEqualTo(0);
		assertThat(entries.getInt(4)).isEqualTo(2);

		var name = new byte[16];
		entries.getBytes(8, name);
		assertThat(new String(name, StandardCharsets.ISO_8859_1).trim())
			.startsWith("Gate");

		var ip = new byte[15];
		entries.getBytes(24, ip);
		assertThat(new String(ip, StandardCharsets.ISO_8859_1).replace("\0", ""))
			.isEqualTo("10.0.0.5");

		assertThat(entries.getShort(39)).isEqualTo((short) 5730);
		// Occupancy derives from players in games; with no games running it reads 0.
		assertThat(entries.getShort(41)).isEqualTo((short) 0);
	}

	/**
	 * Occupancy is players-in-games per lobby (the cheapest BACKLOG sketch), so two players in a
	 * game hosted in a lobby show up in that lobby's count and nowhere else. Operator policy, not
	 * protocol — nothing pins what the original counted, only that the field exists.
	 */
	@Test
	public void countsPlayersInGamesPerLobby() {
		addLobby("Gate", 0, "127.0.0.1", 5730);
		addLobby("Game", 2, "127.0.0.1", 5732);

		var jdbi = mgo2server.TestDatabase.get().jdbi();
		var gameLobbyId = jdbi.withHandle(h ->
			h.createQuery("select id from lobby where type = 2").mapTo(Long.class).one());
		var accountId = jdbi.withHandle(h -> h.createUpdate("""
				insert into account (username, password, session, slots, main_exp)
				values ('host', '', 'feed', 8, 0)
				""").executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		var hostChara = jdbi.withHandle(h ->
			h.createUpdate("insert into chara (account_id, name) values (:a, 'Snake')")
				.bind("a", accountId).executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		var joinerChara = jdbi.withHandle(h ->
			h.createUpdate("insert into chara (account_id, name) values (:a, 'Otacon')")
				.bind("a", accountId).executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		var gameId = jdbi.withHandle(h ->
			h.createUpdate("insert into game (lobby_id, host_chara_id, name) values (:l, :c, 'g')")
				.bind("l", gameLobbyId).bind("c", hostChara)
				.executeAndReturnGeneratedKeys("id").mapTo(Long.class).one());
		jdbi.useHandle(h -> {
			h.createUpdate("insert into game_player (game_id, chara_id) values (:g, :c)")
				.bind("g", gameId).bind("c", hostChara).execute();
			h.createUpdate("insert into game_player (game_id, chara_id) values (:g, :c)")
				.bind("g", gameId).bind("c", joinerChara).execute();
		});

		var entries = requestLobbyList().get(1).getPayload();

		// Entry 0 is the gate (no games), entry 1 the game lobby with two players in a game.
		assertThat(entries.getShort(41)).isEqualTo((short) 0);
		assertThat(entries.getShort(ENTRY_SIZE + 41)).isEqualTo((short) 2);
	}

	/** More lobbies than fit in one payload must be split across several entry packets. */
	@Test
	public void splitsLargeListAcrossPackets() {
		var count = LobbyGameController.entriesPerPacket() + 3;
		for (var i = 0; i < count; i++) {
			addLobby("Lobby" + i, 2, "127.0.0.1", 5730 + i);
		}

		var replies = requestLobbyList();

		var entryPackets = replies.stream()
			.filter(p -> p.getCommand() == LobbyGameController.LOBBY_LIST_ENTRIES)
			.toList();

		assertThat(entryPackets).hasSize(2);
		assertThat(entryPackets.get(0).getPayload().readableBytes())
			.isEqualTo(LobbyGameController.entriesPerPacket() * ENTRY_SIZE);
		assertThat(entryPackets.get(1).getPayload().readableBytes()).isEqualTo(3 * ENTRY_SIZE);
	}
}
