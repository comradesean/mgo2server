package mgo2server.common;

import mgo2server.common.service.AccountService;
import mgo2server.common.service.AwardService;
import mgo2server.common.service.CharacterService;
import mgo2server.common.service.ClanService;
import mgo2server.common.service.GameService;
import mgo2server.common.service.LobbyService;
import mgo2server.common.service.NewsService;
import mgo2server.common.service.RankingService;
import mgo2server.common.service.StatsService;

public class Services {
	private final AccountService accountService;
	private final CharacterService characterService;
	private final ClanService clanService;
	private final GameService gameService;
	private final LobbyService lobbyService;
	private final NewsService newsService;
	private final RankingService rankingService;
	private final StatsService statsService;
	private final AwardService awardService;

	public Services(AccountService accountService, CharacterService characterService,
			ClanService clanService, GameService gameService, LobbyService lobbyService,
			NewsService newsService, RankingService rankingService, StatsService statsService,
			AwardService awardService) {
		this.accountService = accountService;
		this.characterService = characterService;
		this.clanService = clanService;
		this.gameService = gameService;
		this.lobbyService = lobbyService;
		this.newsService = newsService;
		this.rankingService = rankingService;
		this.statsService = statsService;
		this.awardService = awardService;
	}

	public AccountService getAccountService() {
		return accountService;
	}

	public CharacterService getCharacterService() {
		return characterService;
	}

	public ClanService getClanService() {
		return clanService;
	}

	public GameService getGameService() {
		return gameService;
	}

	public LobbyService getLobbyService() {
		return lobbyService;
	}

	public NewsService getNewsService() {
		return newsService;
	}

	public RankingService getRankingService() {
		return rankingService;
	}

	public StatsService getStatsService() {
		return statsService;
	}

	public AwardService getAwardService() {
		return awardService;
	}
}
