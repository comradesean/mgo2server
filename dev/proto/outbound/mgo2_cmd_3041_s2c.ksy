meta:
  id: mgo2_cmd_3041_s2c
  title: "MGO2 0x3041 — reply to 0x3040 (activate character by slot); the exchange is dead code on this build (server -> client)"
  endian: be
doc: |
  Parser arm 0xd377d4 (ACCOUNT dispatcher 0xd37024 (compare tree at 0xd37074)). Wait slot 13 (0xd).

  Two-stage: read a u32 result (primitive 0xd5ccd8 at 0xd37814 — NOT 0xd5cc64; the two are
  byte-identical duplicated read_u32_be routines, but the call target here is 0xd5ccd8); **only
  if it is zero** does the parser continue and read a u32 plus a fixed 16-byte block (0xd37838,
  0xd37858) into the live profile. A non-zero result skips straight to `READ_END`, so an error
  reply is legitimately four bytes long.

  This matches OBSERVED.md exactly ("`0x3041` is s32 result, then (if 0) a u32 and 16 bytes").

  ## Subsystem identified 2026-08-03: character-slot management

  The 0x3040 builder sits in the contiguous ACCOUNT builder bank 0xD37918-0xD37DE4, whose
  members (by the `li r4,<id>` in each) are: 0xD37918 -> 0x3105 delete character (wait 17),
  0xD37A0C -> 0x3103 select character (wait 16), **0xD37B00 -> 0x3040 (wait 13)**,
  0xD37BF0 -> 0x3048 get character list (wait 14), 0xD37CC0 -> 0x3107 check name (wait 18),
  0xD37DE4 -> 0x3101 create character (wait 15). The 0x3040 argument is a u8 guarded
  `cmplwi cr6,r4,7; bgt -> -24` at 0xD37B20/0xD37B34 — the identical 0..7 guard the 0x3103
  select-character builder carries at 0xD37A64/0xD37A6C, and the same 8-slot space as 0x3049's
  character grid. The reply's two success fields land in the live profile at the exact slots
  0x3049's row carries at +4/+8 and 0x4101 writes at 0xD3C18C/0xD3C1AC.

  So: **0x3040 = "activate/fetch character by slot index (0..7)"; 0x3041 returns that
  character's id and name and installs them as the live profile** — a per-slot alternative to
  the 0x3048/0x3049 + 0x3103 flow the shipped client actually uses.

  ## The exchange is DEAD CODE on this build [ELF 2026-08-03]

  The builder's function entry is **0xD37B00** (prologue `stdu r1,-1360(r1); mflr r0`; OPD
  descriptor at 0x1029008). The 0xD37B6C long cited as "the builder" is the `li r4,12352`
  *inside* it. That entry has:

  * zero `bl`/`b`/`bc` callers over the whole executable range 0x10230..0xDE9328;
  * one whole-image dword hit for `00 d3 7b 00` — the OPD descriptor itself — and zero hits
    for a reference *to* that descriptor (`01 02 90 08`);
  * zero `lis/addis`+`addi/ori` constant formations of either address.

  The scan was validated on eight controls in the same OPD bank (0xD36FF8 -> 8 callers,
  0xD37024 -> 1, 0xD378EC -> 7, 0xD37918 -> 1, 0xD37A0C -> 1, 0xD37BF0 -> 3, 0xD37CC0 -> 1,
  0xD37DE4 -> 1) plus the known 0xA7DC48 -> 20 tail-call control. Only 0xD37B00 returns zero.

  Wait slot 13 has exactly two touch points in the image, confirming the pairing and the
  deadness together: 0xD37BBC arms it (`r4=13, r5=1`, inside the dead builder) and 0xD37880
  clears it (`r4=13, r5=2`, this parser). All 251 call sites of the wait-state setter 0xD32E08
  were enumerated to establish that.

  **Consequence for the server: 0x3040 can never arrive from a disc-build client, so this
  reply is unsendable-in-practice and has no stall potential.** Not served in v1; the caveat
  that this may differ on 1.36 applies as always (nothing here transfers).

  ## Hazard — do not send 0x3041 unprompted

  The parser arm does **not** check the wait state before reading. An unsolicited 0x3041 with
  result == 0 on the ACCOUNT connection would overwrite the live profile's chara_id and name —
  and chara_id is the id space chat attribution and the peer descriptor are built from
  (0x9444BC, 0x276694, 0x27687C). Since nothing in the client can arm slot 13, the only way
  this arm ever executes is a server sending 0x3041 unprompted. Hazard, not bug — we never
  send it; recorded because the inertness depends on our behaviour, not the client's.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/OBSERVED.md
seq:
  - id: result
    type: u4
    doc: "[ELF] Wire 0x00. Zero gates the rest of the packet (0xd37828 `cmpwi r0,0; bne -> skip`)."
  - id: body
    type: success_body
    if: result == 0
    doc: "[ELF] Present only when result == 0; the parser does not read it otherwise."
types:
  success_body:
    seq:
      - id: chara_id
        type: u4
        doc: |
          [ELF 2026-08-03] Wire 0x04 -> **profile+0** = netctx+0x57D8. The destination base is
          the raw return of 0xD3A094 (`mr r31,r3` at 0xD377F4, displacement 0 at
          0xD37830-0xD37838), and 0xD3A094 is `getProfile(netctx)`: the whole function is
          `return netctx ? netctx + 22488 : 0` (`addi r0,r3,22488` at 0xD3A0A0). 22488 = 0x57D8.

          The same slot `mgo2_cmd_4101_s2c.ksy`'s `chara_id` fills ([CONFIRMED] there) and
          0x3049's row carries at +4. Heavily read: direct-displacement readers at 0x270CD8,
          0x272D3C, 0x27385C, 0x273FF4, 0x276694; bare getters 0x907F14 (16 callers) and
          0xD36F8C (3 callers); ~35 inline readers in the 0xACxxxx/0xD4B-0xD5B banks; copied
          into the per-slot stat blob as SET(key 332, len 4) at 0x270EB0/0x272EEC/0x273BDC/
          0x281D04. The name transfers from the destination slot, not from this packet's own
          use — no capture of this packet can exist on this build (see the doc block).
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        doc: |
          [ELF 2026-08-03] Wire 0x08 -> **profile+4**, fixed 16 bytes (0xD5D018 with r5=16 at
          0xD37848-0xD37858), NUL written at profile+20 — the 16+1 idiom. Same slot
          `mgo2_cmd_4101_s2c.ksy`'s `name` fills and 0x3049's row carries at +8.

          The 16-char-name reading is now a tier-1 read, not a width analogy: the slot's one
          live reader in the whole image is 0x8E1C28 (`addi r5,r17,4` off the 0xD3A094 return,
          `li r4,32`, `bl 0x23E3F0` string widen/convert, then `bl 0x247110` set-UI-text),
          inside the shared UI text helper 0x8E19B4 (25 callers). Two accessors returning
          &profile[4] exist and are both dead — 0x907EE8 and 0xD36F4C, zero callers each.

          False positives recorded so nobody re-finds them: 0x93E5F4/0x93E684 look like
          profile+4/+20 reads but the base was rebased by `lbzu r0,7648(r8)` at 0x93E5B4 (the
          update-form trap from ADDRESSES.md), so they are profile+7652/+7668; and
          0xD47350/0xD47354 iterate an unrelated array off r26.
