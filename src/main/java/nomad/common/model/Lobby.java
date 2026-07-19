package nomad.common.model;

public class Lobby {
	private long id;

	private int type;

	private int subtype;

	private String name;

	private String ip;

	private int port;

	private boolean beginnersOnly;

	private boolean expansionRequired;

	private boolean noHeadshots;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public int getType() {
		return type;
	}

	public void setType(int type) {
		this.type = type;
	}

	public int getSubtype() {
		return subtype;
	}

	public void setSubtype(int subtype) {
		this.subtype = subtype;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public String getIp() {
		return ip;
	}

	public void setIp(String ip) {
		this.ip = ip;
	}

	public int getPort() {
		return port;
	}

	public void setPort(int port) {
		this.port = port;
	}

	public boolean isBeginnersOnly() {
		return beginnersOnly;
	}

	public void setBeginnersOnly(boolean beginnersOnly) {
		this.beginnersOnly = beginnersOnly;
	}

	public boolean isExpansionRequired() {
		return expansionRequired;
	}

	public void setExpansionRequired(boolean expansionRequired) {
		this.expansionRequired = expansionRequired;
	}

	public boolean isNoHeadshots() {
		return noHeadshots;
	}

	public void setNoHeadshots(boolean noHeadshots) {
		this.noHeadshots = noHeadshots;
	}

	@Override
	public String toString() {
		return "Lobby{" +
			"id=" + id +
			", type=" + type +
			", subtype=" + subtype +
			", name='" + name + '\'' +
			", ip='" + ip + '\'' +
			", port=" + port +
			", beginnersOnly=" + beginnersOnly +
			", expansionRequired=" + expansionRequired +
			", noHeadshots=" + noHeadshots +
			'}';
	}
}
