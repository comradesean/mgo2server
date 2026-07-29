meta:
  id: mgo2_cmd_4b46_c2s
  title: "MGO2 0x4b46 — clan info probe (client -> server), BLOCKS from the clan menu"
  endian: be
doc: |
  **The clan info probe.** 2-byte payload: a single u16, observed as `0000`. Reply is
  `0x4b47`, 28 bytes: `{s4 result, u4 id, u1 state, u2 privileges, u1 emblem, char name[16]}`
  in the parser's read order at 0xD5835C — which is not the struct order, since the u2 is
  read before the second u1 although it lands higher.

  ## CORRECTION 2026-07-27: IT BLOCKS. The previous claim was wrong.

  **What this file used to say:** that the command is non-blocking, on the strength of
  OBSERVED.md's 2026-07-23 entry ("New: `0x4b46` observed, unhandled, non-blocking") — the
  client sending 0x4b46 with 2 bytes `0000` shortly after the lobby connect burst and then
  proceeding normally with no reply at all. It went further and warned against replying:
  *"do not add a reply speculatively — the live trace proves the client does not wait for
  one."*

  **Why that was wrong.** It was true of the *connect burst*, where 0x4b46 fires unprompted
  and the player walks on regardless. It is false from the **clan menu**, where the same
  command is sent and blocked on: leaving it unanswered stalls and then fails with *"Unable
  to update clan information (1933:FFFFFF60)"* — observed live 2026-07-27 in an automatching
  lobby, payload `0000`, and it was the only unanswered command in the log. One command, two
  contexts, and only one of them had ever been tested.

  The sender `0xD58510` is identical in both cases and advances flow state via
  `0xD32E08(session, 98, 1)` either way, so the difference is entirely in what the screen
  does while waiting — nothing in the request distinguishes them, and no server-side
  inspection of the payload can.

  **The general lesson**, worth more than the fix: a command observed as non-blocking in one
  screen is not established as non-blocking, only as non-blocking *there*. Per CLAUDE.md's
  elimination rule, "we saw it not block" is not an elimination of blocking unless the
  experiment could have exposed the blocking context, and this one could not.

  ## Answering it

  Always `result = 0`, never an error, even for a character with no clan: a nonzero result
  ends the payload after four bytes (0xD5835C reads no further), which leaves the client's
  existing record in place instead of correcting it. "No clan" is a **record** — state 99 —
  not a failure.

  ## The privilege word must be zero

  [CONFIRMED 2026-07-27] `0x4b47`'s u2 privilege field lands at `profile+6838`, and the clan
  screen's coroutine stalls on any bit it does not tolerate: `0xAB0074` ands the word with
  -1, or with -257 when the player is the leader (`0xAB004C`), and returns **without
  advancing its state machine** if anything survives. Granting a leader all sixteen bits put
  a "!" badge on the clan and sent the client into a hard poll loop re-sending this very
  command every ~73 ms.

  -257 is `~0x0100`, so bit 8 is the only bit a leader may hold without that loop. Setting
  bit 8 alone was then tried: no stall and no loop, as the tolerance mask predicts, but it
  produced only the saluting-soldier "!" badge and **no new menu row anywhere**, and emblem
  loading worked with or without it. So bit 8 is a **pending-notification** bit, the word as
  a whole is a notification mask the client drains to zero rather than a permission mask,
  and **no privilege bit gates applying an emblem** — that is keyed off membership state 2
  alone (`0xAD409C` tests `ctx+788 & 4`). Send zero.

  Evidence (ELF, retail BLUS30109): sender 0xD58510. `sth r4,1416(r1)` in the prologue
  spills the caller's u16; builder `bl 0xD5CF40` at 0xD58584 (`li r4,0x4b46` at 0xD58580),
  one write `bl 0xD5C918` at 0xD58594 — the 2-byte serializer, which stores `(v >> 8) & 0xFF`
  then `v & 0xFF`, i.e. big-endian — then the seal `bl 0xD5C828` at 0xD585A0 and the flush
  `bl 0xD34CC0` at 0xD585B0.

  Unlike its 0x4Bxx siblings this sender has NO clan-record precondition: only session !=
  NULL plus the two generic connection checks (0xD38504, 0xD3844C). That is what lets it
  fire during the connect sequence before any clan record exists.
seq:
  - id: unknown_0000
    type: u2
    doc: |
      [UNKNOWN] meaning; position and width [CONFIRMED] — 2 bytes, big-endian (0xD5C918),
      observed as `0000` both in the connect burst (2026-07-23) and from the clan menu
      (2026-07-27). It is the caller's u16 verbatim, unvalidated, and both call sites pass
      zero, so the field has never been seen to vary and nothing distinguishes a
      version/flags word from a "which record" selector.

      The two contexts are not distinguished by this field: both captures carry `0000`. That
      is why the server cannot tell the connect-burst probe from the clan-menu one and must
      answer both identically.
