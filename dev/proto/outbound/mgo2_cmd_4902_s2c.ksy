meta:
  id: mgo2_cmd_4902_s2c
  title: "MGO2 0x4902 — game-lobby list entries (server -> client)"
  endian: be
doc: |
  ## !! ENTRY SIZE IS VERSION-DEPENDENT: 99 on 1.0, 35 on 1.36 [2026-08-03] !!

  **This file describes the release-day disc build.** A 1.36 client reads a **35-byte** entry: the
  64-byte text block below does not exist there. Disc parser `0xD47E18` has one `li r5,64` feeding
  the raw copy at `0xD48034`; 1.36's parser `0xF15B30` has **zero** — its only raw copies are
  `li r5,1` and `li r5,16`, and the read after the name is already the u32 open time.

  Coherent rather than arbitrary: the text block's only consumer in the disc build was the
  subtype-5 branch at `0x890504`, and **1.36 deleted the subtype-5 scan entirely**. The field's only
  reader went away and the field went with it.

  **The note below calling the reference servers wrong is itself wrong, and stays as a lesson.**
  They write 35 bytes because they target 1.36-era clients. 35 is correct there and wrong here;
  99 is correct here and wrong there. This is the second case in one session where "upstream is
  wrong" turned out to be "upstream targets a different build" — the login perks field was the
  first. `CLAUDE.md`'s warning about faithful copying of an inapplicable source has an inverse worth
  remembering: an inherited value that looks wrong may be right for a build we do not serve.

  **Observed live 2026-08-03** — sending 99-byte entries to a 1.36 client does not error, because
  the readers bound-check the 1024-byte receive buffer rather than the payload. The client read our
  495-byte payload at 35-byte stride, believed it had **15** entries, and rendered a Lobby Select
  with Automatching working, **Free Battle present but dead** (its phantom entry's `lobbyId` landed
  past the payload end, so the gate lookup failed and the sub-list bounced silently), and **no
  Training row at all**. The server side is `ClientVersion.hubEntryTextLength()`.

  The payload of one 0x4902 packet: N fixed-size entries back to back, the reply body to the
  client's empty 0x4900 request. Bracketed by 0x4901 (4-byte result; also resets the client's
  entry count and marks the list in progress) and 0x4903 (4-byte result; fires the completion
  event). This is what populates the hub's "Lobby Select" screen.

  ENTRY SIZE IS 99 (0x63) BYTES, NOT 35. Read out of the parser at 0xD47E18 on 2026-07-25,
  field by field, after Lobby Select showed only ever one lobby. Both reference servers write
  35 bytes — index/attributes/id/name/open/close/flag — which is the correct field ORDER but
  omits a 64-byte text block between the name and the open time.

  WHY A SHORT ENTRY DOES NOT ERROR, IT DESYNCS. The stream readers (0xD5CCD8 u4, 0xD5CB8C u1,
  0xD5CC14 u2, 0xD5D018 raw) bound-check the read cursor against the 1023-byte packet BUFFER,
  not against the payload length; only the loop condition (0xD5CEB0) looks at the length, and
  only between entries. So 35-byte entries parse entry 0 correctly — the first 26 bytes of the
  two layouts coincide — and then resume 64 bytes into the middle of entry 2, storing rubbish
  until the cursor runs past the end. Symptom: exactly one lobby in Lobby Select, always
  whichever the server sent first, whatever it was.

  CLIENT-SIDE STORAGE. Each parsed entry is memcpy'd into a 120-byte struct appended to a
  64-entry array at ctx+0xB790 ({marker:u4, count:u4, entries[64]}). Entry 64 onward is
  dropped (cmpwi 63 / bgt -> bail). The struct is the wire layout plus NUL-terminator padding
  after each string, so struct offsets run 1 ahead of wire offsets from the name onward.

  THE MENU IS CATEGORIES, NOT LOBBIES (0x890410-0x8905D8). The hub scans the stored array once
  per subtype, in the order 2, 1, 7-or-8, 5, 3, 4, and STOPS AT THE FIRST MATCH. Each match
  emits one menu row whose label comes from the client's own string table (0x8E0C24 — ids
  251/260 for subtype 2, 245/261 for 1, 249/262 for 7 and 8, 246/263 for 3, 248/265 for 4) and
  whose action code is fixed (9, 10, 11, 13, 14). So the name field is NOT what a category row
  says. A second lobby sharing a subtype adds no second row, but it is not dropped: the list
  behind a category is built at 0x89147C from the same array, accepting any entry whose subtype
  matches the current lobby's (7 and 8 as one group) and separating them by lobby id. Two
  subtype-7 lobbies both appear there — confirmed on echo. That grouping is LISTING ONLY: the
  menu inside a training lobby matches the lobby's own subtype exactly (0x884584), so 7 and 8
  are not interchangeable in the seed data.
doc-ref: dev/docs/PROTOCOL.md "0x4900 — get game lobby info"
seq:
  - id: entries
    type: entry
    repeat: eos
