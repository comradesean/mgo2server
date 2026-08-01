meta:
  id: mgo2_cmd_4112_c2s
  title: "MGO2 0x4112 — unidentified connect-family write-back, blocking (client -> server)"
  endian: be
doc: |
  **32 bytes, opaque, and the client BLOCKS on the reply.** Wait slot `0x18` (`li r4,24` at
  `0xD3BEDC`), so an unanswered `0x4112` stalls the screen and ends in `FFFFFF60`.

  [CONFIRMED live 2026-07-27] It fires in ordinary play, immediately after a player search
  (`0x4600`). Before it was handled, a player search left the screen stalled. The reply is
  `0x4113`, a bare u32 result — see `../outbound/mgo2_cmd_4113_s2c.ksy` — so a four-byte ack is
  sufficient to unblock, which is what we send; the body is dropped.

  Evidence: builder call site `bl 0xd5cf40` at `0xd3bea4`
  (`li r4,16658` = `0x4112` at `0xd3bea0`), sender `0xd3be24`-ish. Exactly one write primitive
  runs before the seal (`bl 0xd5c828` at `0xd3bec4`): `bl 0xd5d0ac` (write-blob) at `0xd3beb8`
  with `r5 = 32` and `r4 =` the sender's second argument, a caller-supplied pointer
  (null-checked at `0xd3be58`; a null argument aborts with -24 and nothing is sent). Flush
  `bl 0xd34cc0` at `0xd3bed4`; wait slot `0x18` (`li r4,24` at `0xd3bedc`, `bl 0xd32e08`), so
  the client **does** block on a reply. [ELF]

  COMMANDS.md listed `0x4112` under "Reachable in ordinary flow (priority)" gaps — sendable,
  unanswered, **no stall observed yet** — with no shape recorded anywhere. That last clause is
  now out of date: the stall was observed live on 2026-07-27 after a player search. This is the
  shape: 32 bytes and an armed wait slot. The reply id is `0x4113`, which COMMANDS.md already
  lists under "result singles" the client parses but we never sent.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_body
    size: 32
    doc: |
      [UNKNOWN] Position and length exact (32 bytes, `r5 = 32` at `0xd3beb8`); contents
      unestablished. The client memcpy's a live 32-byte struct rather than serialising fields,
      so **the ELF gives no internal boundaries at all** — no u8/u16/u32 writer runs, so there
      is nothing to read off. Any subdivision would have to come from the *server -> client*
      side or from a capture.

      FIRST CAPTURE, live 2026-07-27, sent right after a player search:

          0000 1000 0000 0000 1110 0000 0000 0000 0000

      Still [UNKNOWN] — that is a byte pattern, not a field map, and it is one sample from one
      screen. Whatever setting these bytes carry **will not persist**, because we acknowledge
      the command and drop the body. Nothing can store them until someone identifies them, and
      the body stays a single unknown field of its exact size until then.

      What is known from position: the sender sits in the `0x41xx` connect-family cluster
      immediately before `0x4110`'s (`0xd3bf1c`-ish) and after `0x4130`'s, i.e. among the
      write-backs for the connect burst — so this is most likely the write-back half of one of
      the burst payloads, as `0x4110` is for `0x4120` and `0x4114` for `0x4121`. **[INFERRED]**,
      and deliberately not narrowed further: none of the burst payloads is 32 bytes, so a
      guess would be a guess. Log the 32 bytes when it first fires; the connect burst's own
      contents will make the match obvious.

      ## [ELF 2026-08-01] The source is named, and the first eight bytes are sixteen nibbles

      The sentence above — "the ELF gives no internal boundaries at all ... no u8/u16/u32 writer
      runs, so there is nothing to read off" — is true of the *sender* and was the wrong place to
      look. The `memcpy` source is a specific object with a **dedicated accessor bank**, and the
      bank supplies boundaries the serialiser never could.

      **Where the bytes come from.** Three of the sender's five `bl` sites pass
      `r4 = 0x907CE4(session)`, and `0x907CE4` is one instruction of arithmetic over the profile
      getter: `return 0xD3A094(session) + 6777` (`addi r3,r3,6777` at `0x907CFC`). So the payload
      is **`profile + 6777`, 32 bytes**.

      | sender call site | context |
      | --- | --- |
      | `0x90BB20` | reaches the `bl` only after three `lbz`/`cmpw` pairs against `119(r19)`, `120(r19)`, `121(r19)` fail to match — a "did the player change this?" guard |
      | `0x90C8B0` | same shape against `116(r28)`/`117(r28)` |
      | `0x90E6D4` | same shape against `108(r27)`/`109(r27)`, and the matching arm reads a nibble via `0x906C9C` |
      | `0xA7E108` | arm 13 of the generic dispatcher `0xA7DC48`; **dead code** — no thunk in the `0xA7E9B0`-`0xA7EBC4` bank sets opcode 13 (see `mgo2_cmd_4b10_c2s.ksy`) |
      | `0xA827BC` | passes its own `r26` argument, not `0x907CE4`'s result |

      All three live senders are "commit if changed" paths, which is consistent with the command
      being a settings write-back and with its blocking wait slot.

      **The accessor bank, which is the field map.** `0x907CE4`'s result is consumed 142 times,
      and every consumption goes through one function in `0x906BE8`-`0x906E24`. That bank is
      exactly **sixteen getters and sixteen setters over bytes 0..7, one pair per nibble**:

      | byte | low nibble get / set | high nibble get / set |
      | --- | --- | --- |
      | 0 | `0x906BE8` / `0x906CA8` | `0x906BF4` / `0x906CC0` |
      | 1 | `0x906C00` / `0x906CD8` | `0x906C0C` / `0x906CF0` |
      | 2 | `0x906C18` / `0x906D08` | `0x906C24` / `0x906D20` |
      | 3 | `0x906C30` / `0x906D38` | `0x906C3C` / `0x906D50` |
      | 4 | `0x906C48` / `0x906D68` | `0x906C54` / `0x906D80` |
      | 5 | `0x906C60` / `0x906D98` | `0x906C6C` / `0x906DB0` |
      | 6 | `0x906C78` / `0x906DC8` | `0x906C84` / `0x906DE0` |
      | 7 | `0x906C90` / `0x906DF8` | `0x906C9C` / `0x906E10` |

      Each getter is three instructions (`lbz r3,N(r3)` then `clrldi r3,r3,60` for the low nibble
      or `rldicl r3,r3,60,60` for the high one); each setter is a read-modify-write of the same
      four bits. `0x8BAA6C`-`0x8BABB4` reads fourteen of the sixteen back to back into `r17`-`r26`
      for one screen.

      So: **bytes 0..7 are sixteen independent 4-bit settings, and the client has no accessor at
      all for bytes 8..31.** That is a real boundary, from the binary, and it is what a future
      split of this field would have to be built on.

      Two things it deliberately does **not** establish, and neither should be guessed:

      * *Which* setting each nibble is. The reading screen is `0x8BA9E4`-`0x8BABB8`; naming the
        nibbles means going at that screen's element names through the module mini-TOC, the
        technique `FIELD_MAPPING.md`'s batch-3b/3c sections describe. Not attempted here.
      * Whether bytes 8..31 are live. "No accessor" is not "no writer" — `FIELD_MAPPING.md`
        records that the `0x907xxx` bank pins widths and never liveness.

      **The field is left as one 32-byte blob on purpose.** Sizes and offsets in these schemas are
      evidence and do not move on a partial map; splitting eight of thirty-two bytes into sixteen
      unnamed nibbles would trade a true statement for a tidier-looking one.
