package nomad.common.model;

import java.time.OffsetDateTime;

public class News {
	private long id;

	private OffsetDateTime time;

	private boolean important;

	private String title;

	private String body;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public OffsetDateTime getTime() {
		return time;
	}

	public void setTime(OffsetDateTime time) {
		this.time = time;
	}

	public boolean isImportant() {
		return important;
	}

	public void setImportant(boolean important) {
		this.important = important;
	}

	public String getTitle() {
		return title;
	}

	public void setTitle(String title) {
		this.title = title;
	}

	public String getBody() {
		return body;
	}

	public void setBody(String body) {
		this.body = body;
	}

	@Override
	public String toString() {
		return "News{" +
			"id=" + id +
			", time=" + time +
			", important=" + important +
			", title='" + title + '\'' +
			", body='" + body + '\'' +
			'}';
	}
}
