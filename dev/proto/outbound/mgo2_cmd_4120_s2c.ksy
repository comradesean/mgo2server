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
      - id: unknown_05
        size: 6
        doc: "[UNKNOWN] 0x05. Zero, purpose unknown."
      - id: switch_modes
        type: u1
        doc: "[INFERRED] 0x0b. Low nibble weapon, high nibble item."
      - id: unknown_0c
        type: u1
        doc: "[UNKNOWN] 0x0c. Zero, purpose unknown."
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
        doc: "[UNKNOWN] 0x17. Zero, purpose unknown."
      - id: codec_entries
        type: codec_entry
        repeat: expr
        repeat-expr: 4
        doc: "[INFERRED] 0x20. Codec entries 1-4, four bytes each; the meaning of the four bytes is unknown."
  codec_entry:
    seq:
      - id: unknown_00
        type: u1
        doc: "[UNKNOWN] PROTOCOL.md calls the four bytes a, b, c, d and records no meaning."
      - id: unknown_01
        type: u1
        doc: "[UNKNOWN]"
      - id: unknown_02
        type: u1
        doc: "[UNKNOWN]"
      - id: unknown_03
        type: u1
        doc: "[UNKNOWN]"
