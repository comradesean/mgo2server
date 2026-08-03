meta:
  id: mgo2_cmd_4910_c2s
  title: "MGO2 0x4910 — CREATE TEAM (client -> server), reply 0x4911"
  endian: be
  encoding: ISO-8859-1
doc: |
  Sender `0xD4AC20`, builder call `0xD4AD64`. Unhandled; post-launch Tournament/Survival
  content, **not served in v1**. Tier-1 only throughout — no available client build exercises
  this family, so nothing here can reach tier 2.

  IDENTIFIED 2026-08-03: **this is the Create Team request**, named by the client's own
  sentences, not by neighbours. The single call site image-wide is `0x8BE6A4`, state 10 of the
  Create Team screen (`0x8BD108`-`0x8BE960`, screen object global `0xFE7358` -> `0x166E924`,
  15-state machine `0x8BDF10`). The screen's confirm row rejects a short name with dialog
  **5123 "Team name is not long enough. Team names must be between 3 and 15 characters."**, a
  short password with **3844 "Password Lock is not long enough..."**, and state 11 maps reply
  results: -262/-1001 -> 5124 "Team name contains an invalid character or word. Unable to
  create team.", -1000 -> 5125 "Comment contains an invalid word...", -1400 -> 5888,
  -1042 -> **5312 "You are currently banned from team competitions."**, else 5122; a nonzero
  builder return -> 5120 "Unable to create team."; 6000-tick timeout -> 5121. The screen's own
  string run (disc `lobby` 664-671; `dev/analysis/strings/lobby.txt` file indices 14041-14090,
  +6-file/+1-id stride verified on four points) reads "Team Name", "Enter a team name...",
  "Require a password to join the team...", "This comment is displayed when players select
  this team.", "Create a team using these settings.". The screen's four `0x94AD8C` rows pair
  label/description/callback as (664,668)->state 4, (665,669)->state 6, (666,670)->state 8,
  (667,671)->state 10 — the three text-entry rows and confirm, in wire-field order.

  **The reply is `0x4911`**, three-point: the builder arms request-status slot **60**
  (`0xD32E08(session, 60, 1)` at `0xD4AED4`; the `li r4,60` is at `0xD4AECC` — the earlier
  "subsystem index 0x3C at 0xD4AEC0" was wrong on both counts, `0xD4AEC0` is a `cmpwi` and 60
  is the slot number), state 11 polls and reads slot 60 (`0xD49AF0`/`0xD49830`), and
  `mgo2_cmd_4911_s2c.ksy` records that `0x4911`'s wrapper completes slot 60. `0xD33D8C(session,
  57)` fires after the send.

  **`S` is a screen-local instance of the 680-byte team record** (`S = screenObj+104`, memset
  to 0 at state 1, `0x8BE01C`), the same type `0x4911` parses into `session+0xD928` — five
  offsets line up simultaneously (name +0x005, comment +0x016, flags +0x094, and the
  {lobby_id, lobby_subtype, rule} triple at +0x25C/+0x260/+0x261). Because the only route to
  this instance is module A's single global, writer enumerations over the module are closed,
  which is what makes the always-zero findings below conclusive.

  Validation in the sender (unchanged from the 2026-07-26 read, plus two gates it omitted):

  - `r3 == 0 || r4 == 0` -> -24 (`0xD4AC28`/`0xD4AC6C`); `0xD3844C(session) == 0` -> **-36**
    (`0xD4AD24`-`0xD4AD34`). `0xD38504(session)` supplies the send target for `0xD34CC0`.
  - `strlen(S+5)` must be **3..16** (`0xDCC7F8`, `ble`/`bgt` at `0xD4AC8C`/`0xD4AC94`) and must
    pass the string-validity check `0xD32DD0`.
  - `strlen(S+22)` must be **<= 128** (`0xD4ACC0`).
  - if bit `0x80` of the u32 at `S+148` is set, `strlen(S+152)` must also be 3..16 and pass
    `0xD32DD0` (`0xD4ACC8`-`0xD4AD08`) — conditional on the flag but **always written**, so
    the wire layout is fixed.
  - `0xD4908C` must not return -1 — and the MEANING of that gate was stated backwards here:
    `0xD4908C` returns -1 when the session team record's id is **non-zero**, so the gate is
    **"you must not already be in a team"**; failing it returns -1004, routed to dialog 5120.

  **Builder side effect, previously unrecorded:** at `0xD4AE3C`/`0xD4AE40`, immediately before
  serialising `S+608`, the builder zeroes `S+609` (rule) and `S+604` (lobby id) — the request
  deliberately carries the lobby *subtype* but not the lobby id or rule; the server supplies
  those in the reply.

  **Reachability: reachable in code, unreachable in play on this build.** No version guard and
  no dead branch — the Create Team row is unconditionally installed by the parent menu
  (`0x8BC028`, label 662 / description 663, callback `0x8BC524` -> constructor `0x8BD188`).
  What gates it is which lobby you are standing in: the constructor reads the selected lobby
  subtype (`0x883F20()+0x294`) to pick its title — string 661 for subtype 5, 660 for 4, 659
  otherwise — and the parent menu swaps in a different row (806/807, callback `0x8BC430`) for
  subtype 4. Subtypes 3/4/5 are Tournament/Survival/Official Tournament (AUTOMATCH.md §10),
  and release day serves no such lobby. Caller scan control: the greps that find zero
  additional callers of `0xD4AC20` (OPD `0x1029B50`, zero data refs) find 108 refs to
  `0xD38504`, 120 to `0xD3844C`, 24 to `0xD4908C` and both intra-band `bl`s.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`), 2026-07-26; screen
  provenance and names 2026-08-03. Method: the packet builder `0xD5CF40` (`li r4,<id>` at
  builder_call-4) memsets a 1024-byte payload buffer at `pkt+0x40`, zeroes the cursor at
  `pkt+0x454` and stores the id at `pkt+0x00`; the enclosing function then appends fields with
  the serialisation primitives; `0xD5C828` finalises (copies the cursor into `pkt+0x04` as the
  length) and `0xD34CC0` sends. Everything between the builder call and the finaliser is the
  payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
