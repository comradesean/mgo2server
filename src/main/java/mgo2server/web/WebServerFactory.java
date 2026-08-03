package mgo2server.web;

import mgo2server.common.ClientVersion;
import mgo2server.common.Services;
import mgo2server.web.controller.AccountWebController;
import mgo2server.web.controller.AuthWebController;
import mgo2server.web.controller.HealthWebController;
import mgo2server.web.controller.NewsWebController;
import mgo2server.web.controller.RankingWebController;

import javax.sql.DataSource;
import java.util.ArrayList;

public class WebServerFactory {
	/**
	 * @param version which client build to serve. Threaded in rather than read from a static, for
	 *     the same reason {@code GameServerFactory} threads {@code AutomatchPolicy}: it differs
	 *     between a test and a deployment, and a test must be able to exercise both in one JVM.
	 */
	public static WebServer createWebServer(Services services, DataSource dataSource,
			ClientVersion version) {
		var controllers = new ArrayList<IWebController>();

		controllers.add(new HealthWebController(dataSource));

		controllers.add(new AuthWebController(services.getAccountService(), version));

		controllers.add(new AccountWebController(services.getAccountService()));

		controllers.add(new NewsWebController(services.getNewsService()));

		controllers.add(new RankingWebController(services.getRankingService()));

		return new WebServer(controllers);
	}
}
