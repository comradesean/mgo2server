meta:
  id: mgo2_cmd_4b40_c2s
  title: "MGO2 0x4b40 — cancel join / leave clan, no payload (client -> server)"
  endian: be
doc: |
  **Cancel Join / leave the clan.** EMPTY PAYLOAD — zero bytes after the 24-byte transport
  header, established positively from the ELF rather than left unmapped. Reply is `0x4b41`,
  a bare u32 result.

  [CONFIRMED 2026-07-27] Identified live: this is what the pending-applicant screen's
  **Cancel Join** button sends. **The zero payload is why it never turned up in a search for
  id-carrying commands** — every other join-related command in the family puts a u32 on the
  wire, so a search shaped around "which command carries the clan id" could not find this
  one by construction.

  Because nothing on the wire identifies the subject, the server resolves it from the
  session: withdraw the caller's pending application, or drop their membership. Answering it
  with a bare result while doing nothing left the application in place — a silent no-op that
  looked like success, which is the failure mode this whole family had.

  Evidence (ELF, retail BLUS30109): sender 0xD578C0. Builder `bl 0xD5CF40` at 0xD57944
  (`li r4,0x4b40` at 0xD5793C) is followed immediately by the seal `bl 0xD5C828` at 0xD57950
  and the flush `bl 0xD34CC0` at 0xD57960, with no serializer call in between (none of
  0xD5C86C/0xD5C8A0, 0xD5C8D4/0xD5C918, 0xD5C95C/0xD5C9BC/0xD5CA1C, 0xD5CA7C, 0xD5CADC,
  0xD5D0AC). The builder zeroes its 1024-byte buffer and resets the cursor, so the sealed
  length is 0.

  Preconditions: session != NULL, and 0xD57750 true — the session clan record at
  `session_ctx+0x1AA0` must be non-NULL with id != 0; otherwise -1202 (0xFFFFFB4E) and no
  packet. Note it does **not** require status == 2, unlike 0x4b04/0x4b30: a pending
  applicant (status 0) and a plain member (status 1) can both send it, which is exactly what
  "cancel join or leave" needs and is corroborating evidence for the reading.

  On a successful flush the flow state advances via `0xD32E08(session, 97, 1)`.

  Sibling 0x4b48 is scoped the same way — by the caller's own clan — but sends the id
  explicitly as a u32. The pair is not redundant: 0x4b48 is a *fetch* whose reply the client
  matches to a request slot, this is an *action* on the session.
seq: []
