meta:
  id: mgo2_cmd_43c4_c2s
  title: "MGO2 0x43c4 — host-rating vote, 1..5 stars (client -> server)"
  endian: be
doc: |
  Builder function `0xD40E2C` = `f(ctx, u32 arg)`; `bl 0xD5CF40` at `0xD40EA8`
  (`li r4,0x43C4` at `0xD40EA4`). One `0xD5C9BC` (u32) write at `0xD40EB8` from `r1+1416`,
  seal `0xD5C828` at `0xD40EC4`, flush `0xD34CC0` at `0xD40ED4`. Not encrypted.
  **Total payload 4 bytes.**

  Worth more than the other single-u32 senders: this one **range-checks its argument**.
  `0xD40E3C`/`0xD40E44`/`0xD40E64` compute `arg - 1` and abort when `(unsigned)(arg-1) > 4`, so
  the client only ever sends **1, 2, 3, 4 or 5**. That makes the field an enumeration, not an
  id — which rules out the "character id" reading the rest of the `0x43xx` family invites.
  Five values in an in-match host command is suggestive (mode? team? round outcome?), but no
  capture exists and nothing is asserted here.

  No `valid:` constraint per `dev/proto/README.md` — the range is documented, not enforced, so a
  first capture outside it reads as a finding rather than a parse error. Reply `0x43C5`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_00
    type: u4
    doc: |
      [ELF + LIVE] 0x00 — the **host rating in stars, 1 to 5**, cast by a player about the host of
      the game they are leaving. Constrained by the sender's own guard at `0xD40E44`
      (`cmplwi cr6, arg-1, 4`; `bgt` skips the whole send), so a value outside 1..5 means the
      reading is wrong rather than the player being unusual. Confirmed live twice: an operator
      giving five stars produced exactly `43c4 = 00000005`.

      **There is no character id in the payload.** The vote is attributed from the sending
      connection's current character, and the recipient from the host of the game that character
      is in.

      ## What gates the send — the part that cost this project days

      Sender `0xD40E2C`, called from three structurally identical coroutine copies (`0xA322A8`,
      `0xA3310C`, `0xA33F70`). Eight conditions guard it, but only two matter in practice, and both
      are upstream of the picker even opening (`0x9DCA18`-`0x9DCA34`, `0xA135AC`-`0xA135C4`):

      * `0x26E958` must return 0 — **you are not the host**. That is bit 0 of `gameObj+3020`, and
        it is how self-rating is prevented.
      * `screen+344` must be nonzero — a **snapshot of `details+964`** taken when the end-of-game
        screen is CONSTRUCTED (six identical sites, e.g. `0x9D7F34`, `0x9DF0B4`, `0xA0C5D8`).

      `details+964` has exactly three writers: the `0x4313` parser (`0xD44588`, wire `0x0a7`), the
      **`0x4321` join-result parser** (`0xD441FC`, wire `0x28`, only when `result == 0`), and the
      `0x4310` create-game sender (`0xD44D00`, a provable zero — the host suppressing its own).

      **The join reply lands last and wins.** We sent a hardcoded 0 at `0x4321` wire `0x28`
      ("echo writes 0"), which switched host rating off on every join, and made the `0x4313` byte
      look necessary-and-insufficient in the most confusing possible way. Fixed 2026-07-29.

      After a successful send `0xA322BC` sets `flags |= 0x20` and `0xA31DC0` zeroes `state+200`.
      Those latches are **client-local and cleared whenever the picker is re-armed**, so the client
      cannot prevent a player rejoining and voting again — only the server can, via the `0x4321`
      gate byte. Observed live: a rejoin produced a second vote that the server then discarded.
