meta:
  id: mgo2_cmd_43e0_c2s
  title: "MGO2 0x43e0 — start automatching (client -> server)"
  endian: be
doc: |
  **Start automatching.** One byte: the rule filter. Reply is `0x43e1`.

  ## It is not a status fetch

  [CORRECTED 2026-07-28] This command was long documented as "a status fetch sent on entry to the
  automatching lobby". It is **start automatching**, sent on *confirm* from state 4 of the screen's
  state machine (`0x93CD58`); the screen's constructor at `0x93B4D0` makes no network call at all.

  The client's own error table settles it without ambiguity: a timeout on this request slot prints
  *"Unable to **start** automatching"* (`0x93CDD4`), where `0x43e2`'s prints *"Unable to **cancel**"*
  (`0x93D178`).

  ## Answering result 0 is a commitment, not an acknowledgement

  A zero result sets the client's "loaded" flag and **registers push channel 60** (`0x93CF04`), after
  which the client sends **nothing whatsoever** and waits — for about twenty minutes, then gives up.
  There is no poll and no keepalive; state 6 makes no network call (`0x93CF78`).

  So answer 0 only when a matchmaker will actually look at this player. Otherwise answer `-970` and
  the client prints the sentence Konami shipped for it, *"Automatching is currently not open."*

  ## Evidence

  Builder `0xD5BCB4` = `f(ctx, u8 arg)` (`stb r4,1416(r1)` at `0xD5BCE0`); `bl 0xD5CF40` at
  `0xD5BD28` (`li r4,0x43E0` at `0xD5BD24`); one `0xD5C8A0` (u8) write at `0xD5BD38`; seal
  `0xD5C828` at `0xD5BD44`; flush `0xD34CC0` at `0xD5BD54`. Not encrypted. **Total payload 1 byte.**
  Marks request-status slot **50**.

  The sender does **not** validate the byte, so 11 is the caller's value rather than a protocol
  constant enforced at the source — the range check lives in the label mapper, not here.

seq:
  - id: rule_filter
    type: u1
    doc: |
      [CONFIRMED] The rule the player selected, or `11` for "no preference".

      Rows are built at `0x93B60C`-`0x93B828`, and state 4 sends the low byte of the selected row's
      u32 (`lbz r4,11(r11)`, `r11 = S+0x450 + idx*792 + 768`):

      | row | value | label |
      | --- | --- | --- |
      | 0 | **11** | disc string 925, *"Do not specify rules."* — the default selection |
      | 1-6 | 0,1,2,3,4,5 | rule names via `0x8E11E0` |
      | 7 | 7 | Team Sneaking, **behind the feature bit we clear** |

      **11 is deliberately out of range**: the rule-label mapper accepts 0-10, so the sentinel cannot
      collide with a real rule. Rule 6 (BOMB) has no row.

      Expect `{0,1,2,3,4,5,11}`, plus 7 only if Team Sneaking is ever enabled. The disc corroborates
      the set independently: `lobby/scenerio.gcl` carries `-rule_bit 191`, bits 0-5 and 7.

      **Rule 0 is a real filter, not a sentinel** — confirmed live 2026-07-29, when two clients both
      requesting rule 0 formed a Deathmatch game.
