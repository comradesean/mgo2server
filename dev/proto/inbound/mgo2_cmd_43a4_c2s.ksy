meta:
  id: mgo2_cmd_43a4_c2s
  title: "MGO2 0x43a4 — host's per-skill experience report (client -> server)"
  endian: be
doc: |
  **IDENTIFIED 2026-07-29 [ELF], confirmed live the same day.** Was titled "in-match per-player
  list report" with every field `[UNKNOWN]`. It is the client reporting **per-skill experience**,
  and it is the ONLY route by which skill progression can persist: skills level by *use*, the
  server cannot observe use, so the client has to tell us. Until this was handled, every
  character's skill levels were frozen at whatever creation granted them.

  Serializer `0xD41940` = `f(ctx, u32 charaId, void *entries, u32 count)`; `entries` null aborts
  (`0xD41984`) and **`count > 127` aborts** (`cmplwi cr7,r0,127; bgt` at `0xD419BC`).
  `bl 0xD5CF40` at `0xD419E0` (`li r4,0x43A4` at `0xD419DC`), seal `0xD5C828` at `0xD41A50`,
  flush `0xD34CC0` at `0xD41A60`. Not encrypted.

  ## Where the numbers come from

  One caller: **`0x27D028`** at `0xD41168` — the only `bl` xref in the text section. It is
  `f(ignored, u8 slot)` and:

  1. `0x27D07C` `memset(r1+1416, 0, 1536)` — 128 x 12, the staging buffer.
  2. `0x27D098` `RecordBuffer(slot+1)` (`0x27EF90`) — the per-player stat blob.
  3. `0x27D0B8` `GET(key 332, 4)` -> the **character id**, wire `+0x00`.
  4. `0x27D0D0` `GET(key 392 (0x188), 256)` -> **live** skill experience, 128 x u16 by skill id.
  5. `0x27D0E8` `GET(key 648 (0x288), 256)` -> the **baseline shadow** of the same array.
  6. `0x27D0F0`-`0x27D148` loop `mtctr 127`, skill id from **1**:
     `delta = live[id] - baseline[id]` (`0x27D11C`/`20`/`24`); a zero delta does not advance the
     cursor, so unchanged skills are omitted; `stb r8, entry+0` (id) and `stw r9, entry+4`.
  7. `0x27D14C` if nothing changed, returns without sending.
  8. `0x27D190` **rebaselines**: `SET(key 648, 256, live)` — the same pattern `0x4390` uses at
     `0x27DC60`.

  Absolute addresses, via ADDRESSES.md section 1 (`blob = 0x1610568 + slot*0x510`, key = byte
  offset): live experience for skill `n` is `0x1610568 + slot*0x510 + 0x188 + 2n` (u16), baseline
  `... + 0x288 + 2n`. **Element stride in the record store is 2**; the 12-byte stride below is the
  staging buffer only.

  ## THE VALUE IS ABSOLUTE, NOT A DELTA

  `0x27D12C` writes the delta and `0x27D140` immediately **overwrites it with `live[id]`** before
  the record is built. Storing deltas would compound every round. The delta exists only to decide
  whether a skill moved.

  ## THE HOST REPORTS FOR EVERYONE

  `0x43A4` is task **1 of 3** in a per-player report queue, not a free-standing send. Task table at
  `g = 0x1610380`: `g+304 = 0xFB1C20` (`0x4390`), **`g+312 = 0xFB1C00` (`0x43A4`)**,
  `g+320 = 0xFB1BE0` (`0x43A2`); installed at `0x27DED0`-`0x27DEE0`, owner bytes at `g+308/316/324`
  reset to `0xFF` at `0x27DE44`. Armed by `SubmitReport(slot, 1)` = `0x27DF38` (arm at `0x27DFC0`),
  driven by `PollReportTasks` = `0x27E780`, which walks the three **in order** — `0x4390`, then
  `0x43A4`, then `0x43A2`. Confirmed live: the three arrive back to back in the same millisecond.
  The two arming sites (`0x7083C8`, `0x708800`) sweep slots 0..23, so the host reports for every
  player whose skills moved.

  **Attribution is therefore the character id at wire `+0x00`, not the connection** — unlike
  `0x4390`, whose attribution is connection-implicit. A server must check that id against the
  game's roster rather than trusting it.

  ## Accrual, for context

  `0x6FC838`-`0x6FCAEC`: `0x6FCA40` is `addi r6,r6,1` — **one point per use**. On level-up
  `0x6FCA6C`-`0x6FCAD4` looks up a per-skill/per-level requirement at `g + (min(id,17)*4 + level)*2`
  and snaps the value to `(level << 13) + 8192`; `0x6FCAE8` writes it back with `SET(key 392, 256)`.
  Level is `min(experience >> 13, 3)` (`0x6FC580`), and the client's validator at `0x93E418`
  **zeroes** any record above 24576 — so 24576 is a legal maximum, not a display ceiling.

  ## The seeding chain, and why nothing persisted before

  `0x4125`/`0x4129` -> `profile+11444` -> the announce builder `0x8841A8` copies it to
  `announce+50` -> the receivers `0x2764E0`/`0x278230` `SET` it into **both** key 392 and key 648,
  so the delta starts at zero on join. **Nothing in the image copies accrued experience back from
  key 392 into `profile+11444`**, so that array is entirely server-authoritative: experience
  earned in a round lived only in the blob and was discarded at teardown.

  ## Reply

  `0x43A5`, and the sender opens **wait slot 53** (`li r4,53` / `bl 0xD32E08` at `0xD41A78`). An
  unanswered `0x43A4` is a latent `FFFFFF60` — observed live on 2026-07-29, when it was still
  unhandled and hung the client.

  ## Live confirmation

  First frame captured 2026-07-29 19:54:29, 14 bytes:
  `00000002 00000002 02 2001 0d 2007` — character 2, two records: skill 2 at 8193 and skill 13 at
  8199, i.e. one and seven uses above the 8192 baseline. Layout matches byte for byte.

  Note the count IS on the wire here, and the loop bound is re-read from `r1+1480` each pass at
  `0xD41A34`, so a reader must use the field rather than end-of-stream. `0x4398` carries no count
  at all; conflating the two conventions has bitten this project before.
