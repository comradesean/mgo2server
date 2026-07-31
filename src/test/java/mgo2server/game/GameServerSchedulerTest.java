package mgo2server.game;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The periodic task on {@link GameServer}.
 *
 * <p>This is the first timer in the server, added for automatching: a searching client sends nothing
 * at all while it waits, so nothing on the request path can advance a search. Everything asserted
 * here is a property that is silently absent if the scheduling call is written the obvious way.
 *
 * <p>No database and no client — the server binds an ephemeral port with no controllers, which is
 * enough to exercise start and stop.
 */
public class GameServerSchedulerTest {

	/** Short enough that the tests are quick, long enough not to be flaky on a loaded machine. */
	private static final Duration INTERVAL = Duration.ofMillis(50);

	private static final long TIMEOUT_SECONDS = 5;

	private GameServer server;

	@AfterEach
	public void teardown() {
		if (server != null) {
			server.stop(0L, 0L, TimeUnit.SECONDS).join();
		}
	}

	@Test
	public void theTaskRunsRepeatedlyOnceThePortIsBound() throws InterruptedException {
		var ran = new CountDownLatch(3);
		server = new GameServer(List.of(), 0,
			new GameServer.PeriodicTask("test", INTERVAL, ran::countDown));

		server.start().join();

		assertThat(ran.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
			.as("the task should run again and again, not once")
			.isTrue();
	}

	/**
	 * The one that matters most, and the reason the body is wrapped rather than passed straight to
	 * the executor: a scheduled task that throws is cancelled <b>permanently and silently</b>. Left
	 * unwrapped, a single transient database error would stop matchmaking for the life of the
	 * process with nothing in the log to explain it.
	 */
	@Test
	public void aThrowingTaskKeepsRunning() throws InterruptedException {
		var runs = new AtomicInteger();
		var thirdRun = new CountDownLatch(3);
		server = new GameServer(List.of(), 0, new GameServer.PeriodicTask("throwing", INTERVAL, () -> {
			runs.incrementAndGet();
			thirdRun.countDown();
			throw new IllegalStateException("deliberate");
		}));

		server.start().join();

		assertThat(thirdRun.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
			.as("throwing must not cancel the schedule")
			.isTrue();
	}

	/**
	 * {@code stop()} must not return while a run is still in flight.
	 * <p>
	 * The integration suite stops a server and the next test truncates the database. A run that
	 * outlives its server would fail in a <em>different</em> test class, against a schema that no
	 * longer exists — the kind of failure nobody attributes to the right cause.
	 */
	@Test
	public void stopWaitsForTheTaskToStop() throws InterruptedException {
		var started = new CountDownLatch(1);
		var running = new AtomicInteger();
		server = new GameServer(List.of(), 0, new GameServer.PeriodicTask("slow", INTERVAL, () -> {
			running.incrementAndGet();
			started.countDown();
			try {
				Thread.sleep(200);
			} catch (InterruptedException e) {
				// shutdownNow interrupts, which is how a long run is cut short rather than waited out.
				Thread.currentThread().interrupt();
			}
			running.decrementAndGet();
		}));
		server.start().join();

		assertThat(started.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)).isTrue();
		server.stop(0L, TIMEOUT_SECONDS, TimeUnit.SECONDS).join();

		// Nothing is executing by the time stop() has returned, which is the whole guarantee.
		assertThat(running.get()).as("nothing may still be executing once stop() has returned").isZero();
		server = null;
	}

	/** A server with no periodic task must start and stop exactly as it always has. */
	@Test
	public void aServerWithoutATaskIsUnaffected() {
		server = new GameServer(List.of(), 0);

		server.start().join();

		assertThat(server.boundPort()).isPositive();
		server.stop(0L, 0L, TimeUnit.SECONDS).join();
		server = null;
	}
}
