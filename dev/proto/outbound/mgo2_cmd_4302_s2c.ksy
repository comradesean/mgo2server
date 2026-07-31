meta:
  id: mgo2_cmd_4302_s2c
  title: "MGO2 0x4302 — server -> client: game-list entries (reply 2/3 to 0x4300)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4302` at `0xD3881C` -> stub `0xD391B0` ->
  parser **`0xD43D48`**. Read primitives: `0xD5CCD8` u32, `0xD5CB8C` u8, `0xD5CC14` u16,
  `0xD5D018` raw block, `0xD5CEB0` remaining-bytes test.

  **The entry is 55 (`0x37`) bytes and the packet carries as many as fit.** The parser loops:
  zero a 60-byte scratch struct, ask `0xD5CEB0` whether the read cursor has reached the
  payload length (`-1` = done, exit clean), read one entry, append it, repeat. So the record
  count is **size-driven — there is no count field**, and the entry stride in the client's
  array is 60 bytes even though the wire record is 55.

  **Correction to PROTOCOL.md:** it says "up to 18 entries". That is a server-side policy
  number, not the client's limit — the parser's own cap is `count > 999 -> -71`, so the array
  holds **1000** entries. (The transport still caps a payload at `0x400` bytes, which is 18
  entries plus change, so 18 per packet is the real per-frame ceiling; the client will accept
  more packets into the same open transfer.)

  **Correction to PROTOCOL.md's tail:** it lists `0x34` as "2 bytes zero" and `0x36` as a u8
  "always `0x63`". The parser reads a **u8 at `0x34`** and then a **u16 at `0x35`** — so the
  famous `0x63` is the low byte of a halfword whose value is `0x0063` (99). Same 55 bytes,
  different field boundaries.

  Appended at `G+8 + count*60` (first 32 bytes) and `G+40 + count*60` (next 28), with
  `count` at `G+4`; `G` is the game-list object shared with `0x4301`/`0x4303`.
  `T+0x..` below is the offset inside that 60-byte client struct.

  Field *meanings* are PROTOCOL.md's, live-derived from the browser; the widths and order
  are the parser's.

  **A second, independent writer of this record exists inside the client, and it is the best
  evidence in this file** [ELF 2026-07-30]. `0xD493CC` fabricates a one-entry game list for the
  game *you* are hosting, without any packet: it allocates the same 968-byte game-details object
  the `0x4313` parser fills, memcpys the 204-byte host-settings block into `obj+752`
  (`0xD49454`-`0xD49480`), then assembles a 60-byte entry at `r1+112` and `lswi`/`stswi`s it into
  the list at `G+8+count*60` / `G+40+count*60` (`0xD4957C`-`0xD4958C`). Because `r1+112` is
  T+0x00, every store in `0xD494C8`-`0xD49558` names a field by its source:

  | entry | source | meaning |
  | --- | --- | --- |
  | T+0x00 | `obj+0` | game id |
  | T+0x04 | `obj+4`, 16 bytes | name |
  | T+0x15 | `obj+150` | password-set flag (`0x4310` `src+150`) |
  | T+0x16 | `obj+167` | dedicated (`0x4310` `src+167`) |
  | T+0x18 | `obj+168` | lobby subtype |
  | T+0x19 / 0x1a / 0x1b | `obj+752` / `+768` / `+784` | rotation round 0 rule / map / flags |
  | T+0x1c | `obj+818` | max players |
  | T+0x1d..0x1e | `obj+929`, 2 bytes | commonA / commonB |
  | T+0x1f | `obj+819` | current player count |
  | T+0x20 | `obj+936` | host ping (`0x4313` settings block +184) |
  | T+0x24 | `obj+846` | host stance |
  | T+0x26 | `obj+847` | level-limit tolerance |
  | T+0x28 | `obj+848` | level-limit base |

  Nothing writes T+0x38 or T+0x3a on this path — they stay zero from the `0xD494C0` memset.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x4302 entry — 55 (0x37) bytes"
