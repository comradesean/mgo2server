package mgo2server.game;

import io.netty.buffer.ByteBuf;

/**
 * Builds the populated {@code 0x4305} reply — the saved host settings the Create Game screen
 * pre-fills with — from the raw {@code 0x4310} blob the client itself pushed last time.
 * <p>
 * <b>Provenance: reference (tier 4), not the binary.</b> The layout is transcribed from
 * GHzGangster/Nomad's {@code Hosts.getSettings()} (fetched 2026-07-22 at the user's request),
 * which served real retail clients. The reply is <em>not</em> the request blob echoed back: the
 * field set matches, but the reply drops the subtype byte, inserts two constants ({@code 0x02} at
 * {@code 0x0ED}, {@code 0x20} at {@code 0x147}) and re-bases every offset, so this class re-maps
 * the stored request-shaped blob into the reply shape. <b>Live-verified 2026-07-22</b>: a real
 * client re-opened Create Game pre-filled from this reply, and the two injected constants came
 * back in its next {@code 0x4310} push at the matching request offsets — so the client parses
 * this layout and stores those fields (see OBSERVED.md, "Where the Common Settings toggles
 * live"). The empty path (128 zero bytes) remains the fallback for a character with nothing
 * saved.
 * <p>
 * <b>Known divergence, chosen deliberately: this class echoes the client's own bytes where Nomad
 * reconstructs them.</b> Nomad round-trips the blob through parsed JSON and its reply therefore
 * fabricates several values we replay verbatim instead: it forces {@code commonA |= 0b100} (bit 2
 * always set — note our own {@code 0x4302} game-list entry does the same), drops {@code commonA}
 * bits 1/6 and {@code commonB} bit 5, derives {@code wr[10]} from the suppressor bit instead of
 * echoing it, zeroes the idle/team-kill kick counts when their enable bits are off, and zeroes
 * the whole password block when the password flag is off. Echoing raw is the safer bet while the
 * {@code 0x142}/{@code 0x143} byte meaning is contested (see BACKLOG, "The 0x4310 byte
 * 0x142/0x143 conflict") — the client sent these bytes, so replaying them cannot invent state,
 * whereas canonicalising on Nomad's decode would bake in the contested reading. If the capture
 * pass confirms Nomad's map and the client misbehaves on the raw echo, canonicalise here.
 */
public final class HostSettingsReply {
	/**
	 * Payload size: the parser's last read ends here.
	 * <p>
	 * <strong>Trimmed 2026-07-26 from {@code 0x163} (355), which was Nomad's allocation.</strong>
	 * The parser at {@code 0xD4548C} is straight-line: 46 reads plus the 16-iteration rotation
	 * loop, ending with one opaque 14-byte read at wire {@code 0x14e..0x15b}. There is no read
	 * after {@code 0x15B}, so the payload is {@code 0x15C} = 348 bytes and the seven bytes we used
	 * to append were never looked at. They did no harm — the read primitives bound-check the
	 * 1023-byte receive buffer, not the payload length, and nothing here calls the
	 * cursor-vs-length test {@code 0xD5CEB0} — but 355 was a reference server's struct length, not
	 * this client's packet length. See {@code dev/proto/outbound/mgo2_cmd_4305_s2c.ksy}.
	 */
	public static final int SIZE = 0x15C;

	/** The lowest blob length carrying every field this mapping reads. */
	private static final int MIN_BLOB = 0x156;

	private HostSettingsReply() {
	}

	/** Whether a stored blob is long enough to transcode; shorter blobs fall back to zeros. */
	public static boolean canWrite(byte[] blob) {
		return blob != null && blob.length >= MIN_BLOB;
	}