doc-ref: dev/proto/outbound/mgo2_cmd_4911_s2c.ksy
seq:
  - id: team_name
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF 2026-08-03] Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AD78`) from `S+5` = team
      record `+0x005`, `0x4911`'s `team_name`. 3..16 characters, name-validity-checked.
      Source: state 1 pre-fills it from client-store key 140 — the character name, per
      CLIENT_STORE.md §4 — then state 4's on-screen keyboard (prompt 664 "Team Name", max 15
      chars) overwrites it, narrowed to 16 bytes in state 5 (`0x8BE3F4`-`0x8BE414`).
  - id: comment
    type: str
    size: 128
    encoding: ASCII
    doc: |
      [ELF 2026-08-03] Raw 128-byte block (`0xD5D0AC` r5=128 at `0xD4AD8C`) from `S+22` = team
      record `+0x016`, `0x4911`'s `comment` ("This comment is displayed when players select
      this team.", string 670). Written directly by the state-8 keyboard (label 666, max 81
      chars, dst `obj+126`, cap 128). The write's terminator lands at `obj+254` with the only
      live flag bit at `obj+255` — the same shape as the overrun `0x4911` analyses from the
      parse side, and inert here for the same reason.
  - id: flags_90
    type: u1
    doc: |
      [ELF] One byte built on the stack at `1328(r1)` and written raw (`0xD5D0AC` r5=1 at
      `0xD4AE0C`). It repacks four bits of the u32 at `S+148`:
      `S+148 & 0x80 -> bit 0x01`, `& 0x40 -> 0x02`, `& 0x08 -> 0x10`, `& 0x04 -> 0x20`
      (`rldicl. r9,r0,57/58/61/62,63` at `0xD4ADA8`-`0xD4ADF4`).

      [ELF 2026-08-03] Named, and the client can only ever send 0x00 or 0x01:
      * **bit 0x01 = password_lock** (struct bit 0x80) — the ONLY bit the screen writes: the
        confirm row sets it when `strlen(password) > 2` (`ld/ori 128/std 248(r9)`), clears it
        when empty, and raises dialog 3844 for lengths 1-2. Same struct bit `0x4911` names
        Password Lock (strings 654/665), gating the join path's password buffer
        (`0x8C99FC`/`0x8C9F08`).
      * **bit 0x02 = clan_affiliation** (struct bit 0x40), named by `0x4911` (strings
        689/690) — **never set here**; the create screen has no writer, so affiliation is a
        later operation (`0x491C`'s subsystem), not a creation option.
      * bits 0x10/0x20 (struct 0x08/0x04): dead both ways — no writer here, and the `0x4911`
        parser expands only wire bits 0/1/2, so no server source either.
      The enumeration is closed, not a grep: `S` is memset at screen entry, the instance is
      reachable only through `0xFE7358`, and a module-wide sweep at displacement 248/252
      returns exactly the four instructions above.
  - id: password
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF 2026-08-03] Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AE24`) from `S+152` = team
      record `+0x098` — inside the `+0x098..+0x0AF` hole the `0x4911` parser never fills,
      which is correct for a secret the server should not echo. Named by dialog 3844
      ("Password Lock is not long enough..."), by the state-6 keyboard (label 665, description
      669 "Require a password to join the team. If no password is entered, password check is
      disabled.", OSK flag 0x20000000 where name/comment use 0x03000000/0x01000000), and by
      the screen rendering it as strlen repetitions of a mask character (`0x8BDBB8`-`0x8BDC1C`,
      `0x8BE5A8`-`0x8BE618`). Validated 3..16 chars only when `flags_90 & 0x01`; always
      present on the wire. The `0x4912` join sender is the twin: `{u32, 16-byte block}`.
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF 2026-08-03] `0xD5C8A0` at `0xD4AE44`, from `S+608` = team record `+0x260`,
      `0x4911`'s `lobby_subtype`. Filled in state 1 from the selected lobby row
      (`0x883F20()+0x294`, the same byte LOBBIES.md documents) or, failing that, from the
      session's current-lobby struct via `0xD3F7B0` (+0x08). **The request declares which
      lobby subtype the team is created in** — and the builder deliberately zeroes the
      adjacent rule and lobby id before sending (doc block), so subtype is the only locator
      the server gets.
  - id: unknown_a2
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD4AE58`, from `S+168` (`0xA8`). [UNKNOWN — and provably a
      CONSTANT ZERO on this build, 2026-08-03.] `S` is memset at screen entry, the instance
      is reachable only through module A's global, and three swept bands (module
      `0x8BD000`-`0x8BE960`, screens `0x8B0000`-`0x8D8000`, networking `0xD38000`-`0xD64000`)
      contain no writer of `S+168..172` — every displacement hit is the Create Game screen's
      unrelated 968-byte host-settings object (a coincidence of offset between two struct
      types; its `+168` is a lobby subtype, and that must NOT be borrowed as a name). Control:
      the same sweep finds 7 real hits for the neighbouring 608/609. Also inside the
      `+0x098..+0x0AF` hole `0x4911` never fills, so no s2c counterpart names it either.
      The client always sends zero here.
  - id: unknown_a3
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD4AE6C`, from `S+169` (`0xA9`). [UNKNOWN — constant zero, no writer;
      same closed enumeration and control as `unknown_a2`.]
  - id: unknown_a4
    type: u4
    doc: |
      [ELF] `0xD5C9BC` at `0xD4AE80`, from `S+172` (`0xAC`). [UNKNOWN — constant zero, no writer;
      same closed enumeration and control as `unknown_a2`.]
