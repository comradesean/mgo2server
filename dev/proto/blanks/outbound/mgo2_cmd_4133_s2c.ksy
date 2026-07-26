meta:
  id: mgo2_cmd_4133_s2c
  title: "MGO2 0x4133 — loadout readback, reply to 0x4132 (server -> client)"
  endian: be
doc: |
  Parser **0xd3c77c** (GAME dispatcher 0xd38804, trampoline 0xd39100), wait slot 27 (0x1b).

  **Not a result code**, as PROTOCOL.md already establishes. Beyond that: this parser is
  instruction-for-instruction the same shape as `0x4124`'s (0xd3ce30), writing into the same gear
  table at `charTable + 9888 + id*12`. Whatever `0x4124` advertises at connect, `0x4133` restates
  after an outfit commit.

      0xd3c808  u32 count -> scratch          (loop entered at the bottom: count 0 = no records)
      0xd3c81c  loop: u8 id, u32 mask         exits when `i >= count` OR `i == 129`
      0xd3c8b0  loop x16: u8 id, u8 bit       (bound `cmpwi cr6,r31,15`, pre-increment compare)

  ### Correction to PROTOCOL.md: the pair loop runs SIXTEEN times, not fifteen

  PROTOCOL.md's `0x4132` section says "a fixed **fifteen** `{u8 slot, u8 bit}` equipped-bit pairs
  — total `34 + 5*count` bytes", and we send the 34-byte empty readback. The loop bound is
  `cmpwi cr6,r31,15` evaluated **before** `addi r31,r31,1` (0xd3c8d4 / 0xd3c8dc), so it exits when
  the pre-increment counter reaches 15 — i.e. after iterations 0..15 inclusive, **16 pairs, 32
  bytes**. The correct empty readback is therefore **36 bytes**, and the true size is
  `36 + 5*count`.

  Cross-check: `0x4124` uses the identical loop and its known-good length is
  `4 + 123*5 + 32 = 651`, which only balances with 16 pairs.

  **Consequence:** our 34-byte `0x4133` is two bytes short. The read primitives bound the cursor
  against the 1024-byte receive buffer, never against the payload length, so the sixteenth pair is
  read out of whatever the previous packet left there. It has not visibly broken anything (the
  stale bytes usually fail the `id <= 128` / `bit <= 31` checks, and even when they pass they can
  only OR in a colour the mask already allows), but it is unbounded stale-buffer input on every
  outfit commit. Sending 36 bytes costs nothing.
doc-ref: dev/docs/PROTOCOL.md "0x4132 — outfit commit"
seq:
  - id: count
    type: u4
    doc: "[ELF] Wire 0x00. Entry count. Not an error field — a non-zero value here is read as a count, not a result. We send 0."
  - id: entries
    type: loadout_entry
    repeat: expr
    repeat-expr: count
    doc: "[ELF] 5 wire bytes each; 12-byte records into `charTable+0x26a0+slot*0xc`. What the original filled these with awaits a capture."
  - id: equipped_bits
    type: equipped_pair
    repeat: expr
    repeat-expr: 16
    doc: "[ELF] **Sixteen**, always read. See the correction above. Note that all-zero pairs redundantly touch bit 0 of slot 0; no distinct no-op encoding is known, though `0xff` pairs (as `0x4124` uses) do skip cleanly."
types:
  loadout_entry:
    seq:
      - id: slot
        type: u1
        doc: "[ELF] Must be <= 128 (0xd3c850) or the record is silently dropped."
      - id: value
        type: u4
        doc: "[UNKNOWN] Written to record +12 and tested bitwise by the equipped_bits loop. Presumably the same colour/ownership mask `0x4124` carries, but unconfirmed for this command."
  equipped_pair:
    seq:
      - id: slot
        type: u1
        doc: "[ELF] Must be <= 128 or the pair is skipped."
      - id: bit_index
        type: u1
        doc: "[ELF] Must be <= 31 or the pair is skipped. ORed into record +16 only if already set in `value`."
