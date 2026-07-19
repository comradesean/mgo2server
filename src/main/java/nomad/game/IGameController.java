package nomad.game;

import java.util.Map;
import java.util.function.Consumer;

public interface IGameController {
	void register(Map<Integer, Consumer<GameControllerContext>> handlers);
}
