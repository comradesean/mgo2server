package nomad.common.model;

public class Room {
	private long id;

	private long lobbyId;

	private long hostCharaId;

	private long roomConfigurationId;

	private int currentMatchIndex;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public long getLobbyId() {
		return lobbyId;
	}

	public void setLobbyId(long lobbyId) {
		this.lobbyId = lobbyId;
	}

	public long getHostCharaId() {
		return hostCharaId;
	}

	public void setHostCharaId(long hostCharaId) {
		this.hostCharaId = hostCharaId;
	}

	public long getRoomConfigurationId() {
		return roomConfigurationId;
	}

	public void setRoomConfigurationId(long roomConfigurationId) {
		this.roomConfigurationId = roomConfigurationId;
	}

	public int getCurrentMatchIndex() {
		return currentMatchIndex;
	}

	public void setCurrentMatchIndex(int currentMatchIndex) {
		this.currentMatchIndex = currentMatchIndex;
	}

	@Override
	public String toString() {
		return "Room{" +
			"id=" + id +
			", lobbyId=" + lobbyId +
			", hostCharaId=" + hostCharaId +
			", roomConfigurationId=" + roomConfigurationId +
			", currentMatchIndex=" + currentMatchIndex +
			'}';
	}
}
