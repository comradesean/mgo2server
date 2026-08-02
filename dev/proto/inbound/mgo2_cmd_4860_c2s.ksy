meta:
  id: mgo2_cmd_4860_c2s
  title: "MGO2 0x4860 — re-send of a composed letter (client -> server)"
  endian: be
doc: |
  ## THE `0xD53B6C` SENDER IS THE `0x4801` FAILURE PATH, NOT A USER ACTION

  `0x4801` (send-mail reply) tests bit 0 of its flags byte (`clrldi. r9,r0,63` at `0xD53E90`).
  When that bit is **clear** the parser calls `0xD53B6C`, which is a packet *sender*: it rebuilds
  the entire letter as this 969-byte `0x4860` (opcode 1, second byte `0xFF`) and puts request slot
  `0x55` back to state 1 = in-flight (`0xD32E08(ctx,85,1)` at `0xD53CE4`).

  So a server that answers `0x4800` with `flags = 0` and does not implement `0x4860` hangs the
  client exactly as if it had never replied. Nomad's `flags = 0` works only because Nomad also
  answers `0x4860` with a no-op `0x4861`; either half alone is a stall. We send `flags = 1` and
  therefore never see this command — see `../outbound/mgo2_cmd_4801_s2c.ksy`.

  **Two** senders, identical wire shape, differing only in the two leading literals:
  `0xD539B8` (builder call `0xD53A50`) writes `1st = 2`, and `0xD53B6C` (builder call `0xD53C04`)
  writes `1st = 1, 2nd = 0xFF`. Subsystem index `0x55` (`li r4,85`) in both.
  Total payload: 969 bytes.

  ## [ELF 2026-08-02] THE SECOND BUILDER IS DEAD CODE — the "file vs forward" split is a mirage

  The title of this file used to be "file / forward mail", on the reading that two builders meant
  two user operations. **`0xD539B8` is never invoked.** Evidence, with its control:

  * **No direct call.** `bl 0xD539B8` occurs nowhere in the image. (`0xD53B6C` has exactly one:
    `0xD53EC8`, inside the `0x4801` parser — the failure path above.)
  * **No indirect call.** Its OPD descriptor lives at `0x1029EC0`; the 4-byte value `0x01029EC0`
    appears **nowhere** in the whole file, so no function-pointer table, vtable or TOC slot holds
    it. Same result for `0xD53B6C`'s descriptor at `0x1029EC8`.
  * **Control, because a negative over descriptors is worthless if descriptors are never used
    here:** sampling 109 OPD entries at a fixed stride, **21 of them are referenced elsewhere in
    the image as data**. Indirect dispatch is in live use in this binary; these two are simply not
    part of it.

  What follows, and it is the whole point of mapping a command we do not serve: **opcode `2` can
  never appear on the wire on this build**, so there is no second operation to implement and no
  second layout to guess at. The `0x4860` this client can send is exactly one thing — *"the letter
  you refused, sent again"* — and the two "unknown" leading bytes are explained by that and not by
  a hypothetical forward/file distinction.

  ## THE PAYLOAD IS A MAIL RECORD, AND `0x4800` ALREADY NAMED EVERY FIELD OF IT

  Fields 2..8 come from the mailbox compose struct at `base = *(u32*)(ctx+0x1904) + 0x20000`
  (`ctx+0x1904` = `ctx+6404`; `lwz r29,6404(r29)` then `addis r29,r29,2` at `0xD53A34`/`0xD53A40`,
  and identically in the other builder). Those are the **same struct offsets, in the same order,
  as the whole of `0x4800`** (`mgo2_cmd_4800_c2s.ksy`), which is capture-confirmed field by field;
  this command prefixes them with `opcode` and one extra byte `0x4800` does not send.

  **Struct-offset bijection, spelled out** — the base expression is textually identical in both
  builders, so equal displacements are equal bytes of one object, not two objects of one shape.
  The compose buffer is itself a mail record (`0xD34728` `MailRecordCopy`, `0xD342A4`
  `ClearComposeLetter`), laid out from `base-8584`:

  | this packet | source | compose off. | mail-record off. | `0x4800` | `0x4822` |
  | --- | --- | --- | --- | --- | --- |
  | `letter_index`    | `base-8576` | `+8`   | `+0`   | *(not sent)*      | `index` |
  | `recipient_count` | `base-8575` | `+9`   | `+1`   | `recipient_count` | `name_count` |
  | `recipients`      | `base-8574` | `+10`  | `+2`   | `recipients`      | `name` |
  | `subject`         | `base-8445` | `+139` | `+131` | `subject`         | `comment` |
  | `body`            | `base-8296` | `+288` | *(after the record)* | `body` | — |
  | `destination`     | `base-8304` | `+280` | `+272` | `destination`     | `message_type` |
  | `echoed_flag_273` | `base-8303` | `+281` | `+273` | `echoed_flag_273` | `important` |

  The one field `0x4800` does **not** carry is `letter_index` — see its `doc:`.

  PROTOCOL.md records only that Nomad answers `0x4861 {0}` as a no-op — tier 4, and silent on
  the request. No name below is taken from it.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26,
  re-read and named 2026-08-02.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.

  **Server note: we do not handle this command, and that is correct, not an omission.** It is
  unreachable while `0x4801` carries `flags = 1`, which is what `MessageGameController` sends.
  If that ever changes, the seven fields below are a re-send of a letter we have already seen —
  treat them as untrusted echo of our own `0x4822`/`0x4801` state, exactly as `0x4800`'s
  `echoed_flag_273` says.
