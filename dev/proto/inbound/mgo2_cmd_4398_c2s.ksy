meta:
  id: mgo2_cmd_4398_c2s
  title: "MGO2 0x4398 — update pings (client -> server)"
  endian: be
doc: |
  Builder function `0xD41028` = `f(ctx, u32 host_ping, u8 count, void *entries)`; `entries`
  null aborts (`0xD41070`). `bl 0xD5CF40` at `0xD410C0` (`li r4,0x4398` at `0xD410BC`), seal
  `0xD5C828` at `0xD41114`, flush `0xD34CC0` at `0xD41124`. Not encrypted.

  The write loop (`0xD410C8`-`0xD4110C`) is entered **mid-body** at `0xD410EC`, which is what
  gives the payload its odd head-then-pairs shape:

    * the first `0xD5C9BC` (u32) executed takes `r1+1448` — the `host_ping` argument;
    * the cursor `r31` then advances by 8 and each subsequent iteration writes
      `0xD5C9BC` twice, from `r31+0` and `r31+4`;
    * the loop counter `r28` starts at 1 and runs while `r28 < (r24 & 0xff)` = `count`.

  So the frame is `u32 host_ping` followed by **count-1** eight-byte pairs, i.e. the caller's
  entry array element 0 is elided in favour of the bare ping. **The count is NOT on the wire**
  — the reader must be size-driven. (This project has been bitten by assuming a leading count;
  see `dev/proto/README.md` on the `0x4601`/`0x4681` result codes.)

  Matches `PROTOCOL.md`'s live-confirmed reading ("u32 host ping, then repeated
  {u32 chara id, u32 ping} pairs").
doc-ref: dev/docs/PROTOCOL.md "0x4398 — update pings"
seq:
  - id: host_ping
    type: u4
    doc: "[CONFIRMED] 0x00. The host's own ping; lands on the game row (`0x4302` offset 0x1e). Second argument of `0xD41028`, staged at `r1+1448`."
  - id: entries
    type: ping_entry
    repeat: eos
    doc: |
      [CONFIRMED] 0x04.. — one 8-byte pair per other player, count-1 of them, **size-driven**:
      the client sends no count field. Also doubles as the host heartbeat (`last_update`).
types:
  ping_entry:
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED] +0x00. A zero id is a hole the server skips."
      - id: ping
        type: u4
        doc: "[CONFIRMED] +0x04. Lands on the player's roster row (`0x4313` player entry offset 0x14)."
