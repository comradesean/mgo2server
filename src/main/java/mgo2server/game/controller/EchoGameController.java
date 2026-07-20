package mgo2server.game.controller;

import mgo2server.game.GameControllerContext;
import mgo2server.game.IGameController;
import mgo2server.game.packet.GamePacket;

import java.util.Map;
import java.util.function.Consumer;

public class EchoGameController implements IGameController {
	@Override
	public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
		handlers.put(0x0001, this::echo);
	}

	private void echo(GameControllerContext ctx) {
		ctx.write(new GamePacket(0x0001, ctx.packet().getPayload()));
	}
}
