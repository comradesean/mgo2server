package mgo2server.common;

import io.netty.buffer.ByteBuf;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.charset.UnsupportedCharsetException;

public class BufferUtil {
	/**
	 * Writes a fixed-width, zero-padded string.
	 * <p>
	 * Most of the protocol is ISO-8859-1, where one character is one byte. Loadout set names are
	 * UTF-8, where they are not — so that path truncates on a byte boundary and never emits a
	 * partial multi-byte sequence, which would render as a replacement character in the client.
	 */
	public static void writeString(ByteBuf buffer, String str, Charset charset, int maxBytes) {
		if (str == null) {
			str = "";
		}

		if (charset == StandardCharsets.ISO_8859_1) {
			for (int i = 0; i < maxBytes; i++) {
				buffer.writeByte(i < str.length() ? str.charAt(i) : 0);
			}
			return;
		}

		if (charset == StandardCharsets.UTF_8) {
			byte[] encoded = str.getBytes(StandardCharsets.UTF_8);
			int length = Math.min(encoded.length, maxBytes);

			// Only back off if the string was actually cut, and test the first *excluded* byte:
			// a complete character also ends in a continuation byte, so inspecting the last
			// included byte would truncate perfectly valid text.
			if (length < encoded.length) {
				while (length > 0 && (encoded[length] & 0xc0) == 0x80) {
					length--;
				}
			}

			buffer.writeBytes(encoded, 0, length);
			buffer.writeZero(maxBytes - length);
			return;
		}

		throw new UnsupportedCharsetException(charset.name());
	}
}
