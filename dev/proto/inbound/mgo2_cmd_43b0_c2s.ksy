meta:
  id: mgo2_cmd_43b0_c2s
  title: "MGO2 0x43b0 — client -> server: Survival match result report"
  endian: be
doc: |
  Builder function `0xD44D50` = `f(session, u32 a, u32 b, u32 c, u32 d, u32 e)` — five caller u32s
  staged at `r1+1432`/`1440`/`1448`/`1456`/`1464` (`0xD44D88`-`0xD44D98`), plus three fields read
  out of a session-resident record. `bl 0xD5CF40` at `0xD44DF8` (`li r4,0x43B0` at `0xD44DF4`),
  seal `0xD5C828` at `0xD44E8C`, flush `0xD34CC0` at `0xD44E9C`. Not encrypted.
  **Total payload 29 bytes (0x1D).**

  Write order (`0xD44E00`-`0xD44E80`): `0xD5C9BC` u32 from `rec+0x00`, `0xD5C8A0` u8 from `rec+0x08`,
  `0xD5C9BC` u32 from `rec+0x10`, then the five caller u32s in argument order. `r29` is the session
  after `addis r29,r29,1` at `0xD44DD8`, so the displacements 5464/5472/5480 are
  `0x10000 + 0x1558/0x1560/0x1568`. The only precondition is `0xD4EA60(session) != 0` at
  `0xD44DC8`, and that function returns `session + 0xDBD0` — i.e. the guard is just "session is not
  null", not a state check.

  ## 1. The record: `session + 0x11558`, 356 bytes, the SURVIVAL MATCH-SERIES record

  All three non-argument fields come from one struct, reached everywhere through the leaf accessor
  **`0xD3F7B0`** (`return session ? session + 0x11558 : 0`) — 38 `bl` call sites binary-wide, which
  is what makes the field census below closed rather than a range sweep.

  Its shape is given by its initialiser **`0xD41850`** = `f(session, a, b, c)`:
  `bzero(session+0x11558, 0x164)` at `0xD4188C` — **the record is 356 bytes** — then
  `rec+4 = a`, `rec+8 = b`, `rec+9 = c` (`0xD41894`-`0xD4189C`).

  Its layout is given by its reader, the **`0x4A13` parser `0xD44EF8`**, which walks it end to end:

  ```
  rec+0x00 u32   read first from the wire and REQUIRED TO MATCH (else -0x452 = -1106) 0xD44F9C
  rec+0x04 u32                                                                        0xD45050
  rec+0x08 u8    join kind                                                            0xD45058
  rec+0x09 u8                                                                         0xD4505C
  rec+0x0C u32   participant A's win count      \                                     0xD45060
  rec+0x10 u32   participant B's win count      |                                     0xD45064
  rec+0x14 u32   participant A's id             |  the two parallel halves            0xD45070
  rec+0x18 [16]  participant A's name           |                                     0xD45090
  rec+0x2C..0x48 8 x u32, A's                   |                                     0xD450C0
  rec+0x4C u32   participant B's id             |                                     0xD450E4
  rec+0x50 [16]  participant B's name           |                                     0xD45104
  rec+0x64..0x80 8 x u32, B's                   /                                     0xD45134
  rec+0x88 u32                                                                        0xD4506C
  rec+0x8C u32   reward                                                               0xD45068
  rec+0x160 u8                                                                        0xD45158
  ```

  **The A/B pairing is proved by the consumer, not by adjacency.** `0x8CE0AC` and `0x8CE1B0` both do
  `if (rec[0x14] == *(*(screen+0x6C))) n = rec[0x0C]; else n = rec[0x10];` then read the reward from
  `rec[0x8C]` — i.e. `rec+0x14` is the id that selects `rec+0x0C`, so `rec+0x14` and `rec+0x0C`
  belong to the same participant and `rec+0x4C`/`rec+0x10` to the other. The 8-u32 arrays are read
  as interleaved pairs (`+0x2C`/`+0x64`, `+0x30`/`+0x68`, …) at `0x270CB4`, `0x272D18` and
  `0x273838`, which independently confirms the two-halves shape.

  ### What names it: the screen's own strings

  `0x8CD260` is the consuming screen, and every `0x8E0C24(id)` call in it lands in disc string group
  **`0xF914BF` = "lobby"** (set `[2f0293]`, header base 9789), ids **756-778**. Read out:

  | id | text |
  | --- | --- |
  | 760 | `Entry into Survival\nhas been canceled.` |
  | 761 | `Your next opponent has been determined.\nThe match will begin shortly.\nPlease wait.\nNext match: vs. %s` |
  | **762** | `Match #%d has ended.\nPlease wait until the next match begins.\nYour reward: %d` |
  | **763** | `The match has ended.\nYour winning streak ends at %d wins.\nYour reward: %d` |
  | 764 | `The match has ended.\nYour streak now stands\nat %d wins.\nYour reward: %d` |
  | 765 | `The final match has ended.\nYou have set a new record\nof %d wins in a row.\nYour reward: %d` |

  `0x8CE0E8` fetches 762 and formats it with `(n + 1, rec[0x8C])`; `0x8CE22C` fetches 763 and
  formats it with `(n, rec[0x8C])`. So `n` is a **win count** — "Match #" is wins + 1 — `rec+0x8C`
  is the **reward**, and `rec+0x18`/`rec+0x50` are the opponent names string 761 renders as `vs. %s`.

  **This record is the Survival ladder.** Its writers are the `0x49xx`/`0x4Axx` parsers
  (`0xD4BD88`, `0xD4CBCC`, `0xD4D860`, `0xD5128C` for `0x4A00`, `0xD51E94` for `0x4A12`), each
  publishing the same eight-field set `{+0, +4, +8, +9, +0xC, +0x10, +0x88, +0x8C}`; `0x4A12`'s
  sources are `session+0xDCB8 + {0, 0x1BF8, 0x1BFC, 0x1BFD, 0xDC(u16), 0xE0(u16)}` at
  `0xD51EA4`-`0xD51ED8`.

  ### RELEASE-DAY SCOPE — this whole command is post-launch content

  **Survival lobbies are Ver. 1.10**, i.e. out of scope for v1 per `CLAUDE.md`. Naming the gate is
  the point here; opening it is not. Two gates are worth recording for a future toggle:

  1. `0x2751A0` (the sender's caller) only reaches the `0x43B0` path when **bit `0x400` of
     `gameObj+0xBCC`** is set — `rlwinm r0,r0,0,21,21` at `0x2751E8`, `bne -> 0x2753AC` at
     `0x2751F0`. Clear, and the function runs the ordinary teardown at `0x2751F4` and sends nothing.
     **The writer of that bit was not located** and is left as an open item rather than guessed.
  2. `0x4A13` will not be accepted at all unless its first u32 equals `rec+0x00`, which only the
     `0x49xx`/`0x4Axx` flow can populate.

  ## 2. The sender chain, which is what names the last three fields

  `0x2753EC` `bl 0xD44D50` is the **sole** entry to the builder (full `b`/`bl`/`bc` decode of
  `0x10200`..`0xDEBEEC`; the same scan finds `0x27DC48` for `0x4390`, the control). Its arguments:

  ```
  0x2753BC  r3 = 0xD3F7B0(session)                -> rec
  0x2753CC  r5 = rec[0x4C]   \  swapped at 0x275688 (r5 = rec[0x14], r4 = rec[0x4C])
  0x2753D0  r4 = rec[0x14]   /  when 0x2751A0's arg0 != 0
  0x2753E0  r6 = 0x2751A0's arg1
  0x2753E4  r7 = 0x2751A0's arg2
  0x2753E8  r8 = 0x2751A0's arg3
  ```

  and `0x2751A0`'s only caller is `0x706A04`, inside the round object's report state machine
  `0x706968` (vtable method, OPD `0x10153A8`, slot `0xFB5160`; state at `obj+0xA0`: 0 -> set 1 and
  `0x9C8C18`, 1 -> poll `0x9C8B28` until the end-of-round screen finishes, then report and set 2).
  It passes **four adjacent bytes of the round object**:

  ```
  0x7069F4  r3 = obj[0x53]    the outcome team  -> selects the swap above
  0x7069F8  r4 = obj[0x54]    the outcome reason
  0x7069FC  r5 = obj[0x55]    outcome operand 1
  0x7069F0  r6 = obj[0x56]    outcome operand 2
  ```

  **The quad's writers**, and the whole of its value set:

  * constructors `0x703038` (`0x703258`-`0x703268`) and `0x7036D0` (`0x7038F0`-`0x703900`) —
    `+0x53 = -1` (0xFF, undecided), `+0x54 = +0x55 = +0x56 = 0`;
  * `0x706388`, entered only when `obj[0x53] == 0xFF` (`0x7063A4`-`0x7063B0`), and its
    instruction-for-instruction sibling `0x7086F8` in another rule's vtable. Three branches:
    - **reason 2** (`0x706444`/`0x708A08`) — a side has reached the round-win target
      (`0x6A9B38(1)[0]` compared against the target at `0x706420`). `+0x55` = `0x6A9B38(0)[0]`,
      `+0x56` = `0x6A9B38(1)[0]`, i.e. team 0's and team 1's round-win counters.
      `0x6A9B38(i)` is `RecordBuffer(0) + 0x56 + i*4` — a per-team byte in property record 1.
    - **reason 5, aggregate-score branch** (`0x706540`/`0x706560`) — each team's live score counter
      n03 is summed over all 24 slots (`0x6A96D0(slot)` for the team, `0x6A9698(slot)` then
      `lhz r0,6(r3)` for the score) at `0x7064E0`-`0x706528`; the higher total sets `+0x53` to 0 or
      1 and **`+0x55` and `+0x56` are both set to that same winning team index** (`lbz r9,0x53`
      read straight back out at `0x706548`).
    - **reason 5, MVP branch** (`0x70656C`), taken when the two totals are equal:
      `s = 0x6EB068(3, 0)`; if `0x6A9630(s)` is non-null, `+0x55 = +0x56 = s` (a player slot) and
      `+0x53 = record[s][1]` — character-record field **1**, the same team byte `0x4344` and
      `0x4440` carry. If it is null, `+0x54 = 0` and `+0x53 = 0xFF`: a true draw, nothing decided.

  **NON-CIRCULAR CAPTURE SUBJECTS.** `POST_LAUNCH.md`'s warning about `0x4310` — that a promising
  "unused" field turned out to be our own byte echoed back — does not apply to wire `0x11`, `0x15`
  and `0x19`. Those three are computed by the client from live gameplay state (score counters,
  roster teams, an MVP pick) and are **never server-supplied**, so a capture of them is genuine
  evidence about the client. The other five fields are all echoes of record bytes we sent and are
  circular; do not read anything into them.

  ## 3. What a reply must look like

  **The reply is mandatory.** On a successful flush the builder calls `0xD32E08(session, 0x37, 1)`
  at `0xD44EA4`-`0xD44EB8`, i.e. it sets **wait slot `0x37` (55)** to state 1 = outstanding.
  (`0xD32E08` = `SetWaitSlot(session, slot, state)`; table at `session + 0x160 + slot*4`, value at
  `+8`, slot capped `0x74`, state capped 2.) A failed flush returns `-0x3D` and opens no slot.

  The completing parser is **`0xD40220`** (arm `cmpwi r0,0x43B1` at `0xD40264`):

  - `0x43B1`, payload **exactly 4 bytes**: one big-endian **s32 result**, read by `0xD5CC64` into
    `r1+0x70` at `0xD4027C`, then `READ_END` `0xD5C858`. Nothing else is parsed.
  - It then does `0xD32E08(session, 0x37, 2)` and `0xD32E70(session, 0x37, result)` with `lwa`, so
    the value is stored **signed**; 0 is success by this protocol's convention.
  - Header mismatch yields `-0x46`; a short read yields `-0x47`.

  Because the sender is gated behind Survival (§1), an unhandled `0x43B0` is a latent `FFFFFF60`
  rather than a live one on a release-day server — but the gate is a *content* gate, not a code one,
  so the handler is cheap insurance.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: series_id
    type: u4
    doc: |
      [ELF] wire 0x00. `rec+0x00` — the key of the Survival match series this report belongs to.

      **What is proved:** the `0x4A13` parser `0xD44EF8` reads a u32 as its very first field and
      **refuses the whole packet with `-0x452` (-1106) unless it equals this slot**
      (`lwzu r0,0x1558(r31); cmpw cr7,r0,r9; bne -> -0x452` at `0xD44F9C`-`0xD44FA4`). Its only
      writers are the five `0x49xx`/`0x4Axx` publication sites listed in the header, always as the
      first member of the eight-field set. So it is a **server-issued identifier that the client
      stores and validates inbound traffic against**, and echoes here.

      **What is not proved:** whether it is a series id, a game id or an entry id. It is not the
      `0x4313` `game_id` by any traced path. Left named for its role, not for a guessed referent.
  - id: join_kind
    type: u1
    doc: |
      [ELF] wire 0x04. `rec+0x08` — upgraded from [INFERRED] to tier 1 by three independent writers:

      * the record initialiser `0xD41850(session, a, b, c)` stores its **second** argument here
        (`stb r28,8(r31)` at `0xD4189C`), immediately after `bzero(rec, 0x164)`;
      * the `0x4310` create-game builder writes it at `0xD44860` (`stb r11,5472(r9)`);
      * the `0x4320` join builder writes it at `0xD45308`, and the guard immediately above
        (`0xD452D8`-`0xD452F8`) admits only the values **1, 2, 7, 8** — the join-kind domain;
      * the five `0x49xx`/`0x4Axx` parsers write it as member 3 of their eight-field publication.

      Readers: `0x8BDF10` (at `0x8BE07C`, which reads `rec+4`, `rec+8` and `rec+9` together) and
      `0x8F96EC` (at `0x8FA03C`). Meaning of the individual values 1/2/7/8 is still [UNKNOWN]; see
      mgo2_cmd_4320.ksy.
  - id: side_b_win_count
    type: u4
    doc: |
      [ELF] wire 0x05. `rec+0x10` — **participant B's win count in the Survival series**.

      Named by the consumer, not by position. `0x8CE0AC` and `0x8CE1B0` both compute
      `n = (rec[0x14] == myId) ? rec[0x0C] : rec[0x10]` and render `n` into disc "lobby" strings
      762 (`Match #%d has ended…`, formatted as `n + 1`) and 763
      (`Your winning streak ends at %d wins.`, formatted as `n`), with `rec[0x8C]` as the reward.
      That test pairs `rec+0x0C` with `rec+0x14` and therefore `rec+0x10` with `rec+0x4C`, which is
      what makes this the **B** side's counter specifically.

      Source width note, flagged not changed: the `0x4A12` parser fills it with
      `lhz r0,0xE0(r29); stw r0,0x10(r3)` at `0xD51ECC`/`0xD51ED4` — a **u16** widened to u32. The
      wire field is genuinely u32 (`0xD5C9BC`), so nothing here moves; values above 65535 are simply
      unreachable.

      The record's own name for the field the earlier revision used, `ctx_11568`, is retired: the
      displacement is real but it described the address, not the value.
  - id: winner_participant_id
    type: u4
    doc: |
      [ELF] wire 0x09. Caller argument 1. **`rec+0x14` when the round outcome byte `obj[0x53]` is
      0, `rec+0x4C` otherwise** — the swap is `0x2753CC`/`0x2753D0` versus `0x275688`/`0x27568C`,
      selected by `cmpwi cr7,r31,0` at `0x2753C4`.

      `obj[0x53]` is the winning team index (see the header, §2), and `rec+0x14` / `rec+0x4C` are
      the two participants' ids, so in both decided branches this field carries **the winner's
      participant id** and the next field the loser's.

      **The one degenerate case, stated because the name would otherwise hide it:** on a true draw
      `obj[0x53]` is `0xFF`, which is non-zero, so B's id lands here and the winner/loser labels
      mean nothing. `obj[0x54]` (wire 0x11) is 0 in exactly that case and is the field to test.
  - id: loser_participant_id
    type: u4
    doc: |
      [ELF] wire 0x0D. Caller argument 2 — the other of `rec+0x14` / `rec+0x4C`, by the same swap.
      Same degenerate-draw caveat as `winner_participant_id`.

      Note that before this batch `rec+0x4C` had **no reader anywhere outside this call site**: the
      38-site census of `0xD3F7B0`'s callers turns up exactly one load of `+0x4C`, at `0x2753CC`.
      It exists to be reported back.
  - id: outcome_reason
    type: u4
    doc: |
      [ELF] wire 0x11. Caller argument 3 = round object byte **`obj[0x54]`**, zero-extended.
      A **u8 source in a u32 field**; only three values are reachable:

      * **0** — nothing was decided. The constructors' initial value (`0x703264`, `0x7038FC`), and
        also what `0x7065B4`/`0x708B94` write on the true-draw path where the MVP lookup fails.
      * **2** — a side reached the round-win target (`0x706448`, `0x708A0C`).
      * **5** — decided after the fact, either on aggregate team score (`0x706554`, `0x708B34`) or
        on an MVP pick when the totals tied (`0x7065A4`, `0x708B78`).

      No other value is written anywhere. **This is client-computed and never server-supplied**, so
      it is a valid subject for a non-circular capture check.
  - id: outcome_operand_1
    type: u4
    doc: |
      [ELF] wire 0x15. Caller argument 4 = round object byte **`obj[0x55]`**, zero-extended. A u8
      source in a u32 field. **Its meaning is keyed by `outcome_reason`** and is not constant:

      * reason **2**: `0x6A9B38(0)[0]` — team 0's round-win counter
        (`0x6A9B38(i)` = `RecordBuffer(0) + 0x56 + i*4`; `0x706460`, `0x708A20`).
      * reason **5**, score branch: the winning team index, copied back out of `obj[0x53]`
        (`0x706558`, `0x708B38`).
      * reason **5**, MVP branch: the deciding player's slot, `0x6EB068(3, 0)`
        (`0x7065A8`, `0x708B7C`).

      A single label would be wrong in two of the three branches, so none is given. Client-computed;
      valid non-circular capture subject.
  - id: outcome_operand_2
    type: u4
    doc: |
      [ELF] wire 0x19. Caller argument 5 = round object byte **`obj[0x56]`**, zero-extended. Frame
      ends at 0x1D. Same three branches as `outcome_operand_1`, and it differs from it in exactly
      one of them:

      * reason **2**: `0x6A9B38(1)[0]` — team **1**'s round-win counter (`0x70646C`, `0x708A30`).
        This is the branch where the pair is a genuine two-element score line.
      * reason **5**, either branch: **identical to `outcome_operand_1`** (`0x706550`/`0x70659C`,
        `0x708B30`/`0x708B70`).

      Per the "no mirror labels without divergence tests" rule this is recorded as *matching*
      operand 1 on the reason-5 paths, not as a duplicate — reason 2 is the divergence, and it is in
      the code, so no experiment is needed to establish it. Client-computed; valid non-circular
      capture subject.
