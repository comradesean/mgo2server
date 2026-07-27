package mgo2server.game;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * A command has exactly one handler.
 * <p>
 * Registration used to be a {@code HashMap.put} followed by {@code putAll}, so a command claimed
 * twice was resolved by declaration order in silence. {@code ClanGameController} claimed 0x4b90 as
 * both a "member action" and clan search; the second won, which happened to be the correct one,
 * and the loser sat there for months reading the same two bytes a different way and looking
 * maintained. This is a wiring bug, so it fails at construction rather than at runtime.
 */
public class GameServerHandlerTest {
	private record StubController(Map<Integer, Consumer<GameControllerContext>> commands)
			implements IGameController {
		@Override
		public void register(Map<Integer, Consumer<GameControllerContext>> handlers) {
			handlers.putAll(commands);
		}
	}

	private static IGameController claiming(int... commands) {
		var map = new java.util.HashMap<Integer, Consumer<GameControllerContext>>();
		for (var command : commands) {
			map.put(command, ctx -> { });
		}
		return new StubController(map);
	}

	@Test
	public void acceptsControllersThatClaimDistinctCommands() {
		assertThatCode(() -> new GameServerHandler(List.of(claiming(0x4b90), claiming(0x4b91))))
			.doesNotThrowAnyException();
	}

	@Test
	public void refusesTwoControllersClaimingTheSameCommand() {
		assertThatThrownBy(() -> new GameServerHandler(List.of(claiming(0x4b90), claiming(0x4b90))))
			.isInstanceOf(IllegalStateException.class)
			.satisfies(e -> assertThat(e.getMessage())
				.contains("0x4b90")
				.contains("registered twice"));
	}
}
