meta:
  id: mgo2_cmd_4b00_c2s
  title: "MGO2 0x4b00 — create clan (client -> server)"
  endian: be
doc: |
  **Create a clan.** 144-byte payload: the 16-byte clan name followed by the 128-byte clan
  description. Reply is `0x4b01` `{u32 result, u32 clan_id}`; on `result == 0` the client
  stores the second word as its own clan id and makes itself leader (`0xD56E84`
  `lwz r9,116(r1)` / `stw r9,6816`, then `0xD56E90` `li r0,2; stb r0,6837`). A nonzero
  result ends the reply after four bytes and the client keeps whatever record it had.

  [CONFIRMED 2026-07-27] Capture-proven live: creating a clan named "best clan" with the
  comment "numbuh 1" put exactly those two fields on the wire, at exactly these widths and
  in this order — the layout the ELF predicted, unchanged. This is the rare case where a
  spec derived from the disassembly alone survived first contact with the client untouched.

  Both fields are written by the fixed-length blob serializer 0xD5D0AC (a bounded `memcpy`
  of exactly r5 bytes into the packet buffer), so the widths are the *field* widths, not
  string lengths — whatever trailing bytes the source buffer holds go on the wire.

  Evidence (ELF, retail BLUS30109): sender 0xD579AC. Builder `bl 0xD5CF40` at 0xD57A9C
  (`li r4,0x4b00` at 0xD57A98), then
  `0xD5D0AC(pkt, arg+0x004, 0x10)` at 0xD57AB0 and
  `0xD5D0AC(pkt, arg+0x67A, 0x80)` at 0xD57AC4,
  then the seal `bl 0xD5C828` at 0xD57AD0 and the flush `bl 0xD34CC0` at 0xD57AE0.

  The two source offsets are the give-away for the whole family: `arg+0x004` and
  `arg+0x67A` are the *same* struct offsets the clan profile reply 0x4b21 fills with the
  clan name and the clan description. The client keeps one clan struct and every command in
  the family addresses fields inside it.

  The sender takes (session, ptr) and validates the pointed-at struct before building:
  `strlen(arg+0x004)` must be > 2 and <= 16, and the string must pass the character-class
  check 0xD32DD0; `strlen(arg+0x67A)` must be <= 128. Any failure returns -24 (0xFFFFFFE8)
  and sends nothing. So a name that reaches the server is already well-formed, and the only
  failure left for the server to raise is a collision.

  **Correction to an earlier reading of the preconditions.** This file previously recorded
  that the sender also requires 0xD57750 — the session clan record at
  `session_ctx+0x1AA0` non-NULL with id != 0, else -1201. That cannot gate this path as
  written: the 2026-07-27 capture was produced by a character with *no* clan, whose record
  id is 0, and the packet went out. So either the 0xD57750 call sits on a branch this path
  does not take, or the gate was misattributed. The clan-record gates on the *other* senders
  (0x4b04, 0x4b30, 0x4b40, 0x4b42, 0x4b48, 0x4b64, 0x4b66) are unaffected and still stand.

  **The founding requirement is not checked here.** 0xD579AC reads no play time and no
  level, and lobby string 17193 ("You must have 20 hours of playing time and a Level of at
  least 3 to create a clan") is not reachable from the client's error table — so the server
  is the only thing that can enforce it. This server does, refusing with -1206,
  "Conditions to create clan have not been met." (dispatcher `0xA7E680`). Neighbouring
  codes on the same op: -1200 name already exists, -1230 banned from creating clans,
  -1231 comment contains an invalid word, -1233 name contains an invalid character, -24
  name not long enough.

  On a successful flush the client advances its flow state with `0xD32E08(session, 92, 1)`.
seq:
  - id: name
    type: str
    size: 16
    encoding: UTF-8
    doc: |
      [CONFIRMED 2026-07-27] The clan name, typed on the create screen — "best clan" on the
      wire in the confirming capture. Exactly 16 bytes, `memcpy`'d from `arg+0x004`; the
      caller-side string is length-checked (3..16) and character-class checked (0xD32DD0)
      before the packet is built. 16 is the protocol name width throughout this game. The
      client appends its own NUL when it stores the name at `profile+6820`, so the wire
      field carries no terminator of its own and a full 16-character name is legal.
      Encoding is a guess — no charset evidence was read; the server reads it as ISO-8859-1.
  - id: description
    type: str
    size: 128
    encoding: UTF-8
    doc: |
      [CONFIRMED 2026-07-27] The clan description — the field the client labels **Clan
      Comment**; "numbuh 1" on the wire in the confirming capture. Exactly 128 bytes,
      `memcpy`'d from `arg+0x67A`. Only `strlen <= 128` is checked, with no character-class
      check, so this is freer text than `name`.

      The same field is edited afterwards by 0x4b64, which sends a lone 128-byte block and
      nothing else, and is echoed back by 0x4b21 at `T+0x67A` — three commands, one struct
      offset. 0x4b66's 512-byte sibling is the separate **Clan Notice** at `T+0x700`, not a
      wider version of this. Encoding is a guess.
