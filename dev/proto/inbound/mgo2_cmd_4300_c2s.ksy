meta:
  id: mgo2_cmd_4300_c2s
  title: "MGO2 0x4300 — get game list (client -> server)"
  endian: be
doc: |
  **Four bytes.** Evidence: builder call site `bl 0xd5cf40` at `0xd415a4`. One write
  primitive: `bl 0xd5c9bc` (write-u32) at `0xd415b4` from stack `1416(r1)`. Seal immediately
  after; wait slot `0x21` (`li r4,33`). [ELF]

  Confirms PROTOCOL.md's one-u32 request. [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x4300 — get game list"
seq:
  - id: filter_type
    type: u4
    doc: |
      [ELF] Read and logged by our server, then ignored — clan rooms (which is what the
      original distinguished with this) are not modelled. **Operator policy**, not protocol:
      the client does send a real value here.
