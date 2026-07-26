meta:
  id: mgo2_cmd_4902
  title: "MGO2 0x4902 — game-lobby list entries (server -> client)"
  endian: be
doc: |
  The payload of one 0x4902 packet: N fixed-size entries back to back, the reply body to the
  client's empty 0x4900 request. Bracketed by 0x4901 (4-byte result; also resets the client's
  entry count and marks the list in progress) and 0x4903 (4-byte result; fires the completion
  event). This is what populates the hub's "Lobby Select" screen.

  ENTRY SIZE IS 99 (0x63) BYTES, NOT 35. Read out of the parser at 0xD47E18 on 2026-07-25,
  field by field, after Lobby Select showed only ever one lobby. Both reference servers write
  35 bytes — index/attributes/id/name/open/close/flag — which is the correct field ORDER but
  omits a 64-byte text block between the name and the open time.

  WHY A SHORT ENTRY DOES NOT ERROR, IT DESYNCS. The stream readers (0xD5CCD8 u4, 0xD5CB8C u1,
  0xD5CC14 u2, 0xD5D018 raw) bound-check the read cursor against the 1023-byte packet BUFFER,
  not against the payload length; only the loop condition (0xD5CEB0) looks at the length, and
  only between entries. So 35-byte entries parse entry 0 correctly — the first 26 bytes of the
  two layouts coincide — and then resume 64 bytes into the middle of entry 2, storing rubbish
  until the cursor runs past the end. Symptom: exactly one lobby in Lobby Select, always
  whichever the server sent first, whatever it was.

  CLIENT-SIDE STORAGE. Each parsed entry is memcpy'd into a 120-byte struct appended to a
  64-entry array at ctx+0xB790 ({marker:u4, count:u4, entries[64]}). Entry 64 onward is
  dropped (cmpwi 63 / bgt -> bail). The struct is the wire layout plus NUL-terminator padding
  after each string, so struct offsets run 1 ahead of wire offsets from the name onward.

  THE MENU IS CATEGORIES, NOT LOBBIES (0x890410-0x8905D8). The hub scans the stored array once
  per subtype, in the order 2, 1, 7-or-8, 5, 3, 4, and STOPS AT THE FIRST MATCH. Each match
  emits one menu row whose label comes from the client's own string table (0x8E0C24 — ids
  251/260 for subtype 2, 245/261 for 1, 249/262 for 7 and 8, 246/263 for 3, 248/265 for 4) and
  whose action code is fixed (9, 10, 11, 13, 14). So the name field is NOT what a category row
  says. A second lobby sharing a subtype adds no second row, but it is not dropped: the list
  behind a category is built at 0x89147C from the same array, accepting any entry whose subtype
  matches the current lobby's (7 and 8 as one group) and separating them by lobby id. Two
  subtype-7 lobbies both appear there — confirmed on echo. That grouping is LISTING ONLY: the
  menu inside a training lobby matches the lobby's own subtype exactly (0x884584), so 7 and 8
  are not interchangeable in the seed data.
doc-ref: dev/docs/PROTOCOL.md "0x4900 — get game lobby info"
seq:
  - id: entries
    type: entry
    repeat: eos
types:
  entry:
    seq:
      - id: index
        type: u4
        doc: "[CONFIRMED] list index, counting from 0 across all packets of the reply. Parsed first (0xD47EB8) and stored at struct+0x00."
      - id: subtype
        type: u1
        doc: |
          [CONFIRMED] lobby subtype, and the only field the hub menu dispatches on (lbz +4 at
          0x890424 and at every other scan). Categories: 1 and 2 are in use and named from
          another server implementation (tier 4 — unverified); 7 and 8 are Basic and Combat
          Training, observed; 3, 4 and 5 exist in the binary but are deliberately left unnamed —
          see LOBBIES.md, which refuses the reference schema's naming as unproven.
          This is the top byte of what the reference servers write as an "attributes" u4 with
          the subtype in its high byte — the same bytes, described correctly.
      - id: unknown_0x05
        type: u1
        doc: "[UNKNOWN] parsed (0xD47EE8) into struct+0x05 and never seen read. Always 0 from us."
      - id: unknown_0x06
        type: u1
        doc: "[CONFIRMED READ, MEANING UNKNOWN] parsed into struct+0x06. The subtype-5 branch requires the value 3 before it will render the entry (0x8904F0), and nothing else reads it. Always 0 from us."
      - id: flags
        type: u1
        doc: "[UNKNOWN] a bit field: the parser expands all 8 bits one by one into the struct (0xD47F40-0xD47FEC), so each is a distinct boolean. No consumer identified. Always 0 from us."
      - id: lobby_id
        type: u2
        doc: "[CONFIRMED] lobby id, the same id the gate's 0x2003 list carries at 0x2b. This is how a menu selection resolves back to an address: the id looks up the gate list entry (0xD35C7C) to get its ip and port."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED] lobby name, NUL-padded. NOT what Lobby Select displays — that row is labelled from the client's own string table by subtype. Presentation surface for this field is unidentified."
      - id: text
        size: 64
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [CONFIRMED PRESENT, PURPOSE PARTIAL] 64-byte text block, read at 0xD48028 into
          struct+0x1b. The only consumer found is the subtype-5 branch, which
          passes it to the string formatter at 0x94AD8C (0x89050C). Every other category reads
          past it. NULs are fine — but the 64 bytes MUST be on the wire or every entry after
          the first is parsed from the wrong offset. This is the field both reference servers
          omit.
      - id: open_time
        type: u4
        doc: "[PREDICTED] open time. Widened to 64 bits when stored (struct+0x60), which is what a time_t on this target looks like. We send 0 and the lobby is usable, so it is not enforced when the open flag is set."
      - id: close_time
        type: u4
        doc: "[PREDICTED] close time. Same 64-bit widening at struct+0x68. We send 0."
      - id: is_open
        type: u1
        doc: "[PREDICTED] open flag, last byte of the entry (struct+0x70). Both references send 1 unconditionally and the lobby is selectable; 0 has never been sent, so the behaviour it gates is untested."
