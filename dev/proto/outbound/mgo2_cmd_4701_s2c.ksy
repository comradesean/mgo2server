meta:
  id: mgo2_cmd_4701_s2c
  title: "MGO2 0x4701 — connection-info ack (server -> client)"
  endian: be
doc: |
  Reply to 0x4700 (connection info: private port, private IP, public port). PROTOCOL.md
  "Reply 0x4701 — 4 bytes": `00000000`, or `C0FFEE02` / `C0FFEE01`. The ELF agrees.

  NOTE ON THE EVIDENCE ADDRESS: unlike every other id in this range, 0x4701 has **no separate
  parser function**. It is handled inline inside the dispatcher at 0xD393A0–0xD39418 (reached
  from the compare at 0xD38B50). The inline body is: fetch header (0xD3879C), re-check the id
  (cmpwi 0x4701 at 0xD393B4), open reader (0xD5C844 at 0xD393C0), read ONE u32
  (0xD5CC64 at 0xD393D0 into a stack temp), close reader (0xD5C858), then the generic
  transaction pair — status setter 0xD32E08(idx 0x73, state 2) and result setter
  0xD32E70(idx 0x73, value) — with the u32 forwarded verbatim (lwa r5,112(r1) at 0xD39408).

  So the payload is one u32 and nothing else; the client blocks on it (PROTOCOL.md notes a
  registration with no character or no socket address is still acknowledged for exactly this
  reason).

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block, 0xD5CE34 delimiter-terminated string, 0xD5CEB0 loop test.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4701 — 4 bytes"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Result code, stored in the subsystem-0x73 result slot verbatim. 0 for success;
      C0FFEE01 / C0FFEE02 are the deliberate failure values we send. [ELF 0xD393D0]
