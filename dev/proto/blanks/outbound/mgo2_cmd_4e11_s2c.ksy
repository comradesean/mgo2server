meta:
  id: mgo2_cmd_4e11_s2c
  title: "MGO2 0x4e11 — session/room list ITEMS, 47-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD5AADC**, which re-checks the id (`cmpwi r0,19985`) before reading anything.

  Items for the 0x4e10 / 0x4e11 / 0x4e12 exchange (slot 90).

  **Count source: size-driven, no count field** (0xD5CEB0 at 0xD5AB88, loop back at 0xD5AD10) —
  BUT unlike the 0x4b54/0x4b75/0x4b92 lists, records are **not appended**: the leading u2 of each
  record is used as the array INDEX (0xD5ACCC-0xD5ACF4: `cmplwi 127; bgt -> stop`, then
  `mulli x,52`), while the count at list+4 is merely incremented. So the server controls
  placement, records may arrive out of order, an index > 127 aborts the loop, and a repeated
  index silently overwrites while still bumping the count. That is a genuinely different
  count/placement model from the clan lists and is exactly the kind of thing that has bitten this
  project before — worth a server-side WARN if index >= 128 or a duplicate index appears.

  Wire record = 47 bytes; client struct = 52 (copied as 32 bytes to struct+8 and 20 bytes to
  struct+40).

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 s4, 0xD5CCD8 u4, 0xD5D018 fixed byte block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. In each
  signed/unsigned pair the LOWER address is the signed accessor (write-side proof: 0xD5C95C uses
  `sraw`, 0xD5C9BC uses `srw`). Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare): that rule holds on the WRITE side
  only. The READ pair 0xD5CC64 / 0xD5CCD8 is instruction-for-instruction identical — same
  `cmpwi 1020` bound check, same byte-assembly loop — so neither is a signed accessor. Where a
  field below is typed s4, the evidence is the CALLER reloading the value with `lwa` (or the
  field being a known-negative error code), never the primitive's address.

seq:
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; each record self-addresses via its `index` field."
types:
  record:
    doc: "47 wire bytes -> 52-byte client struct, placed at list+8+index*52."
    seq:
      - id: index
        type: u2
        doc: "[ELF] Array index for this record; must be <= 127 or the loop aborts. NOT a count. [UNKNOWN] what it indexes (slot number in the room?)."
      - id: unknown_02
        type: u4
        doc: "[ELF] [UNKNOWN]"
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] 16 bytes fixed. [UNKNOWN] whose name."
      - id: unknown_17
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_18
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_19
        type: u1
        doc: "[ELF] Read into the low end of the element buffer, out of order relative to its neighbours. [UNKNOWN]"
      - id: name_2
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] 16 bytes fixed. [UNKNOWN]"
      - id: unknown_2b
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_2c
        type: s4
        doc: "[ELF] SIGNED accessor 0xD5CC64. [UNKNOWN]"
      - id: unknown_30
        type: u1
        doc: "[ELF] Last byte of the record. [UNKNOWN]"
