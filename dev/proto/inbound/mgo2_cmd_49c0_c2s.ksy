meta:
  id: mgo2_cmd_49c0_c2s
  title: "MGO2 0x49C0 — game-lobby request with a counted id list (client -> server)"
  endian: be
doc: |
  **Filename deviates from the `mgo2_cmd_<id>.ksy` rule on purpose: `0x49C0` is bidirectional.**
  The client both SENDS this id (packet builder `0xD5CF40` called with `li r4,18880` at
  `0xD4E6D8`) and PARSES it (dispatcher `0xD38804`: `cmpwi r3,18880` at `0xD38D50` →
  `b 0xD39820` → parser `0xD4E420`). Both facts are tier 1 and were checked directly.
  `mgo2_cmd_49c0.ksy` in this directory holds the **server -> client** (parsed) layout; this file
  holds the **client -> server** (sent) layout. They are different structures and cannot share one
  `.ksy`. The two need reconciling into a naming convention before either is promoted — flagged
  rather than silently resolved.

  Sender: the function containing `0xD4E610`, builder call `0xD4E6D8`, subsystem index `0x4B`
  (`li r4,75` at `0xD4E7AC` before the status setter `0xD32E08`). Unhandled by our server
  (COMMANDS.md lists `0x4904`–`0x49C2` as the game-lobby/roster/GHQ gap).

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.

  **The only assigned client -> server id with a repeating record.** Arguments: r4 = u8
  (`stb 1464(r1)`), r5 = count (`stw 1472(r1)`), r6 = pointer to an array of **44-byte** records.
  Guards before building (`0xD4E61C`–`0xD4E634`): r5 must be `>= 1` **and `<= 3`**, and r6 must be
  non-NULL; otherwise -24 with nothing sent.

  The count is written **first**, with the signed primitive `0xD5C95C`, and the loop's bound is
  read back from that same stack slot (`lwz r0,1472(r1)`, `cmpw r25,r0`, `blt` at
  `0xD4E75C`–`0xD4E77C`). So the record count is **leading-field-driven, not size-driven** —
  worth stating explicitly because this project has previously mis-read count-vs-size.

  Each iteration writes one u32: the word at offset 0 of the current 44-byte record
  (`0xD5C9BC` at `0xD4E710`; stride `addi r27,r27,44` at `0xD4E744`). A record whose first word is
  **zero aborts the whole send** (`lwz r0,0(r29)`, `beq` to the -24 exit at `0xD4E70C`), so all
  ids are nonzero. The 17 bytes the loop also copies out of `record+24` (`lswi`/`stswi` at
  `0xD4E748`) go into a client-side 44-byte-stride table at `ctx+6292`, **not** onto the wire.

  Total payload: 5 + 4*num_ids bytes, i.e. 9, 13 or 17.
seq:
  - id: num_ids
    type: s4
    doc: |
      [ELF] `0xD5C95C` (**signed** 4-byte primitive) at `0xD4E6E8`, source = sender arg r5.
      Constrained by the sender to 1..3 inclusive. Drives `ids` below (named `num_ids` per the
      Kaitai style guide).
  - id: unknown_04
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD4E6F8`, source = sender arg r4. Meaning [UNKNOWN]."
  - id: ids
    type: u4
    repeat: expr
    repeat-expr: num_ids
    doc: |
      [ELF] One u32 per input record, from `record+0`. Count comes from the leading `num_ids`
      field, not from the payload length. Never zero (a zero aborts the send).
      What the ids identify is [UNKNOWN].
