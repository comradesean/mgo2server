package nomad.game.controller;

import nomad.game.GameControllerContext;
import nomad.game.IGameController;
import nomad.game.packet.GamePacket;

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
