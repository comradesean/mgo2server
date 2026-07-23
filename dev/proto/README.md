# Kaitai Struct specs for the lobby protocol

Machine-checkable byte layouts for selected commands, one `.ksy` per packet payload
(the decrypted payload after the 24-byte header / XOR / Blowfish transport layer —
see `dev/docs/CRYPTO.md`). PROTOCOL.md remains the narrative: evidence, history, and
why; these files are the byte-level truth, and the compiler enforces that every byte
belongs to exactly one declared field.

Conventions:

- Every field carries a `doc:` with a confidence tag — **[CONFIRMED]** (capture-proven
  live), **[INFERRED]** (structural or offset-mirror reasoning), **[UNKNOWN]** (position
  exact from the client parser, meaning unestablished; the fingerprint value sent and
  whether it surfaced on screen is recorded).
- `T+0x...` in docs is the client-side struct destination, from the ELF parser traces.
- Unknown regions are named `unknown_*` — an explicit state, not an omission.

To view a capture against a spec, load both into the Kaitai WebIDE
(https://ide.kaitai.io). To compile (generates parsers, validates structure):

    kaitai-struct-compiler -t python --outdir /tmp/out *.ksy

Specs (pilot, 2026-07-23): the `0x4102` personal-stats burst —
`mgo2_cmd_4103.ksy` (character info, 648 B), `mgo2_cmd_4105.ksy` (per-mode grid,
584 B, sent once per period page), `mgo2_cmd_4107.ksy` (personal scores, 588 B,
terminal) — the social family: `mgo2_cmd_4682.ksy` (met-players history record, 25 B),
`mgo2_cmd_4686.ksy` (match-detail record, 93 B), `mgo2_cmd_4221.ksy` (player-details card,
201 B single reply) — and the first client→server frame, `mgo2_cmd_4390.ksy` (the host's
end-of-round stat report, 167 B long form / ~51 B short form; what `round_report` stores).

List-triple start/end packets (`0x4601`/`0x4603`, `0x4681`/`0x4683`, `0x4685`/`0x4687`)
are not specced separately: each is a single u32 **result code**, 0 for success in both
start and end — never a count; the client counts item records itself. Sending a count
there produced the `1032:00000005` error (OBSERVED.md).
