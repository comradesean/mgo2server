meta:
  id: mgo2_cmd_4120_s2c
  title: "MGO2 0x4120 — gameplay and interface settings, packet 2/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xd3d758** (GAME dispatcher 0xd38804, trampoline 0xd39030). **0x150 = 336 bytes.**

  The parser is unusually coarse: only **six** read calls, all of them fixed-size block copies
  (0xd5d018), no field-level reads at all —

      0xd3d7cc  fixed[48]           -> ctx+27424
      0xd3d7e4  loop x4: fixed[64]  -> ctx+27472 + i*64      (bound `cmpwi cr6,r28,3`)
      0xd3d824  fixed[32]           -> ctx+29265

  48 + 4*64 + 32 = 336. So from the client's side this packet is three opaque regions, and the
  per-bit meanings PROTOCOL.md documents for wire 0x00..0x17 are **not visible in this parser** —
  they come from the write-back side (`0x4110`) and from live testing, and they are tagged
  accordingly below. The parser does confirm the segmentation: settings and codec entries are one
  48-byte unit, the four codec names are 64 bytes each, and the trailer is exactly 32.

  Note this arm fires **no** request-status notification: the burst's wait slot 0x15 is released by
  `0x4125` (see mgo2_cmd_4125.ksy), so `0x4120` can be dropped without stalling `0x4100` — it
  would just silently lose every setting.

  ## Where the destination block is, and who can reach it [ELF 2026-07-30]

  `ctx+27424` is `profile+4936` (`0xD3A094` returns `ctx+22488`). The block is **1873 bytes**, and
  three commands write disjoint parts of it:

  ```
  block +0    .. +47     the 48 settings bytes            <- 0x4120 wire 0x000
  block +48   .. +303    four 64-byte names               <- 0x4120 wire 0x030
  block +304  .. +1839   24 x 64 bytes = the two 12-entry chat-macro sets  <- 0x4121
  block +1841 .. +1872   list preferences (profile+6777)  <- 0x4120 wire 0x130
  ```

  The macro region is confirmed by the **write-back builder `0xD3BF2C`**, which is the sole
  producer of both directions of this block: it emits `0x4110` (`li r4,16656` at `0xD3BFC0`) as
  48 bytes from `block+0` plus 4x64 from `block+48` — 304, exactly the length PROTOCOL.md records
  live — and then loops twice emitting `0x4114` (`li r4,16660` at `0xD3C058`) as `{u8 index}` plus
  768 bytes from `block + 304 + index*768` (`0xD3C084`-`0xD3C094`, `mulli r4,r4,768`).

  **The alias space for this block is closed, which is what makes the negatives below real.** The
  pointer is materialised in exactly fourteen places in the image: `addi r4,r31,27424` in this
  parser (`0xD3D7BC`), and thirteen `addi rX,rY,4936` sites, of which two (`0xE68650`, `0xE72C94`)
  are past the end of .text (`0xDE9328`) and disassemble as data. The eleven real ones are
  `0x2811C0`, `0x8841E8`, `0x9472B4`, `0x947D80`, `0x9A85E0`, `0x9AB55C`, `0x9AB89C`, `0x9ACFDC`,
  `0x9C9064`, `0xCA3C24`, `0xCA4664`. Two more functions exist that *would* return it —
  `0x907AB8` (via `0xD3A0AC`) and `0x907D10` (via `0xD3A094`) — and **neither is ever called**:
  zero `bl` sites, and no word anywhere in the file equals their OPD descriptors `0x101C280` /
  `0x101C2E0`.

  Every one of those eleven sites either hands the pointer to `0xD3BF2C` (which copies the bytes
  without interpreting them) or to the **generated accessor family at `0x9066F0`-`0x906BE4`**,
  whose members take the block pointer in `r3` and use small literal displacements:

  ```
  0x9066F0 .. 0x906894   getters, block bytes 0..20, split by nibble/bit-field
  0x9068E4 .. 0x906BB8   the matching setters
  0x906840               block + 48  + min(i,3)*64    the four 64-byte names
  0x9068A0               block + 304 + min(i,23)*64   the 24 macro strings
  0x9068C4 / 0x906BD0    block + 32  + min(i,15)      the 16 bytes at wire 0x20
  ```

  ## Byte 0 bit 0 is an "already initialised" marker — this resolves a PROTOCOL.md "unknown why"

  `0x9472AC`-`0x9472E0`, the options screen's load path: `bl 0xD3A094`, `addi r28,r3,4936`,
  `bl 0x9066F0` (get byte 0's low nibble), then `clrldi. r0,r3,63` / `bne 0x94753C` — **if bit 0
  is set the whole default-apply block is skipped**. If it is clear the client sets bit 0
  (`ori r4,r3,1` -> `bl 0x9068E4`), `memset`s 33 bytes at `profile+6777` (`0x9472E8`, the list
  preferences) and then overwrites roughly thirty settings with hard-coded defaults
  (`0x947300`-`0x947538`).

  So PROTOCOL.md's "bit 0 always **1** (unknown why)" is not cosmetic: **sending 0 there makes the
  client discard every other setting in this packet the first time the options screen opens.**

  ## Suspected wrong claim, reported not edited: wire 0x14 high nibble, 0x15 and 0x16

  The accessor family stops at block byte 20's **low** nibble (`0x906894`). There is no accessor
  for byte 20's high nibble, none for byte 21, none for byte 22, and no direct load or store at
  `profile+4956`/`4957`/`4958` anywhere in .text (scan: every `lbz/lhz/lbzu/lha/stb/sth/sthu` in
  the image whose displacement is 4941..4983 — thirteen hits, all either `(r1)` stack traffic,
  past the end of .text, or displacement 4955). That is the same evidence that makes
  `unknown_17` dead, so PROTOCOL.md's "0x14 bits 4-7 BGM volume", "0x15 radar" and "0x16 HUD"
  cannot be reads of *this* block. Left in place, flagged for a separate argued check.
doc-ref: dev/docs/PROTOCOL.md "0x4120 — gameplay settings, 0x150 = 336 bytes"
seq:
  - id: settings
    type: settings_block
    doc: "[ELF] Wire 0x000, one 48-byte copy to ctx+27424. Sub-fields below are from PROTOCOL.md, not from this parser."
  - id: codec_names
    type: str
    size: 64
    encoding: ISO-8859-1
    repeat: expr
    repeat-expr: 4
    doc: "[ELF] Wire 0x030, four separate 64-byte copies to ctx+27472 + i*64. PROTOCOL.md: four codec names."
  - id: list_preferences
    size: 32
    doc: |
      [CONFIRMED 2026-07-29] **The player's Filter Host List / Sort Host List / Player Search
      preferences.** Bytes 0..7 are **sixteen 4-bit fields**; bytes 8..31 have no reader at all.

      Each nibble has a generated getter and setter (`0x906BE8`..`0x906E10`) and is pinned by **two
      independent paths** — that getter, and its own help-string and value-label ids — so this map is
      READ rather than inferred from ordering. Labels from `lobby/scenerio.gcx`, string set
      `-set [2f0293] $strres:9789 $strres:11033`, where `string id = headerIndex - 9789`.

      `0` is `----` (no filtering) on every filter row:

      ```
      b0lo Filter (master)      0 Disabled | 1 Enabled
      b0hi -- DEAD, no callers anywhere
      b1lo -- DEAD, no callers anywhere
      b1hi Number of Players    0 ---- | 1 Display Only Open Games
      b2lo Level Limit          0 ---- | 1 Only Not Restricted | 2 Only Restricted
      b2hi Password Lock        0 ---- | 1 Only Disabled | 2 Only Enabled
      b3lo Weapon Restrictions  0 ---- | 1 Only Not Restricted | 2 Only Restricted
      b3hi Friendly Fire        0 ---- | 1 Only Disabled | 2 Only Enabled
      b4lo Voice Chat           0 ---- | 1 Only Disabled | 2 Only Enabled
      b4hi Network Quality      0 ---- | 1 Only Good | 2 Normal or Better
      b5lo Friends              0 ---- | 1 Only When Present
      b5hi Blocked Players      0 ---- | 1 Will Not Display
      b6lo Sort key             0 Name | 1 Players Joined | 2 Network Quality
      b6hi Sort order           0 Ascending | 1 Descending
      b7lo Search match         0 Partial and Exact | 1 Exact Only
      b7hi Search case          0 Case Insensitive | 1 Case Sensitive
      ```

      Screens: FILTERING SETTING (`0x9084BC`, nine rows), SORT HOST LIST (`0x90C010`), PLAYER SEARCH
      (`0x90E264` — the `ST1_ON-OFF`/`ST2_ON-OFF` widgets). The ELF also carries a developer name
      table at `0xE0D548`-`0xE0DBF0` naming the same fields in English.

      **The server now sends all zeros.** The inherited constant
      `01 00 10 00 00 00 00 10 11 10 ...` set Filter=Enabled, **Password Lock="Display Only
      Disabled"** — hiding every password-locked game from every browser — and Match Case=Case
      Sensitive. The client's own default for the region is zero (validator memsets 33 bytes at
      `0x9472E8`).

      **Correction:** an earlier note gave a clamp table (b6lo <= 1, b6hi forced to 0). The setters
      `0x906DC8`/`0x906DE0` contain **no clamp** — they mask to four bits — b6lo is three-state
      cycling 0..2 at `0x90C4C0`, and b6hi is a live toggle at `0x90C694`.

      These are per-player preferences and we push one set to everyone. The client does not return
      them in `0x4110`, whose write-back is 304 bytes = this packet minus exactly these 32, so
      whatever persisted them used a path not yet identified.
