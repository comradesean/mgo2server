package nomad;

import io.netty.buffer.ByteBuf;

public class Bytes {
	private final byte[] bytes;

	public static Bytes from(byte[] data) {
		return new Bytes(data);
	}

	public static Bytes from(String hex) {
		int len = hex.length();
		byte[] data = new byte[len / 2];
		for (int i = 0; i < len; i += 2) {
			data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
				+ Character.digit(hex.charAt(i + 1), 16));
		}
		return new Bytes(data);
	}

	public static Bytes from(ByteBuf buffer) {
		var data = new byte[buffer.readableBytes()];
		buffer.getBytes(buffer.readerIndex(), data);
		return new Bytes(data);
	}

	private Bytes(byte[] bytes) {
		this.bytes = bytes;
	}

	public byte[] getBytes() {
		return bytes;
	}
}
