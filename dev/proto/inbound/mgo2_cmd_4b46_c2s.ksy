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
  - id: notification_clear_mask
    type: u2
    doc: |
      [CONFIRMED, ELF 2026-08-01; renamed from `unknown_0000`] Position and width exact — 2 bytes,
      big-endian (`0xD5C918`), observed as `0000` in the connect burst (2026-07-23) and from the
      clan menu (2026-07-27). **The set of clan notification bits the client is asking to have
      cleared** — the same 16-bit word `0x4b47` returns and lands at `profile+6838`.

      **This corrects the 2026-07-30 dead end recorded here.** That note said `0xA7DC48`, the
      dispatcher this sender's one `bl` site sits in, "has **no `bl` site**" and its OPD
      descriptor `0x10202D8` is unreferenced, so it must be entered by indexing an OPD table —
      "a genuine dead end for a static trace". The OPD half is right and still is. The conclusion
      is not: **`0xA7DC48` is entered by twenty tail calls, `b 0xa7dc48`, from a thunk bank at
      `0xA7E9B0`-`0xA7EBC4`.** The search that established the dead end looked for `bl` only.
      *A tail-called function has no `bl` site by construction, and on PPC64 that is the normal
      shape for a bank of one-line wrappers.*

      ## The dispatcher, now that it is reachable

      `0xA7DC48(u8 flag, int opcode, void *out, u32 arg6, u32 arg7)`. The second parameter is an
      opcode, range-checked `cmplwi 30 / bgt` at `0xA7DD48`, and dispatched through a 31-entry
      jump table based at `0xA7DD90` whose entries are byte offsets from that same address.
      This command is **opcode 12** — table entry `0x340`, arm `0xA7E0D0`, `bl 0xD58510` at
      `0xA7E0DC` with `clrldi r4,r26,48`, the low 16 bits of the dispatcher's **fourth**
      parameter (`mr r31,r6` at `0xA7DC94`, `mr r26,r31` at `0xA7DCB8`).

      The thunk for opcode 12 is **`0xA7EAD8`**: `f(x, y)` -> `(r3=1, r4=12, r5=x, r6=y, r7=0)`.
      So the wire u16 is the thunk's **second argument**, and that argument is a mask:

      | thunk call site | what it passes |
      | --- | --- |
      | `0xACF298`, `0xAD2D54` | `li r4,256` — **bit 8, literally** |
      | `0xAB07D8` | `rlwinm r4,r28,0,23,23` — bit 8 masked out of a state word |
      | `0xAB0134`, `0xAB4464` | `r4 = (ctx[100] \| *(u16*)(profile+6838)) & ~ctx[104]` |
      | `0xAB6E28`, `0xABA024` | `r4 = accumulated \| *(u16*)(profile+6838)` |
      | `0xAB497C` | `rlwinm r4,r29,0,23,23` — bit 8 again |

      `profile+6838` is reached as `lhz r0,6838(0xD3A094(session))`, and `profile+6838` is exactly
      where this command's own reply `0x4b47` puts its privilege/notification `u2` — see the
      section above. So the client reads the word we sent it, ORs in whatever it has accumulated
      locally, subtracts what it has already handled, and hands the remainder back here.

      That closes the loop the "must be zero" section opens: the word is **a notification mask the
      client drains to zero**, and this field is the drain. Bit 8 is the only bit a leader may
      hold without the client spinning, and bit 8 is the bit two call sites name as a constant.

      ## What follows for the server

      **We send the privilege word as zero, so this field is structurally forced to `0000`.**
      Every capture showing `0000` is therefore explained rather than merely observed, and the
      earlier phrasing — "both call sites pass zero, so the field has never been seen to vary" —
      was describing our own input coming back. It could never have varied while we send zero,
      which per CLAUDE.md's elimination rule means the captures were incapable of settling the
      field either way.

      It also confirms the operational conclusion already in this file for a second reason: the
      connect-burst probe and the clan-menu probe genuinely cannot be told apart from the request,
      because the discriminator is the opcode inside the client, not anything on the wire. Answer
      both identically.

      Still true, and unchanged: the field is **not** computed from any clan record — nothing
      between the dispatcher's entry and the sender touches one.
