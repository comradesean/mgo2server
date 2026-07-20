package mgo2server.common.model;

/**
 * One preset chat message. Addressed by (type, index) because that is how the client refers to
 * them; there is no surrogate id.
 */
public class ChatMacro {
	public static final int TYPES = 2;

	public static final int PER_TYPE = 12;

	public static final int TEXT_LENGTH = 64;

	private long charaId;

	private int type;

	private int index;

	private String text = "";

	public long getCharaId() {
		return charaId;
	}

	public void setCharaId(long charaId) {
		this.charaId = charaId;
	}

	public int getType() {
		return type;
	}

	public void setType(int type) {
		this.type = type;
	}

	public int getIndex() {
		return index;
	}

	public void setIndex(int index) {
		this.index = index;
	}

	public String getText() {
		return text;
	}

	public void setText(String text) {
		this.text = text;
	}

	@Override
	public String toString() {
		return "ChatMacro{charaId=" + charaId + ", type=" + type + ", index=" + index + "}";
	}
}
