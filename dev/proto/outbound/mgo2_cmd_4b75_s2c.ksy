meta:
  id: mgo2_cmd_4b75_s2c
  title: "MGO2 0x4b75 — clan APPLICANT rows, 93-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **The clan applicant list, and it is UNEXERCISED.** Middle packet of the 0x4b74 / 0x4b75 /
  0x4b76 triple answering 0x4b73. [CONFIRMED LIVE 2026-07-27] that **the client never sends
  0x4b73**: clan APPLICATIONS are delivered as MAIL instead — mailbox type 0x10 on 0x4820, where
  0x0f is ordinary mail — and a leader accepts or declines from the mailbox with 0x4b30 / 0x4b32.

  So this triple has never been on the wire, nothing here has been rendered, and a server can serve
  it or not without any screen noticing. Nothing below can reach tier 2 through 0x4b75 itself.

  One consequence worth recording: the 64-byte text field below has no source. An application
  carries no message — 0x4b42 sends only a clan id — so nothing on the wire ever fills it.

  **[OPEN QUESTION 2026-08-02] Is "applicant rows" still the right framing?** The record, the
  parser, the list slot, the consumer screen and even the screen's element names are all shared
  with **0x4686**, the match-history detail list (see the CLONE section below), and the fields
  that could be decoded decode as *history* fields: a timestamp, a finishing place or a win
  tally. Nothing in the binary says the 0x4b7x copy was re-purposed for applicants rather than
  left as clan match history, and nothing says it was not — the request 0x4b73 is never sent, so
  the question cannot be settled from behaviour. `meta.title` is left as it was rather than
  renamed on an inference; the field labels below carry [ELF/INFERRED] for the same reason.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD55E40**, which re-checks the id (`cmpwi r0,19317`) before reading anything.

  Middle packet of the 0x4b74 / 0x4b75 / 0x4b76 triple (see mgo2_cmd_4b74.ksy). No request-slot
  update.

  **Count source: size-driven, no count field** (0xD5CEB0 test at 0xD55ED8, loop back at
  0xD55FCC). Records are appended at list+8+n*96 with the count at list+4; the client refuses at
  n > 31, so at most **32** records. List object: session[+0x10000+6404] + 0x20000 + 29724.

  Wire record = 93 bytes; client struct = 96. Wire-to-struct, from the staging buffer at `r1+112`
  (memset 96 at 0xD55ECC, appended by `0xDC95C0` at 0xD55FB8): `+0x00` u4 (0xD55EF0),
  `+0x04` 64 raw (0xD55F10, client NUL at +0x44), `+0x45` 16 raw (0xD55F30, NUL at +0x55),
  `+0x56` u1 (0xD55F4C), `+0x58` u4 (0xD55F68), `+0x5C` u4 (0xD55F84). Every offset in the field
  list below is confirmed against those six `addi r4,r1,N` instructions.

  ## The list object is SHARED, and 0x4b75 is a CLONE of 0x4686

  [ELF 2026-07-30, corrected 2026-08-02] `session[+0x10000+6404] + 0x20000 + 29724` is also the
  destination of the **0x4685 / 0x4686 / 0x4687** parsers (`addi ...,29724` at 0xD3AB20, 0xD3AC1C,
  0xD3B488, off the identical `lwz r9,6404(r9)` / `addis r9,r9,2` base). The earlier claim that
  those write **28-byte** records is **wrong for 0x4686**, and that error is what hid the whole
  finding below.

  **0x4686's parser 0xD3B42C is instruction-for-instruction identical to ours at 0xD55E40**,
  differing only in the id it re-checks (`cmpwi r0,18054` at 0xD3B478 vs `cmpwi r0,19317` at
  0xD55E8C) and in branch displacements. Same 96-byte `memset`, same staging buffer at `r1+112`,
  same six reads at the same stack offsets and by the same primitives — including the same
  `0xD5CC64` at `r1+200` and `0xD5CCD8` at `r1+204` — same `cmpwi r3,31` cap, same
  `list + 8 + n*96` append, same count at `list+4`. The whole `0x4b73/74/75/76` family is a
  copy-paste of `0x4684/85/86/87` into the clan namespace: `addi ...,29724` appears at exactly
  twelve sites image-wide, in two mirrored groups of six (0xD3A150 / 0xD3AB20 / 0xD3AC1C /
  0xD3B488 / 0xD3F650 / 0xD3F6A8 against 0xD544A8 / 0xD54F84 / 0xD55080 / 0xD55E9C / 0xD5A158 /
  0xD5A1B0), and the ids confirm the pairing (0x4b74=19316, 0x4b75=19317, 0x4b76=19318 against
  0x4685=18053, 0x4686=18054, 0x4687=18055).

  **This is where the meanings below come from**, and it is why they are tier-1 rather than
  guesswork: 0x4686 has a *finished* consumer screen (three identical copies, 0x918D14, 0x91D094,
  0x91DB68) that reads every field of the struct, whereas the 0x4b75 clone reads five of six and
  discriminates none of them. See `result_kind`.

  It remains true that the slot is general-purpose and reused by whichever screen filled it last:
  a server that somehow got 0x4b75 onto the wire while a match-history list was live would be
  overwriting it, and with a *layout-compatible* record, so the overwrite would render rather than
  crash.

  ## There IS a consumer screen, and it is a degraded copy of a finished one

  The earlier claim that "nothing here has been rendered" is right about the wire and wrong about
  the code. `GetApplicantRow(session, i)` at **0xD5A13C** (`mulli r9,r4,96` at 0xD5A174, rows at
  `list+8+i*96`) has exactly one caller, **0xA8A098**, inside a row loop at 0xA8A080-0xA8A224 that
  paints **five** columns from each record (not four — the date column was not counted); the
  matching count accessor 0xD5A194 is called once, from 0xA8A814. Since the client never sends
  0x4b73 the loop can never see a record, which is the frame for reading everything below: these
  are the fields a screen *would* show.

  [ELF 2026-08-02] `GetApplicantRow` has a byte-identical twin at **0xD3F634** — same base, same
  96-byte stride, same `+8`, same bound against `[list+4]` — which has **zero** `bl` callers; its
  only reference is its own OPD descriptor at 0x1029318. The 0x4686 consumers inline the
  arithmetic instead, which is exactly why a caller sweep on the accessor missed them.

  **How this screen is degraded relative to its 0x4686 twin**, which is the frame for the field
  docs below:

  | | 0x4686 screen (finished) | 0x4b75 screen (this one) |
  | --- | --- | --- |
  | struct+0x00 | `lwz`, `-1` sentinel, widened into a local, `localtime` on **4** bytes | row pointer passed straight in — reads **8** bytes, column 0 is garbage |
  | struct+0x56 | read; selects the render mode for +0x58 | **never read** |
  | struct+0x58 | rendered as place / win-count per +0x56 | printed raw as `%d` |
  | struct+0x5C | printed as `%d` | printed as `%d` (identical) |
  | element names | `STRING_low*` | **the same** `STRING_low*` — one layout template |

  The strongest single sign that this screen is unfinished is in `timestamp` — read on.

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 / 0xD5CCD8 u4 (identical twins — see the CORRECTION below), 0xD5D018 fixed byte
  block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision
  added: "In each signed/unsigned pair the LOWER address is the signed accessor (write-side
  proof: 0xD5C95C uses `sraw`, 0xD5C9BC uses `srw`)." **That claim is SUPERSEDED — see the
  CORRECTION below.** Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare at every width): that rule is wrong,
  and it is wrong on the READ side at ALL widths, not just at u32. Each "signed/unsigned pair"
  is instruction-for-instruction identical — same bound check, same byte-assembly loop, same
  `extsb` on each byte, same store width:
    * u8:  0xD5CB54 == 0xD5CB8C  (bound `cmpwi 1023`, `lbzx`/`stb`, cursor += 1)
    * u16: 0xD5CBC4 == 0xD5CC14  (bound `cmpwi 1022`, two `lbzx`, `sth`,  cursor += 2)
    * u32: 0xD5CC64 == 0xD5CCD8  (bound `cmpwi 1020`, 4-iteration loop, `stw`, cursor += 4)
    * u64: 0xD5CD4C == 0xD5CDC0  (bound `cmpwi 1016`, 8-iteration loop, `std`, cursor += 8)
  So **no read primitive is a signed accessor at any width**, and "0xD5CBC4 s2" / "0xD5CC64 s4"
  are as unfounded as the u32 claim. Signedness comes from the CALLER — the value being
  reloaded with `lwa`, or being compared against known-negative error constants — never from
  the primitive's address.

  The write side does not rescue the rule either. There are **three** u32 write primitives, not
  a signed/unsigned pair: 0xD5C95C (`sraw`), 0xD5C9BC (`srw`) and 0xD5CA1C (`sraw`). The
  sraw/srw difference is inert because each iteration masks with `and r0,r4,r0` where r0 =
  `slw r7,r10` of 255, and then stores only the low byte with `stbx`: for shifts 16/8/0 the
  masked operand is non-negative in 32 bits so the two shifts agree outright, and for shift 24
  they differ only in bits above bit 7, which `stbx` discards. Identical bytes on the wire.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; no leading count."
