package nomad.common.service;

import nomad.common.model.Lobby;
import org.jdbi.v3.core.Jdbi;

import java.util.List;

public class LobbyService {
	private final Jdbi jdbi;

	public LobbyService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/** Lobbies advertised to a client, in a stable order so the list does not shuffle. */
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
