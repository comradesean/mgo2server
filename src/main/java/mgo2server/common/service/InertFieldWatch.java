package mgo2server.common.service;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.jdbi.v3.core.Jdbi;

import java.util.HexFormat;

/**
 * Watches the fields we believe the client never reads, and says so when one moves.
 *
 * <p><b>Why this exists.</b> Several bytes of the host-settings block are established as
 * parsed-and-never-read — either no reader exists in the binary, or the only consumer is an accessor
 * nothing calls. We echo them, because inventing a value for a field we cannot explain is how this
 * project has previously lost days. But <em>"this build never reads it"</em> is a claim about
 * <b>one</b> build, and the plan is to serve later versions behind toggles. When a patched client
 * starts using one of these, that should arrive as a log line, not as a bug report months later.
 *
 * <p><b>It records every distinct value rather than checking a baseline.</b> A field that is
 * genuinely fixed accumulates exactly one row; a second row <em>is</em> the alert. Nothing has to be
 * maintained, and a hardcoded expectation — which quietly becomes wrong the first time reality
 * disagrees — cannot drift.
 *
 * <p><b>Already useful before it was finished.</b> Live data shows {@code unread_824} and
 * {@code unread_931} co-varying: six stored rows carry the pair {@code (0x02000000, 0x20)} and five
 * carry {@code (0, 0)}. Two fields with no reader moving in lockstep is not noise, and it was
 * invisible while those bytes sat inside a blob.
 *
 * <p>Failures here are swallowed deliberately. This is an observation tool; a watcher that can break
 * the thing it watches is worse than no watcher.
 */
public class InertFieldWatch {
	private static final Logger logger = LogManager.getLogger();

	private final Jdbi jdbi;

	public InertFieldWatch(Jdbi jdbi) {
		this.jdbi = jdbi;
	}

	/** A field to watch: a name, and where its bytes live in the host-settings block. */
	public record Field(String name, int offset, int length) {
	}

	/**
	 * The host-settings fields established as unread by this client build.
	 *
	 * <p>Offsets are into the {@code 0x4310} block. Each carries the reason it is here, because a
	 * watcher whose entries cannot be justified becomes noise that gets muted.
	 */
	private static final Field[] HOST_SETTINGS = {
		// Parsed and pushed into the client's own property store; the only consumers are accessors
		// with no callers and no address references anywhere in the image.
		new Field("host_settings.800", 0xD3, 1),
		new Field("host_settings.801", 0xD4, 1),
		// No reader anywhere in the binary. 824 and 931 are the pair seen co-varying.
		new Field("host_settings.824", 0xEA, 4),
		new Field("host_settings.832", 0xEE, 2),
		new Field("host_settings.836", 0xF0, 4),
		new Field("host_settings.844", 0xF4, 2),
		// Low byte of the flags word at +928; every bit test in the client lands in bits 8-23.
		new Field("host_settings.931", 0x144, 1),
		// One raw 14-byte block. No client reader for any byte of it — though the server does decode
		// the host-options flags out of byte 10, so it is unread rather than unused.
		new Field("host_settings.tail", 0x14B, 14),
	};

	/** Records the current value of every watched field in a {@code 0x4310} block. */
	public void observeHostSettings(byte[] blob) {
		if (blob == null) {
			return;
		}
		for (var field : HOST_SETTINGS) {
			if (field.offset() + field.length() <= blob.length) {
				observe(field.name(),
					java.util.Arrays.copyOfRange(blob, field.offset(), field.offset() + field.length()));
			}
		}
	}

	/**
	 * Records one observation, and logs when a field turns out not to be constant after all.
	 *
	 * <p>The log fires on the <b>second</b> distinct value, not the first: the first is simply the
	 * baseline being established, and warning about it would train everyone to ignore this.
	 */
	public void observe(String field, byte[] value) {
		var hex = HexFormat.of().formatHex(value);
		try {
			var distinct = jdbi.withHandle(handle -> {
				handle.createUpdate("""
						insert into inert_field_watch (field, value_hex) values (:field, :hex)
						on conflict (field, value_hex) do update set
							last_seen = now(), observations = inert_field_watch.observations + 1
						""")
					.bind("field", field)
					.bind("hex", hex)
					.execute();
				return handle.createQuery(
						"select count(*) from inert_field_watch where field = :field")
					.bind("field", field)
					.mapTo(Integer.class)
					.one();
			});

			if (distinct > 1) {
				logger.warn("INERT FIELD MOVED: {} now has {} distinct values (latest {}). This field"
					+ " was believed unread by the client — if a patched build is in play, it may be"
					+ " live now. See dev/docs/OBSERVED.md and the inert_field_watch table.",
					field, distinct, hex);
			}
		} catch (Exception e) {
			// An observation tool must never break what it observes.
			logger.debug("Could not record inert-field observation for {}.", field, e);
		}
	}
}
