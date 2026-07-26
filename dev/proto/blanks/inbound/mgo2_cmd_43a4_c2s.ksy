meta:
  id: mgo2_cmd_43a4_c2s
  title: "MGO2 0x43a4 — in-match per-player list report (client -> server)"
  endian: be
doc: |
  Builder function `0xD41940` = `f(ctx, u32 a, void *entries, u32 count)`; `entries` null aborts
  (`0xD41984`) and **`count > 127` aborts** (`cmplwi cr7,r0,127; bgt` at `0xD419BC`), so the
  client will never send more than 127 records. `bl 0xD5CF40` at `0xD419E0`
  (`li r4,0x43A4` at `0xD419DC`), seal `0xD5C828` at `0xD41A50`, flush `0xD34CC0` at `0xD41A60`.
  Not encrypted.

  Writes: `0xD5C9BC` (u32) at `0xD419F0` from `r1+1464`; `0xD5C95C` (u32) at `0xD41A00` from
  `r1+1480` — the count; then a loop (`0xD41A0C`-`0xD41A4C`) of `0xD5C8A0` (u8) from `entry+0`
  and `0xD5C918` (u16) from the low half of `entry+4`, with the source cursor `r31` advancing
  **12 bytes** per record while the wire consumes only 3.

  **Total payload 8 + 3*count bytes.** Unlike `0x4398`, the count IS on the wire here (the loop
  bound is re-read from `r1+1480` each pass at `0xD41A34`), so a reader should use the field, not
  end-of-stream. Recording that distinction because mixing the two up has bitten this project.

  Meaning: unestablished. `COMMANDS.md` lists `0x43A4` as a sendable, unanswered gap in the
  in-match family and `PROTOCOL.md` only names it in the same list. Reply id `0x43A5`
  (a "result single" the client parses) — so an unanswered `0x43A4` is a latent `FFFFFF60`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_00
    type: u4
    doc: "[UNKNOWN] 0x00. Second argument of `0xD41940`, staged at `r1+1464` and written verbatim. By analogy with the rest of the in-match family a character or game-scoped id, but unvalidated and unproven."
  - id: count
    type: u4
    doc: "[ELF] 0x04. Record count, client-capped at 127. **On the wire** — the loop re-reads it from `r1+1480` every pass."
  - id: entries
    type: entry
    repeat: expr
    repeat-expr: count
    doc: "[ELF] 0x08.. — `count` x 3 bytes. Source stride is 12 bytes; only 3 of each 12 reach the wire."
types:
  entry:
    seq:
      - id: unknown_00
        type: u1
        doc: "[UNKNOWN] +0x00, from `entry+0x00`."
      - id: unknown_01
        type: u2
        doc: "[UNKNOWN] +0x01, from the low 16 bits of the u32 at `entry+0x04` (loaded with `lwz`, stored through a `sth` staging slot at `0xD41A28` — so the top half is truncated away, which is itself evidence the source field is logically 16-bit)."