types:
  settings_block:
    doc: |
      The 48 bytes the parser copies as one unit. **Every sub-field here is [INFERRED] from the
      `0x4110` write-back and from live slider testing (PROTOCOL.md), not read out of this
      parser** — the parser cannot distinguish them. Several values are stored one higher than
      they go on the wire; a wrong off-by-one moves a slider one notch and nothing fails visibly,
      which is why PROTOCOL.md keeps this in a separately tested class.
    seq:
      - id: privacy_a
        type: u1
        doc: "[INFERRED] 0x00. bit 0 always 1 (unknown why), bits 4-5 online-status mode, bit 6 email-friends-only."
      - id: view_normal
        type: u1
        doc: "[INFERRED] 0x01. bit 0 invert Y, bit 1 invert X, bits 4-7 speed (stored 1-based, sent 0-based)."
      - id: view_shoulder
        type: u1
        doc: "[INFERRED] 0x02. Same packing as view_normal."
      - id: view_first_person
        type: u1
        doc: "[INFERRED] 0x03. bit 0 invert Y, bit 1 invert X, bit 2 player direction, bits 4-7 speed."
      - id: view_change_speed
        type: u1
        doc: "[INFERRED] 0x04. 0-based."
      - id: dead_settings_05
        size: 6
        doc: |
          [CONFIRMED DEAD 2026-07-30] 0x05..0x0a -> block bytes 5..10 = `profile+4941..4946`.
          **Six independent full-byte settings, each with its own generated getter and setter,
          and not one of the twelve is ever called.**

          Getters `0x906768`, `0x906770`, `0x906778`, `0x906780`, `0x906788`, `0x906790` — each a
          bare `lbz r3,N(r3); blr` with no nibble mask, so these six are byte-wide values, unlike
          their nibble-split neighbours. Setters `0x9069D4`, `0x9069DC`, `0x9069E4`, `0x9069EC`,
          `0x9069F4`, `0x9069FC` — each a bare `stb r4,N(r3); blr`.

          The eliminations actually run: **zero `bl` sites** for all twelve; each appears in the
          file exactly once, as its own OPD descriptor (`0x101BD78`..`0x101BDA0`,
          `0x101BEA8`..`0x101BED0`), and **no word anywhere in the image equals any of those
          descriptor addresses**, which rules out a vtable slot or TOC pointer (PPC64 emits a
          descriptor for every global function, so their existence is not evidence of use). No
          direct load or store at displacement 4941..4946 off any base either. The options screen's
          own load/validate/persist run (`0x9472B4`-`0x947D44`) touches block bytes
          0,1,2,3,4,11,12,13,14,15,16,17,18,19,20 and skips these six.

          They still round-trip: the parser copies them in and `0xD3BF2C` sends them back out in
          `0x4110`. We send zero.
      - id: switch_modes
        type: u1
        doc: "[INFERRED] 0x0b. Low nibble weapon, high nibble item."
      - id: unknown_0c
        type: u1
        doc: |
          [PARTIAL 2026-07-30] 0x0c -> block byte 12 = `profile+4948`. **Only the low nibble
          exists**; there is no high-nibble accessor and no direct load at that displacement, so
          the top four bits are unreachable.

          Getter `0x9067B0` (`lbz r3,12(r3); clrldi r3,r3,60`), setter `0x906A34`. Four call sites
          in total, all inside the options screen:

          - `0x947534` `li r4,0; bl 0x906A34` — the **default is 0**, applied in the
            initialise-if-bit-0-clear block described in the top-level doc.
          - `0x947B4C` get, then `cmplwi cr7,r3,5; ble` / `li r4,0; bl 0x906A34` at `0x947B68` —
            a **clamp: any value above 5 is reset to 0**, so the legal range is 0..5, six states.
          - `0x947D28` get, `stb r3,152(r1)`, and `0x947D44` `RecordSet(record 25, key 200,
            len 40, r1+128)` — so it is byte **+24 of the 40-byte screen-options record**
            (see CLIENT_STORE.md §3, key 200).

          What is NOT established: no consumer. Nothing else calls the getter, and the only
          `RecordGet(25, 200, 40)` (`0x9ACFF8`, buffer at `r1+112`) does not read `+24` in the
          900 instructions that follow. A six-state setting that is defaulted, clamped and
          persisted but never read back. We send 0, which is also the client's own default.
      - id: voice_chat_a
        type: u1
        doc: "[INFERRED] 0x0d. bit 0 always 1 (unknown why), bits 4-7 recognition level."
      - id: voice_chat_b
        type: u1
        doc: "[INFERRED] 0x0e. Low nibble chat volume, high nibble headset volume."
      - id: weapon_switch_ab
        type: u1
        doc: "[INFERRED] 0x0f. Low nibble A, high nibble B."
      - id: weapon_switch_c
        type: u1
        doc: "[INFERRED] 0x10. Low nibble only."
      - id: weapon_recall
        type: u1
        doc: "[INFERRED] 0x11. Low nibble \"before\", high nibble \"now\"."
      - id: first_view_memory
        type: u1
        doc: "[INFERRED] 0x12. bit 1."
      - id: privacy_b
        type: u1
        doc: "[INFERRED] 0x13. bit 0 receive notices, bit 4 receive invites."
      - id: lockon_and_bgm
        type: u1
        doc: "[INFERRED] 0x14. bit 0 lock-on enabled, bits 4-7 BGM volume **+1**."
      - id: radar
        type: u1
        doc: "[INFERRED] 0x15. bit 0 lock north, bit 4 hide floor."
      - id: hud
        type: u1
        doc: "[INFERRED] 0x16. bits 0-1 display size, bit 4 hide name tags."
      - id: unknown_17
        size: 9
        doc: |
          [NO READER IN THE IMAGE 2026-07-30] 0x17..0x1f -> block bytes 23..31 =
          `profile+4959..4967`.

          Two independent scans, both empty:

          - **The accessor family does not cover them.** `0x9066F0`-`0x906BE4` is contiguous and
            complete — it begins at `0x9066F0` (the preceding function ends `blr` at `0x9066EC`)
            and its literal displacements are 0..20, then the three indexed helpers for +32, +48
            and +304. Nothing addresses block bytes 21..31.
          - **No direct access.** Every `lbz/lhz/lbzu/lha/stb/sth/sthu` in the image with a
            displacement in 4941..4983 was listed: thirteen hits, of which nine are `lbz
            rX,4955(rY)` (block byte 19, and on a non-profile base — `r9 = *(*(r26+28)+24)` at
            `0x4289A8`) and four are past the end of .text. None lands in 4959..4967.

          The confirming observation would be a load at `profile+4959..4967`, or an accessor
          taking the block pointer and using displacement 23..31. Neither exists. Note the same
          negative covers bytes 21 and 22 (wire 0x15/0x16), whose meanings PROTOCOL.md asserts —
          see the top-level doc. Kept as `unknown` rather than renamed `dead` for exactly that
          reason: the negative is about readers, and one of its neighbours is claimed to have one.

          The bytes still round-trip through `0x4110`. We send zero.
      - id: codec_entries
        type: codec_entry
        repeat: expr
        repeat-expr: 4
        doc: |
          [CONFIRMED 4x4 2026-07-30] 0x20 -> block bytes 32..47. The 4x4 grouping is read from the
          client, not assumed: the screen at `0x9A8644` handles four slots and each slot reads
          exactly four consecutive indices — slot 0 reads 0,3,1,2 (`0x9A8CA0`-`0x9A8D0C`), slot 1
          reads 4,7,5,6 (`0x9A8B98`-`0x9A8C04`), slot 2 reads 8,11,9,10 (`0x9A8DFC`-`0x9A8E68`),
          slot 3 reads 12,15,13,14 (`0x9A8974`-`0x9A89E0`) — and each slot's arm first fetches
          **its own 64-byte name** with `bl 0x906840` before reading its four bytes, which is what
          ties entry `i` to name `i`.

          The bytes are reached only through the indexed pair `0x9068C4` (get,
          `lbz r3,32(block + min(i,15))`) and `0x906BD0` (set, `stb r5,32(block + min(i,15))`) —
          32 getter call sites and 16 setter call sites, all in `0x9A8xxx`/`0x9ABxxx`/`0x9ADxxx`,
          the four-slot editor screen. Nothing loads `profile+4968..4983` directly.

          **"Codec" is an inherited label.** It comes from PROTOCOL.md, which took it from a
          reference server; nothing in the parser or in these accessors names the feature. What is
          established is the shape and the gating (below), not the noun.
  codec_entry:
    doc: |
      Four bytes, each an independent selection. [ELF 2026-07-30]
    seq:
      - id: entry_id_0
        type: u1
        doc: |
          [CONFIRMED SHAPE 2026-07-30] Block index `i*4 + 0`. **A 1-based id: the client uses
          `value - 1`, and 0 means "unset".**

          Read path, slot 0 byte 0 as the worked example: `0x9A8CA0 bl 0x9068C4(block, 0)`;
          `cmpwi r3,0`; when zero it stores the position's default element id and moves on
          (`0x9A8CB4 li r0,0`), when non-zero it branches to `0x9A9528` which does
          `addi r31,r3,-1` and calls **`0x9B9DF0(id)`**, storing `id` only if that returns
          non-zero and falling back to the default otherwise. The second screen (`0x9AD3D0`+)
          has the same shape written the other way round: store the raw value, then overwrite
          with a default if it was 0.

          **`0x9B9DF0` is the availability check, and it is DLC-gated.** It reads
          `lbz r0,487(0xD36C74(ctx))` — `0xD36C74` returns `ctx+21968`, so this is the
          **`0x3049` trailer byte at displacement 487**, the one migrations V62-V66 record as the
          paid-pack grant (`rlwinm r27,r0,4,27,27` isolates its **bit 0** and scales it to 16).
          It then linearly searches an **82-entry, 6-byte table at `0xE1812C+2`** (`0xE1812E` ..
          `0xE1831A`, terminated by an all-zero row) whose columns are `{u16 id, u16 gate,
          u16 stringish}`; `gate` is 0 for 22 rows, **16 for 32 rows — those need the pack bit** —
          and 128 for 27 rows, which are instead routed through the ownership checks `0x9C0600`
          and `0x9C2C90`. Ids run 0..91.

          So the four bytes of an entry are four ids into that table. What the table *is* has not
          been established and is deliberately not guessed here.
      - id: entry_id_1
        type: u1
        doc: "[CONFIRMED SHAPE 2026-07-30] Block index `i*4 + 1`. Same kind as `entry_id_0`; slot 0's is read at `0x9A8CE8`, validated at `0x9A94E8`."
      - id: entry_id_2
        type: u1
        doc: "[CONFIRMED SHAPE 2026-07-30] Block index `i*4 + 2`. Same kind as `entry_id_0`; slot 0's is read at `0x9A8D0C`, validated at `0x9A94C8`."
      - id: entry_id_3
        type: u1
        doc: "[CONFIRMED SHAPE 2026-07-30] Block index `i*4 + 3`. Same kind as `entry_id_0`; slot 0's is read at `0x9A8CC4`, validated at `0x9A9508`."
