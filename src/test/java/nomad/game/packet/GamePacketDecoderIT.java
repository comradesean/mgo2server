package nomad.game.packet;

import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.Bytes;
import nomad.BytesAssert;
import nomad.game.BaseGameClientServerIT;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.*;

/**
 * Framing tests driven through a real socket, against the echo controller.
 * <p>
 * These were originally hand-written byte arrays carrying plaintext headers and dummy checksums.
 * Now that the wire format XORs every packet and authenticates it with an HMAC, the packets are
 * built with {@link GamePacketCodec#frame} instead, which also lets the expectations describe
 * intent rather than a wall of hex.
 */
public class GamePacketDecoderIT extends BaseGameClientServerIT {
	private static final int ECHO = 0x0001;

	/** Frames a run of echo packets, numbered from 1 as the decoder expects. */
	private static byte[] frames(byte[]... payloads) {
		var out = new ByteArrayOutputStream();
		for (var i = 0; i < payloads.length; i++) {
			out.writeBytes(GamePacketCodec.frame(ECHO, i + 1, payloads[i], false));
		}
		return out.toByteArray();
	}

	private static byte[] payload(int length) {
		var payload = new byte[length];
		for (var i = 0; i < length; i++) {
			payload[i] = (byte) (i * 7 + 1);
		}
		return payload;
	}

	/**
	 * Writes {@code wire} to the server, split at the given fragment sizes, and collects echoed
	 * packets until {@code expected} have arrived.
	 */
	private List<GamePacket> exchange(byte[] wire, int expected, int... fragmentSizes) {
		var received = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				var offset = 0;
				for (var size : fragmentSizes) {
					if (offset >= wire.length) {
						break;
					}
					var end = Math.min(offset + size, wire.length);
					ctx.writeAndFlush(Unpooled.wrappedBuffer(Arrays.copyOfRange(wire, offset, end)));
					offset = end;
				}
				if (offset < wire.length) {
					ctx.writeAndFlush(Unpooled.wrappedBuffer(Arrays.copyOfRange(wire, offset, wire.length)));
				}
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					received.add(packet);
					if (received.size() >= expected) {
						ctx.close();
					}
				}
			}
		});

		return received;
	}

	/**
	 * Writes {@code wire}, waits briefly for any response, then closes. Used where the server is
	 * expected to reject input, so waiting for a packet count would simply time out.
	 */
	private List<GamePacket> exchangeExpectingRejection(byte[] wire) {
		var received = new ArrayList<GamePacket>();

		client.run(10, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(Unpooled.wrappedBuffer(wire));
				ctx.executor().schedule((Runnable) ctx::close, 1, TimeUnit.SECONDS);
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					received.add(packet);
				}
			}
		});

		return received;
	}

	private static void assertEchoed(List<GamePacket> received, byte[]... expectedPayloads) {
		assertThat(received).hasSize(expectedPayloads.length);
		for (var i = 0; i < expectedPayloads.length; i++) {
			assertThat(received.get(i).getCommand()).isEqualTo(ECHO);
			BytesAssert.assertThat(Bytes.from(received.get(i).getPayload()))
				.isEqualTo(Bytes.from(expectedPayloads[i]));
		}
	}

	@Test
	public void singlePacketNoPayload() {
		assertEchoed(exchange(frames(new byte[0]), 1), new byte[0]);
	}

	@Test
	public void threePacketsNoPayload() {
		assertEchoed(exchange(frames(new byte[0], new byte[0], new byte[0]), 3),
			new byte[0], new byte[0], new byte[0]);
	}

	@Test
	public void singlePacketWithPayload() {
		var payload = payload(16);
		assertEchoed(exchange(frames(payload), 1), payload);
	}

	@Test
	public void threePacketsWithPayload() {
		var a = payload(4);
		var b = payload(16);
		var c = payload(37);
		assertEchoed(exchange(frames(a, b, c), 3), a, b, c);
	}

	/** A header split across two writes must still reassemble. */
	@Test
	public void fragmentedHeader() {
		assertEchoed(exchange(frames(new byte[0]), 1, 16, 8), new byte[0]);
	}

	@Test
	public void fragmentedIntoEightByteChunks() {
		var payload = payload(24);
		var wire = frames(payload);

		var sizes = new int[wire.length / 8 + 1];
		Arrays.fill(sizes, 8);

		assertEchoed(exchange(wire, 1, sizes), payload);
	}

	/** Packets coalesced into one write, then split at boundaries that fall mid-packet. */
	@Test
	public void multiplePacketsAcrossArbitraryFragments() {
		var a = payload(100);
		var b = payload(7);
		assertEchoed(exchange(frames(a, b), 2, 30, 5, 200), a, b);
	}

	@Test
	public void maximumSizedPayload() {
		var payload = payload(GamePacketCodec.MAX_PAYLOAD_LENGTH);
		assertEchoed(exchange(frames(payload), 1), payload);
	}

	@Test
	public void maximumSizedPayloadFollowedBySmallPacket() {
		var big = payload(GamePacketCodec.MAX_PAYLOAD_LENGTH);
		var small = payload(17);
		assertEchoed(exchange(frames(big, small), 2), big, small);
	}

	/** A tampered checksum must be rejected rather than dispatched to a controller. */
	@Test
	public void rejectsBadChecksum() {
		var wire = frames(payload(8));
		wire[GamePacketCodec.OFFSET_CHECKSUM] ^= (byte) 0xff;

		assertThat(exchangeExpectingRejection(wire)).isEmpty();
	}

	/** Sequence numbers must advance by one, so a replayed packet is refused. */
	@Test
	public void rejectsReplayedSequenceNumber() {
		var first = GamePacketCodec.frame(ECHO, 1, payload(8), false);
		var replay = GamePacketCodec.frame(ECHO, 1, payload(8), false);

		var wire = new byte[first.length + replay.length];
		System.arraycopy(first, 0, wire, 0, first.length);
		System.arraycopy(replay, 0, wire, first.length, replay.length);

		// The first echoes back; the replay trips the sequence check.
		assertThat(exchangeExpectingRejection(wire)).hasSize(1);
	}

}
