package nomad.common.model;

public class RoomChara {
	private long id;

	private long roomId;

	private long charaId;

	private int team;

	private int ping;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public long getRoomId() {
		return roomId;
	}

	public void setRoomId(long roomId) {
		this.roomId = roomId;
	}

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getTeam() {
		return team;
	}

	public void setTeam(int team) {
		this.team = team;
	}

	public int getPing() {
		return ping;
	}

	public void setPing(int ping) {
		this.ping = ping;
	}

	@Override
	public String toString() {
		return "RoomChara{" +
			"id=" + id +
			", roomId=" + roomId +
			", charaId=" + charaId +
			", team=" + team +
			", ping=" + ping +
			'}';
	}
}
