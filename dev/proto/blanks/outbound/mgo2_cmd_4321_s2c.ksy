meta:
  id: mgo2_cmd_4321_s2c
  title: "MGO2 0x4321 — server -> client: join-game endpoints (reply to 0x4320)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4321` at `0xD38928` -> stub `0xD39210` ->
  parser **`0xD440DC`**. Request-status slot **38**.

  Confirms PROTOCOL.md exactly. Read order: `result` (`0xD5CC64`); **if nonzero, nothing
  further is read** and the transaction completes as failed — so a failure is a bare 4-byte
  result. On success: a 16-byte raw string, a u16, a 16-byte raw string, a u16, and a single
  u8, and then the parser stops. **41 bytes (`0x29`).**

  The string destinations are 18 bytes apart in the client (`ctx+13624` and `ctx+13644`, with
  the ports at `ctx+13642` and `ctx+13662`), i.e. 16 bytes plus a NUL and a pad — the wire
  strings themselves are a flat 16 with no length prefix.

  PROTOCOL.md's note that echo appends two further bytes (current rule, current map) for a
  43-byte reply is confirmed as **not read**: the parser's last read is the u8 at `0x28`.
  Those bytes are inert.

  **Verified against a live client 2026-07-21** — the client accepts the reply and proceeds to
  attempt the peer connection. That is not the same as the peer connection succeeding; see
  `0x4322`/`0x4323` and the P2P notes in the memory of this project (two-machine joins fail in
  the emulator's peer-ID handling, not here).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4321"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] wire 0x00. Nonzero (e.g. C0FFEE01 for a missing game, wrong password, or a host with no registered endpoint) ends the payload here."
  - id: host_public_ip
    size: 16
    doc: "[CONFIRMED] wire 0x04. Dotted quad, ISO-8859-1, NUL-padded. Raw 16-byte read."
  - id: host_public_port
    type: u2
    doc: "[CONFIRMED] wire 0x14."
  - id: host_private_ip
    size: 16
    doc: "[CONFIRMED] wire 0x16."
  - id: host_private_port
    type: u2
    doc: "[CONFIRMED] wire 0x26."
  - id: unknown_28
    type: u1
    doc: |
      [UNKNOWN] wire 0x28. One byte the parser reads into a stack slot; echo writes 0. Position
      exact, meaning unestablished — and note the parser reads it into a *local*, so if it is
      stored anywhere it happens outside the traced range. **Last byte of the payload.**
