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
	 * Lobbies advertised to a client, ordered by name.
	 * <p>
	 * The order is not cosmetic. A client that reconnects to whichever entry leads the list will
	 * loop if that entry is the gate it just came from, so a lobby it can actually enter has to
	 * come first. mgo2-server orders by name for what appears to be the same reason: its rows are
	 * named GATE and ACCOUNT, so alphabetical ordering puts the account lobby ahead of the gate.
	 */
	public List<Lobby> getLobbies() {
		try (var handle = jdbi.open()) {
			return handle.createQuery("select * from lobby order by name")
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
