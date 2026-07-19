package nomad.common.service;

import nomad.common.DbUtil;
import nomad.common.message.GetNewsItemsMessage;
import nomad.common.model.News;
import org.jdbi.v3.core.Jdbi;

import static java.util.stream.Collectors.joining;

public class NewsService {
	private final Jdbi jdbi;

	public NewsService(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	public GetNewsItemsMessage getNewsItems() {
		var message = new GetNewsItemsMessage();

		try (var handle = jdbi.open()) {
			var newsItems = handle.createQuery("select * from news").mapTo(News.class).list();
			message.setNewsItems(newsItems);
		}

		return message;
	}

	public void addNewsItem(News news) {
		try (var handle = jdbi.open()) {
			var update = handle.createUpdate("insert into news (important, title, body<keys>) values (:important, :title, :body<values>)")
				.bind("important", news.isImportant())
				.bind("title", news.getTitle())
				.bind("body", news.getBody());

			DbUtil.addOptional(update, "time", news.getTime());

			update.execute();
		}
	}

}