	public static void write(ByteBuf buffer, byte[] blob) {
		var out = new byte[SIZE];

		// result u32 stays zero at 0x000.
		copy(out, 0x004, blob, 0x00, 0x10);  // name
		copy(out, 0x014, blob, 0x10, 0x80);  // comment
		copy(out, 0x094, blob, 0x90, 0x11);  // password: enabled flag + password[15] + pad
		copy(out, 0x0A5, blob, 0xA1, 1);     // dedicated
		// The request's subtype byte at 0xA2 is not replayed. Rotation: SIXTEEN {rule, map, flags}
		// triples = 48 bytes, wire 0x0A6..0x0D5.
		//
		// Corrected 2026-07-26 from 15 (0x2D bytes). Four independent sources say 16: the 0x4305
		// parser's own loop (cmpdi r27,16 at 0xD45648), the 0x4310 writer's (cmpdi cr7,r27,16 at
		// 0xd44958, which always emits all sixteen), GameDetails.ROUNDS = 16 for the 0x4313 reply,
		// and mgo2_cmd_4305_s2c.ksy. The 15 came from a reference server, and the defence for it —
		// "the reader stops at the first rule==0 && map==0" — is reference-derived and contradicted
		// by the writer. At 15 a host with a full rotation lost its last round on the Create Game
		// pre-fill, and the request's two bytes at 0xD3/0xD4 were dropped with it.
		copy(out, 0x0A6, blob, 0xA3, 0x30);
		// 0x0D6..0x0D8 zero padding.
		// Weapon restrictions, echoed opaquely (1 bit per item, 1 = locked; bit 0 of the first
		// byte is the enable). The per-weapon bit map — 19 bits capture-confirmed on this build,
		// the rest expansion-era per Nomad — is in PROTOCOL.md, "Weapon restrictions".
		copy(out, 0x0D8, blob, 0xD5, 0x10);
		copy(out, 0x0E8, blob, 0xE5, 1);     // max players
		copy(out, 0x0E9, blob, 0xE6, 4);     // briefing time
		out[0x0ED] = 0x02;                   // constant Nomad writes; meaning unknown
		// 0x0EE..0x0F9 zero padding.
		copy(out, 0x0F9, blob, 0xF6, 1);     // stance
		copy(out, 0x0FA, blob, 0xF7, 1);     // level-limit tolerance
		copy(out, 0x0FB, blob, 0xF8, 4);     // level-limit base (u32, per Nomad — see BACKLOG)
		copy(out, 0x0FF, blob, 0xFC, 17 * 4); // per-rule timers/rounds/tickets
		copy(out, 0x143, blob, 0x140, 2);    // unique characters red/blue
		copy(out, 0x145, blob, 0x142, 1);    // commonA
		copy(out, 0x146, blob, 0x143, 1);    // commonB
		out[0x147] = 0x20;                   // commonC: constant in Nomad, request byte ignored
		// Kick timers are u16 on both sides, corrected 2026-07-26. The request writes them as
		// halfwords at 0x145/0x147 (0x4310 sender, 0xd44bf8/0xd44c0c) and the 0x4305 parser reads
		// u16 at 0x148/0x14a (block +180/+182). Nomad's map copies one byte into each destination's
		// LOW half and leaves the high half zero, which is identical for values <= 255 and drops
		// the high byte above — a third instance of the same truncation as GameService and
		// GameDetails. See dev/proto/outbound/mgo2_cmd_4305_s2c.ksy.
		copy(out, 0x148, blob, 0x145, 2);    // idle kick (u16)
		copy(out, 0x14A, blob, 0x147, 2);    // team-kill kick (u16)
		copy(out, 0x14C, blob, 0x149, 1);    // capture extra time
		copy(out, 0x14D, blob, 0x14A, 1);    // sneaking-mission Snake side
		copy(out, 0x14E, blob, 0x14B, 8);    // sdm t/r, int t, dm r, scap t/r, race t/r
		// 0x156 zero.
		copy(out, 0x157, blob, 0x154, 1);    // extra-time flags
		copy(out, 0x158, blob, 0x155, 1);    // host options (bit 1 = non-stat)
		// 0x159..0x15B zero — the tail of the parser's final 14-byte opaque read at 0x14E.

		buffer.writeBytes(out);
	}

	/** Copies what the blob actually holds; a short blob leaves the destination zeroed. */
	private static void copy(byte[] out, int dst, byte[] blob, int src, int length) {
		var available = Math.max(0, Math.min(length, blob.length - src));
		if (available > 0) {
			System.arraycopy(blob, src, out, dst, available);
		}
	}
}
