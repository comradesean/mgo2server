meta:
  id: mgo2_cmd_43c9_s2c
  title: "MGO2 0x43c9 — server -> client: start-round reply (reply to 0x43c8)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43C9` at `0xD38A40` -> stub `0xD39300` ->
  parser **`0xD3FEAC`**. Request-status slot **49**.

  This is the reply of the pair PROTOCOL.md renumbered on 2026-07-23: the client's real
  start-round command is `0x43c8` (builder `0xD40CB4`, payload `{u32, u8}`), **not** `0x43ca`,
  which has no builder anywhere and is never sent; our handler and reply were bound to
  `0x43ca`/`0x43cb`, which the client has no parser for.

  Parser, in order:

  1. verify `hdr.command == 0x43C9` (else `-70`); zero a stack slot;
  2. `0xD5C844` open; `0xD5CC64` u32 -> `result`;
  3. **only if `result == 0`**, `0xD5CCD8` u32 -> field 2; and **only if that field is nonzero**,
     call `0xD3A094(ctx)` and store it at `+13048` (`0x32F8`) of what it returns — the profile
     sub-object;
  4. `0xD5C858` close; `0xD32E08(ctx, 49, 2)`, `0xD32E70(ctx, 49, result)`.

  **8 bytes on success; 4 bytes on failure is well-formed** (the second read is skipped when
  `result != 0`, unlike `0x4317`). Two fields, both understood — see each field's `doc:`.

  ## The second field is not a round token (corrected 2026-07-26)

  It was documented for three days as an opaque "round handle" whose single reader was a UI
  record populator, and that reading was used to argue that round reports carry no game
  identifier. The *conclusion* about round reports still holds — no packet builder references
  the slot — but the reader was misidentified, and the field is not inert.

  `profile+0x32F8` has exactly three accesses in the whole binary:

  | site | what it does |
  | --- | --- |
  | `0x414898` | zero-fill; one word of a bulk clear covering ~200 consecutive profile fields |
  | `0xD3FF6C` | this parser's write, guarded by `!= 0` |
  | `0x8842AC` | `lwz r0,13048(r11)` / `stw r0,12(r31)` — the **join-announcement packer** |

  From `struct+12` it is published by `0x2762A0` as replicated player variable **352**, broadcast
  as P2P opcode `0x24` to every peer, and lands in `G->0x1C0` on each receiving client, where
  `0xA359A4` branches on it: **nonzero skips the instructor recognition prompt** ("Save current
  instructor, <name>, as the instructor for your personal data?").

  So the value travels — over the in-game P2P link, not over ours — and it means "this player
  already has a saved instructor". Nothing in the client ever clears it; only the profile reload
  at `0x414898` resets it, so it survives for the rest of a boot.

  ## Resolved 2026-07-26: this was one of TWO writers, and the other one was the culprit

  Sending `{0, 0}` here did **not** raise the prompt on its own (live combat training, 01:28:30
  UTC, wire `0000000000000000`, graduation recorded, still only "Choose a rating"). The reason is
  that `profile+0x32F8` has a **second writer**: the `0x4122` personal-info parser at `0xD3D624`
  (`addi r4,r25,13048` -> the same u32 reader `0xD5CCD8`), which stores the payload's last word
  **unguarded** — no `!= 0` test — on every personal-info reply, i.e. at every login. We were
  sending a fixed `00 A7 00 0D` there, copied from another server, so the field was re-stamped
  long before any round started. See `blanks/outbound/mgo2_cmd_4122_s2c.ksy`, field
  `saved_instructor`. Both writers now send zero; the `0x4122` one is the fix that matters, and
  this one is still required, because otherwise the first round start would re-stamp it.

  Two corrections to the chain as originally written here. `0xA359A4` reads **`G+0x1C0`**, not
  `profile+0x32F8` — the two are joined by the P2P hop, not a direct read (`G+0x1C0` has one
  writer, `0x9D17C8`, reachable only from arm 36 of the P2P table at `0x9D1500`, and one reader,
  `0x9CD5D0`). And the prompt's text is **not** absent from the game: it is not in the ELF, but it
  is in the disc data — stage `n002a` string resource **3099**, "Save current instructor, %s, as
  the instructor for your personal data?\n(Instructor name cannot be erased once saved)", with the
  rating prompt at **3105**. Extracted with Solideye (decrypt, key = the file's own path
  `stage/n002a`) plus the Gcx decompiler; the dump lives in `dev/analysis/strings/`. So the gate is
  now string-anchored, not inferred from control flow alone.

  Still open: nobody located the code that *sends* P2P message 36. The receive side is proved, so
  the fix does not depend on it.

  Consequence for the server: **send zero.** We sent the game id here, which stamped every
  character that started a round or graduated, and their console then told every future training
  host to suppress the prompt for them. A reply of `{0, 0}` leaves the slot untouched, which is
  the correct behaviour for a server that does not track saved instructors.
doc-ref: dev/docs/OBSERVED.md "The token never leaves the client on the LOBBY link — but it does leave over P2P"; dev/docs/PROTOCOL.md "0x4390 — update stats"
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD3FF18] wire 0x00. 0 = round started. Nonzero ends the payload — nothing further is read."
  - id: instructor_saved
    type: u4
    doc: |
      [ELF 0xD3FF40] wire 0x04, present only when `result == 0`. **Not a round token.** Written to
      `profile+0x32F8` at `0xD3FF6C` only when nonzero (`0xD3FF64: cmpwi r0,0; beq`), read only by
      the join-announcement packer at `0x8842AC`, and carried to peers as replicated variable 352 /
      P2P opcode `0x24`, where `0xA359A4` treats nonzero as "an instructor is already saved" and
      suppresses the recognition prompt. The server should always send **0**; there is no path by
      which the client returns this value. Note this is the *second* writer of that slot — `0x4122`
      writes the same field unguarded at login, and that is the one that was suppressing the prompt
      (see the doc above). Zero is required in both places. The boolean reading is established on
      the local read path; consumers on *receiving* clients have not been enumerated.
