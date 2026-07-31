meta:
  id: mgo2_cmd_4583_s2c
  title: "MGO2 0x4583 — bulk roster fetch, list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4580 roster triple. Parser 0xD465D4 (ends 0xD467BC), dispatcher stub
  0xD39360. PROTOCOL.md records it as a 4-byte result; the ELF agrees — 0xD5CC64 at 0xD466A8 is
  the only read primitive in the function.

  FINDING — THIS HANDLER FILTERS THE COLLECTED 0x4582 RECORDS. After closing the reader the
  handler runs a compaction loop (0xD466D4–0xD46734) over the entries 0x4582 accumulated:

      lhz  r0,30(r9)        ; r9 = srcArray + i*68, records start at +8
      cmpwi r0,0
      beq  <skip this record>
      ... memcpy 68 bytes into destArray[count++] ...

  i.e. for each 68-byte source slot it loads the u16 at slot+30 — which is record struct+0x16,
  the 0x4582 field at **wire offset 0x14** — and copies the record into the display array ONLY
  when that u16 is nonzero. Records with 0 there are silently dropped.

  Consequence for us: PROTOCOL.md says we answer 0x4580 empty because "we cannot fill the
  59-byte record honestly", and separately says the tail fields are sent as zeros for the
  byte-identical 0x4602 search record. If 0x4582 is ever populated with a zero at wire 0x14 the
  roster screen will come up empty even though every record parsed correctly — a silent desync of
  exactly the shape the 0x4902 35-vs-99-byte bug had. Not yet tested live; the address above is
  the whole basis.

  Subsystem index is 0x51 + the requested state (0xD46738: `extsb r29,r23` / `addi r29,r29,81`),
  matching 0x4581. Status setter 0xD32E08 and result setter 0xD32E70 follow (0xD46754/0xD46768).
doc-ref: dev/docs/PROTOCOL.md "0x4580 — bulk roster fetch (answered empty)"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED by PROTOCOL.md] Result code, 0 for success — never a count. Stored into the
      subsystem 0x51/0x52 result slot and marks the transaction complete. [ELF 0xD466A8]
