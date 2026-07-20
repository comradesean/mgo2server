package mgo2server;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.ServerSocket;

public class TestUtil {
	/**
	 * Reserves an ephemeral port. Lets test servers avoid fixed ports, which otherwise collide
	 * between concurrent test classes and with anything already running on the machine.
	 */
	public static int freePort() {
		try (var socket = new ServerSocket(0)) {
			return socket.getLocalPort();
		} catch (IOException e) {
			throw new UncheckedIOException(e);
		}
	}

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
