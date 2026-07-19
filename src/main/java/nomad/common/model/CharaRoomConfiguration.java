package nomad.common.model;

public class CharaRoomConfiguration {
	private long id;

	private long charaId;

	private long roomConfigurationId;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public long getRoomConfigurationId() {
		return roomConfigurationId;
	}

	public void setRoomConfigurationId(long roomConfigurationId) {
		this.roomConfigurationId = roomConfigurationId;
	}

	@Override
	public String toString() {
		return "CharaRoomConfiguration{" +
			"id=" + id +
			", charaId=" + charaId +
			", roomConfigurationId=" + roomConfigurationId +
			'}';
	}
}
