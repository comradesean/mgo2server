package mgo2server.common.service;

import mgo2server.common.ServicesFactory;
import mgo2server.TestDatabase;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Storage and display are different things.
 * <p>
 * [OBSERVED 2026-07-27] A clan whose emblem had been deleted reported no emblem through the flag
 * and then served the full 768 bytes to anything that asked for the picture, because the fetch
 * selected on {@code emblem is not null} and never looked at the mode. The emblem stayed on Player
 * Details -> More Details across a full logout and login while the clan screen correctly showed
 * nothing — one server, two answers.
 * <p>
 * [ELF] Mode 3 is the client's own "on display" constant ({@code 0xAD4724}); 2 and 4 reach neither
 * the flag nor the bitmap copy, so they mean stored-but-not-shown.
 */
public class ClanEmblemIT {
	private static ClanService clanService;

	private static final byte[] IMAGE = image();

	private static byte[] image() {
		var bytes = new byte[768];
		Arrays.fill(bytes, (byte) 0x5a);
		return bytes;
	}

	@BeforeAll
	public static void setUp() {
		clanService = ServicesFactory.createServices(TestDatabase.get().jdbi()).getClanService();
	}

	private static long clanWithEmblemMode(int mode) {
		var id = TestDatabase.get().jdbi().withHandle(handle -> handle
			.createUpdate("insert into clan (name) values (:name)")
			.bind("name", "e" + System.nanoTime() % 100000000L)
			.executeAndReturnGeneratedKeys("id")
			.mapTo(Long.class)
			.one());
		clanService.setEmblem(id, IMAGE, mode);
		return id;
	}

	@Test
	public void servesTheEmblemWhenItIsOnDisplay() {
		var clan = clanWithEmblemMode(ClanService.EMBLEM_ON_DISPLAY);

		assertThat(clanService.emblemFlagOf(clan)).isEqualTo(ClanService.EMBLEM_ON_DISPLAY);
		assertThat(clanService.emblemOf(clan)).contains(IMAGE);
	}

	/** The regression. Both modes must answer the same way, and it must match the flag. */
	@Test
	public void servesNothingForAStoredButUndisplayedEmblem() {
		for (var mode : new int[] { 2, 4 }) {
			var clan = clanWithEmblemMode(mode);

			assertThat(clanService.emblemFlagOf(clan))
				.as("mode %d must not report as on display", mode)
				.isNotEqualTo(ClanService.EMBLEM_ON_DISPLAY);
			assertThat(clanService.emblemOf(clan))
				.as("mode %d must not be served", mode)
				.isEmpty();
		}
	}

	/**
	 * The image survives the mode change. A non-display mode looks like the editor's Save, so
	 * discarding the bytes would destroy work the player expects to be able to put back on display.
	 */
	@Test
	public void keepsTheImageWhenItIsTakenOffDisplay() {
		var clan = clanWithEmblemMode(ClanService.EMBLEM_ON_DISPLAY);
		clanService.setEmblem(clan, IMAGE, 4);
		assertThat(clanService.emblemOf(clan)).isEmpty();

		clanService.setEmblem(clan, IMAGE, ClanService.EMBLEM_ON_DISPLAY);
		assertThat(clanService.emblemOf(clan)).contains(IMAGE);
	}

	@Test
	public void servesNothingForAClanThatNeverUploadedOne() {
		var clan = TestDatabase.get().jdbi().withHandle(handle -> handle
			.createUpdate("insert into clan (name) values (:name)")
			.bind("name", "n" + System.nanoTime() % 100000000L)
			.executeAndReturnGeneratedKeys("id")
			.mapTo(Long.class)
			.one());

		assertThat(clanService.emblemFlagOf(clan)).isZero();
		assertThat(clanService.emblemOf(clan)).isEmpty();
	}
}
