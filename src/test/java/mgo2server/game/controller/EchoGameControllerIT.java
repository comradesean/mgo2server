package mgo2server.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.Bytes;
import mgo2server.BytesAssert;
import mgo2server.TestUtil;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;

import static org.assertj.core.api.Assertions.*;

public class EchoGameControllerIT extends BaseGameClientServerIT {
	@Test
	public void echoTest() {
		var packets = new ArrayList<GamePacket>();
		client.run(1, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(0x0001, TestUtil.toBuffer("aabbccdd")));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					packets.add(packet);
					ctx.close();
				}
			}
		});

		var packet0 = packets.get(0);
		assertThat(packet0.getCommand()).isEqualTo(0x0001);
		BytesAssert.assertThat(Bytes.from(packet0.getPayload())).isEqualTo(Bytes.from("aabbccdd"));
	}

	/**
	 * Regression: GameServerHandler is shared across channels, so it must be @Sharable. Without
	 * that, Netty refuses to build the pipeline for the second connection and the server can
	 * only ever serve one client.
	 */
	@Test
	public void serverAcceptsMoreThanOneConnection() {
		for (var attempt = 0; attempt < 3; attempt++) {
			var connection = new mgo2server.GameClient(server.boundPort());
			var packets = new ArrayList<GamePacket>();

			connection.run(5, new ChannelInboundHandlerAdapter() {
				@Override
				public void channelActive(ChannelHandlerContext ctx) {
					ctx.writeAndFlush(new GamePacket(0x0001, TestUtil.toBuffer("aabbccdd")));
				}

				@Override
				public void channelRead(ChannelHandlerContext ctx, Object msg) {
					if (msg instanceof GamePacket packet) {
						packets.add(packet);
						ctx.close();
					}
				}
			});

			connection.disconnect(0L, 0L, java.util.concurrent.TimeUnit.SECONDS).join();

			assertThat(packets).as("connection %d", attempt + 1).hasSize(1);
		}
	}
}
