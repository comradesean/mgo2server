meta:
  id: mgo2_cmd_4b4c_c2s
  title: "MGO2 0x4b4c — fetch a clan's emblem, in-game variant (client -> server)"
  endian: be
doc: |
  **The third emblem fetch.** 4-byte payload: the clan id whose emblem is wanted. Reply is
  `0x4b4d`, `{s4 result, byte[768]}` — the same shape as `0x4b49` and `0x4b4b`.

  ## Correction: this command DOES carry a payload

  [CORRECTED 2026-07-29] `PROTOCOL.md` recorded `0x4b4c` as having **no request payload**,
  and this server answered it with the *requester's own* clan regardless of what was asked.
  Both were wrong.

  The sender is `0xD56618`, and it is built byte-for-byte like `0x4b4a`'s sender
  `0xD56704`: it spills its clan-id argument with `stw r4,1416(r1)` at `0xD56644` and passes
  it to the unsigned-u32 serializer `bl 0xD5C9BC` at `0xD5669C`, between the builder
  `0xD5CF40` and the seal `0xD5C828`. All **three** emblem fetches append a u32 clan id —
  `0xD57838` (`0x4b48`), `0xD56704` (`0x4b4a`), `0xD56618` (`0x4b4c`).

  ## Why it exists separately from 0x4b4a

  The two are the same request against different reply buffers, and the client picks between
  them by **round mode**. `0x9C2918` returns 1 iff the mode (`0x6A9A38`) is 9; at `0x9D47C0`
  that installs the OPD triple `{0xD56618, 0xD54AA0, 0xD546AC}` and the `conn+0xFBC9` buffer
  (field 103), versus `{0xD56704, ...}` and `conn+0xF8C7` (field 102) otherwise. Reply
  parsers are `0xD59DA0` (`0x4b4d`) and `0xD59EBC` (`0x4b4b`); both `memset` 769 bytes, read
  the `s4`, and on result `== 0` read 768 raw bytes with `0xD5D018`.

  **Mode 9 is not identified by name in the binary.** `GATES.md` enumerates rules 0-8 only,
  and `0x6A9A38` is compared against 0-10 across 192 sites. So which round type routes the
  fetch through this command rather than `0x4b4a` is [UNKNOWN] — it is simply not decidable
  from the ELF.

  ## Serve any clan, not just the caller's

  The in-game emblem manager `0x9D4500` walks **all 24 player slots** and, for each occupied
  slot with a non-zero clan id that passes the flag test at `0x9C2C00`, issues a fetch keyed
  on **that peer's** clan id. Results are cached 30 deep at `0x166F8F4` (stride 776,
  `{u32 clanId, byte[768], pad}`).

  So a server that resolves the clan from the session instead of the payload hands every
  peer the wrong picture, and hands a clanless viewer nothing at all. Contrast `0x4b48`,
  which genuinely can only ask for the caller's own clan because its id comes out of the
  caller's own cached record.

  ## What the 768 bytes must contain

  Not an opaque blob: the decoder is `0xA9B3E8` and it validates. `"EMBD"` magic at +0
  (`memcmp` at `0xA9B458` against `0xE1E6A8`); a byte at +4 that must be **signed-negative**,
  i.e. high bit set (`0xA9B470`); 16 RGB palette entries at +5; 512 bytes of packed 4-bit
  palette indices, high nibble first, at +53 (unrolled at `0xA9B718`). 1024 pixels against a
  width asserted `== 32` at `0xA9B744` — a **32x32, 16-colour** image. Bytes 565..767 are
  padding.

  A block failing either check is dropped **silently**; there is no error dialog on this
  path, only the 6000-tick backoff at `0x9D4A34`.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-29] The clan whose emblem is wanted — chosen by the caller, so
      routinely a clan the requester has nothing to do with. Position and width exact
      (unsigned, `0xD5C9BC`); the sender does not validate it.

      A clan with no stored emblem should be answered with result 0 and 768 zeros, which the
      parser accepts — its only requirement is the length. To refuse deliberately, the
      sanctioned code is **`-1230`**, which the client renders as *"Use of the clan emblem is
      currently forbidden."* (id 24065).
