package mgo2server.common.service;

import mgo2server.common.model.Lobby;
import org.jdbi.v3.core.Jdbi;

import java.util.ArrayList;
import java.util.List;
import java.util.random.RandomGenerator;

public class LobbyService {
	private static final RandomGenerator RANDOM = RandomGenerator.getDefault();

	private final Jdbi jdbi;

	public LobbyService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/**
	 * Lobbies advertised to a client, ordered by id.
	 * <p>
	 * The order is not cosmetic, and it is not alphabetical. SaveMGO's Nomad — the server this
	 * client was actually developed against — never sorts: {@code Hub.getLobbyList} iterates
	 * {@code NLobbies.get().values()}, a map keyed by lobby id, which for small integer keys
	 * yields ascending id. With the canonical seeding (Gate 1, Account 2, Game 3) that makes the
	 * list index and the lobby type coincide:
	 * <pre>
	 *   index 0 -> type 0 (Gate)    index 1 -> type 1 (Account)    index 2 -> type 2 (Game)
	 * </pre>
	 * That identity matters because the client keys its connections by type — it holds a
	 * three-slot table at stride 0x44 indexed by type — while its own debug string reads
	 * {@code mgo_connect_server_by_index() index=%d, type=%d}, carrying both. Sorting by name put
	 * Account at index 0 and the Gate at index 2, breaking it.
	 * <p>
	 * This previously ordered by name, citing mgo2-server. That reference targets a different
	 * client build and has been wrong for this disc repeatedly; see dev/docs/OBSERVED.md.
	 */
	public List<Lobby> getLobbies() {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from lobby order by id")
				.mapTo(Lobby.class)
				.list();
		}
	}

	/**
	 * A lock key every registering lobby takes, so two starting at once cannot pick the same name.
	 * <p>
	 * Arbitrary but fixed; advisory locks share one namespace per database, so this only needs to
	 * be unique against our own other uses, of which there are none.
	 */
	private static final long REGISTRATION_LOCK = 0x10BB1_0001L;

	/**
	 * Registers this instance's own lobby row on startup, choosing a display name from a pool.
	 * <p>
	 * Lobby rows used to exist only because {@code dev/tools/seed.sql} had been run by hand, which
	 * meant a lobby's identity lived in two places that could disagree — compose passing
	 * {@code MGO2SERVER_LOBBY_ID} to a process, and a row somebody inserted separately. A server
	 * that knows its id, subtype, address and port can write that row itself, and now does.
	 * <p>
	 * The name is picked from {@code names}, skipping any name another lobby row already holds, so
	 * three Free Battle lobbies starting together get three different names. Concurrency is real
	 * here — compose starts them in parallel — so the whole thing runs under a transaction-scoped
	 * advisory lock. Without it two instances read the same "taken" set and pick the same name.
	 * <p>
	 * If every name in the pool is taken the first is reused rather than failing: a duplicate name
	 * is cosmetic, and the sub-list separates lobbies by <em>id</em>, not by name. Refusing to
	 * start over a cosmetic clash would be worse than the clash.
	 *
	 * @param names the pool to pick from; empty keeps whatever name the row already has
	 * @return the name this lobby is now registered under
	 */
	public String register(Lobby lobby, List<String> names) {
		return jdbi.inTransaction(handle -> {
			handle.execute("select pg_advisory_xact_lock(?)", REGISTRATION_LOCK);

			var name = lobby.getName();
			if (!names.isEmpty()) {
				var taken = handle
					.createQuery("select name from lobby where id != :id")
					.bind("id", lobby.getId())
					.mapTo(String.class)
					.set();

				var free = new ArrayList<>(names);
				free.removeAll(taken);
				// Random so a restart does not always produce the same board, and so the pool is
				// a pool rather than an ordered preference.
				name = free.isEmpty() ? names.get(0) : free.get(RANDOM.nextInt(free.size()));
			}

			// OVERRIDING SYSTEM VALUE because id is GENERATED ALWAYS: the id is chosen by whoever
			// wired the deployment, not by the sequence. Same reasoning as seed.sql.
			handle.createUpdate("""
					insert into lobby (id, type, subtype, name, ip, port, beginners_only,
						expansion_required, no_headshots, hub_flags)
					overriding system value
					values (:id, :type, :subtype, :name, :ip, :port, :beginnersOnly, false, false,
						:hubFlags)
					on conflict (id) do update set
						type = excluded.type,
						subtype = excluded.subtype,
						name = excluded.name,
						ip = excluded.ip,
						port = excluded.port,
						beginners_only = excluded.beginners_only,
						hub_flags = excluded.hub_flags
					""")
				.bind("id", lobby.getId())
				.bind("type", lobby.getType())
				.bind("subtype", lobby.getSubtype())
				.bind("name", name)
				.bind("ip", lobby.getIp())
				.bind("port", lobby.getPort())
				.bind("beginnersOnly", lobby.isBeginnersOnly())
				.bind("hubFlags", lobby.getHubFlags())
				.execute();

			// Keep the sequence past the explicit ids, or a later plain insert collides.
			handle.execute("""
					select setval(pg_get_serial_sequence('public.lobby', 'id'),
						greatest((select max(id) from lobby), 1), true)
					""");

			return name;
		});
	}

	public void addLobby(Lobby lobby) {
		try (var handle = jdbi.open()) {
			handle.createUpdate("""
					insert into lobby (type, subtype, name, ip, port, beginners_only,
						expansion_required, no_headshots)
					values (:type, :subtype, :name, :ip, :port, :beginnersOnly,
						:expansionRequired, :noHeadshots)
					""")
				.bind("type", lobby.getType())
				.bind("subtype", lobby.getSubtype())
				.bind("name", lobby.getName())
				.bind("ip", lobby.getIp())
				.bind("port", lobby.getPort())
				.bind("beginnersOnly", lobby.isBeginnersOnly())
				.bind("expansionRequired", lobby.isExpansionRequired())
				.bind("noHeadshots", lobby.isNoHeadshots())
				.execute();
		}
	}
}
