meta:
  id: mgo2_cmd_43c0_c2s
  title: "MGO2 0x43c0 — in-game info / edit game settings (client -> server)"
  endian: be
doc: |
  Builder function `0xD4161C` = `f(ctx, void *settings)`; a null `settings` aborts (`0xD41660`).
  `bl 0xD5CF40` at `0xD41744` (`li r4,0x43C0` at `0xD41740`), seal `0xD5C828` at `0xD417B8`,
  **Blowfish-encrypted in place by `0xD5D124`** at `0xD417D4` (consistent with `0x43C0` being in
  `DECRYPT_COMMANDS`), flush `0xD34CC0` at `0xD417E4`. **Total payload 162 bytes (0xA2).**

  Writes (`0xD41758`-`0xD417AC`): `0xD5D0AC` r5=16 from `settings+0x04`; `0xD5D0AC` r5=128 from
  `settings+0x15`; `0xD5C86C` u8 from `settings+0x96`; `0xD5D0AC` r5=16 from `settings+0x97`;
  `0xD5C8A0` u8 from `settings+0x34E`.

  The sender's pre-write validation is what identifies the fields, and it is worth having in full
  because it is the client's own policy on these strings:
    * `settings+0x04` — `strlen` must be **3..16** (`0xDCC7F8`, `<=2` or `>16` aborts) and must
      pass the charset validator `0xD32DD0`. The game **name**.
    * `settings+0x15` — `strlen` must be **<= 128**, no charset check. The **comment**
      (free text, which is why it is unvalidated).
    * `settings+0x96` — compared against 1 at `0xD416C0`; only when it equals 1 is the password
      at `settings+0x97` validated (`strlen` 3..16 plus `0xD32DD0`). So this is the
      password-enabled flag, and the password bytes are sent regardless.
  This matches `PROTOCOL.md`'s admin-action table, where "Edit name/comment/password" is the one
  action that sends `0x43C0`. The layout itself is new here (PROTOCOL.md does not decode it).
doc-ref: dev/docs/PROTOCOL.md "What the host admin menu actually sends"
seq:
  - id: name
    size: 16
    doc: "[ELF] 0x00. Game name, ISO-8859-1 NUL-padded. Client enforces 3..16 characters and its own charset validator (`0xD32DD0`) before sending — the 16-character width is protocol, the 3-character minimum is the client's."
  - id: comment
    size: 128
    doc: "[ELF] 0x10. Game comment, ISO-8859-1 NUL-padded, up to 128 bytes. No charset validation client-side."
  - id: password_enabled
    type: u1
    doc: "[ELF] 0x90. From `settings+0x96`; the sender validates the password only when this is exactly 1 (`0xD416C0`). Whether other nonzero values are meaningful is [UNKNOWN]."
  - id: password
    size: 16
    doc: "[ELF] 0x91. ISO-8859-1 NUL-padded. Always on the wire, validated (3..16 + charset) only when `password_enabled == 1`."
  - id: unknown_a1
    type: u1
    doc: "[UNKNOWN] 0xA1. From `settings+0x34E` — far past the validated region, and the only field in the frame the sender never inspects. Last write before the seal, so the frame ends at 0xA2 = 162 bytes."
