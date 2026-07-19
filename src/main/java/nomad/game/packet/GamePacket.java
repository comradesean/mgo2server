package nomad.game.packet;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;

public class GamePacket {
	private final int command;

	private final ByteBuf payload;

	public GamePacket(int command, ByteBuf payload) {
		this.command = command;
		this.payload = payload;
	}

	public GamePacket(int command) {
		this(command, Unpooled.EMPTY_BUFFER);
	}

	public GamePacket(int command, int result) {
		this(command, Unpooled.wrappedBuffer(new byte[] { (byte) (result >>> 24), (byte) (result >>> 16),
			(byte) (result >>> 8), (byte) result }));
	}

	public int getCommand() {
		return command;
	}

	public ByteBuf getPayload() {
		return payload;
	}
}
