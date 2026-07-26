meta:
  id: mgo2_cmd_4822_s2c
  title: "MGO2 0x4822 — mailbox entry (server -> client)"
  endian: be
doc: |
  Item packet of the 0x4820 mailbox triple (0x4821 start / 0x4822 entries / 0x4823 end). Parser
  0xD536AC (ends 0xD53850), dispatcher stub 0xD39504. We never send it — PROTOCOL.md: "never
  sent — the mailbox is always empty", which is reference parity for the mail selector 0x0f.

  ELF CONFIRMATION OF A TIER-4 LAYOUT. PROTOCOL.md carries a 266-byte entry transcribed from
  Nomad (used there only for clan applications, selector 0x10): `u8 mtype(0), u8 index, u8 1,
  name[128], comment[128], u32 time, u8 0, u8 important, u8 read`. The parser's read sequence is
  exactly that, field for field and width for width, and sums to the same 266 bytes. Widths and
  order are therefore [ELF]-confirmed; the *names* remain tier 4 and are marked below.

  Trace, in order: reader open 0xD5C844 (0xD53704); u8 0xD5CB54 → stack temp (0xD53714); u8
  0xD5CB8C → recordBase+0 (0xD53734); u8 → recordBase+1 (0xD5374C); 128-byte block 0xD5D018
  → recordBase+2 (0xD53768); 128-byte block → recordBase+131 (0xD53784, i.e. after the previous
  block's NUL); u32 0xD5CCD8 → temp, widened to 64 bits at 0xD537B8 (0xD5379C); u8 → +392,
  u8 → +393, u8 → +394 (0xD537BC / 0xD537D4 / 0xD537EC); reader close; then 0xD347E4 is called
  with the FIRST u8 (sign-extended, 0xD53810) and the record pointer.

  ONE RECORD PER PACKET — there is no 0xD5CEB0 loop test and no back-edge in this function,
  unlike 0x4582/0x4602/0x4902. Each mailbox entry needs its own 0x4822 packet.

  Note the first u8 is NOT part of the stored record: it is read into a separate slot and passed
  as an argument, so it selects where the record goes rather than describing it.
doc-ref: dev/docs/PROTOCOL.md "0x4820 — get messages"
seq:
  - id: mailbox_type
    type: u1
    doc: |
      [ELF 0xD53714] Read first, into its own slot, then sign-extended and passed as the first
      argument of 0xD347E4 along with the record — so it routes the entry. Tier-4 name "mtype",
      sent 0 by Nomad; the mailbox selector values 0x0f mail / 0x10 clan applications are
      themselves unverified (PROTOCOL.md).
  - id: index
    type: u1
    doc: "[ELF 0xD53734] recordBase+0x00. Tier-4 name \"index\"."
  - id: unknown_0x02
    type: u1
    doc: "[ELF 0xD5374C] recordBase+0x01. Nomad sends the constant 1; meaning [UNKNOWN]."
  - id: name
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[ELF 0xD53768, 0xD5D018 r5=128] recordBase+0x02, NUL-terminated at +0x82 in the struct. Tier-4 name \"name\"."
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[ELF 0xD53784, r5=128] recordBase+0x83. Tier-4 name \"comment\"."
  - id: time
    type: u4
    doc: |
      [ELF 0xD5379C] Widened to 64 bits when stored (std at 0xD537B8) — the same time_t-shaped
      widening 0x4902's open/close times get, which is the only support for the tier-4 name
      "time". [INFERRED] Unix timestamp.
  - id: unknown_0x107
    type: u1
    doc: "[ELF 0xD537BC] Nomad sends 0; meaning [UNKNOWN]."
  - id: unknown_0x108
    type: u1
    doc: "[ELF 0xD537D4] Tier-4 name \"important\"; unverified."
  - id: unknown_0x109
    type: u1
    doc: "[ELF 0xD537EC] Last byte of the 266. Tier-4 name \"read\"; unverified."
