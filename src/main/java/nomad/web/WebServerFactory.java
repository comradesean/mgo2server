package nomad.web;

import nomad.common.Database;
import nomad.common.Services;
import nomad.common.ServicesFactory;
import nomad.web.controller.AccountWebController;
import nomad.web.controller.NewsWebController;

import java.util.ArrayList;

public class WebServerFactory {
	public static WebServer createWebServer() {
		var jdbi = Database.getJdbi();
		var services = ServicesFactory.createServices(jdbi);
		return createWebServer(services);
	}

	public static WebServer createWebServer(Services services) {
		var controllers = new ArrayList<IWebController>();

		controllers.add(new AccountWebController(services.getAccountService()));

		controllers.add(new NewsWebController(services.getNewsService()));

		return new WebServer(controllers);
	}
}
