package mgo2server.common.service;

import mgo2server.TestDatabase;
import mgo2server.common.model.Lobby;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.*;

/**
 * Lobby self-registration on startup.
 * <p>
 * Rows used to exist only because {@code dev/tools/seed.sql} had been run by hand. A server that
 * knows its own id, subtype, address and port writes the row itself, and picks a display name from
 * a pool so several Free Battle lobbies can start together without colliding.
 */
public class LobbyRegistrationIT {
	private LobbyService lobbies;

	private static Lobby lobby(long id, int port) {
		var lobby = new Lobby();
		lobby.setId(id);
		lobby.setType(2);
		lobby.setSubtype(1);
		lobby.setIp("192.168.1.200");
		lobby.setPort(port);
		lobby.setName("placeholder");
		return lobby;
	}

	@BeforeEach
	public void setup() {
		TestDatabase.reset();
		lobbies = new LobbyService(TestDatabase.get().jdbi());
	}

	@Test
	public void registersARowWithTheConfiguredIdentity() {
		var name = lobbies.register(lobby(4, 15733), List.of("SNAKE"));

		assertThat(name).isEqualTo("SNAKE");

		var row = lobbies.getLobbies().stream().filter(l -> l.getId() == 4).findFirst().orElseThrow();
		assertThat(row.getName()).isEqualTo("SNAKE");
		assertThat(row.getType()).isEqualTo(2);
		assertThat(row.getSubtype()).isEqualTo(1);
		assertThat(row.getIp()).isEqualTo("192.168.1.200");
		assertThat(row.getPort()).isEqualTo(15733);
		assertThat(row.isBeginnersOnly()).isFalse();
	}

	/** Restarting must update the row in place, not add a second one or move the id. */
	@Test
	public void registeringTwiceKeepsOneRow() {
		lobbies.register(lobby(4, 15733), List.of("SNAKE"));
		lobbies.register(lobby(4, 15733), List.of("SNAKE"));

		assertThat(lobbies.getLobbies()).hasSize(1);
	}

	/** An empty pool leaves whatever name the caller supplied, for lobbies with a fixed name. */
	@Test
	public void anEmptyPoolKeepsTheGivenName() {
		assertThat(lobbies.register(lobby(1, 15731), List.of())).isEqualTo("placeholder");
	}

	@Test
	public void aSecondLobbyDoesNotTakeANameAlreadyInUse() {
		lobbies.register(lobby(4, 15733), List.of("SNAKE"));

		var second = lobbies.register(lobby(7, 15734), List.of("SNAKE", "MERYL"));

		assertThat(second).isEqualTo("MERYL");
	}

	/**
	 * The pool can run dry, and that must not stop a lobby starting: a duplicate name is cosmetic,
	 * because the client's sub-list separates lobbies by id rather than by name.
	 */
	@Test
	public void anExhaustedPoolReusesRatherThanFailing() {
		lobbies.register(lobby(4, 15733), List.of("VAMP"));

		assertThat(lobbies.register(lobby(7, 15734), List.of("VAMP"))).isEqualTo("VAMP");
	}

	@Test
	public void beginnersOnlyIsPersisted() {
		var beginner = lobby(8, 15735);
		beginner.setBeginnersOnly(true);

		lobbies.register(beginner, List.of("JOHNNY"));

		var row = lobbies.getLobbies().stream().filter(l -> l.getId() == 8).findFirst().orElseThrow();
		assertThat(row.isBeginnersOnly()).isTrue();
	}

	/**
	 * The reason registration takes an advisory lock.
	 * <p>
	 * Compose starts the Free Battle lobbies in parallel. Without serialising the read of "which
	 * names are taken" against the write that takes one, two instances read the same free set and
	 * pick the same name — and the whole point of the pool is that they do not.
	 */
	@Test
	public void concurrentRegistrationsPickDistinctNames() throws Exception {
		var pool = List.of("OTACON", "MERYL", "SNAKE", "LIQUID");
		var ids = List.of(4L, 7L, 8L, 9L);

		try (var pool2 = Executors.newFixedThreadPool(ids.size())) {
			var futures = ids.stream()
				.map(id -> pool2.submit(() -> lobbies.register(lobby(id, 15730 + id.intValue()), pool)))
				.toList();

			var chosen = futures.stream().map(f -> {
				try {
					return f.get(30, TimeUnit.SECONDS);
				}
				catch (Exception e) {
					throw new AssertionError(e);
				}
			}).toList();

			assertThat(chosen).containsExactlyInAnyOrderElementsOf(pool);
		}
	}
}
