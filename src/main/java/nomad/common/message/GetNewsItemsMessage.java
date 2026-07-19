package nomad.common.message;

import nomad.common.model.News;

import java.util.List;

public class GetNewsItemsMessage {
	private List<News> newsItems = List.of();

	public List<News> getNewsItems() {
		return newsItems;
	}

	public void setNewsItems(List<News> newsItems) {
		this.newsItems = newsItems;
	}

	@Override
	public String toString() {
		return "GetNewsItemsMessage{" +
			"newsItems=" + newsItems +
			'}';
	}
}
