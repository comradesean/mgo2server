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
      The 48 bytes the parser copies as one unit. The parser cannot distinguish the sub-fields —
      it memcpys the block — so for a long time every field here was `[INFERRED]` from the
      `0x4110` write-back and from live slider testing. **As of 2026-08-04 they are read out of
      the client instead**, and five of them turned out to be served wrong.

      **The route, because it is reusable.** The client generates *one accessor function per
      nibble*, and they sit in one contiguous bank: getters `0x9066F0`-`0x906894`, setters
      `0x9068E4`-`0x906BB8`. Each getter is a bare `lbz r3,N(r3)` plus a mask, so reading the bank
      top to bottom gives the **exact field division of all 48 bytes** — which byte splits into
      nibbles, which is byte-wide, and where the bank simply stops (it ends at byte 20's low
      nibble, which is how bytes 21 and 22 were refuted).

      Three independent channels then name them, and they agree:

      1. **`0x9AD0F4` is an 88-entry jump table** — the ONLINE GAME OPTIONS screen's per-row value
         fetch (bound `cmplwi cr7,r9,87` at `0x9AD0D0`, target = `0x9AD0F4 + table[i]`). Each arm
         calls exactly one accessor and stores the result to `rowRecord+16`. That gives
         **row -> accessor** for all 88 rows.
      2. **The options screen's load/validate/persist run** `0x9472B4`-`0x947D44` gives each field
         its client-side **default**, its **clamp**, and its slot in the local save
         (`RecordSet(record 25, key 200, len 40, r1+128)`).
      3. **Disc string resources.** The contiguous block `$strres:20344`-`20524` is this screen's
         per-row help text *in row order*, `20101`-`20342` the row labels, `20530`-`20646` the
         value labels.

      The row-to-string alignment is not assumed. Rows 0-15 match help strings 20344-20434
      **sixteen for sixteen**, rows 17-22 plus 24 match 20440-20476 **seven for seven**, and rows
      83-87 match 20500-20524 **five for five**. It is independently corroborated by arithmetic —
      the help text says *"Default setting is 5"* for every speed row, the stored default is **4**,
      and the row arms do `addi r3,r3,1` before display — and by shape, e.g. help 20440 describes
      three quick-change behaviours against a field the validator holds to exactly three values.
      It is still an *alignment* argument rather than a direct read of the screen's string ids, so
      it is tier 1 plus disc resources, not tier 2.

      Several values are stored one higher than they go on the wire; a wrong off-by-one moves a
      slider one notch and nothing fails visibly, which is why the server keeps this in a
      separately tested class.
    seq:
      - id: privacy_a
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x00 -> block byte 0. **Three fields, not two.** Accessors
          `0x9066F0` (low nibble), `0x9066FC` (bits **4-5**), `0x906708` (bits **6-7**,
          `rldicl r3,r3,58,62` = a genuine 2-bit field, not a single flag).

          - **bit 0** — the "settings have been initialised" latch (see the top-level doc).
          - **bits 4-5 `online_status`** — ONLINE GAME OPTIONS row 0, **Online Status**. Three values,
            which is why it needs two bits: **Show / Hide / Friends Only** (strres 20530/20536/20542).
            Help text 20344: *"Set your online status. You can set who you appear online/offline to."*
          - **bits 6-7 `block_mail_from_non_friends`** — row 1, **"Only Accept Email from Friends"**
            (Yes/No, strres 20547/20552). Help 20350: *"Block mail from players not on your Friend
            List."* Two bits wide even though only 0/1 are used.

          **The one in-game consumer of anything in this byte**, and it is what the field is for:
          `0x8842B4`-`0x8842D8`, inside the peer-to-peer player-announce builder `0x88407C`:

          ```
          8842b8  bl   0x9066fc            ; online status
          8842c8  xori r3,r3,1
          8842cc  addi r3,r3,-1
          8842d0  rlwinm r3,r3,5,27,27     ; == 0x10 iff the value was exactly 1
          8842d8  stb  r29,2(r31)          ; announce byte +2, broadcast to all 24 slots
          ```

          So picking **Hide** (and only Hide — "Friends Only" does not) sets bit 4 of the announce
          record every peer in the match receives. That is why the value has to come down the wire at
          all: the client cannot re-broadcast a privacy choice it was never told.

          Defaults are 0 and 0 (`0x947308`, `0x947318`). What we send is **right** — the 2-bit mask and
          the bit-6 encoding both match.
      - id: view_normal
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x01 -> block byte 1. Rows 4/5/6 of ONLINE GAME OPTIONS:
          **Normal View Left/Right** (bit 1, masked `rldicl r3,r3,63,63` at `0x9ADD10`), **Normal View
          Up/Down** (bit 0, `clrlwi r3,r3,31` at `0x9ADCD8`), **Normal View Movement Speed** (high
          nibble, `0x9ADC98`).

          The two inverts are the ordinary camera-inversion options — help 20368/20374: *"When set to
          Invert, the camera moves in the opposite direction the right stick is pressed."* Values
          **Normal / Invert** (strres 20556/20559).

          The speed is a **ten-notch slider shown 1-10 and stored 0-9**: the row arm does `addi r3,r3,1`
          before display, the validator resets anything above 9 to 4 (`0x947768`), the stored default is
          4 (`0x947354`), and the help text 20380 says *"The higher the value, the faster the camera.
          Default setting is 5."* Stored 4 = shown 5 — the off-by-one is the client's, and our
          `speed(v) = (v-1) & 0xF` matches it exactly. What we send is **right**.
      - id: view_shoulder
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x02 -> block byte 2. Identical packing to `view_normal`, for
          the **over-the-shoulder aim camera**: rows 7/8/9, **Left/Right** (bit 1, `0x9ADC60`),
          **Up/Down** (bit 0, `0x9ADC28`), **Movement Speed** (high nibble, `0x9ADBE8`, `+1` at display).
          Labels strres 20214/20220/20226. Default speed 4 (`0x947374`).

          **One asymmetry worth recording:** this is the *only* speed slider with **no clamp**. The
          validator run bounds `view_normal`'s, `view_first_person`'s and `view_change_speed`'s high
          nibbles with "above 9 -> 4" and simply does not touch this one. A value of 10-15 here would
          survive and display as 11-16. We never send one, but it is a real difference in what the
          client will accept. What we send is **right**.
      - id: view_first_person
        type: u1
        doc: |
          [CORRECTED 2026-08-04, tier 1] 0x03 -> block byte 3. Rows 10/11/12/13: **First Person View
          Left/Right** (bit 1, `0x9ADBB0`), **Up/Down** (bit 0, `0x9ADB78`), **Speed** (high nibble,
          `0x9ADB38`, `+1` at display, clamp "above 9 -> 4"), and bit 2.

          **Bit 2 is now read rather than guessed, and its polarity was named backwards.** Row 13
          (`0x9ADB00`, `rldicl r3,r3,62,63`) is **"Direction After View Change"**, help 20422: *"Set the
          default camera direction when switching to Over-the-Shoulder or First Person. View to the
          direction the Player is facing or the direction the camera is facing."* The value labels are
          `20565 Player direction` = **0** and `20571 Camera direction` = **1** — so **the bit SET means
          Camera direction**, and the client's own default for this nibble is 4 (`0x947388`), i.e. the
          bit set.

          The value we send was always correct and the round trip is symmetric, so nothing on the wire
          changed; the server field was renamed `firstViewPlayerDirection` -> `firstViewCameraDirection`
          on 2026-08-04 so the name stops asserting the wrong pole.
      - id: view_change_speed
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x04 -> block byte 4, low nibble (`0x90675C`). Row 14, **View
          Change Speed** — how fast the camera travels when you switch between the normal, shoulder and
          first-person views. Help 20428: *"Change the speed at which the view changes... Default setting
          is 5."* Shown 1-10, stored 0-9 (`+1` at `0x9ADADC`), clamp "above 9 -> 4" (`0x9477B8`), default
          4 (`0x9473D4`). What we send is **right**.
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
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x0b -> block byte 11. Low nibble (`0x906798`) = row 17
          **Weapon Switch**; high nibble (`0x9067A4`) = row 24 **Item Switch**. Both clamped "above 2 ->
          0" (`0x947808`, `0x9479E0`) and both defaulted to **2** (`0x9473EC`, `0x94745C`).

          Three modes, and they are the same three for weapons and items — strres
          `20589 Toggle Mode / 20595 Recall Mode / 20601 Cycle Mode`, which the ELF's own stale developer
          table at `0xE0DB70`-`0xE0DB98` calls `EQUIPPED/BARE HANDS`, `FLASHBACK` and `CYCLE`.

          **This is the option that decides what a tap of R2 (weapons) or L2 (items) does in a
          firefight**, so it is squarely gameplay rather than presentation. Help 20440: *"Set the Quick
          Change method for weapons. Tap R2 button to equip/unequip the weapon, switch to the last
          weapon, or cycle through 3 slots."* The three phrases in that sentence are the three modes, in
          order. Which weapon each mode actually reaches is the business of bytes 0x0f, 0x10 and 0x11 —
          and the dispatcher at `0x9C9070` branches on **this** nibble to decide which of them to read.

          What we send is **right**; our defaults 2/2 are the client's own.
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
        doc: |
          [CORRECTED 2026-08-04, tier 1 — THIS FIELD WAS BEING SERVED WRONG] 0x0d -> block byte 13.
          **Three fields**: `0x9067BC` bits 0-1, `0x9067C8` bits 2-3, `0x9067D4` bits 4-7. These are the
          **Sound** section of ONLINE GAME OPTIONS, rows 87, 83 and 85.

          - **bits 0-1 `voice_chat_output_device`** — *"Set the output device for Voice Chat messages
            from other players."* (help 20524). Values `20637 Standard Device` = 0 / `20643 USB/Bluetooth
            Device` = 1. Clamp "above 1 -> 0" (`0x947A08`), default **0** (`0x9474B8`).
          - **bits 2-3 `codec_output_device`** — *"Set the output device for preset Codec messages."*
            (help 20500). Same two values. Clamp `0x947A30`, default **0** (`0x9474D0`).
          - **bits 4-7 `voice_chat_recognition_level`** — *"Set the level at which input signals will be
            recognized as sound by USB/Bluetooth devices."* (help 20512). Range **1-10**, displayed as
            stored with no `+1`, default 5 (`0x9474E4`). Uniquely among the sliders it is clamped from
            **both** ends: `== 0 -> 5` at `0x947A64` as well as `above 10 -> 5` at `0x947A8C`.

          This byte decides whether a player hears other people's voice chat and the preset Codec lines
          through the TV or through their headset — the single most complained-about setting in an
          online shooter.

          **The bug this closed.** The server sent a hardcoded `1` in bits 0-1 — the long-standing
          "bit 0 always 1 (unknown why)" — which forced every player onto USB/Bluetooth voice output at
          every login, and read back neither device field, so both choices were discarded on write-back
          and reset on the next session. Fixed 2026-08-04: both are now columns, sent and read, and both
          default to the client's own 0.
      - id: voice_chat_b
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x0e -> block byte 14. Low nibble (`0x9067E0`) = row 86,
          **Voice Chat Playback Volume**, *"Set the volume for Voice Chat messages from other players."*
          (help 20518). High nibble (`0x9067EC`) = row 84, **USB/Bluetooth Device Output Volume**,
          *"Set the output volume for USB/Bluetooth devices."* (help 20506). Neither is displayed with an
          offset; both default to 5 (`0x9474F4`, `0x947504`).

          **Zero is a legal value here and means silence.** These two are clamped with "above 10 -> 5"
          alone (`0x947AB4`, `0x947ADC`) where the recognition level in the previous byte also gets
          "== 0 -> 5" — the client coerces zero away from one slider and deliberately not from these.
          So a 0 is a state the game itself permits, and neither the schema nor the server rejects it.
          The hazard is only that a 0 reaching the client is inaudible rather than invalid; the columns
          are `NOT NULL DEFAULT 5`, so nothing produces one by accident.

          What we send is **right**. (`headset_volume` is the colloquial column name for the second one;
          the game's own phrase is "USB/Bluetooth device output volume".)
      - id: weapon_switch_ab
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x0f -> block byte 15. Rows 18 and 19, **Slot A**
          (`0x9067F8`, low nibble, strres 20273) and **Slot B** (`0x906804`, high nibble, row 19 at
          `0x9AD9A8`, strres 20278). Help 20446/20452: *"Choose a weapon
          category for Slot A / Slot B."* Five values: `20607 Primary / 20613 Secondary / 20619 Support /
          20625 Knife / 20631 None`.

          **The validator is the proof of the grouping.** `0x94782C`-`0x9478F4` requires Slot A, Slot B
          and Slot C (the low nibble of the next byte) each to be `<= 4` **and all three to differ
          pairwise**; any violation resets the whole triple to (0, 1, 2) at `0x9478F8`. That is exactly
          "you cannot put the same weapon category in two of the three cycle slots".

          **What the player does with it:** in **Cycle Mode**, tapping R2 rotates A -> B -> C. These are
          the three categories the rotation cycles through. The in-game reader is `0x9CA2E8`-`0x9CA324`,
          which loads all three, re-checks distinctness, and indexes a 5-arm jump table on the category
          to pick the actual weapon.

          What we send is **right**; our defaults A=0, B=1, C=2 are the client's own
          (`0x947400`/`0x947410`/`0x947420`).
      - id: weapon_switch_c
        type: u1
        doc: |
          [CORRECTED 2026-08-04, tier 1 — THE HIGH NIBBLE WAS BEING SERVED AS ZERO] 0x10 -> block byte
          16. **Both nibbles are live.**

          - **Low nibble `weapon_switch_c`** (`0x906810`, row 20 at `0x9AD970`) — **Slot C**, the third
            member of the Cycle-Mode rotation and of the distinctness triple described under
            `weapon_switch_ab`.
          - **High nibble `weapon_switch_now`** (`0x90681C`, row 21) — **"Now"** (strres 20287), help
            20464: *"Choose a weapon type to start with."* Validator `0x94792C`-`0x9479AC`: this and
            "Before" (the next byte's low nibble) must each be `<= 4` **and must differ**, else both
            reset to (0, 1). Default 0 (`0x94742C`).

          **"Now" is Recall Mode's pair.** The quick-change dispatcher at `0x9C9070` branches on the mode
          nibble and reads a different number of categories per mode — three for Cycle, **two for
          Recall** (`0x9C9E6C`: `bl 0x90681C` then `bl 0x906828`), one for Toggle. So this high nibble is
          one of the two weapons a Recall-Mode player alternates between with R2.

          **The bug this closed.** The server sent only the low nibble, so the high nibble was always 0
          and was never read back. A player who set "Now" to anything but Primary lost it at logout and
          was forced back to Primary at the next login — and because the client's validator resets
          *both* "Now" and "Before" when they collide, losing one silently reset the other too. Fixed
          2026-08-04.
      - id: weapon_recall
        type: u1
        doc: |
          [CORRECTED 2026-08-04, tier 1 — THE HIGH NIBBLE IS NOT "NOW"] 0x11 -> block byte 17.

          - **Low nibble `weapon_switch_before`** (`0x906828`, row 22 at `0x9AD900`, strres 20292) — **"Before"**, help
            20470: *"Choose a weapon type to switch with."* Recall Mode's other half; see
            `weapon_switch_c`.
          - **High nibble `weapon_switch_toggle`** (`0x906834`, row 23) — **the single weapon category
            Toggle Mode equips and unequips**, i.e. the "tap R2 to put your rifle away, tap again to
            bring it back" weapon. Clamp "above 4 -> 0" (`0x9479B8`), default 0 (`0x947448`).

          **The branch that settles it**, and it settles all three quick-change modes at once:

          ```
          9c9078  lhz   r0,2788(r9)        ; the quick-change mode
          9c9080  cmpwi cr7,r0,2
          9c9084  beq   0x9ca2e8           ; mode 2 -> reads Slot A, Slot B, Slot C   (THREE)
          9c9088  cmpwi cr7,r0,1
          9c908c  beq   0x9c9e6c           ; mode 1 -> reads "Now", "Before"           (TWO)
          9c9094  bl    0x906834           ; otherwise -> reads THIS nibble             (ONE)
          ```

          Three modes, three arms, 3 / 2 / 1 values — which also pins mode 2 = Cycle, mode 1 = Recall,
          mode 0 = Toggle.

          **The bug this closed.** The server wrote its `weapon_switch_now` column here. Because both
          columns default to 0 a fresh character looked correct, and the divergence only appeared once a
          player edited either one — at which point their real "Now" was unrecoverable and the column
          named `now` was in fact holding the toggle weapon. Fixed 2026-08-04 by renaming the column to
          `weapon_switch_toggle` (the stored data was always the toggle weapon, so no data was reset) and
          adding a genuine `weapon_switch_now` at byte 16's high nibble.
      - id: first_view_memory
        type: u1
        doc: |
          [CORRECTED 2026-08-04, tier 1 — THIS SETTING HAD NEVER WORKED] 0x12 -> block byte 18.
          **Two nibbles, and the field is the low one, compared against 1 — not bit 1.**

          - **Low nibble `first_view_memory`** (`0x906864`) — row 15, **First Person View Memory**, help
            20434: *"Set memory function for First Person View. Decide whether or not the camera will
            keep its position after you exit 'aim'."* Values `20577 Enabled` = **0** / `20583 Disabled` =
            **1**. Clamp "above 1 -> 1" (`0x947AF8`), default **0** = Enabled (`0x947514`).

            What the player experiences: with it enabled, dropping out of first-person aim leaves the
            camera where you were looking instead of snapping back — it changes what happens every single
            time you release aim.

          - **High nibble** (`0x906870`) — a **second, independent two-state field** with the same clamp
            (`0x947B20`) and a client default of **1** (`0x947524`), persisted at record byte +37. It has
            **no row in the 88-arm options switch and no reader outside the defaults run**, so it is inert
            on this build. We send 0 where the client's own default is 1. Recorded rather than fixed
            because the negative is about readers, and its neighbour in the same byte does have one.

          **The bug this closed.** The server wrote `0b10`. The client reads the whole low nibble and its
          validator rewrites anything above 1 to 1, so a stored "true" arrived as **Disabled**; and
          because the write-back read the same absent bit, the player's choice was discarded every
          session and the option never persisted at all. Fixed 2026-08-04; the column was renamed
          `first_view_memory_disabled` so its polarity matches the wire's.
      - id: privacy_b
        type: u1
        doc: |
          [CONFIRMED 2026-08-04, tier 1] 0x13 -> block byte 19. Two nibbles, rows 2 and 3, both
          storing the raw nibble: low (`0x90687C`, row 2 at `0x9ADD80`) = **Receive Notices from
          Server**, high (`0x906888`, row 3 at `0x9ADD48`) = **Receive Invites**. Values Yes/No (strres 20547/20552), both
          defaulted to **1** = Yes (`0x947324`, `0x947334`).

          Help 20356: *"Set whether or not to receive notices from the server, which are then displayed
          at the top of the screen. You will always receive important announcements, regardless of this
          setting."* — so this is the ticker at the top of the lobby, and the client tells the player
          outright that the server can override it. Help 20362: *"Set whether or not to receive invites
          from clan members."*

          Bits 0 and 4 are the low bits of the two nibbles, so what we send is **right** and our
          defaults match the client's.
      - id: lockon_and_bgm
        type: u1
        doc: |
          [CORRECTED 2026-08-04 — BOTH HALVES OF THE OLD READING ARE REFUTED] 0x14 -> block byte 20.

          **High nibble: no accessor exists. "BGM volume" is refuted.** The nibble-accessor bank ends at
          `0x906894` (`lbz r3,20(r3); clrldi r3,r3,60` — byte 20's *low* nibble), and the next function
          `0x9068A0` is the indexed macro helper. Control that the enumeration works: displacement 20 is
          found, and displacements 18 and 19 are each found twice, so the sweep detects present members.
          Combined with the earlier direct-load sweep over `profile+4941..4983`, **bits 4-7 have no
          reader on this build**. The server's `bgm_volume` column cannot mean anything here.

          **Low nibble: a real, displayed row — but it is not lock-on.** `b20.lo4` stores to
          `rowRecord+16` exactly like every other value row (unlike ids 25-38, whose arms jump straight
          to the loop-continue at `0x9AD280`), so row 16 is drawn. It is two-state: clamp "above 1 -> 1"
          (`0x9477E0`), default 0 (`0x9473C4`), persisted at record byte +38, and it has **no reader
          outside the options screen**.

          It cannot be Lock-On, because **Lock-On is a host game rule, not a player option**: strres
          21044 *"Lock-On Settings"* / 21050 *"Set whether to turn Lock-On (Auto Aim) targeting on or
          off"* sit in the game-creation block, and 12626/12632/12638 are the host-list filter strings
          *"Only display games where 'Lock On' is enabled/disabled"*. A per-player toggle would make no
          sense for a property of the room — which is exactly why it is filterable.

          **What row 16 actually is remains unsettled.** Rows 0-15 consume the contiguous help block
          20344-20434 sixteen for sixteen and row 17 takes 20440, so row 16 has no help string in that
          run, and no matching label was found anywhere in `strres`. *Explicitly labelled speculation:*
          the stale developer table at `0xE0DAC0`/`0xE0DBE0`/`0xE0DBF0` lists a two-valued `USB KEYBOARD
          TYPE` (`101 ENGLISH` / `102 FRENCH`) with no home among the identified rows — but `strres`
          contains no keyboard-layout string at all, so that table is describing an earlier build of this
          screen and the claim is not made. What would settle it: a live capture with this nibble varied,
          or the row-descriptor array (192-byte stride, element id at `+0`) traced to its constructor.

          **Server status:** we send `lock_on_enabled ? 1 : 0` in the low nibble (default false = 0 =
          the client's own default) and `(bgm_volume + 1) << 4` in the high nibble, which nothing reads.
          Nothing is broken on the wire, and the round trip is faithful — but `lock_on_enabled` and
          `bgm_volume` are two columns that do not mean what they say, and `bgm_volume` cannot mean
          anything on this build. Recorded as a hazard rather than renamed, because row 16's real name is
          still unknown and inventing a second wrong label would not be an improvement.
      - id: radar
        type: u1
        doc: |
          [REFUTED 2026-08-04] 0x15 -> block byte 21. **No accessor exists for this byte anywhere in
          `0x9066F0`-`0x906BE4`**, by the same enumeration and the same control as byte 20's high nibble,
          and the earlier displacement sweep over `profile+4941..4983` found nothing at 4957 either.
          There is no row for it in the 88-arm options switch, and no radar row in the options `strres`
          block.

          So "bit 0 lock north, bit 4 hide floor" has **no support in this binary**. The byte round-trips
          — the parser copies it in and `0xD3BF2C` sends it back out in `0x4110` — and nothing else
          touches it. `radar_lock_north` and `radar_floor_hide` are server columns with no client meaning
          on this build. **Inert, with evidence.**
      - id: hud
        type: u1
        doc: |
          [REFUTED 2026-08-04] 0x16 -> block byte 22. Identical negative to `radar`: no accessor, no
          row, no reader.

          Worth recording *where the old reading came from*, so it is not re-derived: the stale developer
          table does carry a `NAME TAGS` row at `0xE0DA58` with values `DISPLAY ON`/`DISPLAY OFF`
          (`0xE0DB50`/`0xE0DB60`). But that same table also lists `CHASE CAMERA WHILE SHOOTING` and
          `USB KEYBOARD TYPE` as rows and **omits the entire Over-the-Shoulder group**, so it describes a
          different build of this screen than the one that shipped. The live screen has no name-tag row.

          `hud_display_size` and `hud_hide_name_tags` are inert on this build. **Inert, with evidence.**
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