doc-ref: dev/proto/inbound/mgo2_cmd_4800_c2s.ksy
seq:
  - id: opcode
    type: s1
    doc: |
      [ELF] `0xD5C86C` at `0xD53A60` / `0xD53C14`. Literal per call site: **2** from the
      `0xD539B8` sender, **1** from the `0xD53B6C` sender.

      **[ELF 2026-08-02] Only `1` is reachable.** `0xD539B8` is uncalled and unregistered — no
      `bl`, and no reference anywhere to its OPD descriptor `0x1029EC0` — so opcode `2` is dead
      code and cannot be produced by this build. See the header for the sweep and its control.
      `1` therefore means, and can only mean, *"this is the `0x4801`-refused letter, re-sent"*.
  - id: letter_index
    type: u1
    doc: |
      [ELF 2026-08-02] `0xD5C8A0` at `0xD53A70` / `0xD53C24`. **The letter's handle within its
      mailbox category** — mail-record `+0`, i.e. the identical byte `0x4822` sends as `index` and
      that the client echoes back in `0x4840` (open) and `0x4880` (delete). Was `unknown_01`.

      Bijection: the source is `base-8576`, and `base-8584 + 8` is the 280-byte mail record that
      `0xD34728` `MailRecordCopy` fills from `records[cat] + idx*280` when a letter is opened
      (`0xD5415C`); `+0` is the first byte it copies. Same struct, same offset, same byte —
      see the table in the header.

      **The live sender writes the literal `0xFF` (-1) here, not the struct byte**
      (`0xD53C24`'s source is an immediate, `0xD53A70`'s is `base-8576`). That is consistent and
      is the reason to believe the naming: a letter refused by `0x4801` was composed, not opened,
      so it has no index in any category, and `-1` is this binary's "none" for exactly this field
      — `0xD342A4` clears the compose buffer's category selector to `-1` the same way. The dead
      opcode-2 sender is the one that would have sent a real index.
  - id: recipient_count
    type: u1
    doc: |
      [ELF 2026-08-02] `0xD5C8A0` at `0xD53A84` / `0xD53C38`, from `base-8575` = mail-record `+1`.
      **How many of the eight slots in `recipients` are populated**, 0..8. Was `unknown_02`.
      Identical offset and primitive to `0x4800`'s `recipient_count` (`base-8575`), which is
      capture-confirmed, and to `0x4822`'s `name_count`. Written by the compose screen at
      `0x8EEDD8` (`stb r0,1(r24)`) from its recipient-table loop bound; a GM letter sends 0.
  - id: recipients
    size: 128
    doc: |
      [ELF 2026-08-02] Raw 128 bytes, `0xD5D0AC` r5=128 at `0xD53A9C` / `0xD53C50`, from
      `base-8574` = mail-record `+2`. **Eight fixed 16-byte recipient-name slots**, not one
      128-byte name — the same block `0x4800` sends as `recipients` (capture-confirmed: slot 0
      held the operator's typed `to:`, slots 1-7 NUL) and `0x4822` delivers as `name`.
      Was `unknown_03`. Only the first `recipient_count` slots are meaningful; the block is
      zeroed before filling (`bzero(base-8574,128)` at `0x8EEA00`/`0x8EED08`).

      **Declaration flagged, not changed.** `0x4800` models the identical block as
      `str size:16 / repeat expr 8`; this file models it as one opaque 128-byte field. The total
      width is the same 128 either way, so this is a modelling difference rather than a contested
      length, and `size`/`repeat` are evidence — see `dev/proto/README.md`. Refining it to eight
      slots would make the two specs agree.
  - id: subject
    size: 128
    doc: |
      [ELF 2026-08-02] Raw 128 bytes, `0xD5D0AC` at `0xD53AB4` / `0xD53C68`, from `base-8445` =
      mail-record `+131`. **The letter's subject line**, NUL-padded. Was `unknown_83`.
      Same offset as `0x4800`'s `subject` (capture: `hi`) and `0x4822`'s `comment`, which the
      OPENmail painter renders into the element the developers named `NULL_OPENmail_SUBJECT`
      (`0x8E8E78`). The client refuses to send a whitespace-only value (`0x8EEBCC`), so a non-blank
      subject is guaranteed on the wire here too — this packet re-sends what `0x4800` already
      validated.

      **Declaration flagged, not changed:** `0x4800` declares `type: str` / `encoding: ISO-8859-1`
      / `pad-right: 0` on the same 128 bytes; this file leaves it a raw block. Same width, so the
      difference is presentation, not a contested length.
  - id: body
    size: 708
    doc: |
      [ELF 2026-08-02] Raw 708 bytes (`0x2C4`), `0xD5D0AC` at `0xD53ACC` / `0xD53C80`, from
      `base-8296` = compose `+288`, the 709-byte region that follows the 280-byte mail record.
      **The message body.** Was `unknown_103`.
      Byte-for-byte the same buffer as `0x4800`'s `body` (capture: `poop`) and as `0x4841`'s
      708-byte delivery block: all three compute `*(session+6404) + 0x20000 - 8296`
      (`0xD535F8`/`0xD53620` for `0x4841`, `0xD53F80`/`0xD53FE4` for `0x4800`, `0xD53ABC` here).
      The OPENmail screen word-wraps it from byte 0 into twelve line elements, so there is no
      header in front of the text.

      **Declaration flagged, not changed:** as `subject` — `0x4800` types the same 708 bytes as a
      padded `str`, this file as a raw block.
  - id: destination
    type: s1
    doc: |
      [ELF 2026-08-02] `0xD5C86C` (signed) at `0xD53AE4` / `0xD53C98`, from `base-8304` =
      mail-record `+272`. **The destination class: 0 = an ordinary letter to named recipients,
      3 = the GAME MASTER.** Was `unknown_3c7`.
      Same offset and same signed primitive as `0x4800`'s `destination`, which is confirmed live
      (a To -> GM letter put `3` here with count 0 and all eight name slots zeroed), and as
      `0x4822`'s `message_type`. `stb ...,272(rN)` occurs once in the whole mail module and `3` is
      the only literal stored, so the value set is `{0, 3}`.

      Server consequence, if this is ever handled: a `3` has no recipient character, so a plain
      recipient loop delivers "0 of 0" and silently succeeds. `0x4800` needed its own GM path
      (`V61`, `gm_mail`) for exactly this reason, and a re-send would need the same one.
  - id: echoed_flag_273
    type: s1
    doc: |
      [ELF 2026-08-02] `0xD5C86C` (signed) at `0xD53AF4` / `0xD53CA8`, from `base-8303` =
      mail-record `+273`. **The same byte `0x4822` carries as `important`, round-tripped back to
      us.** Was `unknown_3c8`.
      Identity only, not meaning — the tier-4 name "important" is not adopted here, exactly as in
      `0x4800`'s `echoed_flag_273`. What is proved: `MailRecordCopy` (`0xD34728`) copies `+273`
      into the compose buffer when a letter is opened, `0xD342A4` zeroes it on clear, and nothing
      else in the binary writes it; its sole client-side reader is the mailbox row painter at
      `0x8E3934`, where it combines with `+274` (`read`) and `+272` (`message_type`) to pick one
      of three UI state hashes.

      Treat it as untrusted echo of a value we ourselves put in a `0x4822` entry, never as new
      input.
