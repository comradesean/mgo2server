meta:
  id: mgo2_cmd_4908_c2s
  title: "MGO2 0x4908 — request the event/official-match detail record by one-byte selector (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender `0xD47D2C`, builder call `0xD47DA0`, request-status slot `0x3A` (58) completed with
  state 1 at `0xD47DEC`.

  **Paired reply: `0x4909`** — slot bijection, as for `0x4904`: the only `slot 58 = 1` site is
  this sender and the only `slot 58 = 2` site is `0xD48B44`, inside the parser at `0xD48674`
  whose id check is `cmpwi r0,0x4909` at `0xD486C4`.

  **`0x4908` is the one-byte sibling of `0x4904`.** Both fill the *same* destination: the
  912-byte record at `session+0xD598` (`addi r0,r28,-10856` at `0xD48218` for `0x4905`, at
  `0xD4873C` for `0x4909`). So this request selects the same kind of record with a small
  selector instead of a 32-bit id. Note the asymmetry with `0x4904`: `0x4908` does **not** cache
  its argument anywhere, and the `0x4909` parser has no echo check, so the server has no
  identity constraint to satisfy here.

  **No preconditions.** Between the session-validity checks (`0xD38504` / `0xD3844C`, failure
  `-24` / `-36`) and the builder call there is nothing: no team-membership gate, no leader gate,
  and **no range check on the byte** (contrast `0x4940`, which rejects > 7 with `-24`).

  **DEAD SENDER — no caller in the image.** [ELF — VALIDATED SWEEP, 2026-08-01]
  Method: every instruction in the whole text section `0x10230`–`0xDE9328` was decoded and every
  branch to `0xD47D2C` collected, accepting **`bl`, `b`, `bc` and `bcl`** (opcodes 18 and 16,
  both `AA=0` and `AA=1`) — not `bl` only. Zero hits. The same pass over the same range found
  the real callers of the other five live senders in this batch (`0x902274` → `0x4904`,
  `0x8C9A54` → `0x4912`, `0x89386C` and `0x8F9E4C` → `0x491B`, `0x8C20D4` → `0x4923`,
  `0x8C22AC` → `0x4940`), so the sweep is validated against controls that should succeed.
  Indirect calls were checked too: the whole file was searched for the sender's **OPD descriptor
  address** `0x1029928` as both a u32 and a u64 — zero hits. That last check is weak on its own
  (all seven descriptors in this batch have zero data references, including the five that are
  demonstrably called), so the branch sweep is the load-bearing evidence.

  Consequence: `0x4908` cannot be produced by ordinary play in this build. It is a library entry
  point the game does not use.

  Total payload: 1 byte.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26, extended
  2026-08-01. Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a
  1024-byte payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at
  `pkt+0x00`; the enclosing function then appends fields with the serialisation primitives;
  `0xD5C828` finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends.
  Everything between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
doc-ref: dev/docs/PACKETS_NOT_OBSERVED.md
seq:
  - id: detail_selector
    type: u1
    doc: |
      [ELF — POSITION AND SOURCE CERTAIN; SEMANTICS UNKNOWN] `0xD5C8A0` at `0xD47DB0`, source =
      the sender's r4 argument, spilled with `stb` at `0xD47D58` (so it is byte-sized at the API
      boundary, not a truncated word).

      Named for what it does — it is the only field, and the reply it fetches is the same
      912-byte detail record `0x4904` fetches — but **its domain is [UNKNOWN] and unconstrained**:
      the sender range-checks nothing, and with no caller in the image (see above) there is no
      site that shows a value. Whether it is an ordinal, a list index or a category is not
      readable from this side.
