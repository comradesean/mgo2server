meta:
  id: mgo2_cmd_4110_c2s
  title: "MGO2 0x4110 — update gameplay options (client -> server)"
  endian: be
doc: |
  **304 bytes exactly (0x130).** Evidence: builder call site `bl 0xd5cf40` at `0xd3bfc0`.
  Between it and the seal (`bl 0xd5c828` at `0xd3c008`) exactly two write primitives run, the
  second in a four-iteration loop:

    * `bl 0xd5d0ac` (write-blob, `r5 = 48`) at `0xd3bfd0`, source `r26` — the settings block;
    * `bl 0xd5d0ac` (write-blob, `r5 = 64`) at `0xd3bff8` inside a loop
      (`cmpwi cr7,r28,3` / `addi r28,r28,1` / `bne cr7,0xd3bfdc`, four passes), source `r31`
      advancing by 64 each pass (`addi r31,r31,64`) — the four codec-name strings.

  48 + 4 x 64 = **304**. Flush `bl 0xd34cc0` at `0xd3c018`; wait slot `0x17` (`li r4,23` at
  `0xd3c030`, `bl 0xd32e08`). [ELF]

  This independently reproduces the live 2026-07-22 observation of a 304-byte push
  (PROTOCOL.md), and it explains *why* 304: the payload is exactly the first `0x130` bytes of
  the `0x4120` reply — its 48-byte settings header plus its 256 bytes of codec names — with the
  32-byte trailer at `0x4120`'s `0x130` omitted. So the correct parse for `0x4110` is
  `0x4120`'s own layout truncated at `0x130`, which is what PROTOCOL.md says. [ELF + CONFIRMED]

  **Same enclosing function as `0x4114`.** After this packet is flushed and its slot armed, the
  function falls through to `bl 0xd5cf98` (reset) at `0xd3c04c` and a `0x4114` builder at
  `0xd3c05c`, looping over macro type 0 then 1. That is the single burst PROTOCOL.md records
  ("the client fires `0x4110` + both `0x4114`s in a single burst without waiting between
  them") — it is one function, not three independent sends. [ELF]

  **Not encrypted**: this sender makes no `bl 0xd5d124` call, so the body arrives in the clear.
doc-ref: dev/docs/PROTOCOL.md "0x4110 — update gameplay options"
seq:
  - id: settings
    size: 48
    doc: |
      [ELF] Written as one opaque 48-byte blob — the client does not serialise these fields
      individually, it memcpy's a live struct, so the ELF gives no field boundaries here.
      Parse it as `0x4120` offsets `0x00`..`0x2f`: the packed privacy / view / switch / voice /
      radar / HUD bytes at `0x00`..`0x17` and the four 4-byte codec entries at `0x20`..`0x2f`.
      That mapping (including the several sliders stored one higher than they go on the wire)
      is documented under `0x4120` and is **[CONFIRMED]** on the write side only; the read side
      here has not been byte-verified against a capture.
  - id: codec_names
    type: str
    size: 64
    encoding: ISO-8859-1
    repeat: expr
    repeat-expr: 4
    doc: |
      [ELF] Four fixed 64-byte ISO-8859-1 names, count fixed by the loop bound
      (`cmpwi cr7,r28,3`) — **not** size-driven and **not** preceded by a count field.
      Same region as `0x4120` offsets `0x30`..`0x12f`.
