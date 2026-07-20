package nomad.common.service;

import nomad.common.model.Lobby;
import org.jdbi.v3.core.Jdbi;

import java.util.List;

public class LobbyService {
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
	 * client build and has been wrong for this disc repeatedly; see dev/OBSERVED.md.
	 */
	public List<Lobby> getLobbies() {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from lobby order by id")
				.mapTo(Lobby.class)
				.list();
		}
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
