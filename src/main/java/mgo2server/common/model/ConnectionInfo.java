package mgo2server.common.model;

/**
 * A character's peer-to-peer endpoints, registered by command 0x4700 and handed to a joining
 * player by command 0x4321. The public address is what the server observed on the socket; the
 * private address is the LAN address the client reported for same-network peers.
 */
public class ConnectionInfo {
	private long charaId;

	private String publicIp;

	private int publicPort;

	private String privateIp;

	private int privatePort;

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public String getPublicIp() {
		return publicIp;
	}

	public void setPublicIp(String publicIp) {
		this.publicIp = publicIp;
	}

	public int getPublicPort() {
		return publicPort;
	}

	public void setPublicPort(int publicPort) {
		this.publicPort = publicPort;
	}

	public String getPrivateIp() {
		return privateIp;
	}

	public void setPrivateIp(String privateIp) {
		this.privateIp = privateIp;
	}

	public int getPrivatePort() {
		return privatePort;
	}

	public void setPrivatePort(int privatePort) {
		this.privatePort = privatePort;
	}
}
