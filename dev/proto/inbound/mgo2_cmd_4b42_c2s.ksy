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

  ## Two gates, and the one that bit us is on the clan NAME

  0xD585FC has nine exits before the packet is built (`li r4,19266` at 0xD586CC). They fall
  into two groups, and conflating them is what made this section wrong twice.

  **Gate 1 — the TARGET clan must carry a valid name. Refusal -24, nothing sent.**
  Five paths reach `li r3,-24` at 0xD5877C, and **not one of them reads a clan id**:

      d58604  session == NULL
      d5863c  clan_struct_ptr == NULL
      d58658  strlen(ptr+0x004) <= 2      <- ble, the one that fired
      d58660  strlen(ptr+0x004) > 16
      d58674  0xD32DD0(ptr+0x004) == 0    <- character-class check

  Three of the five test the 16-byte name at `ptr+0x004`. The id at `ptr+0x000` is never
  compared against zero at all — a record with id 0 and a valid 3..16 character name would
  still transmit.

  [RESOLVED 2026-07-27] This is what the live observation was. While `0x4b81` answered 217
  zero bytes, the cached record's name was 16 NULs, `strlen` returned 0, and the `ble` at
  0xD58658 was taken. The section this replaces said the gate was "the session clan record
  at `session_ctx+0x1AA0` non-NULL with id != 0" and credited the fix to serving a real
  `subject_id`. The fix worked, but not for that reason: the same change began writing
  `T+0x00` **and** `T+0x04`, so the id and the name went from zero to real together and the
  id got the credit. Two variables moved; only one was named.

  The target record is `session+0xF850`, filled by the `0x4b81` handler at 0xD58C90
  (`addis r31,r31,1; addi r4,r31,-1968`), in the order `u32 +0x000`, `name[16] +0x004`,
  `u32 +0x018`, `name[16] +0x01C`, `u32 +0x378`, `text[128] +0x67A`, `u32 +0x1384` — the
  same struct shape 0x4b00 and 0x4b21 use.

  **Gate 2 — the SENDER must not already be in a clan. Refusal -1201, nothing sent.**
  0xD586A8 calls 0xD57750, which returns -1 when `profile+6816` is nonzero, 0 when it is
  zero, and -24 with no session; 0xD56EDC is its one-line accessor (`bl 0xD3A094`, then
  `addi r3,r3,6816`). It never reads the membership state at `profile+6837`. The site tests
  `cmpwi r3,-1` -> -1201, so this is "you are already in a clan", matching the polarity
  correction in `mgo2_cmd_4b00_c2s.ksy`.

  **`session_ctx+0x1AA0` was the right word under a wrong base.** 0xD3A094 is
  `profile = session + 22488`, and 0x1AA0 = 6816, so `session_ctx+0x1AA0` and `profile+6816`
  name the same field at absolute `session+22488+6816`. It is the player's OWN clan id. It
  is not a cache of the target clan and `0x4b81` does not populate it.

  Two more exits worth knowing: -36 at 0xD58698 when the link-state check 0xD3844C fails,
  and -61 at 0xD5870C when the flush 0xD34CC0 reports an error.

  Not verified: that the Apply UI passes `&session[0xF850]` rather than another instance of
  the same struct type. The layout match and the 0x4b81 handler writing exactly there make
  it near-certain, but the call site of 0xD585FC was not located.

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
