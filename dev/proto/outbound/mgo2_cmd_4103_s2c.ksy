meta:
  id: mgo2_cmd_4103_s2c
  title: "MGO2 0x4103 — personal-stats character info (reply 1/4 of the 0x4102 burst)"
  endian: be
  encoding: ISO-8859-1
doc: |
  First reply to 0x4102 {u32 chara_id}. Fixed 648-byte (0x288) grid on success; a 4-byte
  error form (nonzero status, no body) makes the client error-complete wait slot 0x16 and
  skip the body (parser 0xd3e9ac, branch 0xd3ea38).

  Layout READ from the client parser (full trace 2026-07-23, loop trip counts from
  disassembly, total emulator-verified). Field LABELS are marked per-field:
  [CONFIRMED] = live capture-proven via the fingerprint sessions (OBSERVED.md),
  [INFERRED]  = offset-mirror of the 0x4101 record or structural reasoning,
  [UNKNOWN]   = position exact, meaning unestablished; fingerprint value & outcome noted.
  "T+0x..." is the client-side struct destination (T = *(obj+0x11904)).

  2026-07-27: the block at the head of the tail — T+0x1AA0 / T+0x1AA4 / T+0x1AB5, previously
  three separate unknowns carrying fingerprint values — is the **clan record**, the same
  `{u32 id, char name[16], u8 state}` triple this protocol uses for a clan in the session record
  at +0x1AA0, in `0x4122`'s block, in `0x4b47`, in `0x4b21`'s head and in `0x4221` at wire 0xa7.
  It is followed by the twelve u16s of the clan privilege/notification word. See those fields for
  why the earlier "NOT the clan field" elimination did not hold.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: status
    type: u4
    doc: "0 = success. Nonzero: packet is 4 bytes total, client error-completes. [CONFIRMED]"
  - id: body
    type: stats_info_body
    if: status == 0
