package mgo2server.web;

import mgo2server.common.Services;
import mgo2server.web.controller.AccountWebController;
import mgo2server.web.controller.AuthWebController;
import mgo2server.web.controller.HealthWebController;
import mgo2server.web.controller.NewsWebController;

import javax.sql.DataSource;
import java.util.ArrayList;

public class WebServerFactory {
	public static WebServer createWebServer(Services services, DataSource dataSource) {
		var controllers = new ArrayList<IWebController>();

		controllers.add(new HealthWebController(dataSource));

		controllers.add(new AuthWebController(services.getAccountService()));

		controllers.add(new AccountWebController(services.getAccountService()));

		controllers.add(new NewsWebController(services.getNewsService()));

		return new WebServer(controllers);
	}
}
