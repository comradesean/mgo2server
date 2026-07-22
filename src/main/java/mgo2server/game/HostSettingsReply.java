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
 * the stored request-shaped blob into the reply shape. The {@code 0x4305} parser has not been
 * located in the ELF; until the populated path is verified against a live client, treat a
 * Create-Game hang after a settings save as this class's prime suspect — the empty path (128
 * zero bytes) is the known-good fallback.
 */
public final class HostSettingsReply {
	/** Reply size Nomad allocates: result word plus the settings structure. */
	public static final int SIZE = 0x163;

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
		// The request's subtype byte at 0xA2 is not replayed. Rotation: 15 [rule, map, flags]
		// triples; the reader stops at the first rule==0 && map==0, so trailing zeros are inert.
		copy(out, 0x0A6, blob, 0xA3, 0x2D);
		// 0x0D3..0x0D8 zero padding.
		copy(out, 0x0D8, blob, 0xD5, 0x10);  // weapon restrictions
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
		// 0x148 zero.
		copy(out, 0x149, blob, 0x146, 1);    // idle kick
		// 0x14A zero.
		copy(out, 0x14B, blob, 0x148, 1);    // team-kill kick
		copy(out, 0x14C, blob, 0x149, 1);    // capture extra time
		copy(out, 0x14D, blob, 0x14A, 1);    // sneaking-mission Snake side
		copy(out, 0x14E, blob, 0x14B, 8);    // sdm t/r, int t, dm r, scap t/r, race t/r
		// 0x156 zero.
		copy(out, 0x157, blob, 0x154, 1);    // extra-time flags
		copy(out, 0x158, blob, 0x155, 1);    // host options (bit 1 = non-stat)
		// 0x159..0x163 zero.

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
