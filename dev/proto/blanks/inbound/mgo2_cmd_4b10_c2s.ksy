meta:
  id: mgo2_cmd_4b10_c2s
  title: "MGO2 0x4b10 — clan list page request (client -> server)"
  endian: be
doc: |
  **The clan list, paged.** 6-byte payload: u8 `kind`, s32 `start_index`, u8 — in that
  order. The reply is the triple `0x4b11` header / `0x4b12` entries (48 bytes each,
  size-driven, no count) / `0x4b13` end.

  ## Correction: this is paging, not a "value adjust"

  [CONFIRMED 2026-07-27] This file previously read the command as "a clan/GHQ points or
  funds adjust — deposit / withdraw / query", on the strength of the ±100 arithmetic and the
  signed serializer. It is **paging**, and the ±100 is the page step: the client's own list
  array holds exactly 100 entries (`cmpwi r4,99` at 0xD561E4), so 100 is the page size and
  the arms step one page back and one page forward. The observation that settled it: after
  being shown a list containing a single clan, the client asked for **101** — which is
  "start at the 101st clan", not "add 100 to a balance".

  So `amount` is a **1-based ENTRY INDEX, not a page number**. Nothing in the request is a
  page count, and nothing anywhere is a record count.

  ## The client pages optimistically — the server must clamp

  It asks for the next 100 without knowing whether they exist. Honouring "start at 101" when
  there is one clan produces a self-contradictory answer ("0 clans, starting at 101, out of
  a total of 1"), which the screen renders as "2 out of 1" and then corrupts the list on the
  next scroll. Clamping the requested index to the last populated page makes paging past the
  end a no-op. The clamp is **server policy forced by client behaviour**, not a wire rule.

  Reply-side note recorded here because it is the same bug: `0x4b11`'s two words after the
  result are `{offset, total}` IN THAT ORDER, and the client renders its "%d/%d" indicator
  (`0xE11518`, drawn at `0xAC11A4` and `0xAC2958`) as
  `left = A <= 0 ? 1 : (A - 1) / 100 + 2` over `right = (B - 1) / 100 + 1`. The record count
  never enters that text at all.

  Evidence (ELF, retail BLUS30109): sender 0xD58164. Builder `bl 0xD5CF40` at 0xD582AC
  (`li r4,0x4b10` at 0xD582A8), then
  `bl 0xD5C86C` at 0xD582BC (u8 from stack 1480),
  `bl 0xD5C95C` at 0xD582CC (**signed** u32 serializer — the `sraw` variant, distinct from
  the unsigned 0xD5C9BC every other 0x4Bxx sender uses — from stack 1328), and
  `bl 0xD5C86C` at 0xD582DC (u8 from stack 1488),
  then the seal `bl 0xD5C828` at 0xD582E8 and the flush `bl 0xD34CC0` at 0xD582F8.
  On success the flow state advances via `0xD32E08(session, 100, 1)`.

  The sender is (session, u8 kind, u8 arg2). `kind` is spilled to 1480, `arg2` to 1488, and
  the s32 is *computed*, not passed: `kind` must be <= 4 (else -24) and indexes a jump table
  at 0xD58238 whose arms read a u32 at offset +0x08 of a global clan block
  (`[global+0x2_2868]+8`, resolved at 0xD58204) — that u32 being the client's current list
  cursor:

  | kind | s32 written | reading |
  | --- | --- | --- |
  | 0 | 0 | first page; the stack slot was zeroed at 0xD581B8 |
  | 1 | cursor - 100 | page back, and if the result is negative the client **rewrites kind to 3** (0xD5826C) |
  | 2 | cursor + 100 | page forward |
  | 3 | 0 | first page — the "stepped back past the start" arm |
  | 4 | cursor | absolute; the index is used verbatim |

  Never mind the arm: the server can treat `amount` uniformly as the requested 1-based start
  index, because the client has already done the arithmetic.
seq:
  - id: kind
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] Which paging arm the client chose — 1 back a page, 2 forward a
      page, 4 absolute, 0 and 3 both meaning "the first page". Position and width exact
      (0xD5C86C, 1 byte); range 0..4, enforced at 0xD58218, and rewritten from 1 to 3 by the
      client when stepping back would go negative.

      A server that clamps `amount` does not need to branch on this at all — it is recorded
      because it is the only evidence for the page size and because a kind outside 0..4 would
      mean the packet did not come from this client.
  - id: amount
    type: s4
    doc: |
      [CONFIRMED 2026-07-27] The **1-based index of the first entry wanted**, not a page
      number: after being shown one entry the client asked for 101. Signed 4 bytes (0xD5C95C,
      the `sraw` serializer — the sign is real evidence, not an assumption, and the kind-1
      arm can produce a negative, which is exactly the case the client rewrites to kind 3).

      Derived client-side from the list cursor at `[clan_block+0x08]` as tabulated above;
      never a caller argument. Values past the end of the list are normal and expected — see
      the clamping note in the top-level doc.
  - id: unknown_0005
    type: u1
    doc: |
      [UNKNOWN] Position and width exact (0xD5C86C). The sender's second u8 parameter, passed
      through with no validation and untouched by the jump table, so nothing in the sender
      narrows it. The list renders correctly while the server ignores this byte entirely,
      which is evidence that it is not load-bearing for the list contents and no evidence at
      all about what it means. A sort order or a filter selector would both look like this.
