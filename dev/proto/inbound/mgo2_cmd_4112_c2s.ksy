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
