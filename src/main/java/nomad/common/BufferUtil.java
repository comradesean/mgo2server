package nomad.common;

import io.netty.buffer.ByteBuf;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.charset.UnsupportedCharsetException;

public class BufferUtil {
	/**
	 * Currently only supports ISO-8859-1 and always pads the string.
	 */
	public static void writeString(ByteBuf buffer, String str, Charset charset, int maxBytes) {
		if (charset == StandardCharsets.ISO_8859_1) {
			for (int i = 0; i < maxBytes; i++) {
				buffer.writeByte(i < str.length() ? str.charAt(i) : 0);
			}
		} else {
			throw new UnsupportedCharsetException(charset.name());
		}
	}
}
