package nomad.web.controller;

import io.jooby.Jooby;
import nomad.common.model.News;
import nomad.common.service.NewsService;
import nomad.web.IWebController;

public class NewsWebController implements IWebController {
	private final NewsService newsService;

	public NewsWebController(NewsService newsService) {
		this.newsService = newsService;
	}

	public void use(Jooby jooby) {
		jooby.get("/news", ctx -> {
			var message = newsService.getNewsItems();

			return message.toString();
		});

		jooby.post("/news", ctx -> {
			var title = ctx.form("title").value("");
			var body = ctx.form("body").value("");
			if (title.isBlank() || body.isBlank()) {
				return "FAIL";
			}

			var news = new News();
			news.setTitle(title);
			news.setBody(body);

			newsService.addNewsItem(news);

			return "OK";
		});
	}
}
