meta:
  id: mgo2_cmd_4344_c2s
  title: "MGO2 0x4344 — peer register (client -> server)"
  endian: be
doc: |
  Builder function `0xD42FA8`; `bl 0xD5CF40` at `0xD43058` (`li r4,0x4344` at `0xD43050`).
  Payload writes: `0xD5C9BC` (u32) at `0xD43068`, then `0xD5C8A0` (u8) at `0xD43078`. Seal
  `0xD5C828` at `0xD43084`, flush `0xD34CC0` at `0xD43094`. Not encrypted.
  **Total payload 5 bytes.**

  This is the only one of the four peer-register senders with a second argument:
  `f(ctx, u32 a, u8 b)`, staged at `r1+1432` (`stw r4` at `0xD42FDC`) and `r1+1440`
  (`stb r5` at `0xD42FD8`). Its three siblings (`0x4340`/`0x4342`/`0x4346`) are the same
  function shape minus the byte.

  `PROTOCOL.md`'s admin-action table records the `0x4440`/`0x4344` pair firing on a host
  Restart (Round)/Restart (Stage), which is the only live sighting; no payload was decoded
  there.
doc-ref: dev/docs/PROTOCOL.md "What the host admin menu actually sends"
seq:
  - id: chara_id
    type: u4
    doc: "[ELF] 0x00, position and width exact. **[UNKNOWN] meaning** — first argument, passed through unvalidated. See mgo2_cmd_4340.ksy for why the name is a guess."
  - id: team
    type: u1
    doc: |
      [CONFIRMED, ELF 2026-08-01; renamed from `unknown_04`] 0x04. Second argument, written
      verbatim with no range check in `0xD42FA8`. **The player's team/role slot, raw.**

      `0xD42FA8` has exactly one `bl` site, **`0x277B90`** (OPD `0x10295E8` unreferenced,
      `ET_EXEC`), and it loads both wire fields off one roster entry in `r31`:

          277b58  lbz r3,0(r31); r3 += 1
          277b64  rec = 0x27ef90(r3)              ; my roster slot -> character record
          277b7c  0x27f160(rec, 332, 4, &v)       ; field 332
          277b84  lwz r4,116(r1)                  ; v      -> the u32 on the wire
          277b88  lbz r5,1(r31)                   ; entry+1 -> THIS byte
          277b90  bl 0xd42fa8

      `entry+1` is the byte the team setter `0x275FE0` maintains: it does
      `0x27F258(record, 1, 1, &value)` and then `stb value,1(entry)` at `0x276068`, keeping the
      roster entry's byte 1 in step with replicated record field 1. The full derivation of that
      field — the auto-balance picker `0x6EB4F0` returning 0/1, the `li r4,2` third role, and the
      eleven `li r4,254` "no team" sites — is written up once, in
      `mgo2_cmd_4440_c2s.ksy`'s `team`.

      **This byte is the raw slot, so unlike `0x4440`'s it can be `0`, `2` or `254`.** `0x4440`
      passes the value through `v == 1 ? 2 : 1`, which is 1-based and collapses everything else
      onto 1. A server must not assume the two packets encode the team the same way; the same
      admin action (host Restart) fires both, which is exactly the situation where the difference
      would bite.

      This resolves the note this field used to carry — "a team or slot index is the obvious
      candidate — untested". It is the team, and the evidence is the load instruction, not the
      pairing.
