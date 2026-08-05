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
      [UNKNOWN — meaning; ELF — fate. 2026-07-29, producer pinned 2026-07-30] wire 0x0d3, src+800.
      Position and width exact; no name is established and none is guessed. Pushed into the client's
      own property store (record 0, key 86 byte 1); the only ELF-side consumer is the accessor
      `0x7F4C98`, which has no callers and whose OPD word appears nowhere in the image.

      **The push site is now named:** `0x8CA460` (`lbz r0,800(r9)`) → `stb r0,125(r1)`, into an
      8-byte scratch zeroed at `0x8CA444`-`0x8CA450`, published by
      `0x8CA6E4`-`0x8CA6F0` as `0x27F258(obj, key=86, len=8, src=r1+124)`. Byte 1 of that record is
      this field, byte 5 is `unknown_0d4`. So the value's only destination is the lobby stage
      script's namespace, which is outside the ELF and outside what disassembly can settle — an
      open question that belongs to the stage script, not the image.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.

      **[ELF 2026-08-01] The offset sweep was re-run from scratch and adds a third decoy, no
      fourth writer.** Every `st{b,h,w}` to displacement `800` or `801` in the whole image
      resolves to one of three things: the documented push at `0x8CA460`/`0x8CA468`; the
      `0x644FBC`/`0x644FC0` particle matrix this note already names; and — new — `0xA4E1A8`
      (`stb r0,801(r5)`, guarded by a bitfield test on `[r4+8]`) and `0xA4ED8C`
      (`stb r0,800(r29)`), both **`li r0,1` into a graphics object**, not this struct. The giveaway
      is the same function's neighbours: `stw r9,768(r3)` / `stw r9,772(r3)` at `0xA4E114`/`0xA4E11C`
      store the float constant `1.0f` (`0x3F800000`), and `0xA4E118` stores `128` at `+756`. Add
      it to the decoy list rather than re-deriving it a third time.
  - id: unknown_0d4
    type: u1
    doc: |
      [UNKNOWN — meaning; ELF — fate. 2026-07-29, producer pinned 2026-07-30] wire 0x0d4, src+801.
      Position and width exact; no name is established and none is guessed. Store record 0 key 86
      **byte 5**, dead accessor `0x7F4C50`; ELF-side accessor `0x907844` is likewise dead (no `bl`,
      OPD only). Push site `0x8CA468` (`lbz r0,801(r9)` → `stb r0,129(r1)`), same key-86 record as
      `unknown_0d3`.

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
      [UNKNOWN, ECHO-ONLY — 2026-07-29; negative re-established 2026-07-30] wire 0x0ee, src+832 =
      settings-block +80. Position and width exact; no name is established and none is guessed.
      No reader anywhere in the binary.

      Re-run independently: every displacement access at `832` in the text section resolves to a
      **u32-strided TOC global** (`lwz r9,-32768(r30)`, read in contiguous `lwz` runs at `0x9D6508`,
      `0x9DC66C`, `0x9DCFD4`, `0x9DDB30`, `0x9E1860`, `0xA0A684`) which cannot be this struct — it
      reads `+846`/`+847` inside u32s where this struct has two u8 fields. There is **no
      accessor-bank wrapper for +832**, unlike its neighbours `+834` and `+840`.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: unknown_0f0
    type: u4
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29; negative re-established 2026-07-30] wire 0x0f0, src+836 =
      settings-block +84. Position and width exact; no name is established and none is guessed.
      No reader anywhere in the binary.

      Re-run independently: all hits at `836` are the same u32-strided TOC global (`0x9D64C8`,
      `0x9DC670`, `0x9DCFD8`, `0x9DDB48`, `0x9E1878`, `0xA0A68C`). No accessor-bank wrapper.

      The server stores it in a typed column so the settings round-trip is exact. Two decoys make
      any re-hunt here expensive: a particle loop at `0x644D00` writes a 16x16 byte matrix and
      produces a false hit at essentially every offset in this range, and the create-game screen
      embeds this struct at `+108`, so each field also appears at `N+108` and `N+112` on other
      registers. The `0x907xxx` accessor bank pins **widths**, never liveness — all of it is dead.
  - id: unknown_0f4
    type: u2
    doc: |
      [UNKNOWN, ECHO-ONLY — 2026-07-29; negative re-established 2026-07-30] wire 0x0f4, src+844 =
      settings-block +92. Position and width exact; no name is established and none is guessed.
      No reader anywhere in the binary.

      Re-run independently: all hits at `844` are the u32-strided TOC global (`0x9D64D0`,
      `0x9DC678`, `0x9DCFE0`, `0x9DDB50`, `0x9E1880`, `0xA0A698`) or `+112` aliases of `+956` in the
      create-game screen. No accessor-bank wrapper.

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
      3 HOST_STANCE_EVERYONE             8 (slot left zero -- NOT "Special", see below)
      4 HOST_STANCE_OTHER                9 HOST_STANCE_NONE
      ```

      Range-gated `cmplwi 9 / bgt` at `0xA31230`; the +/- cycler clamps 0..9 at `0xA32700`, with
      values above 4 additionally gated on a lobby flag (`0x964470`, mask `0x20020`) — the
      training-only half.

      **[CONFIRMED 2026-08-04, and the `[INFERRED]` label list was wrong in one slot.]** The
      `HOST_STANCE_*` strings are **not** a debug enum→name table — they are **string-resource
      keys**. Each hashes (rot-5-add 24-bit, `0xD25D0`) to an index record in disc set `[40eff4]`,
      so the mapping is read rather than assumed. The dispatch table is built on the stack at
      `0xA31194`-`0xA312CC`: nine `bl 0xD25D0` calls hash the nine pointers at `0xFEB694`-`0xFEB6B4`
      into r19…r27, which are stored into a **10-entry, 8-byte-stride table** at `r1+152` after a
      `memset(r1+152, 0, 80)` (`0xA31248`). Lookup is `r5 = r18 + (stance << 3) & 0x7F8`, then
      `lwz r3,40(r5)`, resolved and pushed to the text widget at `0xA31B68`.

      | value | store site | key | strres id | JP | EN |
      | --- | --- | --- | --- | --- | --- |
      | 0 | `stw r19,152` | `HOST_STANCE_EASY` | 173 | 気楽 | **Casual** |
      | 1 | `stw r20,160` | `HOST_STANCE_REAL` | 174 | 真剣 | **Serious** |
      | 2 | `stw r21,168` | `HOST_STANCE_BEGINNER` | 175 | 初心者歓迎 | **Newbies Welcome** |
      | 3 | `stw r22,176` | `HOST_STANCE_EVERYONE` | 176 | 誰でも歓迎 | **Everyone Welcome** |
      | 4 | `stw r23,184` | `HOST_STANCE_OTHER` | 178 | その他 | **Other** |
      | 5 | `stw r24,192` | `HOST_STANCE_TRAINING` | 179 | 訓練 | **Training** |
      | 6 | `stw r25,200` | `HOST_STANCE_INSTRUCTOR_ENTRY` | 180 | 生徒受付中 | **Accepting Trainees** |
      | 7 | `stw r26,208` | `HOST_STANCE_INSTRUCTOR_STARTED` | 181 | 生徒締切 | **Closed to New Applicants** |
      | **8** | *(nothing — offset 216 is never written)* | — | — | — | **no label at all** |
      | 9 | `stw r27,224` | `HOST_STANCE_NONE` | 172 | スタンスなし | **No Conditions** |

      **The correction: slot 8 is not "Special".** The old inferred list mapped ids 172-181 onto
      values 0-9 in order and so handed id 177 (特殊 / "Special") to slot 8. `entry[8]` is left zero
      by the `memset` and never stored, and `cmpwi r3,0 / bne` at `0xA312D4` sends it down the
      *no-stance* path — identical to an out-of-range value. Id **177 is not a stance label**: its
      hash `0xB0514A` matches no string in the ELF and it appears nowhere in the dispatch table; it
      merely sits between EVERYONE and OTHER in the set, which is exactly what made the in-order
      mapping look right. Note the real order is not sequential either — `HOST_STANCE_NONE` is id
      **172**, the *lowest* id, bound to the *highest* value.

      Control for that negative: the same hash search does find all nine `HOST_STANCE_*` names plus
      488 other name↔record matches, so it finds strings when they exist.

      **Cycler detail**, refining the note above: the ± cycler only ever *produces* 0-4. Down from 0
      wraps to 4; down from anything above 5 lands on 4 via the `cmplwi 4 / ble … li 4` clamp; up
      from 9 wraps to 0; up past 4 is either forced to 0 or reverted to 4 depending on the
      `0x964470` lobby-flag query. So **5-7 are server- or training-assigned states the host cannot
      reach by hand**, and 9 is enterable but not cyclable-to. Corroborated by the Create Game
      default at `0x89B508` picking 6 in training lobbies, which lands on "Accepting Trainees".

      **What the player sees.** This is the "Conditions" line on Create Game and the room's header
      in the lobby browser — the host's advertised etiquette. Someone scanning the list reads
      *Casual* against *Serious* against *Newbies Welcome* to judge whether they are wanted there.
      The training values are the tutorial lobby's own state machine, shown while an instructor is
      recruiting or has closed applications.

      **The in-game edit `0x43c0` carries this field at ITS OWN wire `0xA1`**, not here. That packet
      is a strict subset of the same struct — name, comment, password flag, password, stance — and
      `0xA1` in *this* packet is `dedicated`. Reusing the offset writes the wrong field.

  - id: level_limit_tolerance
    type: u1
    doc: |
      [CONFIRMED, RESOLVED 2026-07-30] wire 0x0f7, src+847. Previously `unknown_0f7`, "same
      candidate pair as unknown_0f6" — a note left over from when the stance byte beside it was
      also unnamed. **The level-limit tolerance**, the ± window around `level_limit_base`.

      Three lines, all tier 1:

      1. **Struct-offset identity.** `src+847` is settings-block +95 (`block+X = src+752+X`, proved
         by the `0x4305` parser's inlined copy writing block+48 to `+800`, +66 to `+818`, +94 to
         `+846`, +96 to `+848`, commonA/B to `+929`, +189 to `+941`). The reply specs
         `mgo2_cmd_4305_s2c.ksy` and `mgo2_cmd_4313_s2c.ksy` both have block +95 as the tolerance,
         and this file's own `level_limit_base` note already used the same +0x10 correspondence to
         place `0xF8` at block +96.
      2. **The client publishes it as its own property.** `0x8CA544` (`lbz r0,847(r9)`) →
         `0x8CA72C` `0x27F258(obj, key=98, len=1, ...)`, immediately beside key 99 = `src+848`, the
         level-limit base.
      3. **The browser consumes it as a tolerance.** `0xD49550` copies `+847` into the `0x4302`
         game-list entry at T+0x26 (`level_limit_tolerance` there, [CONFIRMED]), and the list picker
         at `0x93452C`-`0x93455C` tests a candidate's level against `entry+40 + entry+38` and
         `entry+40 − entry+38` — base plus and minus this byte.

      This also resolves the standing disagreement `mgo2_cmd_4305_s2c.ksy` flagged on 2026-07-26:
      "one byte cannot be capture-proven in the reply and unknown in the request." It is the
      request spec that was behind.
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

      **[COMPLETE BIT MAP — read directly, 2026-08-04.]** Every bit is bound to a named row by
      the client's own Create Game code. **This is not an ordinal argument.** The Common Settings
      **summary renderer** `0x8A8A2C`-`0x8A93C4` emits, per row, a `lwz rX,928(rY)` followed by a
      single-bit test and then a `li r3,<help id>` for that same row — so each bit and its row name
      come out of the same straight-line block. The bit falls out of the `rldicl.` shift with no
      interpretation, and the row name falls out of the id.

      Bit numbering is LSB = bit 0 of the big-endian u32 at src+928, so `common_a` is bits 16-23
      and `common_b` is bits 8-15.

      | LSB bit | byte | summary site | label id | row | edit handler |
      | --- | --- | --- | --- | --- | --- |
      | 8 | commonB 0 | `0x8A8EC0` | 560 | **Teams Switch Positions** | `0x8A6720` |
      | 9 | commonB 1 | `0x8A8E60` | 559 | **Auto Assign Teams** | `0x8A6810` |
      | 10 | commonB 2 | `0x8A8E00` | 558 | **Silent Mode** | `0x8A6900` |
      | 11 | commonB 3 | `0x8A8DA0` | 557 | **Enemy Nametag Display** | `0x8A69F0` |
      | 12 | commonB 4 | `0x8A9000` | 563 | **Level Limit** (enable) | `0x8A6234` |
      | 13 | commonB 5 | `0x8A8FA0` | 562 | **Allow Quick-Join** | `0x8A64D0` |
      | 14 | commonB 6 | `0x8A9114` | 564 | **Voice Chat** allowed | `0x8A6110` |
      | 15 | commonB 7 | `0x8A9178` | 565 | **Team Kill Kick** (enable) | `0x8A5EB8` |
      | 16 | commonA 0 | `0x8A9258` | 566 | **Idle Kick** (enable) | `0x8A5C60` |
      | 17 | commonA 1 | — | — | *no row rendered anywhere* | — |
      | 18 | commonA 2 | — | — | *no row rendered anywhere* | — |
      | 19 | commonA 3 | `0x8A8CC0` | 554 | **Friendly Fire** | `0x8A6BD0` |
      | 20 | commonA 4 | `0x8A8F20` | 561 | **Ghost Pranks** | `0x8A65FC` |
      | 21 | commonA 5 | `0x8A8D40` | 556 | **Lock On (AUTO AIM)** | `0x8A6AE0` |
      | 22 | commonA 6 | — | — | **touched by no instruction in the image** | — |
      | 23 | commonA 7 | — | — | *no row rendered anywhere* | — |

      The one **tier-2** cross-check: bit 19 is Friendly Fire, which is exactly the capture-proven
      2026-07-22 result (flipping only friendly fire moved `0x142` bit 3 = LSB 19).

      **[CORRECTION, later the same day — the ids in this table were wrong by 37.]** They were
      first published as 585..607 and described as label ids. **585..607 are the HELP ids.** The
      row **labels** are **548..570**, and the relation is exact: *every row's help text is at
      `label + 37`*. The mistake was harmless to the bit map — the summary renderer loads the help
      id, so the binding above is unaffected — but it made a run of ids wrong wherever they were
      quoted, and it invented an anchor that does not exist. That claimed anchor was: *"Weapon
      Restriction Settings only lands on 606 if Auto Balance consumed two ids (604, 605), which the
      disc predicts because auto-balance is the one row with two help texts."* Reading the group's
      index table gives a single **567 Auto Balance Teams**, with **568 Weapon Restrictions** and
      **569 Weapon Restriction Settings** adjacent — an enable plus its sub-screen. The
      two-help-text observation was real; the inference drawn from it was not, and it is retracted.

      The full label run, read from the group's index records rather than counted:

      ```
      548 Dedicated Host Settings      560 Teams Switch Positions
      549 Unique Characters            561 Ghost Pranks
      550 A Team Unique Characters     562 Allow Quick-Join
      551 B Team Unique Characters     563 Level Limit
      552 Max Number of Characters     564 Voice Chat
      553 Briefing Time                565 Team Kill Kick
      554 Friendly Fire                566 Idle Kick
      555 Headshots                    567 Auto Balance Teams
      556 Lock On (AUTO AIM)           568 Weapon Restrictions
      557 Enemy Nametag Display        569 Weapon Restriction Settings
      558 Silent Mode                  570 Skills
      559 Auto Assign Teams
      ```

      followed contiguously by the shared value labels **571 Enable / 572 Disable**, the unit
      suffixes **573** (JP 人, blank in every western language) and **574** (`min.`), a second
      **575/576 Enable/Disable** pair, the unique-character names **577-581** (Johnny (Akiba),
      Meryl, Liquid Ocelot, Mei Ling, Raiden), **582 Allow / 583 Disallow**, the level-limit format
      **584 `%d ± %d`**, and then the 23 help texts at 585-607.

      **What a player sees**, for the rows worth spelling out: Silent Mode hides the Information Log
      (*"When enabled, the Information Log is not displayed."*); Friendly Fire is *"player's attacks
      can harm their teammates"*; Level Limit restricts the room to a level band, and the band is
      the `±` pair at src+847/848 rendered through format 584; Allow Quick-Join decides whether the
      room accepts automatched joiners; Team Kill Kick and Idle Kick are the **enables** for the two
      counters at src+934 and src+932, so clearing either bit makes the client zero the matching
      number.

      **Four bits have no rendered row: 17, 18, 22 and 23.** Four rows are unrendered too — 549
      Unique Characters, 555 Headshots, and the two Auto Balance variants behind 567. Four and
      four, but **which goes where is not decidable from this image**, and any pairing is
      speculation. Bit 22 is the strongest of the four negatives: no instruction anywhere touches
      it.

  - id: common_flags_lsb
    type: u1
    doc: |
      [ELF; renamed from `common_c` 2026-07-30] wire 0x144, src+931 — the **least significant byte
      (bits 0-7) of the 32-bit Common Settings flags word** based at src+928. The old name implied a
      third toggle byte in the commonA/commonB series; it is the same word's other end. The reply
      specs use the same name, and `mgo2_cmd_4313_s2c.ksy` names the word's fourth byte
      `common_flags_msb` (src+928, block +176, not carried on this wire).

      Our `HostSettingsReply` used to write a constant here.

      [ELF 2026-07-29] It has **its own u8 read** (`0xD43B10` via `0xd5cb8c`), distinct from the
      raw-2 covering src+929/930, and the builder splits the same way. It is the **low byte of the
      32-bit flags word at src+928** — and that settles it: 117 sites do `lwz rX,928(rB)` and
      bit-test the result, and **every tested bit lies in bits 8-23**, i.e. in src+929/930 only.
      Nothing tests bits 0-7. The constant `0x20` sets bit 5, which no site consumes.

      **[RE-CONFIRMED 2026-08-04, with the last loose end closed.]** The sweep was re-run as
      "every `lwz rX,928(rY)` in .text (141 sites) followed within 8 instructions by a single-bit
      test on rX". Exactly one site tests bit 0 — `0x2A9FD4` — and it is **disqualified**: its
      base `r31` takes `stfs f13,740(r31)` / `stfs f0,744(r31)` / `stfs f0,764(r31)` two
      instructions away, so it is a float object, not this struct.

      The negative also has a *reason* now rather than an absence. With the complete bit map
      above, **15 of the 16 bits at 8-23 are named rows and bit 22 is untouched by any
      instruction** — so there is genuinely no leftover Common Settings label that bits 0-7 could
      be carrying. The "second bank of toggles" idea is neither strengthened nor weakened by
      that; it stays a hypothesis with no evidence either way. Our `0x20` remains **inert, with
      evidence**.

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

      **The client never reads OR WRITES any byte of it** [READ 2026-07-29]. The block has exactly
      three touch points in the whole binary: the `0x4310` builder emitting it (`0xD44C3C`), the
      `0x4305` parser reading it (`0xD45A54`), and the create-game initialiser memsetting it to zero
      (`0x89B5E8`). No access at any byte, on any alias, anywhere else.

      **So its default is fourteen zero bytes, and anything else the server sees came from the
      server.** All 214 archived captures (`dev/proto/samples/4310/`) carry it entirely zero.

      This retracts an earlier claim in this file. It said the server decodes `non_stat` from byte 10
      and that this was capture-proven, so the block was "unread rather than unused". **That is
      circular**: our `0x4305` reply writes its `0x158` from the request's `0x155`, the parser lands
      it in the struct, and the builder sends it back as `0x155`. The bit can only read back what we
      put there — and it never has, because every capture is zero.

      The tier-4 labels for this region are likewise unsupported. "Per-rule byte-sized timers for
      Stealth DM / Interval / Solo Capture / Race" names modes whose strings **do not exist on this
      disc at all**: the online-lobby set enumerates exactly eight rules (DM, TDM, Rescue, Capture,
      Sneaking, Base, Bomb, Team Sneaking), and the ELF developer table agrees.

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
