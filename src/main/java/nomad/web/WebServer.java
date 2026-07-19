package nomad.web;

import io.jooby.Jooby;

import java.time.ZoneOffset;
import java.util.List;
import java.util.TimeZone;

public class WebServer {
	private final List<IWebController> controllers;

	public WebServer(List<IWebController> controllers) {
		this.controllers = controllers;
	}

	public void use(Jooby jooby) {
		TimeZone.setDefault(TimeZone.getTimeZone(ZoneOffset.UTC));

		jooby.get("/", ctx -> "Hello world!");

		for (var controller : controllers) {
			controller.use(jooby);
		}
	}

	public static void main(String[] args) {
		Jooby.runApp(args, jooby -> WebServerFactory.createWebServer().use(jooby));
	}
}
