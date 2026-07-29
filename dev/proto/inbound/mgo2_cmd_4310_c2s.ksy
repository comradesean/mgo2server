meta:
  id: mgo2_cmd_4310_c2s
  title: "MGO2 0x4310 — check/push host settings (client -> server, payload Blowfish-encrypted)"
  endian: be
doc: |
  **345 bytes exactly (0x159), before Blowfish padding.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd44880`; seal `bl 0xd5c828` at `0xd44c58`;
  Blowfish encrypt `bl 0xd5d124` at `0xd44c60`-ish; flush `bl 0xd34cc0` at `0xd44c84`; wait
  slot `0x23` (`li r4,35` at `0xd44cf8`, `bl 0xd32e08`). Every field below is one write
  primitive between the builder and the seal — 46 call sites plus one 16-iteration loop, read
  in order from the disassembly of `0xd44880`..`0xd44c58`. Source offsets are given as
  `src+N` off the settings object in `r28` (name and comment come from separate pointers `r24`
  and `r25`). [ELF]

  **Why PROTOCOL.md says 352 and this says 345.** 352 is the *observed ciphertext* length.
  Blowfish is an 8-byte block cipher and 345 rounds up to 352 — the seven-byte difference is
  padding, not payload. The plaintext is 345 bytes and the last real field ends at `0x158`.
  [ELF; reconciles the live 2026-07-22 capture]

  **Three previously open questions closed by the ELF:**

  1. **The rotation starts at `0xA3`, not `0xA2`.** PROTOCOL.md flags this as a "one-byte
     caveat ... Model A = `0xA2`, Model B = `0xA3`; we use `0xA3`", with an experiment
     proposed. No experiment is needed: `src+168` is written as a standalone u8 at wire `0xA2`
     (`bl 0xd5c8a0` at `0xd448fc`) and the loop begins at wire `0xA3`. **We were right.**
  2. **The rotation is 16 triples, not 15.** The loop bound is `cmpdi cr7,r27,16` at
     `0xd44958`. It occupies `0xA3`..`0xD2` (48 bytes), matching the 16 triples the `0x4313`
     reply parser reads.
  3. **The triples are interleaved on the wire but come from three separate 16-byte arrays**
     (`src+752`, `src+768`, `src+784`), one byte of each per iteration. So a server writing
     this region back out must interleave; treating it as three contiguous runs would be
     wrong in both directions.

  **Two capture-proven facts reproduced independently**, which is the useful kind of
  agreement: the commonA/commonB toggle bytes land at `0x142`/`0x143` (one 2-byte blob write
  from `src+929`) and the level-limit base is a u32 at `0xF8` — both exactly where the
  2026-07-22 live sweep put them, and the earlier "u16 base at `0x142`" reading is confirmed
  dead. [ELF + CONFIRMED]

  **One field that is wider than we read it.** Our `applyHostSettings` reads idle-kick as a
  single byte at `0x146` and team-kill-kick as a single byte at `0x148`. The ELF writes a
  **u16** at `0x145` and a **u16** at `0x147` (`bl 0xd5c918` at `0xd44bf8` and `0xd44c0c`).
  Because the writer is big-endian, our byte reads happen to pick up the *low* byte of each —
  correct for any count <= 255 and silently wrong above it. Not a live bug at observed values;
  worth widening.
doc-ref: dev/docs/PROTOCOL.md "0x4310 — check host settings"
seq:
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: |
      [CONFIRMED] wire 0x000. Game name, from a separate pointer (`r24`), NUL-padded.
      **There is no leading "type" field** — the blob starts here. The historic "settings type
      1399153006" was `name[0:4]` read as an int (`0x5365616E` = "Sean").
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    doc: "[CONFIRMED] wire 0x010. From pointer `r25`."
  - id: password_enabled
    type: u1
    doc: "[ELF] wire 0x090, src+150."
  - id: password
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: |
      [ELF] wire 0x091..0x0a0, src+151, **16 bytes**. PROTOCOL.md's table says 15 here and puts
      `dedicated` at `0xA1`; the write is `bl 0xd5d0ac` with `r5 = 16` at `0xd448d4`, and
      `dedicated` is still at `0xA1`, so the field is 16 wide and the table's 15 was an
      arithmetic slip that happens to end in the same place. Never parsed by us — we do not
      implement passworded games — and it should not be logged.
  - id: dedicated
    type: u1
    doc: "[ELF] wire 0x0a1, src+167."
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF] wire 0x0a2, src+168. A standalone u8 immediately before the rotation — this is the
      byte the `0xA2`-vs-`0xA3` ambiguity was about. The same value the `0x4313` reply reports
      at its `0x09a`, and the key our server stores host settings under, per
      (character, lobby subtype).
  - id: rotation
    type: rotation_entry
    repeat: expr
    repeat-expr: 16
    doc: |
      [ELF] wire 0x0a3..0x0d2, 48 bytes. **Count is fixed at 16 by the loop bound**
      (`cmpdi cr7,r27,16`) — not size-driven, not preceded by a count. Sources are three
      parallel 16-byte arrays at src+752 (rule), src+768 (map), src+784 (flags), read one byte
      each per iteration, so the wire order is rule[0], map[0], flags[0], rule[1], ...
      Round 0 is the one our handler parses into the game row; a `rule == 0 && map == 0` triple
      is the conventional terminator (**reference-derived**, not visible in the writer, which
      always emits all 16).
  - id: unknown_0d3
    type: u1
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29] Position and width exact; no name is established and none is
      guessed. Parsed and pushed into the client's own property store (record 0, key 86 byte 1), and the only consumer is the accessor `0x7F4C98`, which has no callers and whose OPD word appears nowhere in the image.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: unknown_0d4
    type: u1
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29] Position and width exact; no name is established and none is
      guessed. As `unread_800`: store record 0 key 86 byte 5, dead accessor `0x7F4C50`.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: weapon_restrictions
    size: 16
    doc: |
      [CONFIRMED] wire 0x0d5..0x0e4, src+802, 16 bytes. One bit per item, **1 = locked**; bit 0
      of the first byte is the master "restrictions enabled" flag. Copied opaquely into the game
      row and replayed by `0x4313`/`0x4305` — the server never decodes individual bits. The
      per-bit table (two provenance tiers: confirmed weapon-by-weapon on BLUS30109 vs.
      transcribed and unverifiable) is in PROTOCOL.md, not duplicated here.
  - id: max_players
    type: u1
    doc: "[ELF] wire 0x0e5, src+818."
  - id: briefing_time
    type: u4
    doc: |
      [ELF] wire 0x0e6, src+820. Named per PROTOCOL.md's table and the `0x4313` reply's
      briefing-time slot; the name is **[INFERRED]** from that correspondence, the width and
      position are [ELF].
  - id: unknown_0ea
    type: u4
    doc: |
      [UNKNOWN] wire 0x0ea, src+824 — and now [ELF 2026-07-29] a **proven u32 with no reader and no
      writer anywhere in the binary**. An exhaustive scan for `,824(rN)` found zero sites in the MGO
      ranges, while every identified neighbour appears at its literal offset (`818` max players, 12
      sites; `820` briefing, 10; `847` tolerance, 11; `941` SNAKE, 8). Not in the accessor bank
      either. The create-game screen never stores to it.

      Width settled both directions: parser `0xD43784` uses the u32 reader `0xd5ccd8`, builder
      `0xD449C8` the u32 writer `0xd5c9bc`. Our captured value `0x02000000` is therefore 33554432 and
      not a u8 `2` with padding — identical on the wire, which is why it needed checking.

      So the value is **server-authored and echoed back**. The disc's Common Settings label run
      (13671-13820) has nothing between briefing time and friendly fire, so no UI label matches it.
  - id: unknown_0ee
    type: u2
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29] Position and width exact; no name is established and none is
      guessed. No reader anywhere in the binary.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: unknown_0f0
    type: u4
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29] Position and width exact; no name is established and none is
      guessed. No reader anywhere in the binary.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: unknown_0f4
    type: u2
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29] Position and width exact; no name is established and none is
      guessed. No reader anywhere in the binary.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: host_stance
    type: u1
    doc: |
      [CONFIRMED 2026-07-29] wire 0x0f6, src+846. **The host stance** — the Create Game and in-game
      "Conditions" row. A u8 enum 0..9, named in the client's own developer table at `0xE1BC48`+:

      ```
      0 HOST_STANCE_EASY                 5 HOST_STANCE_TRAINING
      1 HOST_STANCE_REAL                 6 HOST_STANCE_INSTRUCTOR_ENTRY
      2 HOST_STANCE_BEGINNER             7 HOST_STANCE_INSTRUCTOR_STARTED
      3 HOST_STANCE_EVERYONE             8 (slot left zero)
      4 HOST_STANCE_OTHER                9 HOST_STANCE_NONE
      ```

      Range-gated `cmplwi 9 / bgt` at `0xA31230`; the +/- cycler clamps 0..9 at `0xA32700`, with
      values above 4 additionally gated on a lobby flag (`0x964470`, mask `0x20020`) — the
      training-only half. [INFERRED] the disc labels (set `[40eff4]`, ids 172-181) map on in order:
      Casual, Serious, Newbies Welcome, Everyone Welcome, Other, Training, Accepting Trainees,
      Closed to New Applicants, Special, No Conditions. Corroborated by the Create Game default at
      `0x89B508` picking 6 in training lobbies, which lands on "Accepting Trainees".

      **The in-game edit `0x43c0` carries this field at ITS OWN wire `0xA1`**, not here. That packet
      is a strict subset of the same struct — name, comment, password flag, password, stance — and
      `0xA1` in *this* packet is `dedicated`. Reusing the offset writes the wrong field.

  - id: unknown_0f7
    type: u1
    doc: "[UNKNOWN] wire 0x0f7, src+847. Same candidate pair as unknown_0f6."
  - id: level_limit_base
    type: u4
    doc: |
      [CONFIRMED] wire 0x0f8, src+848. Capture-proven 2026-07-22 and reproduced here as a u32
      write (`bl 0xd5c9bc` at `0xd44a4c`-region). The earlier reading of a u16 base at `0x142`
      was a bug that stored commonA/commonB toggle bits as the base.
  - id: rule_timers
    type: u4
    repeat: expr
    repeat-expr: 17
    doc: |
      [ELF] wire 0x0fc..0x13f, src+852..src+916, seventeen consecutive u32 writes. This is
      PROTOCOL.md's "`0xFC`... per-rule timers/rounds/tickets", and the count cross-checks
      exactly against the `0x4313` reply's `0x10c | 68 bytes | u32 x17 per-rule timers and
      rounds`. Which index is which rule is **[UNKNOWN]** from the writer — the source array is
      contiguous, so the order is the client's internal rule enumeration, not something the
      call sites label. The ordering (SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM
      t/tickets, BASE t/r, BOMB t/r, TSNE t/r) was recorded as a **tier-4 guess** to be tested
      one timer at a time.

      **Corroborated 2026-07-28 by two independent lines, and no longer tier 4.**

      (1) ELF: the client's post-create cache at `0x8CA470` multiplies exactly **eight** of the
      seventeen by 60 and stores the other **nine** as bytes. The scaled indices are 0, 2, 4, 6,
      9, 11, 13, 15 — which under this ordering are precisely the eight *time* fields, with no
      unscaled value being a time and no scaled value being a count. The 2/2/2/3/2/2/2/2 shape
      is what makes that alignment possible at all.

      (2) Observed: an automatching TDM match ran round time 5 min, round limit 4, tickets 25 —
      landing on indices 6, 7 and 8 in that order. An SNE match ran round time 7 min, round
      limit 4, which fits indices 0 and 1.

      (3) **Confirmed outright, same day, against client defaults.** Four stored blobs from
      characters that had never edited their timers all read `[0]=8 [1]=4` and
      `[6]=3 [7]=4 [8]=15`, matching the client's own documented defaults for Sneaking
      (time 8, rounds 4) and Team Deathmatch (time 3, rounds 4, tickets 15) at exactly the
      predicted indices. Two rules, two defaults, four independent rows.

      The SNE "kill Snake" figure is **not** in this array: it is the byte at `0x14a`, which
      this schema and PROTOCOL.md both labelled "sneaking Snake side". That label was wrong — the
      byte reads 3 in every blob, which is the client's default SNAKE setting. Sneaking has
      three settings on screen and two slots here; the third is that byte.
  - id: unique_characters
    size: 2
    doc: |
      [INFERRED] wire 0x140..0x141, src+920, one 2-byte blob write. Mapped to the `0x4313`
      reply's `0x150 | u8, u8 | unique characters red/blue (+0x80 when random)` by the constant
      +0x10 offset that relates the request's `0x0fc` timer block to the reply's `0x10c` one.
      Not capture-confirmed.
  - id: common_toggles
    size: 2
    doc: |
      [CONFIRMED] wire 0x142..0x143 — commonA then commonB, same bitfields as the `0x4302`
      game-list entry. Written as one 2-byte blob from src+929, so note the source gap: bytes
      src+922..928 exist in the client's struct and are **not** transmitted.
      Capture-proven: flipping only friendly fire moved exactly `0x142` bit 3.
  - id: common_c
    type: u1
    doc: |
      [INFERRED] wire 0x144, src+931. Our `HostSettingsReply` writes a constant here.

      [ELF 2026-07-29] It has **its own u8 read** (`0xD43B10` via `0xd5cb8c`), distinct from the
      raw-2 covering src+929/930, and the builder splits the same way. It is the **low byte of the
      32-bit flags word at src+928** — and that settles it: 117 sites do `lwz rX,928(rB)` and
      bit-test the result, and **every tested bit lies in bits 8-23**, i.e. in src+929/930 only.
      Nothing tests bits 0-7. The constant `0x20` sets bit 5, which no site consumes.

      The only load of src+931 is the accessor `0x9072AC`, which returns the byte raw and is **dead
      code** — its sole appearance is its OPD descriptor at `0x101C118`, there is no `bl` to it, and
      the file is `ET_EXEC` with no relocations, so a runtime-patched reference is impossible.

      Meaning [UNKNOWN]. The disc's Common Settings list is ~16 items, matching the 16 bits at 8-23
      exactly, so no leftover label is available for this byte.

  - id: idle_kick
    type: u2
    doc: |
      [ELF] wire 0x145..0x146, src+932, written by the **u16** writer (`bl 0xd5c918`). Gated by
      commonA bit 0: `applyHostSettings` zeroes the count when the enable bit is off
      (**operator policy**, mirroring what the client shows).

      FIXED 2026-07-26: our server read a single byte at `0x146` — this field's low half — which
      was right for values <= 255 and silently truncated above. It now reads the u16. The tell was
      internal: `GameDetails` already wrote these back as shorts at these exact offsets, so the
      two halves of our own server disagreed about the width. The `0x4305` reply had the same bug
      in a third place (`HostSettingsReply` copied one byte into each destination's low half).
  - id: team_kill_kick
    type: u2
    doc: |
      [ELF] wire 0x147..0x148, src+934, u16 (`bl 0xd5c918`). Gated by commonB bit 7. Note
      src+936..939 are not sent. Same low-byte truncation as `idle_kick`, fixed the same day.
  - id: capture_extra_time
    type: u1
    doc: |
      [CONFIRMED 2026-07-29] wire 0x149, src+940. **Capture Mission "EXTRA TIME"** — extend the round
      until a victor emerges. A plain toggle: the handler at `0x8A02B4` is `x = x ? 0 : 1`, drawn as
      disc string 33 "ON" / 34 "OFF".

      Named from the disc: row label 507 "EXTRA TIME" under header 498 "Capture Mission", help text
      541 *"Enabling this adds extra time to the end of the round until a victor emerges."*
  - id: sneaking_snake_kills
    type: u1
    doc: |
      [CONFIRMED 2026-07-29] wire 0x14a, src+941. **Sneaking Mission "SNAKE"** — how many times Snake
      must be defeated for Red and Blue to win. Rendered as a number at `0x89D7B8`, clamped to [1,5]
      by the create-game adjuster at `0x8A1AC8`.

      Named from the disc: row label 508 "SNAKE", units 520 "times", help 542 *"Set the number of
      times Snake must be defeated (victory condition for Red and Blue Teams)."*

      **This independently confirms the 2026-07-28 correction** that renamed the byte from
      "sneaking-Snake side" to a count — that reading came from the clamp and the numeric render;
      this one comes from the disc, by a different route.
  - id: unread_tail
    size: 14
    doc: |
      [PARTIAL] wire 0x14b..0x158, src+942 — **one 14-byte raw block write**, so the ELF gives no
      field boundaries inside it and any split would be invented.

      No CLIENT reader exists for any byte of the range. **That is not the same as inert**: the
      server decodes the host-options flags out of byte 10 of this block (wire `0x155`), which is
      where `non_stat` comes from and is capture-proven. So "the client never reads it back" is
      established; "nothing uses it" is not.

      Round-tripped whole. Splitting it needs live divergence testing, not disassembly.
types:
  rotation_entry:
    doc: "One round of the rotation. Three parallel source arrays, interleaved on the wire."
    seq:
      - id: rule
        type: u1
        doc: "[ELF] src+752+i."
      - id: map
        type: u1
        doc: "[ELF] src+768+i."
      - id: flags
        type: u1
        doc: |
          [ELF] src+784+i. Called "flags" after PROTOCOL.md's `[rule, map, flags]` naming;
          the contents are **[UNKNOWN]** and no bit of it has been exercised.
