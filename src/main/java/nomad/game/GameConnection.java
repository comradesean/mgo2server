package nomad.game;

import io.netty.channel.Channel;
import io.netty.util.AttributeKey;
import nomad.common.model.Account;

/**
 * Per-connection state, most importantly which account has authenticated.
 * <p>
 * Held in a channel attribute rather than a static map keyed by channel, so it is discarded with
 * the connection and cannot leak between players.
 */
public final class GameConnection {
	private static final AttributeKey<GameConnection> KEY = AttributeKey.valueOf("nomad.gameConnection");

	private Account account;

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

	public void clear() {
		this.account = null;
	}
}