doc-ref: dev/docs/OBSERVED.md "Skill progression"
seq:
  - id: chara_id
    type: u4
    doc: |
      [ELF, CONFIRMED LIVE] 0x00. The character these records belong to — blob key 332, read at
      `0x27D0B8` and staged at `r1+1464`. **Attribution comes from here, not from the connection**,
      because the host reports for every player in the game.
  - id: count
    type: u4
    doc: "[ELF] 0x04. Record count, client-capped at 127 (`0xD419BC`). **On the wire** — the loop re-reads it from `r1+1480` every pass, so use it rather than end-of-stream."
  - id: entries
    type: entry
    repeat: expr
    repeat-expr: count
    doc: "[ELF] 0x08.. — `count` x 3 bytes, one per skill whose experience CHANGED this round. Unchanged skills are omitted (`0x27D130`). Source stride is 12 bytes in the staging buffer; only 3 of each 12 reach the wire."
types:
  entry:
    seq:
      - id: skill_id
        type: u1
        doc: "[ELF] +0x00, from `entry+0x00` (`stb r8` at `0x27D13C`). 1-based; the loop starts at id 1. Ids 1..17 are real, and the requirement lookup clamps at `min(id,17)`."
      - id: experience
        type: u2
        doc: |
          [ELF] +0x01, the low 16 bits of the u32 at `entry+0x04` (`stw r9` at `0x27D140`, loaded
          with `lwz` and stored through a `sth` staging slot at `0xD41A28` — the truncation is
          itself evidence the source is logically 16-bit).

          **An ABSOLUTE total, not a delta**, and not a level: level is `min(value >> 13, 3)`, so
          8192/16384/24576 are levels 1/2/3 and intermediate values are progress toward the next.
          Legal maximum 24576 — the client's validator at `0x93E418` zeroes any record above it,
          so an over-cap value makes the skill VANISH rather than clamping.