types:
  record:
    doc: "93 wire bytes -> 96-byte client struct."
    seq:
      - id: timestamp
        type: u4
        doc: |
          [ELF 2026-08-02] struct+0x00, read at 0xD55EF0. **A 32-bit Unix timestamp in seconds,
          unsigned, with `0xFFFFFFFF` as the "not set" sentinel.** Rendered as the row's first
          column with `strftime` `"%Y/%m/%d %H:%M:%S"` (0xE14040).

          **The width contradiction recorded here is RESOLVED, and it was the 0x4b75 screen's bug,
          not the field's.** The earlier note read: the consumer hands the row pointer to
          `0xDC9358`, which does an *eight*-byte `ld r0,0(r28)` at row+0, while the parser writes
          only four bytes there followed by a 64-byte block — so "we cannot say this u32 *is* the
          timestamp". The 0x4686 twin screen settles it. At **0x918D1C-0x918D3C** the mature
          consumer does:

              lwz  r0,0(r9)          ; r9 = row+0 -- a FOUR-byte load
              cmpwi cr7,r0,-1        ; 0xFFFFFFFF => skip the date entirely
              std  r0,112(r1)        ; widen into a 64-bit local
              addi r3,r1,112         ; pass the LOCAL's address
              bl   0xDC9358

          So `0xDC9358` takes a **pointer to a 64-bit time value**, and the correct call sequence
          is load-4 / widen / pass-the-local. The 0x4b75 clone at 0xA8A0B0 passes `r26`, the row
          pointer, straight in — it dropped the widening step. That is a transcription bug in the
          clone, and it is why column 0 would show garbage assembled from
          `timestamp << 32 | first four bytes of text_04`. The field is four bytes; the caller is
          wrong. Naming it is therefore no longer laundering anything.

          Two corrections to the mechanism as previously described. `sc 144` is **not** the
          current-time syscall — it fills `r1+112` with a **timezone offset in minutes** and
          `r1+116` with a daylight-saving flag; 0xDC9358 multiplies the first by 60
          (`slwi 6` minus `slwi 2` at 0xDC9390-0xDC93A0), adds it to the caller's time value and
          calls `0xDCFEA0(0, local_seconds, dst)`. The whole time value comes from the record and
          none of it from the clock. And the load is `lwz`, i.e. **zero**-extending, which is the
          second reason this stays `u4`.

          `0xFFFFFFFF` is a real sentinel, not an accident: 0x918D20 `cmpwi cr7,r0,-1` branches to
          0x918D74, which substitutes the empty string at 0xE2C538 for the whole date column.

          **Live-code verdict: WRONG BUT INERT.** `ClanGameController.applicants` writes
          `applicant.charaId()` into these four bytes. A character id is not epoch seconds, so the
          date column would read as some date in 1970 or later depending on the id — it is the
          wrong *kind* of value, not a wrong instance of the right one. It cannot reach a screen:
          [CONFIRMED LIVE 2026-07-27] the client never sends 0x4b73 (applications arrive as
          mailbox type 0x10 on 0x4820 and are answered with 0x4b30/0x4b32), so the handler is
          unreachable; and the 0x4b75 consumer's date column is broken by the missing widening
          step regardless of what we put here. Correct value if 0x4b73 is ever served: the
          application's epoch-seconds timestamp, or `0xFFFFFFFF` to blank the column. Recorded as
          a hazard per CLAUDE.md's third case rather than fixed, because the feature is not live.
      - id: text_04
        size: 64
        type: str
        encoding: ASCII
        doc: |
          [ELF] struct+0x04, 64 bytes fixed (client NUL at +0x44). 64 is comment/message sized.

          [ELF 2026-07-30] **It is rendered**: at 0xA8A134 the consumer does `addi r5,r27,4` — the
          address of this field — and passes it as the text of the element named by the column-id
          table entry `[r28+16]` (`0x244340` / `0x2452A0` / `0x246EC0` at 0xA8A110-0xA8A148). So
          the client does have a place to put it.

          What it never has is a **source**: 0x4b42, the apply-to-clan request, sends only a clan
          id, so no message ever reaches the server to put here. [UNKNOWN] what it was meant to
          carry.

          [ELF 2026-08-02] The 0x4686 twin screen sets the same column from the same offset
          (`addi r5,r24,4` at 0x918DA4), so the offset and the 64-byte width are corroborated by a
          second consumer. It does nothing further with the text, so the twin adds no label here
          either — this is the widest string in the family and stays uninterpreted.

          **Live-code verdict: INERT, and correct by default.** `ClanGameController.applicants`
          zero-fills it, which renders as an empty column. There is nothing else it could carry,
          and the handler is unreachable in any case.
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: |
          [ELF] struct+0x45, 16 bytes fixed. [UNKNOWN] whose name — the applicant's is the obvious
          reading and remains unevidenced.

          [ELF 2026-07-30] It is rendered as one of the row's columns: 0xA8A144 computes
          `addi r27,r27,69` (= `struct+0x45`, this field) and 0xA8A174-0xA8A180 sets it as the text
          of the element named by `[r28+32]`.

          [ELF 2026-08-02] The 0x4686 twin screen renders it from the same offset — `addi r4,r24,69`
          at 0x918DC8 — but pipes it through `0xAF70F0(dest, src, 97)` first rather than setting it
          directly. So the width and offset are corroborated by a second, finished consumer.

          **Live-code verdict: RIGHT.** `ClanGameController.applicants` writes the applicant's name
          here, ISO-8859-1, capped at the 16-byte field. That matches what both consumers read.
          Checked 2026-08-02; does not need rechecking.
      - id: result_kind
        type: u1
        doc: |
          [ELF/INFERRED 2026-08-02] struct+0x56, read at 0xD55F4C. **The render-mode discriminator
          for `result_value`.**

          **This OVERTURNS the [ELF — NEGATIVE 2026-07-30] "No reader" recorded here.** That
          negative said: "Image-wide, every `lbz rX,86(rY)` is outside the clan/UI code entirely
          ... the only other route to a record is `GetApplicantRow` 0xD5A13C, whose single `bl` is
          the one in that loop." **Both halves were wrong**, and in exactly the two ways
          dev/proto/README.md and the task rules warn about:

          * **The reader is a pointer walk, so a displacement sweep could never see it.** The
            0x4686 consumer keeps *two* cursors into the row: `r24 = list + 8 + scroll*96` (the
            row) and `r26 = list + 100 + scroll*96` (= row + 92), both bumped by 96 per iteration
            (0x918D00-0x918D0C, 0x918F90/0x918F98). This field is reached as `addi r9,r26,-6`
            then `lbz r0,0(r9)` at **0x918E00-0x918E08** — displacement **0** off a walked
            pointer, and *negative* off that pointer at that.
          * **There is a second row accessor, and a second parser filling the same list.**
            See the top-level doc: 0x4686's parser 0xD3B42C is instruction-identical to ours and
            writes the same 96-byte struct into the same slot, and 0xD3F634 is a byte-identical
            twin of `GetApplicantRow`.

          **What it selects** (0x918E0C onward, and the two identical copies at 0x91D188 and
          0x91DC5C):

          | value | column 3 becomes |
          | --- | --- |
          | 3 or 5 | a **finishing place**: `result_value` switched to `HISTORY_1ST`/`2ND`/`3RD`/`5TH`, else `"-"` |
          | 4 or 6 | a **win tally**: `"%d%s"` of `result_value` with `SURVIVAL_WIN` / `SURVIVAL_WINS` |
          | anything else | the empty string at 0xE2C538; `result_value` is not read |

          No `enum:` is added here: the four live values are certain but the space they come from
          is not, and README.md's rule is that `enum` is a finding rather than a convenience.

          **The 0x4b75 screen does not read it.** The consumer loop 0xA8A080-0xA8A224 touches the
          record only at +0 (via 0xDC9358), +4, +69, +88 and +92, and prints struct+0x58 raw. So
          within *this* command the field is inert; the label is inherited from the twin.

          **Swept range for any other reader of the struct, with the control.** The only ways to
          hold a row address are (a) the parser's own staging buffer at `r1+112`, which is
          function-local and leaves only through the `0xDC95C0` copy at 0xD55FB8; (b) an accessor
          returning `list + 8 + i*96`; (c) that arithmetic inlined. (b) and (c) are both found by
          sweeping the **whole image** for `mulli rX,rY,96`, which returns **exactly seven** sites:
          0xD55FA8 and 0xD3B594 (the two parser appends), 0xD5A174 and 0xD3F66C (the two
          accessors), and 0x918D00, 0x91D080, 0x91DB54 (the three 0x4686 consumer copies).
          `0xD5A13C` has exactly one `bl` (0xA8A098) and `0xD3F634` has **none** — its only
          reference is its own OPD descriptor at 0x1029318, so it is dead code. The controls that
          had to succeed and did: the sweep finds both parsers and the consumer this file already
          knew about, and the same census is what surfaced the previously-missed 0x4686 screen.
          Full-image `mulli`, so there is no edge to justify.

          **Live-code verdict: INERT, and the value we send is harmless.**
          `ClanGameController.applicants` zero-fills this byte. 0 is not in {3,4,5,6}, so on the
          twin screen it would blank the column; on the 0x4b75 screen nothing reads it at all.
          Inert twice over — the handler is unreachable (the client never sends 0x4b73,
          [CONFIRMED LIVE 2026-07-27]) and the 0x4b75 loop has no load at +0x56. Recorded as a
          hazard: if 0x4b73 is ever exercised, or the 0x4b75 screen is ever finished to match its
          twin, this byte starts choosing a render mode.
      - id: result_value
        type: u4
        doc: |
          [ELF] struct+0x58, read at 0xD55F68.

          ## ADJUDICATED 2026-08-02: `s4` -> `u4`. The `s4` was REFUTED.

          Third, independent reading, per dev/proto/README.md "Widths are evidence — and evidence
          can be re-read". The original justification was *"read with the SIGNED accessor
          0xD5CC64"*, a member of the class README.md closes under "A signed type whose only
          support is the primitive's address". The restated caller-side defence — *"the caller
          does `extsw` before formatting"* — is the **laundered form** README.md warns about, and
          it does not survive checking:

          * **The load is `lwz`, not `lwa`.** 0xA8A188 is `lwz r3,88(r26)`; the sign extension is a
            separate 0xA8A190 `extsw r3,r3`.
          * **The `extsw` belongs to the call, not to the field.** A census of all **47** `bl
            0xCFB8C8` sites in the image finds `extsw r3,r3` as the immediately preceding
            definition of r3 at **46** of them (the 47th passes a literal `li r3,0`). It is the
            ELFv1 widening of that helper's `int` formal parameter and is emitted whatever the
            argument's source type is. **That is what the incorrect reading mistook for the
            answer** — ABI boilerplate present at every call site read as per-field type evidence.
          * **The same instruction is applied to values that cannot be signed.** In the same loop,
            0xA8A0D8/0xA8A0E0, 0xA8A110/0xA8A118, 0xA8A150/0xA8A158, 0xA8A18C/0xA8A19C and
            0xA8A1D8/0xA8A1E8 do `lwz` + `extsw` on **element-name hashes** out of the stack table
            at `r1+200`. Hashes are not negative numbers.
          * **`lwa` is not evidence here either, in the other direction.** The twin screen
            (below) loads *this same struct slot* with `lwz` at 0x918E24 and with `lwa` at
            0x918EF4, in two arms of one `if`. One C member, two encodings — the choice tracks the
            callee's parameter type, not the member's.

          **Swept range for signed idioms, with the control.** `lwa` / `lwax` / `lwaux` / `lha` /
          `lhax`, and any compare against a negative constant, over the four functions that make
          up the whole reader path: the consumer **0xA89A40-0xA8A39C** (the function containing
          0xA8A098, bounds from the OPD), the parser **0xD55E40-0xD5600C**, `GetApplicantRow`
          **0xD5A13C-0xD5A190** and the count accessor **0xD5A194-0xD5A1C0**. Edges are the OPD
          entry points either side, so the ranges are whole functions and nothing is clipped.
          **Result: zero sign-extending loads.** The control that had to succeed and did: the sweep
          finds the parser's one genuinely signed value, `cmpwi cr7,r3,-1` at 0xD55EE4 (the
          0xD5CEB0 end-of-payload sentinel), plus all 51 `extsw`/`cmpwi` sites in the consumer —
          so it is not blind to the idiom it reports absent. Image-wide the compiler emits `lwa`
          1,674 times, so its absence here is a choice and not a capability gap.

          **Two positive supports for `u4`, both independent of the primitive's address:**

          1. **The twin parser declares it `u4` already.** 0x4686's parser **0xD3B42C** is
             instruction-for-instruction identical to this one (see the top-level doc) and reads
             this same slot with the same `bl 0xD5CC64` at 0xD3B554. `mgo2_cmd_4686_s2c.ksy`
             calls it `unknown_u32_b`, `u4`. Two byte-identical parsers, one slot, opposite
             declarations — the `0x4e10` shape exactly.
          2. **The meaning is a placing or a count, and neither can be negative** — see below.

          ## What the value MEANS (resolved 2026-08-02 from the 0x4686 twin screen)

          The mature consumer of this struct — the 0x4686 history screen, three identical copies
          at **0x918D14**, **0x91D094** and **0x91DB68** (verified instruction-identical apart
          from stack offsets and branch targets) — renders this field
          **through `result_kind` at struct+0x56**:

          * `result_kind` in {3, 5}: switch on this field at 0x918E24. `1` -> `HISTORY_1ST`,
            `2` -> `HISTORY_2ND`, `3` -> `HISTORY_3RD`, `5` -> `HISTORY_5TH`, anything else
            (including 4) -> the literal `"-"` at 0xE2FC20. So here it is a **finishing place**.
          * `result_kind` in {4, 6}: at 0x918EF4-0x918F3C it is `sprintf`ed with `"%d%s"`
            (0xE2DCE0) against `SURVIVAL_WIN` (0xE14068) when `<= 1` and `SURVIVAL_WINS`
            (0xE14078) when `> 1`. So here it is a **win count**, and the singular/plural test is
            a `bgt` against 1, not a sign test.
          * any other `result_kind`: the column is set to the empty string 0xE2C538 and this field
            is not read at all.

          An ordinal place and a win tally are both unsigned. String ids resolved by the standard
          route: `r30 = *(0x10353A8 - 28608) = 0xFF04E8`, then `*(r30 + disp)`.

          ## What THIS command's screen does with it — a degraded copy

          The 0x4b75 consumer at 0xA8A080 **skips the discrimination entirely** and prints the raw
          number: 0xA8A188 `lwz r3,88(r26)`, `extsw`, `bl 0xCFB8C8` (which is
          `sprintf(static_buf, "%d", v)`, format at 0xE225C8 via `r30 = *(0x10353A8 - 26488) =
          0x1004C00`), then set as the text of the element named by `[r28+48]`. It never loads
          struct+0x56. Confidence on the *label*: **[ELF/INFERRED]** — the layout, the width and
          the offset are exact and tier-1; the *meaning* is read from the twin command's consumer
          and inherited by clone, and cannot be confirmed for 0x4b75 because the client never
          sends 0x4b73. If the 0x4b7x triple was repurposed for applicants without rewriting the
          record, the label could be stale while the width stays right.

          **Live-code verdict: WRONG BUT INERT.** `ClanGameController.applicants` zero-fills this
          field. Zero is not a valid place (renders `"-"` in the twin screen) and would print a
          bare `0` in this one. It cannot reach a screen: [CONFIRMED LIVE 2026-07-27] the client
          never sends 0x4b73, so the handler is unreachable, and even if it were reached the
          0x4b75 loop prints this column without the `result_kind` gate. Recorded as a hazard
          rather than a fix, per CLAUDE.md's third case.

          [ELF 2026-08-01] **The column's element name, and why the name cannot help.**
          `r28 = r17 + 4*row` with `r17 = r1+200` (`addi r17,r1,200` at
          `0xA89ED8`), so the loop reads a 5-column x 4-row table of element-name hashes built on
          the stack at `0xA89F00`-`0xA8A04C` — column stride 16, row stride 4. Resolving each
          store against the screen module's mini-TOC (`lwz r30,-27996(r2)`, r2 = `0x10353A8`, so
          r30 = `0xFF4D18`) gives the whole table:

          | col | read at | stack slots | element names | source |
          | --- | --- | --- | --- | --- |
          | 0 | `0(r28)` | 200-212 | `STRING_low1_DATE`..`low4_DATE` | `timestamp` via `0xDC9358` + `strftime` |
          | 1 | `16(r28)` | 216-228 | `STRING_low_1_1`..`low_4_1` | `text_04` |
          | 2 | `32(r28)` | 232-244 | `STRING_low_1_2`..`low_4_2` | `name` |
          | 3 | `48(r28)` | 248-260 | `STRING_low_1_3`..`low_4_3` | **this field** |
          | 4 | `64(r28)` | 264-276 | `STRING_low_1_4`..`low_4_4` | `unknown_5c` |

          The names are **purely positional** — row N, cell M — so the developer-element-name lever
          (FIELD_MAPPING.md, batch 3c) is exhausted: the caption is bound to `STRING_low_N_3` in
          the layout file on the disc, not in the binary.

          [ELF 2026-08-02] And the twin screen uses **the same names**, which is the last proof
          that the two screens are one template. Its tables are precomputed hashes in rodata at
          `*(0xFF04E8 - 32748) = 0xE1377C`: `+1512` holds four date-column hashes
          `0x0B5FC3/C5/C7/C9` and `+1528` holds sixteen `0x55CE25..0x55DA28`. The client's own
          name hash (0xD25D0: 24-bit, `h = ((h << 5) | (h >> 19)) + c`, masked to 24 bits)
          reproduces them exactly from `STRING_low1_DATE`..`STRING_low4_DATE` and
          `STRING_low_1_1`..`STRING_low_4_4`. Positional there too, so no caption from that side
          either.

          **Two corrections to this file's own account of the screen.** It paints **five** columns
          per row, not four — the date column was not counted. And the row count is fixed at
          **four**: `r29 = min(r29 - r16, 0)` then `r25 = r29 + 4` (`0xA8A044`-`0xA8A050`), so the
          loop can never run more than four times, which matches the four-row element table exactly
          and caps what the 32-record parser limit could ever display.
      - id: unknown_5c
        type: u4
        doc: |
          [ELF] struct+0x5c, last 4 bytes of the record, read at 0xD55F84. **[UNKNOWN] — and this
          is the one field in the record the ELF genuinely cannot name.**

          [ELF 2026-07-30] **Rendered as a decimal number**, in the column after `result_value`'s:
          0xA8A1D4 `lwz r3,92(r26)`, `extsw`, `bl 0xCFB8C8`, then set as the text of the element
          named by `[r28+64]`.

          [ELF 2026-08-02] **The 0x4686 twin screen renders it the same way and adds nothing.**
          It is the other cursor's own target: `r26 = row + 92`, and 0x918F94 `lwa r5,0(r11)`
          (r11 = r26) hands it to `0x943B00(widget, elem, value, 0)`, which is
          `sprintf(r1+112, "%d", value)` (format 0xE2E3F0 via `r30 = *(0x10353A8 - 28524) =
          0xFF0D68`) followed by a set-text. So both screens print it as a bare `%d` in the last
          column. Unlike `result_value`, **nothing switches on it, nothing compares it, and no
          `result_kind` arm changes how it is drawn** — there is no second reader anywhere to
          disambiguate it.

          Type stays `u4` and is **not** contested: it is read by `0xD5CCD8` at 0xD55F84, the same
          primitive its `mgo2_cmd_4686_s2c.ksy` counterpart (`unknown_u32_c`) is read by, both are
          declared `u4`, and the two `extsw`/`lwa` sites above carry no signedness for the reasons
          set out at length under `result_value`.

          **[ELF — NEGATIVE 2026-08-02] No third reader.** Same sweep as `result_kind`: the only
          routes to a row are the two parser staging buffers, the two accessors and the three
          inlined `list + 8 + i*96` sites, found by an **image-wide** `mulli rX,rY,96` census
          returning exactly seven hits (0xD55FA8, 0xD3B594, 0xD5A174, 0xD3F66C, 0x918D00,
          0x91D080, 0x91DB54). Control that had to succeed and did: the same census found the
          0x4686 consumer that overturned `result_kind`'s earlier negative, so it is demonstrably
          capable of finding a reader this file did not already know about.

          Its element is `STRING_low_N_4`, the last of the five columns, and the twin screen's
          table resolves to the **same** positional names — full working under `result_value`. So
          the caption binding lives in the layout file on the disc, not in the ELF, on both sides.

          **What would decide it.** Nothing static — the ELF is closed out for this field. Two
          experiments, in order of cost:

          1. **Cheap and available today: exercise 0x4686, not 0x4b75.** It is a live command on
             the match-history path, its parser is instruction-identical to ours, and its screen
             is the finished one. A capture with distinct sentinels in `+0x58` and `+0x5C` read
             against the printed captions names both fields for both commands at once.
          2. Make the client send `0x4b73` (it never does on its own; applications arrive as
             mailbox type `0x10`) and answer with a sentinel-bearing triple. Note the row-0 hazard
             under `timestamp`: this screen's date column passes the row pointer where a
             `time_t*` is wanted, so column 0 is garbage regardless and is not evidence.

          **Live-code verdict: INERT, value unverifiable.** `ClanGameController.applicants`
          zero-fills these four bytes, which would print a bare `0`. Whether `0` is right cannot
          be judged while the field is unnamed; it cannot reach a screen either way, because the
          client never sends 0x4b73 ([CONFIRMED LIVE 2026-07-27]).
