package nomad.web.controller;

import nomad.common.message.GetNewsItemsMessage;
import nomad.common.model.News;
import nomad.web.BaseWebClientServerTest;
import okhttp3.Request;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

public class NewsWebControllerTest extends BaseWebClientServerTest {
	@Test
	public void getNewsItems1() throws IOException {
		var news = new News();
		news.setTime(Instant.ofEpochSecond(1213228801).atOffset(ZoneOffset.UTC));
		news.setImportant(true);
		news.setTitle("Test");
		news.setBody("Hello, world!");
		services.getNewsService().addNewsItem(news);

		var expectedMessage = new GetNewsItemsMessage();
		news.setId(1);
		expectedMessage.setNewsItems(List.of(news));

		var request = new Request.Builder()
			.url(HOST + "/news")
			.build();

		try (var response = client.newCall(request).execute()) {
			var body = response.body();
			assertThat(body).isNotNull();
			assertThat(body.string()).isEqualTo(expectedMessage.toString());
		}
	}
}
