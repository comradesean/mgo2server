package mgo2server.game;

import mgo2server.common.AutomatchPolicy;
import mgo2server.common.ClientVersion;
import mgo2server.common.Services;
import mgo2server.common.service.PresenceService;
import mgo2server.game.ChannelRegistry;
import mgo2server.game.controller.AccountGameController;
import mgo2server.game.controller.AutomatchGameController;
import mgo2server.game.controller.CommonGameController;
import mgo2server.game.controller.CharacterConnectController;
import mgo2server.game.controller.CharacterGameController;
import mgo2server.game.controller.ChatGameController;
import mgo2server.game.controller.ClanGameController;
import mgo2server.game.controller.EchoGameController;
import mgo2server.game.controller.GameListGameController;
import mgo2server.game.controller.HostGameController;
import mgo2server.game.controller.HubGameController;
import mgo2server.game.controller.LobbyGameController;
import mgo2server.game.controller.MessageGameController;
import mgo2server.game.controller.NewsGameController;
import mgo2server.game.controller.PersonalInfoController;
import mgo2server.game.controller.PersonalStatsController;
import mgo2server.game.controller.SocialGameController;

import java.util.ArrayList;
import java.util.List;

public class GameServerFactory {
	/**
	 * Builds a server for one lobby. Which commands are answered depends on the lobby type, so a
	 * gate cannot be asked to create a character and a game lobby cannot be asked for the lobby
	 * list — the same split the original gets from running a separate server per lobby.
	 */
	public static GameServer createGameServer(Services services, int port, LobbyType lobbyType,
			long lobbyId, int lobbySubtype) {
		return createGameServer(services, port, lobbyType, lobbyId, lobbySubtype,
			AutomatchPolicy.from(System::getenv), ClientVersion.from(System::getenv));
	}

	/** Keeps the old five-argument shape working for callers that do not care about the version. */
	public static GameServer createGameServer(Services services, int port, LobbyType lobbyType,
			long lobbyId, int lobbySubtype, AutomatchPolicy automatchPolicy) {
		return createGameServer(services, port, lobbyType, lobbyId, lobbySubtype, automatchPolicy,
			ClientVersion.from(System::getenv));
	}

	/**
	 * Takes the automatch policy explicitly, so a test can stand up a server with the window open or
	 * closed. Unlike a cooldown, this differs between a test and a deployment, which is why it is
	 * threaded through rather than read from a static the way {@code Policy} is.
	 */
	public static GameServer createGameServer(Services services, int port, LobbyType lobbyType,
			long lobbyId, int lobbySubtype, AutomatchPolicy automatchPolicy, ClientVersion version) {
		var controllers = new ArrayList<IGameController>();

		// The queue lives here rather than behind Services: it holds channels and per-lobby state,
		// while Services is lobby-agnostic and shared across a process.
		var automatch = new Automatch(automatchPolicy, lobbyId, lobbySubtype,
			new Automatch.GameLookup() {
				@Override
				public long hostedGameId(long lobby, long host) {
					return services.getGameService().getHostedGame(lobby, host)
						.map(mgo2server.common.model.Game::getId).orElse(0L);
				}

				@Override
				public void renameAndUnlock(long gameId, String name) {
					services.getGameService().renameAndUnlock(gameId, name);
				}
			});

		// Handles no commands: it is here so its onPacket/onDisconnect hooks fire, which is what keeps
		// the character-id to channel map current. Anything that has to reach a client other than the
		// one currently asking takes this.
		var channels = new ChannelRegistry(services.getPresenceService(), lobbyId);
		controllers.add(channels);

		// Disconnect and ping, which every lobby answers.
		controllers.add(new CommonGameController());

		// Useful for smoke-testing a connection regardless of lobby type.
		controllers.add(new EchoGameController());

		switch (lobbyType) {
			case GATE -> {
				controllers.add(new LobbyGameController(services.getLobbyService(),
					services.getGameService()));
				controllers.add(new NewsGameController(services.getNewsService()));
			}
			case ACCOUNT -> {
				controllers.add(new AccountGameController(services.getAccountService(),
					services.getCharacterService(), lobbyType,
					services.getLobbyService(), lobbyId));
				controllers.add(new CharacterGameController(services.getAccountService(),
					services.getCharacterService(),
					services.getClanService()));
			}
			case GAME -> {
				controllers.add(new AccountGameController(services.getAccountService(),
					services.getCharacterService(), lobbyType,
					services.getLobbyService(), lobbyId));
				controllers.add(new CharacterConnectController(services.getCharacterService(),
					services.getClanService(), services.getGameService(),
					services.getAwardService()));
				controllers.add(new GameListGameController(services.getGameService(),
					services.getCharacterService(), lobbyId, lobbySubtype));
				controllers.add(new ChatGameController(services.getGameService(), channels));
				controllers.add(new MessageGameController(services.getCharacterService(), services.getClanService()));
				controllers.add(new HubGameController(services.getLobbyService(), version));
				controllers.add(new AutomatchGameController(automatchPolicy, automatch,
					services.getCharacterService()));
				controllers.add(new PersonalInfoController(services.getCharacterService()));
				controllers.add(new SocialGameController(services.getCharacterService(),
					services.getClanService(), services.getGameService(),
					services.getPresenceService()));
				controllers.add(new PersonalStatsController(services.getCharacterService(),
					services.getClanService(), services.getAccountService(),
					services.getStatsService(), services.getAwardService()));
				controllers.add(new ClanGameController(services.getClanService(),
					services.getCharacterService(), services.getPresenceService()));
				controllers.add(new HostGameController(services.getGameService(),
					services.getCharacterService(), services.getClanService(),
					services.getAwardService(), services.getPresenceService(), lobbyId, lobbySubtype,
					automatch::gameCreated));
			}
		}

		// Only game lobbies run the matchmaker; a gate or account server has no searchers and no
		// reason to hold a thread open.
		var automatchTask = lobbyType == LobbyType.GAME
			? new GameServer.PeriodicTask("automatch", automatchPolicy.tick(), automatch::tick)
			: null;

		// Presence runs on EVERY lobby type, unlike the matchmaker. A gate or account server holds
		// connections too, and a row left behind by one is just as stale as one left by a game
		// lobby -- and its reaper is the only thing that cleans up after a process that died and
		// never came back, so the more servers running it, the sooner that happens.
		var presenceTask = new GameServer.PeriodicTask("presence",
			PresenceService.HEARTBEAT_INTERVAL, channels::refreshPresence);

		// Clear this lobby's rows BEFORE the port is open, not after: a client that connects between
		// bind and clear would have its brand-new presence wiped by our own startup sweep.
		channels.clearStalePresence();

		// Built explicitly rather than with List.of(automatchTask, presenceTask): automatchTask is
		// null on every lobby type except GAME, and List.of throws NullPointerException on a null
		// element before GameServer ever gets the chance to filter it. That failed 51 integration
		// tests at server construction, which is a long way from where the mistake reads.
		var tasks = new ArrayList<GameServer.PeriodicTask>();
		if (automatchTask != null) {
			tasks.add(automatchTask);
		}
		tasks.add(presenceTask);

		return new GameServer(controllers, port, tasks);
	}
}