types:
  entry:
    seq:
      - id: index
        type: u4
        doc: "[CONFIRMED] list index, counting from 0 across all packets of the reply. Parsed first (0xD47EB8) and stored at struct+0x00."
      - id: subtype
        type: u1
        doc: |
          [CONFIRMED] lobby subtype, and the only field the hub menu dispatches on (lbz +4 at
          0x890424 and at every other scan). Categories: 1 and 2 are in use and named from
          another server implementation (tier 4 — unverified); 7 and 8 are Basic and Combat
          Training, observed; 3, 4 and 5 exist in the binary but are deliberately left unnamed —
          see LOBBIES.md, which refuses the reference schema's naming as unproven.
          This is the top byte of what the reference servers write as an "attributes" u4 with
          the subtype in its high byte — the same bytes, described correctly.
      - id: dead_05
        type: u1
        doc: |
          [ELF — PRECISE NEGATIVE by CLOSED PROVENANCE, 2026-08-01] parsed (0xD47EE8) into
          struct+0x05. **Nothing in the image reads it**, and this is established by enumerating
          every route to a stored entry rather than by sweeping an address band (batch 2a's
          mistake).

          The array lives at `session + 0x10000 - 18544` = `ctx+0xB790`, `{marker:u4, count:u4,
          entries[64] of 120 bytes}`. That base is computed at **exactly six instructions in the
          whole text section** — every `addi rX,rY,-18544`:

          | site | what it is |
          | --- | --- |
          | `0xD47E64` | this parser |
          | `0xD47850` | the `0x4901` parser (opens the list) |
          | `0xD47758` | the `0x4903` parser (closes it) |
          | `0xD48D10` | `GetLobbyCount(session)` — returns `count`, touches no entry |
          | `0xD49040` | `GetLobbyEntry(session, i)` -> `base + 8 + i*120`, the only entry accessor |
          | `0xD4744C` | `GetLobbyListIfReady(session)` -> the list **header** pointer |

          `0xD49040` has **12 `bl` sites**, all enumerated: `0x884520`, `0x8845F8`, `0x89041C`,
          `0x890458`, `0x890494`, `0x8904D8`, `0x890584`, `0x8905C0`, `0x89144C`, `0x89148C`,
          `0xD4B4C0`, `0xD511E4`. Across all twelve the entry is touched only at **+0** (list
          index), **+4** (subtype), **+6** (see below), **+8** (lobby id), **+10** (name) and
          **+27** (the 64-byte text). `0xD4744C` has **3 `bl` sites** (`0x893374`, `0x893500`,
          `0x893524`); two of them walk the array by hand with `addi r28,r28,120` and read only
          `8(r28)` (= entry+0) and `r28+35` (= entry+27). No entry pointer escapes any of those
          functions — the only values passed on are `entry+27` (a string) and the entry index.

          So `+5` has no reader. Always 0 from us, and it may stay that way.
      - id: subtype5_row_gate
        type: u1
        doc: |
          [ELF — NAMED 2026-08-01, meaning of the value still UNKNOWN] parsed at `0xD47F04`
          (`addi r4,r1,126` into the staging buffer, third of the three consecutive u8 reads at
          `0xD47ECC`/`0xD47EE8`/`0xD47F04`) and memcpy'd to struct+0x06. **Exactly one reader in the image, and it is a hard gate**: at `0x8904F0`,
          inside the subtype-5 scan of the hub menu builder, `lbz r0,6(r29); cmpwi cr7,r0,3; bne
          -> skip`. A subtype-5 lobby whose byte here is anything other than **3** emits no Lobby
          Select row at all. Everything downstream of that test — `GetString(264)` at `0x890504`,
          the format call `0x94AD8C(screen, entry+27, 264, ...)` at `0x890520`, the help id 12 at
          `0x89055C` — is unreachable without it.

          The name says what the byte does, which is all the binary supports. **What the value 3
          means is [UNKNOWN]** and is not guessed: it is not a subtype (that is `+4`), and 0, 1, 2
          and 4..255 are all equally rejected, so the field has no observed domain beyond "3 or
          not 3".

          Same closed-provenance argument as `dead_05` above: six base computations, 12 + 3
          consumer sites, all enumerated, and `+6` appears in exactly one of them.

          Release-day note: subtype 5 is the **Official Tournament** family (`AUTOMATCH.md` §10;
          its title string reads "OFFICIAL CUP LOBBY"), which is post-launch content. Naming this
          gate is not a proposal to open it. `LOBBIES.md`'s open-questions list still files entry
          fields `0x05`/`0x06` as unknown; `0x06` is now settled to this extent and `0x05` is a
          proven dead field.
      - id: flags
        type: u1
        doc: "[UNKNOWN] a bit field: the parser expands all 8 bits one by one into the struct (0xD47F40-0xD47FEC), so each is a distinct boolean. No consumer identified. Always 0 from us."
      - id: lobby_id
        type: u2
        doc: "[CONFIRMED] lobby id, the same id the gate's 0x2003 list carries at 0x2b. This is how a menu selection resolves back to an address: the id looks up the gate list entry (0xD35C7C) to get its ip and port."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED] lobby name, NUL-padded. NOT what Lobby Select displays — that row is labelled from the client's own string table by subtype. Presentation surface for this field is unidentified."
      - id: text
        size: 64
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [CONFIRMED PRESENT, PURPOSE PARTIAL] 64-byte text block, read at 0xD48028 into
          struct+0x1b. The only consumer found is the subtype-5 branch, which
          passes it to the string formatter at 0x94AD8C (0x89050C). Every other category reads
          past it. NULs are fine — but the 64 bytes MUST be on the wire or every entry after
          the first is parsed from the wrong offset. This is the field both reference servers
          omit.
      - id: open_time
        type: u4
        doc: "[PREDICTED] open time. Widened to 64 bits when stored (struct+0x60), which is what a time_t on this target looks like. We send 0 and the lobby is usable, so it is not enforced when the open flag is set."
      - id: close_time
        type: u4
        doc: "[PREDICTED] close time. Same 64-bit widening at struct+0x68. We send 0."
      - id: is_open
        type: u1
        doc: "[PREDICTED] open flag, last byte of the entry (struct+0x70). Both references send 1 unconditionally and the lobby is selectable; 0 has never been sent, so the behaviour it gates is untested."
