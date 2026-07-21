package mgo2server.game;

import io.netty.channel.Channel;
import io.netty.util.AttributeKey;
import mgo2server.common.model.Account;

/**
 * Per-connection state, most importantly which account has authenticated.
 * <p>
 * Held in a channel attribute rather than a static map keyed by channel, so it is discarded with
 * the connection and cannot leak between players.
 */
public final class GameConnection {
	private static final AttributeKey<GameConnection> KEY = AttributeKey.valueOf("mgo2server.gameConnection");

	private Account account;

	/**
	 * The active round's rule/map/flags the host pushed via {@code 0x4310} just before creating a
	 * game. Held here because create-game ({@code 0x4316}) carries no settings of its own — it
	 * relies on the preceding push. {@code null} until a push arrives.
	 */
	private int[] hostRotation;

	private GameConnection() {
	}

	public static GameConnection of(Channel channel) {
		var attribute = channel.attr(KEY);
		var connection = attribute.get();
		if (connection == null) {
			connection = new GameConnection();
			var existing = attribute.setIfAbsent(connection);
			if (existing != null) {
				connection = existing;
			}
		}
		return connection;
	}

	public boolean isAuthenticated() {
		return account != null;
	}

	/** The authenticated account, or null if this connection has not checked in yet. */
	public Account account() {
		return account;
	}

	public void authenticate(Account account) {
		this.account = account;
	}

	/** Record the round-0 {@code [rule, map, flags]} from a host-settings push. */
	public void setHostRotation(int rule, int map, int flags) {
		this.hostRotation = new int[] { rule, map, flags };
	}

	/** The pushed round-0 {@code [rule, map, flags]}, or null if the host pushed nothing. */
	public int[] hostRotation() {
		return hostRotation;
	}

	public void clear() {
		this.account = null;
		this.hostRotation = null;
	}
}