types:
  stats_info_body:
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED]"
      - id: name
        type: str
        size: 16
        doc: "NUL-padded character name. [CONFIRMED]"
      - id: const_block
        type: u2
        repeat: expr
        repeat-expr: 4
        doc: |
          Always 0x16AE, 0x0338, 0x013E, 0x0150 — same constants as 0x4101 offset 0x14,
          reproduced byte-for-byte from the original server. Meaning [UNKNOWN].
      - id: experience
        type: u4
        doc: |
          [INFERRED] from the 0x4101 offset mirror — the raw number never renders on this
          screen. The header showed "Level 22" while this carried 1234; the level is
          presumably client-derived from experience, but that mapping is unverified.
      - id: login_previous
        type: u4
        doc: "Unix seconds. [INFERRED] from the 0x4101 mirror; never seen rendered on this screen."
      - id: login_current
        type: u4
        doc: "Unix seconds. [INFERRED], as login_previous."
      - id: hud_class_nibble
        type: u1
        doc: |
          wire 300, T+0x3328 = **profile+13096**. Parser `0xD3EB4C` (`addi r4,r31,13096` -> the u8
          reader `0xD5CB54`). Previously `unk_flag`.

          [EXPLAINED, IDENTITY STILL OPEN — 2026-08-01, by struct-offset bijection]
          **This is the same struct slot as `0x4101` wire 0x028** (`unknown_028`, parser
          `0xD3C288`, `addi r4,r27,13096` with `r27 = ctx+22488`). The bijection is not a name
          resemblance: this packet writes `T = *(ctx+0x11904)` and `0x4101` writes
          `profile = ctx+0x57D8`, two instances of ONE struct type, and three independently
          CONFIRMED fields agree on their displacements across the pair — the 128-byte `comment`
          at +7716, the worn title at +7845, and the whole clan record at +6816/+6820/+6837.

          What `0x4101`'s entry establishes, and is not repeated here: it is a **4-bit enum**, the
          only values anything distinguishes are **2 and 3**, and its readership is four predicate
          thunks (`0x9BEB88`, `0x9BEBE0`, `0x9BFFF0`, `0x9C0050`) behind 18 in-game HUD/nameplate
          call sites. Bits 4-7 are NOT ours — the join-announcement packer at `0x8842B4` builds
          `announce[2] = (profile[13096] & 0xF) | (client settings bit << 5)`, so the client's own
          settings occupy the high nibble.

          **Bits tested / discarded, for this packet specifically:** every reader masks with
          `clrlwi r0,r0,28`, i.e. **bits 0-3 are read and bits 4-7 are discarded**. There is no
          overrun hazard into it: the field is preceded on the wire by `login_current` (a u32), not
          by a string, and the nearest string is 279 bytes earlier.

          Two direct readers exist off `0xD3A094` (the LOCAL record, not `T`): `0x8842B4` and
          `0x8BA540`. **No reader was found off `0xD3A0AC` (`T`)**, so the copy THIS packet writes
          may well be inert while the `0x4101` copy is the live one — stated as an open question,
          not a negative, because the two share a slot and a reader cannot tell them apart.

          Renamed from `unk_flag` on the enum's shape alone. It is deliberately NOT given a
          semantic name: `0x4101`'s entry records that nibble 3 shares one HUD branch with the
          Combat Training instructor predicate `0x9C0600`, and one shared branch is not an
          identity.
      - id: friend_ids
        type: u4
        repeat: expr
        repeat-expr: 32
        doc: |
          T+0x20..0x9C. Flat id array [CONFIRMED structurally] (32-trip parser loop; v4
          fingerprint 8001-8032 changed nothing on the stats screen — not stats).
      - id: blocked_ids
        type: u4
        repeat: expr
        repeat-expr: 32
        doc: "T+0xA0..0x11C. As friend_ids (v4 fingerprint 8501-8532). [CONFIRMED structurally]"
      # ---- tail: flat packed field sequence, wire offsets 301..647 ----
      - id: beginner_flag
        type: u1
        doc: |
          wire 301, T+0x3329 = **profile+13097**. Parser `0xD3EBDC`. Previously `unk_u8_a`
          (fp v5: 42, never surfaced — which is the expected outcome under both hypotheses, since
          the flag is only consulted when a lobby carries the beginners-only restriction bit and
          we never set that bit).

          [NAMED 2026-08-01, by struct-offset bijection with `0x4101` wire 0x129 — which is
          CONFIRMED there.] Same struct slot, same u8 reader `0xD5CB8C`; four parsers write it
          (`0x4101` `0xD3C318`, `0x4129` `0xD3CA6C`, `0x4122` `0xD3D964`, this one `0xD3EBDC`).

          **Non-zero means the character may enter a lobby whose list entry is marked
          "beginners only". Zero makes the client refuse the lobby locally**, error screen `0x933`
          ("You cannot login to this lobby.", ERRORS.md 2355) with code `-0x194`. Six readers, all
          based on `bl 0xD3A094`: `0x89224C`, `0x935B34`, `0xABCF90`, `0xABDA14`, `0xAC8270`,
          `0xACCED4`. Full working — including why `0x884300` is what makes it a *beginner* flag —
          is in `mgo2_cmd_4101_s2c.ksy`; it is not duplicated here.

          As with `hud_class_nibble` above, all six readers take the LOCAL record from `0xD3A094`,
          not `T` from `0xD3A0AC`, so what this packet's copy is for is open. The name is
          nonetheless right: it is the same slot, and the slot's meaning is a property of the
          struct, not of the packet that filled it.
      - id: clan_id
        type: u4
        doc: |
          wire 302, T+0x1AA0. **The clan id**, first member of the `{u32 id, char name[16],
          u8 state}` clan record. [CONFIRMED 2026-07-27.] It is the gate: readers check the id
          first and treat 0 as "no clan" whatever the name says. (fp 4001 — see the elimination
          note on `clan_name`.)
      - id: clan_name
        type: str
        size: 16
        doc: |
          wire 306, T+0x1AA4. **The clan name**, second member of the clan record.
          [CONFIRMED 2026-07-27.]

          CORRECTS A FALSE ELIMINATION. This field previously read: `[UNKNOWN] (fp "FP-STR-A",
          never surfaced; NOT the clan field — clan stayed blank)`. The observation was real and
          the conclusion was invalid. The fingerprint pass put a string here with **fp 4001 — a
          made-up number, not a real clan — in `clan_id` before it**, and a zero-or-nonsense id
          means the client renders no clan no matter what the name holds. So "clan stayed blank"
          was the expected outcome under BOTH hypotheses and could not distinguish them.

          Per CLAUDE.md: an elimination is only valid if you can state the observation that would
          have confirmed it and check the experiment actually produced that observation. This one
          could not have. Nothing had ever put a real clan — a non-zero id with a matching name
          and state — into these three fields until 2026-07-27, and when something did, the clan
          rendered. Same triple, same failure mode, as `0x4221` wire 0xa7/0xab/0xbb.
      - id: clan_state
        type: u1
        doc: |
          wire 322, T+0x1AB5. **Clan membership state**, third member of the clan record.
          [CONFIRMED 2026-07-27.] Constants the client writes for itself: 0 affiliation pending
          (0xD58740), 1 member (0xD56B68), 2 leader (0xD56B84), 99 not in a clan (0xD56B44 /
          0xD56C7C / 0xD56D68). Readers test membership as `state - 1 <= 1`. (fp 43.)
      - id: clan_privilege_block
        type: u2
        repeat: expr
        repeat-expr: 12
        doc: |
          wire 323, T+0x1AB6..0x1ACC. **The clan privilege/notification word and its eleven unread
          siblings.** [CONFIRMED 2026-07-27] for element 0; elements 1-11 [UNKNOWN] and have no
          reader anywhere in the binary. Previously logged as an undifferentiated unknown block
          (fp 5101-5112, "never surfaced") — for the same reason as `clan_name` above: with no
          real clan in the record before it, there was nothing for a privilege word to apply to.

          **Element 0 must be sent as ZERO.** Two experiments, both live 2026-07-27:
            * All 16 bits set produced a saluting-soldier "!" badge and a hard poll loop at
              roughly 73 ms — the clan screen coroutine at `0xAB0074` ands the word with `-1`, or
              with `-257` when the player is the leader (`0xAB004C`), and returns without
              advancing its state machine if anything survives, so the screen re-entered and
              re-sent its request forever.
            * Bit 8 alone (`-257` = `~0x0100`, the one bit a leader may hold without stalling)
              did not stall, but produced only the "!" badge and no new menu row anywhere; emblem
              loading worked with and without it. So bit 8 is a **pending-notification** bit and
              gates nothing.

          The whole word is therefore a notification mask the client drains to zero, not a
          permission mask. No privilege bit gates applying an emblem: the commit gate at
          `0xAD409C` reads membership state 2 (`clan_state` above) and nothing else.
      - id: clan_join_time_high
        type: u4
        doc: |
          wire 347, T+0x1AD0 = **profile+6864**. Parser `0xD3EDA0` -> the u32 writer `0xD5CCD8`,
          which does a 4-byte `stw`. Previously `unk_u32_b` (fp 4002).

          [SLOT IDENTIFIED, VALUE UNREAD — 2026-08-01.] The slot is `0x4122` wire 0x2d, which that
          schema calls `current_time` (ctx+29352; 29352 - 22488 = 6864). It is the last member of
          the clan block: clan record at +6816/+6820/+6837, the twelve privilege u16s at
          +6838..+6860, this at +6864, the emblem flag at +6872.

          **The two packets disagree on the width, and that is a finding, not a transcription.**
          `0x4122` reads a u32 and stores it **eight bytes wide** — `std r0,48(r26)` at `0xD3D264`,
          `r26 = ctx+29304 = profile+6816`, so it fills 6864..6871 as a zero-extended u64 (a
          `time_t`). This packet stores **four** bytes, at 6864..6867. On a big-endian u64 that is
          the **HIGH half**, i.e. the half `0x4122` always leaves zero. So the two writers do not
          agree on what lives here, and ours cannot be a seconds value in `0x4122`'s
          interpretation. The name above records the slot, with `_high` recording which half this
          packet actually reaches.

          **STATED NEGATIVE — nothing reads profile+6864..6871.** Swept range: every D-form and
          DS-form load/store in the whole of `.text`, `0x10230` (first instruction) ..`0xDE9328`
          (end of `.text`, the bound `mgo2_cmd_4122_s2c.ksy` established), at displacements
          6864-6871 off any base. 23 hits, every one rejected:
            * `0x41297C`/`0x412980` — the dense engine-struct `stw` init already rejected on
              provenance in `0x4101`'s `unknown_028` and `0x4122`'s `unknown_3a`.
            * `0x5366F8`/`0x536744` — `stfs`, a **float** struct.
            * `0x94F08C`/`0x94F094`/`0x950908`/`0x950910` — rejected on provenance: the same run
              writes u32s at 6840, 6844, 6848 …, which would straddle the profile's u16
              `clan_privilege_block` at the ODD displacement 6838. A u32 array on a 4-byte grid and
              a u16 array based at 6838 cannot be the same bytes.
            * `0x8AA378`, `0x8AD6C8`, `0x8ADADC`, `0x8ADDE4`, `0x8ADE34`, `0x8ADEFC`, `0x8AE0C0`,
              `0x8AE2C0`, `0x8AEE60`, `0x8AFE4C`, `0x8B1774`, `0x8B2318` — all at 6868 only, none
              at 6864, and none with `0xD3A094`/`0xD3A0AC` anywhere in provenance.
            * `0xA9ED70`, `0xA9FF70`, `0xD3EDA0` — `addi`, pointer formation; the last is this
              parser.

          **The re-based-pointer path was swept too, because a displacement sweep alone would miss
          it.** Every `addi rX,rY,6816` in `.text` (the clan-record pointer) was enumerated — 17
          sites — and each scanned forward for an access at +40..+64 off the register it defines.
          Every hit is at **+56 = 6872, the emblem flag** (`0x8E1EB4` lbz; `0xAB5C04`, `0xAB98FC`,
          `0xAD40C0`, `0xAD4724` stb). **Not one touches +48..+55.**

          Control that should succeed, and does: the same sweep finds the readers for this packet's
          three known-good anchors — wire 541 (worn title, +7845) at `0x906270`, `0x906320`,
          `0x915D3C`, `0x916AFC`, `0x8842A4`; wire 563 (title mask, +13008) at `0x91B338` and
          `0x91D83C`; wire 575 (host-rating denominator, +13020) at `0x91858C`.

          Limit of the sweep, stated so nobody re-derives it as a certainty: it cannot see an
          `lwzx`-style indexed load whose offset is computed in a register. Every reader found
          anywhere in this struct uses a direct displacement, so that form is not this code's
          idiom, but it was not excluded.
      - id: appearance_a
        type: u1
        repeat: expr
        repeat-expr: 9
        doc: |
          wire 351, T+0x1DE0..0x1DE8 = **profile+7648..7656 = appearance struct +0..+8**.
          Nine separate u8 reads, `0xD3EDBC`..`0xD3EEA8`. Previously `unk_u8_block_a` (fp 61-69).

          [NAMED 2026-08-01.] **This is the head of the 200-byte appearance struct** — the one the
          whole `0x4130`/`0x4131` pair is about. `0xD3EDBC` is `addi r27,r31,7648`, and every
          subsequent field of this packet's tail through wire 541 is addressed off that `r27`, so
          the parser itself declares the struct boundary.

          Same nine bytes as `0x4122` `appearance_a` (ctx+30136..30144; 30136 - 22488 = 7648) and
          `0x3049` `appearance_a`: **appearance bytes 0-8, gender … pitch**.

          **Which of the nine the player can edit, from the client's own change detector.**
          `0x93E5B4`-`0x93E720` is the "has anything been edited?" comparator that gates the
          `0x4130` send; it compares struct offsets **0..8** and **16..29**, then the two
          five-slot arrays and the u32 array. `0x4130` itself serialises only **+2..+6** (upper,
          lower, face paint, upper colour, lower colour). So **+0, +1, +7 and +8 are
          create-time-only** — carried in this packet and in `0x4122`, never re-sent by an outfit
          change. `mgo2_cmd_4131_s2c.ksy` states the same boundary from the other side.

          **Two of the create-only bytes have readers, and they constrain the value range.**
          `+7` (profile+7655) is read at `0x887A6C`, `0x9B2D08`, `0x9B4218`, `0x9B56B0`, and
          `+8` (profile+7656) at `0x887A70`, `0x9BC098`. The gate at `0x887A74` is
          `(byte[+7] - 7) <=u 7`, i.e. it accepts **7..14 and nothing else**, and `0x9B2D14`
          computes `byte[+7] - 7` and stores it as a model/appearance selector at `screen+1136`.
          So `+7` is a 1-of-8 selector biased by 7. What the eight are is **open**.

          The join-announcement packer `0x88407C` copies all nine to `announce+28..+36`
          (`0x88424C`-`0x884290`), so they are published to peers.
      - id: dead_appearance_12
        type: u4
        doc: |
          wire 360, T+0x1DEC = **profile+7660 = appearance struct +12**. Parser `0xD3EEB8`.
          Previously `unk_u32_c` (fp 4003).

          [STATED NEGATIVE — no reader; meaning unestablished. 2026-08-01, agreeing with the
          independent negative already run for the same slot as `0x4122`'s `unknown_3a`.]

          Swept range: all of `.text`, `0x10230`..`0xDE9328`, every D-form/DS-form load and store at
          displacements **7660-7663** off any base. **Two hits, both accounted for:** `0x412D88`
          (the engine-struct init whose siblings do `lfs`/`stfs` — a float struct, rejected on
          provenance) and `0xD3EEB8`, this parser.

          The re-base path matters here more than anywhere else in the packet, because the
          appearance struct really is passed around as a pointer, and it was swept: the seven
          `addi rX,rY,7648` sites are `0x8DF554`, `0x929280`, `0x93DF9C`, `0x93E9C8`, `0x9CB4E8`,
          `0x9D0F28`, `0x9D102C`. Four are 200-byte `memcpy`s (which move the slot without reading
          it); two feed `0xD3BB28`, the `0x4130` request builder, which serialises +2..+6,
          +16..+29, +30..+34, +35..+39, +60 and +68..+195 and **omits +12**. `0x4131`'s parser
          skips +12 as well, and the character-edit screen's copy at `screen+26660` has no load or
          store at 26672.

          The confirming observation would be a load at profile+7660, or at +12 off any provable
          copy of the struct. There is none. Control: the same sweep finds wire 541 / 563 / 575's
          readers (see `clan_join_time_high` for the addresses).

          Note the shape this leaves: `appearance_a` ends at +8 and `appearance_b` starts at +16,
          so +9..+11 and +13..+15 are not read by ANY parser. This u32 is the only thing in that
          seven-byte hole that is on the wire at all.
      - id: appearance_b
        type: u1
        repeat: expr
        repeat-expr: 14
        doc: |
          wire 364, T+0x1DF0..0x1DFD = **profile+7664..7677 = appearance struct +16..+29**.
          Fourteen separate u8 reads, `0xD3EED4`..`0xD3F04C`. Previously `unk_u8_block_b`
          (fp 71-84).

          [NAMED 2026-08-01.] **The gear run: head, chest, hands, waist, feet, accessory 1,
          accessory 2, then the seven matching colours in the same order.** Same fourteen bytes as
          `0x4122` `appearance_b` (ctx+30152..30165) and `0x4130` wire 0x05..0x12, where every one
          of the fourteen is individually CONFIRMED and named.

          Unlike `appearance_a`, **all fourteen are player-editable** — `0x4130` serialises the
          whole run from source +16..+29 and the change detector at `0x93E5B4` compares the whole
          run. Published to peers: `0x88407C` copies +16..+27 to `announce+16..+27` and +28/+29 to
          `announce+37/+38` (`0x8841E4`-`0x8842A0`).

          Per-item colour semantics — a colour bit is a per-ITEM slot, so the same colour is a
          different bit on a different item — are in GEAR.md and are not repeated here.
      - id: skills
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: |
          wire 378, T+0x1DFE..0x1E02 = **profile+7678..7682 = appearance struct +30..+34**.
          Five-iteration parser loop at `0xD3F05C` (`addi r4,r27,30`, bound `cmpdi cr6,r29,5`).
          Previously `unk_u8_block_c` (fp 91-95).

          [NAMED 2026-08-01.] **The five equipped-skill id slots.** Same array as `0x4122` `skills`
          (ctx+30166), `0x4130` `skills` (wire 0x13) and `0x4131` `skills` (wire 0x17). Slots 0..3
          are the four the UI shows; slot 4 is the fifth the loop bound proves exists and which
          every packet currently carries as zero — see `mgo2_cmd_4130_c2s.ksy` for why that is
          logged rather than assumed.

          **Tier-1 confirmation that this array is skill IDS and that the u32 array at +40 is
          keyed by them** [ELF 2026-08-01, new]: `0x281708(id, value)` takes a skill id in `r3`
          and, after a separate 128-entry table walk, does a **linear search of exactly these five
          bytes** — `lbz r0,7678(r10)` … `lbz r0,7682(r10)` at `0x281798`-`0x2817D8`, each
          `cmpw`'d against the id, setting an index 0..4 — and on a match stores its `r4` at
          `charBlock + 7680 + 4*index`, then `+8` (`stw r31,8(r11)` at `0x281818`), i.e. at
          **7688 + 4*index**. That is `skill_experience[index]` exactly. `r10`'s provenance is
          `bl 0xD3A094` at `0x281734`, so the base is the profile, not a look-alike struct. This
          pairs the two arrays by construction rather than by adjacency.

          Published to peers interleaved with `skill_levels` — see that field.
      - id: skill_levels
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: |
          wire 383, T+0x1E03..0x1E07 = **profile+7683..7687 = appearance struct +35..+39**.
          Five-iteration loop at `0xD3F08C`. Previously `unk_u8_block_d` (fp 96-100).

          [NAMED 2026-08-01.] **The five skill levels, index-paired with `skills` above.** Same
          array as `0x4122` `skill_levels` (ctx+30171), `0x4130` wire 0x18, `0x4131` wire 0x1c.

          **The pairing is visible in the wire format the client itself builds.** The
          join-announcement packer `0x88407C` runs a five-trip loop (`0x884184`-`0x8841A4`) that
          reads `skills[i]` and `skill_levels[i]` and writes them to `announce+39+2i` and
          `announce+40+2i` — an interleaved `{id, level}` array, 2-byte stride. A packer that
          interleaves two arrays is stating they are parallel.

          Level is otherwise derived, never authoritative: `min(experience >> 13, 3)` at
          `0x6FC580`.
      - id: skill_experience
        type: u4
        repeat: expr
        repeat-expr: 5
        doc: |
          wire 388, T+0x1E08..0x1E18 = **profile+7688..7707 = appearance struct +40..+59**.
          Five-iteration loop at `0xD3F0BC` through the u32 reader `0xD5CC64`.
          Previously `unk_u32_block` (fp 4011-4015).

          [NAMED 2026-08-01.] **Per-skill experience for the five equipped slots, in `skills`
          order.** Same array as `0x4122` `skill_experience` (ctx+30176) and `0x4131`
          `skill_experience` (wire 0x21). The client's own change detector sizes the region as a
          five-element u32 array (`lwz r0,40(r11)` with `r5` stepping by 4, `0x93E77C`).

          **The keying is proved, not inferred** — `0x281708` looks a skill id up in `skills` and
          writes the match's value at `7688 + 4*index`. See `skills` above for the full trace.

          **Legal maximum is 24576**, and the validator at `0x93E418` ZEROES a record above it
          rather than clamping. `mgo2_cmd_4131_s2c.ksy` records why the inherited `0x600000`
          constant was inert rather than correct, and that `0x4122` and `0x4131` must agree here
          because they write the same destination — this packet is now a **third** writer of that
          same destination, so all three must agree or the last to arrive wins.
      - id: echoed_appearance_60
        type: u1
        doc: |
          wire 408, T+0x1E1C = **profile+7708 = appearance struct +60**. Parser `0xD3F0F4`.
          Previously `unk_u8_c` (fp 44).

          [STATED NEGATIVE for a reader; fate CLOSED — 2026-08-01.] The same byte as `0x4122`
          `unknown_6a` and `0x4131` `unknown_35`, by struct-offset bijection. **Meaning still
          unestablished; what is established is that nothing on the client ever chooses it.**

          It is server-authored, stored, and handed straight back: the `0x4130` request builder
          reads it (`0xD3BD88 addi r4,r31,60` -> `bl 0xD5C8A0`, `r31`'s provenance
          `0x9CB4D8 bl 0xD3A094; 0x9CB4E8 addi r4,r3,7648`) and `0x4131`'s parser reads it back
          in. **The client's own change detector excludes it** — `0x93E5B4`-`0x93E720` enumerates
          every editable field, including both five-slot arrays, and never touches +60. A byte the
          editor's own equality test excludes is a byte the editor does not own.

          Swept range: all of `.text`, `0x10230`..`0xDE9328`, displacement **7708** off any base.
          Six hits, all rejected: `0x412DC0` (the engine-struct init) and
          `0x559D0`/`0x55A04`/`0x56144`/`0x56450`/`0x56750`. **The `0x55xxx` cluster is worth
          naming as a trap** — it looks like a match and is not. Its base is
          `*(r30 - 32768) + 0x10000` (`r30` from TOC-32484), it writes a literal `1` into
          displacement 7716 (which in the profile is the 128-byte `comment`), and at `0x55A24` it
          reads 7712 with **`lfs`** — a float. It is a different struct with colliding
          displacements, and it accounts for near-misses on several fields in this packet.

          Consequence, unchanged from `0x4122`: whatever we send here must equal what `0x4122`
          sent, or the value is lost on the first appearance change.
      - id: chara_id_copy
        type: u4
        doc: |
          wire 409, T+0x1E20 = **profile+7712 = appearance struct +64**. Parser `0xD3F110`
          through the u32 reader `0xD5CC64`. Previously `unk_u32_d` (fp 4016).

          [NAMED 2026-08-01 — and its readers found, which is new.] The slot is `0x4122`
          `chara_id` (wire 0x6b -> ctx+30200; 30200 - 22488 = 7712), where PROTOCOL.md recorded
          only *"the original sends the character id here; its purpose is not documented"*.
          `0x4131` deliberately omits it, which is why its 200-byte memcpy-in/memcpy-out pair
          preserves rather than overwrites this slot.

          **Its purpose is now partly documented: the Personal Stats screen renders it as a
          number.** Two sites, both with the base from `0xD3A0AC` cached at `screen+128`, i.e.
          reading `T` — the block THIS packet writes:

            * `0x916010` and `0x916090`: `lwz r3,7712(r27)` -> `bl 0x942564` -> `bl 0x943B00(...,
              0x56F2FE, value, 0)`. `0x942564` is `min(x, 9999999)` — a **seven-digit clamp**
              (`0x98967E`/`0x98967F` at `0x942564`/`0x942578`), so the field is displayed as a
              decimal number, not as a handle. It is rendered immediately after the level, which
              the same code derives from `experience` (profile+288) through `0x6F9260` and sends
              to the neighbouring widget `0x56F2FC`.
            * `0x8D8358`: `lwa r5,7712(r9)` -> `sprintf` (`0xDD0688`) into a menu label, with the
              base from `bl 0xD3A094` at `0x8D833C`. The no-profile fallback substitutes string
              resource 18 via `0x8E0C24`.

          So a character's own id is shown to them on the stats screen and in one menu. The
          seven-digit clamp is the client's presentation choice and bounds nothing server-side.

          Kept as `chara_id_copy` rather than `chara_id`: the packet already has a `chara_id` at
          wire 4, and these are separate slots (+0 and +7712) that nothing forces to agree. If they
          are ever allowed to differ, the stats screen will show this one.
      - id: comment
        type: str
        size: 128
        doc: |
          wire 413, T+0x1E24. The 128-byte player comment. [CONFIRMED] — located by the v3
          fingerprint leak ({|}~ from misaligned u16s) and verified end-to-end in v5 with the
          real database comment.
      - id: equipped_title
        type: u1
        doc: |
          [CONFIRMED 2026-07-28] The title the character is wearing, **1-based** — 0 for none.
          Previously `unk_u8_d`, sent as the fingerprint 45, which is out of range for the
          22-title table.
          **This is not the only place the worn title goes.** 0x4103 writes its copy into a SCRATCH
          block (`*(ctx+0x11904)`), which the Personal Stats screen renders from and which is never
          published to peers. The in-game scorecard's animal-rank badge reads a different byte
          entirely — 0x4122 wire 0xef — which lands in the LOCAL character record at
          charBlock+0x1EA5 and is replicated over P2P as record slot+1 key 358.

          So both must carry the same value. Until 2026-07-28 this one was correct and 0x4122 sent
          `chara.rank` (dead, always 0), which is why the badge showed on the stats screen and
          nowhere else. See PROTOCOL.md's 0x4122 section.

      - id: dead_u8_block_32b8
        type: u1
        repeat: expr
        repeat-expr: 9
        doc: |
          wire 542, T+0x32B8..0x32C0 = **profile+12984..12992**. Nine separate u8 reads,
          `0xD3F168`..`0xD3F258` (`r28 = T+12984`, then +1..+8). Previously `unk_u8_block_e`
          (fp 101-109).

          [STATED NEGATIVE — no reader anywhere in the image. 2026-08-01.]

          Swept range: all of `.text`, `0x10230`..`0xDE9328`, every D-form/DS-form load and store at
          displacements **12984-12992** off any base. **Thirteen hits, and not one is a read of
          these bytes as these bytes:**
            * `0x414838`, `0x41483C`, `0x414848` — `stw` at 12984/12988/12992 inside the dense
              engine-struct init at `0x4148xx` (the same run that writes 12996..13028, 13032,
              13036, 13040..13052, 13072, 13080, 13096). It is a u32 array on a 4-byte grid;
              incompatible with nine independently addressed BYTES, and already rejected on that
              exact ground in `0x4101`'s `unknown_028`.
            * `0x452884` — `addis`, not a displacement.
            * `0xD3F168`..`0xD3F24C` — the nine `addi`s of this parser itself.

          Re-based-pointer path swept as well: the only `addi rX,rY,D` sites with `D` in
          12856..12992 are 12928 (`0x350928`, single site, no +40..+64 access off the register it
          defines) and 12944 (`0xC322C`). **`0xC322C` is rejected on provenance and is worth
          recording** — `0xC31FC`-`0xC3320` initialises an object with sub-objects at 4336, 4432,
          8640, 8736, 12944, 13040, 17248, 21552, 25856, 30160 on a ~4208-byte stride, storing
          self-pointers and the literal `0xFF000000`. The profile has no 4208-byte repeating
          substructure, and `0xC32F4 stw r11,13052(r29)` would put a self-pointer inside the
          16-byte `instructor_name` string. Different struct.

          Control that should succeed, and does: the identical sweep finds the readers for wire 541
          (+7845), wire 563 (+13008) and wire 575 (+13020). Addresses in `clan_join_time_high`.

          Position is exact and the block is nine bytes; the meaning is unestablished and there is
          nothing in the binary left to establish it from.
      - id: rating_block
        type: u4
        repeat: expr
        repeat-expr: 9
        doc: |
          wire 551, T+0x32C4..0x32E4. Nine u32s, **three of them identified 2026-07-28**:

          - **entry 3 (wire 563) — the TITLE unlock bitmask, 22 bits, LSB-first.** This is what
            made every character wear eight titles: the fingerprint 4024 set bits 3..11, which is
            exactly the "titles 3-11" OBSERVED recorded and attributed to the stats changing.
            **NEVER set bit 22 or above** — the client's popcount loop runs 23 iterations over a
            22-entry table and reads past the end.
          - **entry 5 (wire 571) — Host Rating star NUMERATOR.**
          - **entry 6 (wire 575) — Host Rating star DENOMINATOR**, the "/ N votes" on screen.

          The gauge is `clamp(ceil(2 * num / den), 0, 10)` half-stars (`0x94258C`), so the rating
          SUM over the vote COUNT renders the average. Both halves are fed from `host_review`,
          filled by `0x43c4` — before that command was identified nothing stored a host vote and
          this gauge could only read zero.

          Entries 0, 1, 2, 4, 7, 8 remain [UNKNOWN].

          **CORRECTION 2026-08-01 — the "entry 4 is read at `0x91b338`" line was an off-by-one and
          is withdrawn.** The block starts at T+0x32C4 = profile+12996, so entry *i* is at
          `12996 + 4i`: entry 3 = **13008**, entry 4 = 13012, entry 6 = 13020. `0x91B338` and
          `0x91D83C` both load displacement **13008**, which is entry 3 — the title mask — and what
          they do with it is exactly the 23-iteration popcount this entry already documents
          (`li r9,23; mtctr r9;` then `sraw`/`clrldi.`/increment, accumulating into `screen+204`).
          Their base comes from `bl 0xD3A0AC` (`0x91B300`), i.e. from **`T`**, the block this
          packet writes — so this is the one confirmed reader chain that reads *this* copy rather
          than the local record.

          That leaves **entry 4 (wire 567) with no reader at all.** Swept range: all of `.text`,
          `0x10230`..`0xDE9328`, displacement 13012 off any base — two hits, `0x414858` (the
          `0x4148xx` engine-struct init) and `0xD3F2D8` (this parser). The `li rX,13012` sites at
          `0xCB8260`/`0xCB827C` are **immediates, not displacements**: they sit in a run passing
          10082, 10083, 11033, 13016, 13020 to `0xB7E340`, an id list, not struct access. Same
          rejection applies to the `li` hits at 13008/13020/13024/13028/13032/13036/13044/13048
          scattered through `0xCB7000`-`0xCC0000`.
      - id: dead_u32_32e8
        type: u4
        doc: |
          wire 587, **T+0x32E8 = profile+13032**. Previously `unk_u32_session` (fp 4030).

          **CORRECTS THE DESTINATION.** This field previously read *"Stored to obj+0x30, not the
          character struct"*. That is wrong, and the error was reading the base register in
          isolation. The parser reads into stack scratch at `0xD3F364` and then stores
          `std r0,48(r28)` at `0xD3F390` — but `r28` is not the packet object; it was set at
          `0xD3F168`-`0xD3F170` to **`T + 12984`** (the base of the nine-byte block above).
          12984 + 48 = **13032**, squarely inside the character struct. So the offset is +0x32E8,
          and there is no separate "obj" destination.

          Two consequences the old note hid. First, the store is a **`std`** — eight bytes,
          13032..13039 — while the wire field is four, so the value is zero-extended into a u64
          slot and 13036..13039 always ends up zero. Second, the previous note implied this field
          was outside the profile and therefore off the table for a struct-offset argument; it is
          not, and it was swept accordingly.

          [STATED NEGATIVE — no reader. 2026-08-01.] Swept range: all of `.text`,
          `0x10230`..`0xDE9328`, every D-form/DS-form load and store at displacements
          **13032-13039** off any base. **Six hits, all rejected:** `0x414878`/`0x41487C` (the
          `0x4148xx` engine-struct init) and `0xCB7980`, `0xCB798C`, `0xCB9118`, `0xCB9124`, which
          are `li` immediates in the `0xB7E340` id lists described under `rating_block`, not
          struct accesses. The parser's own `std` is at `0xD3F390` and is a store.

          Re-base path: the only `addi` displacements in 12904..13039 are 12928 and 12944 (both
          rejected under `dead_u8_block_32b8`), 12984 (this parser's `r28`, whose only use at
          +40..+64 is this very store), and 12996..13028 (the nine `rating_block` `addi`s, all in
          this parser at `0xD3F268`-`0xD3F348`).

          Control that should succeed, and does: wire 541, 563 and 575's readers are found by the
          same sweep.

          The name `unk_u32_session` was itself a guess — nothing tied this slot to a session id.
          The tool note about `0xD32E08`'s 117-entry request-status table at `session[360 + 4*slot]`
          does not apply: this packet's slot arming happens at `0xD3F4BC`/`0xD3F4D0` with
          `li r4,22`, on the packet object `r25`, and has no relationship to profile+13032.
      - id: instructor_name
        type: str
        size: 16
        doc: "wire 591, T+0x32FC. [CONFIRMED] — rendered as \"Instructor:\" (showed FP-STR-B)."
      - id: stats_list_count
        type: u4
        doc: |
          wire 607, T+0x3310 = **profile+13072**. Parser `0xD3F3A4`. Previously `unk_u32_e`
          (fp 4031; the speculative "candidate for the v2 'generation' u32" is withdrawn — nothing
          supported it and the reader below contradicts it).

          [SHAPE ESTABLISHED, IDENTITY OPEN — 2026-08-01. It is a COUNT.]

          **It has exactly one reader, and that reader reads THIS packet's copy.** `0x917B00`:
          `lwz r9,128(r31)` — and `screen+128` is where the Personal Stats screen caches the
          pointer returned by `bl 0xD3A0AC`, i.e. `T` (the same caching seen at `0x91B300`
          `stw r3,128(r31)`). Then:

              0x917B04  lwz  r0,13072(r9)      ; the value
              0x917B08  cmpwi r0,0
              0x917B0C  beq  -> 0x917B58       ; zero arm
                        li r0,37 ; stw r0,196(r31) ; r23 = value - 1     (nonzero arm)
              0x917B58  li r0,36 ; stw r0,196(r31) ; r23 = 0             (zero arm)

          So **zero selects an "empty" screen state (36) and nonzero selects state 37 with
          `value - 1` as the highest index** — the classic count/last-index pair. The shared tail
          then decomposes `r23` as `r18 = r23 / 10` and `r19 = r23 % 10` (`0x917B98`-`0x917BA4`),
          which is a **10-per-row grid coordinate**, and `r16 = r19 - 1`.

          The enclosing function `0x917A30`-`0x918B84` is the Personal Stats page builder: it is
          the same function that reads the Instructor Score pair at 13040/13044 (`0x918450`,
          `0x91844C`) and the Host Rating pair at 13016/13020 (`0x918590`, `0x91858C`).

          **Open question, stated as one:** which list this counts. The candidates in the
          neighbourhood — titles, medals, awards history — are all fed by bitfields elsewhere in
          this packet rather than by a count, so it is probably none of them, and no disc string
          was resolvable at the reader's call site to settle it. What is safe to act on: it is a
          count, `count - 1` must be a valid index, and a value larger than the list the client can
          build is the failure mode to watch for. **We should keep sending zero** until the list is
          identified; zero is the state the client explicitly handles.
      - id: beta_award_bits
        type: u4
        doc: |
          [CONFIRMED 2026-07-28] Award bits outside the main bitfield; **bit 0 is the "Beta test
          participant" award**. Previously `unk_u32_f`. Higher bits unexamined.
      - id: medal_bitfield
        type: str
        size: 16
        doc: |
          [CONFIRMED 2026-07-28] **The medal bitfield — 16 bytes, and the ONLY thing that decides
          which awards the player has.** Not a string; the ksy called it `unk_str_c` and this
          server sent the literal text "FP-STR-C" into it for weeks.

          The gate at `0x916E20` reads a medal row's id, tests the matching bit through
          `0xD5C2A8`, and skips the row when it is clear. **No stat is loaded anywhere in
          `0x916E20`..`0x916FD0`** — which is what proves medals are server-driven. The
          `threshold` word in the 39-row table at `0xE139C0` is loaded *after* the gate and
          sprintf'd into the description as its `%d`, so "500 Mk.II destructions" is display text,
          not a condition the player met.

          Layout is **medal-id-keyed, not row-indexed**: a hand-written switch with a byte and bit
          per id, LSB-first. Bits 3 and 7 of each byte and bytes 13-15 are unused.

          How it was caught: a live character showed "500 Mk.II destructions" against zero Mk.II
          kills, and kept the award after every stat was zeroed. "FP-STR-C" byte 4 is 'T' = 0x54,
          bit 6 set = medal id 65 = that award. The whole string lit 17 medals.
      - id: clan_emblem_flag
        type: u1
        doc: |
          wire 631, T+0x1AD8 = **profile+6872**. Parser `0xD3F3FC` — note the base is `r24`, set at
          `0xD3EBF8` to `T + 6816` (the clan record), so the parser writes it as **clan record
          +56**, not as a standalone byte. Previously `unk_u8_e` (fp 46).

          [NAMED 2026-08-01, by struct-offset bijection with `0x4122` `emblem_flag` (wire 0xf0 ->
          ctx+29360; 29360 - 22488 = 6872) — and independently corroborated by its readers, which
          is what makes this more than a transcription.]

          **`0x4122`'s entry says only "3 when the clan has an emblem". The readers agree exactly,
          and 3 is the only value any of them tests:**

            * `0x8F9950` — the clan-menu gate. Full condition:
              `clan_id != 0 && (clan_state - 1) <=u 1 && (clan_privileges[0] & 1 || emblem == 3)`.
              So this byte is an **alternative to clan privilege bit 0** for reaching that arm.
            * `0x905A90` — `(clan_state - 1) <=u 1 && emblem == 3` before calling
              `0xD56704(clan_id)`.
            * `0x905B68` — copies it to `0x883F20()+636` alongside `clan_id` -> `+640`
              (`0x905B58`/`0x905B5C`); `0x905A68` then re-tests that cached copy against 3.
            * `0x88415C` — the join-announcement packer copies it to `announce+4`, so it is
              published to peers.

          Four more sites reach it through the clan-record pointer rather than by displacement, and
          they are the emblem-apply path: `0xAB5C04`, `0xAB98FC`, `0xAD40C0`, `0xAD4724`, each
          `stb r?,56(rP)` where `rP = addi rX,rY,6816`. `0xAD40C0` sits beside the emblem commit
          gate at `0xAD409C` that `clan_privilege_block` already documents.

          **Bits: none — it is compared for equality against 3, never masked.** Values 0/1/2 all
          take the same "no emblem" path. No overrun hazard: the preceding wire field is
          `medal_bitfield`, a fixed 16-byte block written by the sized reader `0xD5D018` with
          `li r5,16`, which cannot run long.
      - id: instructor_score_numerator
        type: u4
        doc: |
          [CONFIRMED 2026-07-28] The **Instructor Score star numerator**, paired with the
          denominator that follows. The client draws
          `clamp(ceil(2 * numerator / denominator), 0, 10)` half-stars (`0x94258C`, 11-entry icon
          table), so sending the rating SUM over the vote COUNT puts the true average on the gauge.
          Previously `unk_u32_g`.
      - id: instructor_score_denominator
        type: u4
        doc: "wire 636, T+0x32F4. [CONFIRMED] (fp 4034 rendered as \"1 star / 4034\"); numerator not located."
      - id: saved_instructor
        type: u4
        doc: |
          wire 640, T+0x32F8 = **profile+13048**. Parser `0xD3F450`. Previously `unk_u32_h`
          (fp 4035).

          [NAMED 2026-08-01, by struct-offset bijection with `0x4122` `saved_instructor`
          (`0xD3D624`, `addi r4,r25,13048`, `r25 = ctx+22488`) — CONFIRMED there 2026-07-26/27.]

          **The character's saved instructor, as a character id in our id namespace; 0 = none.**
          The route is already fully traced under `0x4122` and `0x43c9` and is not repeated: stored
          verbatim, copied into the join announcement by `0x8842AC` (`lwz r0,13048(r11)` ->
          `stw r0,12(r31)`), broadcast as P2P message 36, and nonzero suppresses the "Save current
          instructor, %s, as the instructor for your personal data?" prompt at `0xA359A4`.

          **This packet is a THIRD writer of profile+0x32F8, which `mgo2_cmd_43c9_s2c.ksy` does not
          list.** That schema states the slot "has exactly three accesses in the whole binary" and
          enumerates `0xD3D624` (0x4122), `0xD3FF6C` (0x43c9) and `0x8842AC` (the reader). The
          sweep run here finds a fourth: `0xD3F450`, this parser. The two guarded/unguarded
          asymmetry it records still holds and now has a third case —
          `0x4122` stores unguarded, `0x43c9` stores only when nonzero
          (`0xD3FF64: cmpwi r0,0; beq`), and **this packet stores unguarded**, like `0x4122`.

          Practical consequence: `0x4103` can silently clear a saved instructor that `0x43c9` just
          set, because it writes whatever we send with no zero check. The three must agree.
      - id: grade_points
        type: u4
        doc: |
          wire 644, T+0x124 = **profile+292**. Parser `0xD3F46C` — the last read in the packet, and
          the only tail field that lands back in the low part of the struct rather than in the
          0x1Axx/0x1Exx/0x32xx regions. Previously `unk_u32_i` (fp 4036).

          [NAMED 2026-08-01, by struct-offset bijection with `0x4101` `grade_points` (`0xD3C374`,
          `addi r4,r27,292`) — CONFIRMED there 2026-07-30, and the same slot `0x4129` patches after
          each round.]

          The reader evidence lives in `0x4101`'s entry and is summarised only: `0x905E00` and
          `0x915F64` both run `profile+292` through the level-from-experience walker `0x6F9260`,
          clamp to 1..23, index a 24-entry table and render `"%s (%d)"`. So it is a **second
          experience-scale quantity, distinct from Level**, and it is rendered on the very screen
          this packet feeds — `0x915F64` is nineteen instructions before `0x915FE4`, where the same
          function derives Level from `experience` (profile+288) for the adjacent widget.

          That co-location is the useful part for this packet: wire 0x1c (`experience`), wire 644
          (this) and wire 409 (`chara_id_copy`) are the three numbers the Personal Stats header
          renders, and they arrive at three widely separated wire offsets.

          `0x4101` notes an inconsistency worth fixing rather than a protocol fact: it sends zero
          here while `0x4129` mirrors `experience` into the same slot. This packet is a third
          writer of profile+292 and inherits the same requirement to agree.
