meta:
  id: mgo2_cmd_4904_c2s
  title: "MGO2 0x4904 — request the event/official-match detail record by id (client -> server)"
  endian: be
doc: |
  **SUBSYSTEM IDENTIFIED 2026-08-01: this is the TEAM / OFFICIAL-TOURNAMENT block, not "clan".**
  See the shared note at the bottom of this file.

  Sender `0xD47AFC`, builder call `0xD47B70`, request-status slot `0x39` (57) completed with
  state 1 at `0xD47BDC`.

  **Paired reply: `0x4905`** — established by slot bijection, which is tier 1 and not a guess:
  `0xD32E08(session, slot, state)` writes `session[352 + slot*4 + 8]`; exactly one site in the
  image sets slot 57 to 1 (this sender, `0xD47BDC`) and exactly one sets it to 2
  (`0xD48620`, inside the parser at `0xD4812C`, whose own id check is `cmpwi r0,0x4905` at
  `0xD4817C`). The whole slot table was enumerated — 251 `0xD32E08` call sites, one `=1` and one
  `=2` per slot — so the pairing is exhaustive, not sampled.

  **What the reply is.** `0x4905` memsets and fills a **912-byte record at `session+0xD598`**
  (`addi r0,r28,-10856` off `session+0x10000`, at `0xD48218`). Its accessor is `0xD47478`
  (`return session + 0xD598`), which has exactly two `bl` sites in the image:
    * `0x8C31D8`, inside the team/tournament screen, which reads `record+0x112` as the second
      operand of disc string 731 — *"Number of Players Currently Joined: %d / %d"*;
    * `0x901858`, in the screen module that also contains this request's only caller, which
      passes `record+0x118` (the 64-byte block, wire `+0x106`) to the text formatter `0x246EC0`.
  So the record is an **event/official-match detail record carrying a participant count and a
  display name**. The exact event class it describes is [UNKNOWN] beyond that.

  **What triggers the send.** Exactly one caller in the image: `0x902274`, inside the screen
  state machine entered at `0x902184`. It passes `r4 = *(screen+0x6C)`, a word written once at
  screen construction (`stw r26,108(r29)` at `0x9024A8`) from a constructor argument — i.e. the
  id of the record the screen was opened to display. On success the screen advances to state 2.

  **Release-day note.** The surrounding screens are the Official Tournament / Survival / Team
  family (disc strings 676 "TEAM CREATION", 38 "OFFICIAL TOURNAMENT", 72 "SURVIVAL",
  75 "TOURNAMENT", 640 "TEAM SELECT", 806 "Survival Match List"). Survival is Ver. 1.10 and
  Tournament Ver. 1.20 content, so this whole family is **post-launch and out of scope for v1**;
  mapping it is research, not a proposal to serve it.

  Total payload: 4 bytes.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26, extended
  2026-08-01. Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a
  1024-byte payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at
  `pkt+0x00`; the enclosing function then appends fields with the serialisation primitives;
  `0xD5C828` finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends.
  Everything between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.

  ---
  **Shared note — the 0x49xx family is TEAM / TOURNAMENT, not clan.** `COMMANDS.md` and the
  `0x49xx` outbound schemas file this block as "clan / GHQ / roster". The UI callers say
  otherwise, in the client's own words: the screens that drive `0x4923`, `0x4940`, `0x4912` and
  `0x491B` render disc strings 691 "Kick", 692 "Disband Team", 695 "Leave Team", 698 "You are
  about to kick\n%s off the team.", 699 "Are you sure you want to\ndisband the team?", 701 "This
  will affiliate the team with the team leader's clan…", 713 "The team has been disbanded.",
  716 "Forming a team…", 726 "Team formation complete." A clan is a separate object the *team*
  can be affiliated with (see `0x4923`). The 680-byte record the outbound schemas call the "clan
  record" lives at `session+0xD928` — the object returned by `0xD491F8`, which the team screens
  call — and its 8-slot member array at `+0x17C` is the **team roster**, member 0 being the
  **team leader** (three senders in this batch gate on `members[0].character_id == my character
  id`). [ELF, 2026-08-01]
doc-ref: dev/docs/PACKETS_NOT_OBSERVED.md
seq:
  - id: detail_id
    type: u4
    doc: |
      [ELF — POSITION AND SOURCE CERTAIN; SEMANTICS INFERRED] `0xD5C9BC` at `0xD47B80`, source =
      the sender's r4 argument (spilled `1416(r1)`).

      It is the **key of the record being requested**, on two independent pieces of evidence:
        1. After a successful send the client caches it into a global — `stw r0,27908(r9)` at
           `0xD47BD8`, where `r9 = *(session+0x11904) + 0x20000`, i.e. `hub+0x26D04` — and only
           when that hub pointer is non-NULL (`0xD47BC0`–`0xD47BD0`).
        2. The `0x4905` parser reads a u32 at wire `+0x04` and, when the same hub pointer is
           non-NULL, **discards the entire reply** unless it equals that cached value
           (`0xD481E8`–`0xD4820C`). So the server must echo whatever this request carried; it
           cannot choose the value.
      The caller supplies it from `screen+0x6C`, set at screen construction (`0x9024A8`).
      Which id space it belongs to (event id, match id, list index…) is [UNKNOWN] — the
      constructor argument was not traced past the screen boundary.
