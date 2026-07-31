meta:
  id: mgo2_cmd_4b90_c2s
  title: "MGO2 0x4b90 — clan search by name (client -> server)"
  endian: be
doc: |
  **Clan search.** 18-byte payload: `{u8 exact_only, u8 ignore_case, char name[16]}`. The
  reply is a start/items/end triple: `0x4b91` start, `0x4b92` entries (44 bytes each —
  `{u32 id, char name[16], u32 leader_id, char leader_name[16], u32}`), `0x4b93` end. The
  start and end packets carry a result code, never a count.

  ## Two readings were settled here, and both had been wrong

  **1. What the command is.** This file previously read it as "a request that identifies a
  *player by name* with a two-valued mode flag — invite/kick, accept/reject and add/remove
  all fit", and the server briefly implemented it as a leader's "member action" with two
  unknown selector bytes. It is not a member action: it is the **clan search screen**, and
  the two bytes are that screen's own toggles — "Partial and Exact Matches" vs "Exact
  Matches Only", and "Case Sensitive" vs "Case Insensitive". The 16-byte field is the search
  term. [CONFIRMED 2026-07-27] by watching the screen's toggles change the bytes.

  This is why the ELF's `r4 <= 1` range check reads the way it does: a two-valued flag,
  because a checkbox is two-valued — not because it selects between two opposite actions.

  **2. The polarity of the second byte.** It was named `case_sensitive`. It means the
  **opposite**: 1 = IGNORE case. [CONFIRMED 2026-07-27] — searching "bob" with **Case
  Insensitive** selected arrived as `{0, 1}` and matched nothing against a clan named "Bob",
  because the server was running a case-sensitive query. The falsifying observation is
  exactly the one that would have confirmed the old reading and did not: under
  `case_sensitive = 1` the search *should* have been the strict one the user did not ask
  for, and the user had asked for the loose one.

  The polarity is the **client's**, not a per-screen quirk: the player-search screen
  (`0x4600`) sends the same `{0, 1}` from its own identical pair of toggles, and it failed
  the same way for the same reason. Both searches now read 1 as ignore-case.

  Evidence (ELF, retail BLUS30109): sender 0xD55CDC, signature (session, u8 a, u8 b,
  char* name). Prologue spills `stb r4,1432(r1)` and `stb r5,1440(r1)`. Builder
  `bl 0xD5CF40` at 0xD55D98 (`li r4,0x4b90` at 0xD55D94), then
  `bl 0xD5C86C` at 0xD55DA8 (u8 from 1432 = the r4 parameter),
  `bl 0xD5C86C` at 0xD55DB8 (u8 from 1440 = the r5 parameter),
  `0xD5D0AC(pkt, name, 0x10)` at 0xD55DCC (fixed 16-byte `memcpy`),
  seal `bl 0xD5C828` at 0xD55DD8, flush `bl 0xD34CC0` at 0xD55DE8.

  Validation, all returning -24 without sending: session != NULL; **r4 <= 1** (`clrlwi` to a
  byte then `cmplwi 1` / `bgt` at 0xD55CF4/0xD55D20); name != NULL; `strlen(name) <= 16`
  (0xDCC7F8 at 0xD55D30); and the name passes the character-class validator 0xD32DD0 — the
  same one 0x4b00 and 0x4b42 apply to their name fields. Note r5 is NOT range-checked, even
  though it is used as a boolean.

  On a successful flush the flow state advances via `0xD32E08(session, 114, 1)`. This sender
  has no clan-record precondition (no 0xD57750 / 0xD5709C call), which sets it apart from the
  rest of the family and fits a search reachable by anyone.

  Record-size note: `0x4b92`'s entry is **44 bytes**, which is what this build's parser
  reads. Another server writes 48, adding a flag byte and three pad bytes before the
  trailing u32; that is a different build, not a correction to this one.
seq:
  - id: exact_only
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] The screen's "Partial and Exact Matches" (0) vs "Exact Matches
      Only" (1) toggle. Position and width exact (0xD5C86C), and **range-checked to 0 or 1**
      at 0xD55D20 — the client will not send any other value.
  - id: ignore_case
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] **1 = ignore case**, 0 = case-sensitive. Named `case_sensitive`
      here until 2026-07-27, which was backwards: "bob" searched with Case Insensitive
      selected arrives as `{0, 1}` and must match "Bob".

      The same polarity holds on the player-search screen (`0x4600`), so it belongs to the
      client's toggle convention rather than to this screen. Position and width exact
      (0xD5C86C); unlike `exact_only` it is not range-checked by the sender.
  - id: name
    type: str
    size: 16
    encoding: UTF-8
    doc: |
      [CONFIRMED 2026-07-27] The search term — a clan name, typed by the user. Exactly 16
      bytes, `memcpy`'d from the caller's string; `strlen <= 16` and the 0xD32DD0
      character-class check are enforced first, so a term that reaches the server is already
      a legal clan name. 16 is the protocol name width throughout this game.

      Whether the tail is zero-filled depends on the caller's buffer and is [UNKNOWN] —
      unlike 0x4b64/0x4b66 there is no `memset` of a staging buffer here, so `pad-right` is
      deliberately not asserted and the server reads up to the first NUL. Encoding is a
      guess.
