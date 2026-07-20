package mgo2server.game.controller;

import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import mgo2server.game.BaseGameClientServerIT;
import mgo2server.game.LobbyType;
import mgo2server.game.packet.GamePacket;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;

import static org.assertj.core.api.Assertions.*;

/**
 * Commands every lobby answers. A real client sends 0x0003 when it is finished with a lobby and
 * waits for the close; without it the connection hangs and the client stalls with no error.
 */
public class CommonGameControllerIT extends BaseGameClientServerIT {
	@Override
	protected LobbyType lobbyType() {
		return LobbyType.GATE;
	}

	@Test
	public void pingIsEchoedBack() {
		var replies = new ArrayList<GamePacket>();

		client.run(5, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CommonGameController.PING));
			}

			@Override
			public void channelRead(ChannelHandlerContext ctx, Object msg) {
				if (msg instanceof GamePacket packet) {
					replies.add(packet);
					ctx.close();
				}
			}
		});

		assertThat(replies).hasSize(1);
		assertThat(replies.get(0).getCommand()).isEqualTo(CommonGameController.PING);
	}

	/** The server must close the connection itself, rather than leaving the client waiting. */
	@Test
	public void disconnectClosesTheConnection() {
		var closedByServer = new boolean[] { false };

		client.run(5, new ChannelInboundHandlerAdapter() {
			@Override
			public void channelActive(ChannelHandlerContext ctx) {
				ctx.writeAndFlush(new GamePacket(CommonGameController.DISCONNECT));
			}

			@Override
			public void channelInactive(ChannelHandlerContext ctx) {
				closedByServer[0] = true;
				ctx.close();
			}
		});

		assertThat(closedByServer[0]).isTrue();
	}
}
