package nomad.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import nomad.game.BaseGameClientServerTest;
import nomad.Bytes;
import nomad.BytesAssert;
import nomad.TestUtil;
import nomad.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;

import static org.assertj.core.api.Assertions.*;

public class EchoGameControllerTest extends BaseGameClientServerTest {
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
}
