meta:
  id: mgo2_cmd_4303_s2c
  title: "MGO2 0x4303 — server -> client: game-list END (reply 3/3 to 0x4300)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4303` at `0xD38940` -> stub `0xD391C0` ->
  parser **`0xD40A14`**.

  The **end** half of the `0x4301`/`0x4302`/`0x4303` triple, and the mirror image of
  `0x4301`'s parser. Same game-list object `G = *(ctx+0x11904) + 0x10000 - 24424`. It:

  1. verifies `hdr.command == 0x4303` (else `-70`);
  2. **requires `*(G+0) != 0`**, i.e. a transfer must be open; arriving with no `0x4301`
     before it returns **`-73`** and is dropped, so the client is left waiting;
  3. reads exactly **one u32** (`0xD5CC64`);
  4. `0xD32E08(ctx, 33, 2)` then `0xD32E70(ctx, 33, result)` — completes request-status
     slot 33 with that result, which is what releases the screen;
  5. clears `*(G+0) = 0` (transfer closed). The entry count at `*(G+4)`, accumulated by
     `0x4302`, is left alone — that is the list the browser then renders.

  Note the asymmetry with `0x4301`: **this packet's result is what the screen sees**, so a
  nonzero here fails the whole list even if every entry arrived. 0 for success in both start
  and end (`dev/proto/README.md`).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x4300 — get game list"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] 0 = success. Completes request-status slot 33. [ELF 0xD40A14]"
