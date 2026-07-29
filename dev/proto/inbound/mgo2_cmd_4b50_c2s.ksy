meta:
  id: mgo2_cmd_4b50_c2s
  title: "MGO2 0x4b50 — upload clan emblem (client -> server)"
  endian: be
doc: |
  **The clan emblem upload.** 769-byte payload: one u8 `mode` followed by the 768-byte
  emblem block. Reply is `0x4b51`, a bare u32 result.

  [CONFIRMED 2026-07-27] Sender 0xD5804C, reached from the emblem screen through **task
  kind 25**. The 768 bytes are the **clan emblem** — the same block that comes back in
  `0x4b49`, `0x4b4b` and `0x4b4d`. On success the client copies the block to
  `profile+6873` and sets `profile+6872` to the mode it just sent, so the client's own
  "does my clan have an emblem" flag is whatever the server accepted.

  **Correction.** This block was previously called an unknown fixed table, and elsewhere in
  the repo it was briefly filled with pending applicant names on a "768 = 48 x 16" theory.
  That was writing text into the client's emblem buffer. The block is an emblem; its
  *internal* encoding is still [UNKNOWN] and does not need to be known, because the block
  only ever round-trips — stored verbatim on upload, returned verbatim on fetch.

  ## Modes

  Mode 3 is "put on display" and is the **only** mode the client post-processes. Modes 2 and
  4 also occur and are [UNKNOWN]. All three are stored; the mode becomes the emblem flag the
  server reports back at `profile+6872` and at `T+0x378` in the profile replies, which is
  how the two sides stay in agreement about whether the clan has an emblem to show.

  ## No privilege bit gates this

  [CONFIRMED 2026-07-27] The commit gate is `0xAD409C`, which tests `ctx+788 & 4` — a bit
  set purely from **membership state 2**, the leader. The privilege word at `profile+6838`
  is not involved: granting a leader all sixteen bits did not unlock Apply Emblem, put a "!"
  badge on the clan, and sent the client into a ~73 ms poll loop re-sending `0x4b46`
  (`0xAB0074` ands the word with -1, or -257 for a leader at `0xAB004C`, and returns without
  advancing its state machine if anything survives). Bit 8 alone — the one bit -257 tolerates
  — produced the badge and no new menu row, and emblem loading worked with or without it, so
  it is a pending-notification bit. Send that word as zero. See mgo2_cmd_4b46_c2s.ksy.

  So a missing "Apply" row is never a permissions problem on this build; it is the emblem
  flags (`T+0x76` work-in-progress, `T+0x378` published) or membership state.

  ## Refusing an upload

  `0x4b51`'s result is routed at `0xA7E410`. Refusing a re-display inside a cooldown uses
  -1216, "A fixed amount of time must pass in order for the emblem to be updated." Other
  codes on this op: -1215 "Use of the clan emblem is currently forbidden", -1218 "You do not
  have emblem editing rights", -1207 "Unable to locate designated clan", -1202 "Unable to
  update clan emblem".

  **Caveat, unresolved.** An earlier trace concluded that only -1207 and -1202 reach a dialog
  and that every other value memsets the client's 768-byte emblem buffer, destroying work in
  progress. A later, deeper trace could not reproduce that: every branch of the dispatcher
  reaches a dialog, and neither it nor the `0x4b51` handler (`0xD555D4`) contains a memset —
  so the wipe, if it happens, lives in the emblem screen's event-104 consumer, which nobody
  has located. If a refusal is ever seen to clear a work-in-progress emblem, fall back to
  -1202.

  The display cooldown itself is **operator policy**, not protocol: nothing client-side
  enforces it on this build (the emblem can be re-displayed immediately), the countdown
  string 17247 is orphaned, and `0x4b21`'s `T+0x48` was tried as its driver and eliminated.

  Evidence (ELF, retail BLUS30109): sender 0xD5804C. Builder `bl 0xD5CF40` at 0xD580CC
  (`li r4,0x4b50` at 0xD580C8), then `bl 0xD5C8A0` at 0xD580DC (u8, from stack 1440 = the
  sender's r5 parameter, spilled at 0xD58074) and `0xD5D0AC(pkt, r4_param, 0x300)` at
  0xD580F0, then the seal `bl 0xD5C828` at 0xD580FC and the flush `bl 0xD34CC0` at 0xD5810C.
  Note the argument order is inverted relative to the C signature: the *second* argument
  (r5, the u8) is written first, the pointer's contents second.

  Preconditions: session != NULL and the pointer != NULL — that is all; no clan-record gate
  and no validation of the 768 bytes, so the leader check is entirely the screen's and the
  server's. On success the flow state advances via `0xD32E08(session, 104, 1)`.

  This file stays a draft only because `mode` is not fully enumerated.
  ## The 768 bytes are a decoded image format — and a blob we should KEEP

  **`EMBD`, 32x32, 16 colours.** Decoder `0xA9B3E8`, the only one in the image (17 call sites):

  | offset | size | meaning |
  | --- | --- | --- |
  | 0 | 4 | magic, `memcmp` against `"EMBD"` (string `0xE1E6A8`, compare `0xA9B458`) |
  | 4 | 1 | must be **signed-negative**, i.e. high bit set (`extsb` / `bge -> fail`, `0xA9B470`) |
  | 5 | 48 | **16 palette entries**, 3 bytes RGB each, expanded to `0xRRGGBBFF` (`0xA9B47C`-`0xA9B6E4`) |
  | 53 | 512 | **packed 4-bit palette indices, high nibble first** (unrolled 512x at `0xA9B718`) |
  | 565 | 203 | unused padding |

  512 packed bytes are 1024 pixels, and the target texture width is asserted `== 32` at `0xA9B744`.
  A block failing either check is dropped **silently** — the in-game path has no error dialog, only
  a 6000-tick backoff at `0x9D4A34`. Verified against a live upload, which begins `45 4D 42 44 80`.

  **Why this one stays a blob, deliberately.** The project's standing goal is no blobs and every byte
  typed, and this is the documented exception rather than an oversight:

  - It is an **image**, not a structure. Decoding it into palette and pixel columns would let us
    validate an upload, but the bytes have no server-side meaning to reason about — nothing queries
    a clan by its emblem's third palette entry.
  - It is a true **round trip**: the client authors it in its own editor and the client renders it.
    Neither side asks us to interpret it, and both parsers NUL-terminate at +768 into a 769-byte
    buffer without inspecting the contents.
  - Knowing the format is what makes keeping it a *choice*. The failure this project cares about is
    storing bytes we cannot describe; these are fully described and simply not worth exploding.

  If validation is ever wanted, the two cheap checks are the magic and the high bit at +4 — those are
  exactly what the client tests, and a block failing them disappears with no diagnostic.

  **Do not confuse the `"%s/%s%d.emb"` string (`0xE1E680`) with a network path.** It sits in the
  emblem *editor*'s literal pool beside `"clanemblem"`, `"emblemeditor"` and `"brush_x1"`, with
  "not enough space on the hard disk" errors around it — it is the local save path for the editor's
  work in progress. There is no URL anywhere on the emblem path.

seq:
  - id: mode
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] What the client will set its own emblem flag to on success —
      the value that ends up at `profile+6872`. **3 = put on display**, and the only value
      the client post-processes. 2 and 4 also occur and their meanings are [UNKNOWN]; "save
      without displaying" and "clear" are both consistent with what has been seen and
      nothing distinguishes them yet.

      Position and width exact (0xD5C8A0, 1 byte). The sender's r5 parameter, unvalidated —
      it will send whatever the screen passes.
  - id: emblem
    size: 768
    doc: |
      [CONFIRMED 2026-07-27] The clan emblem, exactly 768 bytes (0x300), `memcpy`'d from the
      caller's buffer by 0xD5D0AC with no inspection by the sender (0xD580E4..0xD580F0).
      The same 768 bytes come back in `0x4b49`/`0x4b4b`/`0x4b4d` and land at
      `profile+6873`.

      **Internal structure [UNKNOWN] and deliberately not modelled.** No count field precedes
      it and no stride is evidenced; the "768 = 48 x 16 so it is a name table" reading was
      tried and was wrong. Store and return it verbatim. Recovering the encoding means
      tracing what the emblem editor writes into the caller's buffer, not slicing the wire
      format.

      Typed as raw bytes on purpose. The client NUL-terminates the block at +768 into a
      769-byte buffer, which is why code that handles it as a string does not crash, but the
      content is not text.
