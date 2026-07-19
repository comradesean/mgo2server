package nomad.web;

import nomad.common.Services;
import nomad.web.controller.AccountWebController;
import nomad.web.controller.AuthWebController;
import nomad.web.controller.HealthWebController;
import nomad.web.controller.NewsWebController;

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