seq:
  - id: entries
    type: game_entry
    repeat: eos
    doc: |
      [ELF 0xD43D48] Size-driven, **no leading count**. This project has been bitten by
      count-vs-size before (`dev/proto/README.md`: sending a count in a list-start packet
      produced `1032:00000005`), so it is worth restating: the count here is maintained by
      the client, incremented per record, and capped at 999.
types:
  game_entry:
    doc: "55 bytes on the wire, 60 in the client's array."
    seq:
      - id: game_id
        type: u4
        doc: "[CONFIRMED] wire 0x00 -> T+0x00. Game id. [ELF 0xD43DFC]"
      - id: name
        size: 16
        doc: "[CONFIRMED] wire 0x04 -> T+0x04. Game name, ISO-8859-1, NUL-padded. Raw 16-byte read (0xD5D018), not length-prefixed."
      - id: host_options
        type: u1
        doc: |
          [CONFIRMED] wire 0x14. Read into a temporary and **expanded bit by bit** into three
          separate client bytes: bit 0 -> T+0x15, bit 1 -> T+0x16, bit 2 -> T+0x17. PROTOCOL.md
          names bit 0 = password set and bit 1 = dedicated; **bit 2 is also expanded and its
          meaning is [UNKNOWN]** — the parser stores it exactly like the other two, so it is a
          real flag the browser can read, not padding.
      - id: lobby_subtype
        type: u1
        doc: |
          [ELF, RESOLVED 2026-07-30] wire 0x15 -> T+0x18. **The lobby subtype**, previously
          `unknown_15` ("PROTOCOL.md: always 0x08; nothing is known about what reads it").

          Evidence is the client's own writer, not this parser. `0xD493CC` fabricates a game-list
          entry for the game *you* are hosting, from the 968-byte game-details object the `0x4313`
          parser fills (it memsets 968 at `0xD49440` and drops a 204-byte settings block at
          `obj+752`, exactly as `0xD4364C` does). Inside it:

          ```
          0xD49470  lbz r0,608(r29)     ; current lobby subtype out of the lobby context
          0xD4947C  stb r0,168(r31)     ; -> details object +168
          0xD49500  lbz r0,168(r31)
          0xD4950C  stb r0,136(r1)      ; -> scratch entry +24 = T+0x18
          0xD49588  lswi/stswi 28       ; scratch -> list element +32
          ```

          The scratch buffer is the 60-byte list element (`r1+112` = T+0x00: `0xD494DC` stores the
          game id there, `0xD494D8` the 16-byte name at T+0x04), so `r1+136` is T+0x18 exactly.
          Details-object `+168` is the same slot the `0x4313` parser writes from its wire `0x09a`
          (`0xD44518`), which that spec already calls `lobby_subtype`, and the same `src+168` the
          `0x4310` request builder sends at its wire `0x0a2`.

          PROTOCOL.md's "always 0x08" is consistent: 8 is Combat Training (LOBBIES.md §"Lobby
          subtypes"). It is **not** a constant — it must track the lobby the game is filed under.
      - id: rule
        type: u1
        doc: "[CONFIRMED] wire 0x16 -> T+0x19. Match rule."
      - id: map
        type: u1
        doc: "[CONFIRMED] wire 0x17 -> T+0x1a."
      - id: round_flags
        type: u1
        doc: |
          [ELF, RESOLVED 2026-07-30] wire 0x18 -> T+0x1b. **The rotation round-0 `flags` byte** —
          GATES.md §2's per-round three-way radio (`0` Normal, `2` Drebin Points, `4` Headshots
          Only). Previously `unknown_18` ("PROTOCOL.md: zero, purpose unknown").

          Same writer as `lobby_subtype` above, and the three rotation bytes go out together, which
          is what makes the identification airtight — round 0's rule, map and flags land in three
          consecutive entry bytes:

          ```
          0xD49510  lbz r0,752(r31) / stb r0,137(r1)   ; rotation rule[0]  -> T+0x19 (`rule`)
          0xD49518  lbz r0,768(r31) / stb r0,138(r1)   ; rotation map[0]   -> T+0x1a (`map`)
          0xD49520  lbz r0,784(r31) / stb r0,139(r1)   ; rotation flags[0] -> T+0x1b (THIS)
          ```

          `+752/+768/+784` are the three parallel 16-byte rotation arrays (`0xD4364C` scatter loop,
          `0x4310` builder source arrays). So this byte is the browser's copy of round 1's flags.

          **PROTOCOL.md's "zero" is a fact about the corpus, not the field.** GATES.md §2 records
          that every archived round carried `flags = 0`; a Headshots-Only or Drebin-Points first
          round would put 4 or 2 here. Whether the browser renders it is not established — this
          spec proves the transport, not the presentation.
      - id: max_players
        type: u1
        doc: "[CONFIRMED] wire 0x19 -> T+0x1c."
      - id: stance
        type: u1
        doc: |
          [CONFIRMED] wire 0x1a -> **T+0x24**. Note the out-of-order destination: the parser
          reads this byte here but stores it past the two toggle bytes and the player count.
          Wire order is what matters for a server; the struct offset is recorded because it is
          the only reason the read sequence looks shuffled.
      - id: common_toggles
        size: 2
        doc: |
          [CONFIRMED] wire 0x1b..0x1c -> T+0x1d..0x1e. **Read as one 2-byte raw block**
          (`0xD5D018` size 2), not as two u8s — commonA then commonB. Bit maps in PROTOCOL.md:
          commonA bit 0 idle kick, bit 2 always set (unknown), bit 3 friendly fire, bit 4
          ghosts, bit 5 auto-aim, bit 7 uniques; commonB bit 0 team switch, bit 1 auto-assign,
          bit 2 silent mode, bit 3 enemy nametags, bit 4 level limit, bit 6 voice chat,
          bit 7 team-kill kick. Capture-proven for the 0x4310 push (OBSERVED.md, "Where the
          Common Settings toggles live"); the same bitfields are replayed here.
      - id: player_count
        type: u1
        doc: "[CONFIRMED] wire 0x1d -> T+0x1f. Current player count."
      - id: ping
        type: u4
        doc: |
          [CONFIRMED] wire 0x1e -> T+0x20. Host ping, fed from the 0x4398 report.

          [ELF 2026-07-30] Independently corroborated twice. The picker at `0x934574`-`0x934598`
          buckets it as `>80 / >20 / else` — millisecond thresholds, and *lower is preferred* in the
          comparison at `0x9346CC`. And on the client's own hosting path `0xD49548` fills this slot
          from game-details `obj+936`, i.e. the `0x4313` settings block's `+184`, which is why that
          field is now named `host_ping` there.
      - id: friend_block_flags
        type: u1
        doc: |
          [ELF] wire 0x22 -> T+0x25. PROTOCOL.md: bit 0 contains a friend, bit 1 contains a blocked
          player — always 0 from this server, neither list is modelled, so the bit names are
          unverified against the browser.

          [ELF 2026-07-30] The picker at `0x934024` reads it into `r23` (`0x934584`) and tests
          **both** bits, in a revealing order: bit 1 first, at the very top of the preference
          cascade (`0x9346A8`-`0x9346C8`), then bit 0 last, after the star rating
          (`0x93471C`-`0x934738`). Both are "prefer set over clear" comparisons against the
          incumbent's stored copy at `screen+136`. That a picker ranks bit 1 above ping, free slots
          and rating fits "contains a friend" far better than "contains a blocked player" — so the
          two bit names may well be **swapped** relative to PROTOCOL.md. Not asserted: the ELF
          shows the ranking, not the labels.
      - id: level_limit_tolerance
        type: u1
        doc: "[CONFIRMED] wire 0x23 -> T+0x26."
      - id: level_limit_base
        type: u4
        doc: "[CONFIRMED] wire 0x24 -> T+0x28. Capture-proven as a u32 in the 0x4310 push (at push offset 0xF8); an earlier u16-at-0x142 reading was a bug (OBSERVED.md)."
      - id: average_experience
        type: u4
        doc: "[CONFIRMED] wire 0x28 -> T+0x2c. Average experience across current players."
      - id: host_score
        type: u4
        doc: |
          [CONFIRMED] wire 0x2c -> T+0x30. The host's star NUMERATOR — the SUM of ratings, paired
          with `host_votes` as the denominator; the client draws
          `clamp(ceil(2 * numerator / denominator), 0, 10)` half-stars, so the ratio is the average.
          Derived from `host_review` at query time since 2026-07-29; the `game.host_score` column
          it used to read is dead and always zero.
      - id: host_votes
        type: u4
        doc: "[CONFIRMED] wire 0x30 -> T+0x34."
      - id: selector_flags
        type: u1
        doc: |
          [ELF, PARTIAL 2026-07-30] wire 0x34 -> T+0x38. A flags byte; **bit 1 disqualifies the
          entry** from the client's automatic game-picker. Previously `unknown_34`.

          The picker is the game-list scan task at `0x934024` (entry OPD `0x101C7A8`; no `bl` to
          it, it is a task/vtable entry). It walks the `0x4302` list, holding the current candidate
          in `screen+156`, and the very first test on the entry itself is:

          ```
          934568  lbz     r0,56(r9)        ; entry T+0x38 = THIS byte
          93456c  rldicl. r11,r0,63,63     ; extract bit 1
          934570  bne     0x93477c         ; -> skip this entry entirely
          ```

          That `r9` is a `0x4302` entry is proved by the fields around it, which match this spec
          slot for slot: `28(r9)`/`31(r9)` are max_players and player_count and are subtracted at
          `0x9345D0` to get free slots; `32(r9)` is `ping` and is bucketed against 20 and 80 at
          `0x934580`-`0x934590`; `48(r9)`/`52(r9)` are host_score/host_votes and are passed to the
          star helper `0x94258C`; `37/38/40` are friend_block_flags / tolerance / base.

          **Only bit 1 is established.** No other bit of this byte is tested anywhere. This is
          **not** the automatch screen — that is `0x93B4D0`-`0x93E000` and is server-matched
          (AUTOMATCH.md); this is a client-side "best entry" scan.
      - id: selector_tiebreak
        type: u2
        doc: |
          [ELF, RESOLVED 2026-07-30] wire 0x35 -> T+0x3a. **A u16 ranking key, lower wins**, and
          the last tie-break in the same `0x934024` picker. Previously `unknown_35`.

          ```
          9345fc  lhz    r24,58(r9)        ; entry T+0x3a = THIS halfword
          ...
          93474c  clrlwi r0,r24,16
          934750  lhz    r9,152(r31)       ; the incumbent best's stored copy
          934754  cmplw  cr7,r0,r9
          934758  bge    cr7,0x93477c      ; not strictly lower -> keep the incumbent
          934778  sth    r24,152(r31)      ; strictly lower -> this entry becomes the best
          ```

          It is consulted only after friend/block flags, the ping bucket, the free-slot bucket, the
          star rating and a nonzero `rule` have all tied (`0x9346A8`-`0x934748`), so it is the final
          discriminator.

          Confirms the width correction this file already made: it is a **u16**, not the u8
          PROTOCOL.md places at 0x36. PROTOCOL.md's "always 0x63" makes the halfword `0x0063` = 99,
          a constant that can therefore never discriminate between two games as served today. The
          resemblance to the `0x4902` entry size is coincidence.
