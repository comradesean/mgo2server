package nomad;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;

public class TestUtil {
	public static ByteBuf toBuffer(String hex) {
		int len = hex.length();
		byte[] data = new byte[len / 2];
		for (int i = 0; i < len; i += 2) {
			data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
				+ Character.digit(hex.charAt(i + 1), 16));
		}
		return Unpooled.wrappedBuffer(data);
	}
}
