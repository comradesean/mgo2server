meta:
  id: mgo2_cmd_4b42_c2s
  title: "MGO2 0x4b42 — apply to join a clan (client -> server)"
  endian: be
doc: |
  **Apply to join the clan named by this id.** 4-byte payload: one unsigned u32, the clan id
  taken from the caller's struct. Reply is `0x4b43`, a bare u32 result.

  [CONFIRMED 2026-07-27] The sender also validates a 16-byte NAME string in that struct and
  does **not** put it on the wire; the name travels only as the label the client caches
  locally after the send.

  ## The client refuses to transmit unless it already holds a clan id

  This is the part that matters for making Apply work at all. 0xD585FC requires 0xD57750 —
  the session clan record at `session_ctx+0x1AA0` non-NULL **with id != 0** — and returns
  -24 (0xFFFFFFE8) *without sending anything* if that fails. The record is populated by the
  `0x4b81` reply (Clan Info for a clan you are not in). So while `0x4b81` was 217 zero
  bytes, pressing Apply produced -24 and no packet ever reached the server: the command
  looked unimplemented when it had simply never been sent. Serving a real `subject_id` in
  `0x4b81` is what makes 0x4b42 start arriving.

  **Open conflict — the observation stands, the attribution may not.** A later reading of
  0xD57750 has it returning **-1** when `profile+6816` is non-zero and **0** when it is zero,
  reading the character's own clan id and never touching `session_ctx+0x1AA0`. On that
  reading this sender's use of it at 0xD586A8 is `cmpwi r3,-1` -> -1201, i.e. **"you are
  already in a clan, so you may not apply to another"** — the opposite gate from the one
  described above, and the same polarity error that was corrected in
  `mgo2_cmd_4b00_c2s.ksy`.

  What is not in doubt is the live behaviour: with `0x4b81` serving 217 zero bytes, Apply
  sent nothing, and serving a real `subject_id` made it send. So *something* in this sender
  reads a cached clan id and gives up. Whether that something is 0xD57750 or a separate -24
  check on the argument — 0xD585FC and 0xD586A8 are different addresses and may well be two
  gates, one on the target clan and one on the sender's own membership — has not been
  settled. Do not collapse the two into one claim; disassemble 0xD585FC and confirm which
  address produces the -24 before rewriting this section.

  ## After the send, the client marks itself pending

  0xD58714..0xD58758: the client writes into its session context (0xD3A094) at `+0x1AA0` —
  `stw` the sent id at +0x1AA0, `stb` **0** at +0x1AB5 (the status byte), memset 17 bytes at
  +0x1AA4 and `strncpy` 16 bytes of the validated name in. Status 0 is **pending**, leaving
  1 (member) and 2 (leader) to come from the server. So an application is real state on both
  sides, and the server stores it as one rather than treating it as a fire-and-forget.

  ## Where the application goes

  Not into a roster the leader polls: clan applications are delivered to the leader as
  **mail**, mailbox type `0x10` on `0x4820` (type `0x0f` is ordinary mail). There is no
  applicant-list command in the client's flow — see mgo2_cmd_4b73_c2s.ksy.

  Evidence (ELF, retail BLUS30109): sender 0xD585FC. Builder `bl 0xD5CF40` at 0xD586D0
  (`li r4,0x4b42` at 0xD586CC), one write `bl 0xD5C9BC` at 0xD586E0 (unsigned u32, 4 bytes
  MSB first, from `*(u32*)arg+0x00`), seal `bl 0xD5C828` at 0xD586EC, flush `bl 0xD34CC0`
  at 0xD586FC.

  Other preconditions on (session, ptr): ptr != NULL; `strlen(ptr+0x04)` > 2 and <= 16; and
  that string passes the character-class validator 0xD32DD0 — the same one 0x4b00 applies to
  the clan name. Failures return -24.

  On success the flow state advances via `0xD32E08(session, 96, 1)`.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The id of the clan being applied to. Position and width exact
      (unsigned, 0xD5C9BC), read from `*(u32*)(arg+0x00)` — the same value the client
      immediately caches at `session_ctx+0x1AA0`, the field 0xD57750 tests for non-zero as
      the "am I in a clan" gate, and the field 0x4b48 later sends back.
