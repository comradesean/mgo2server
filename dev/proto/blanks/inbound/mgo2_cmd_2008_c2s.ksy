meta:
  id: mgo2_cmd_2008_c2s
  title: "MGO2 0x2008 — get news (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd36888`
  (`li r4,8200` = `0x2008` at `0xd36884`), sender `0xd3681c`. Exactly one write primitive runs
  before the seal: `bl 0xd5c86c` (write-u8) at `0xd36898`, taking its value from the stack slot
  `1416(r1)` where the sender's `r4` argument was spilled at `0xd36848`. Seal at `0xd368a4`,
  flush at `0xd368b4`, wait slot `0x0c` (`li r4,12` at `0xd368bc`). [ELF]

  **This corrects PROTOCOL.md**, which says "Request payload is not read". That is true of our
  server, but the sentence reads as though the client sends nothing: it sends one byte.
doc-ref: dev/docs/PROTOCOL.md "0x2008 — get news"
seq:
  - id: selector
    type: u1
    doc: |
      [ELF] The sender's only argument, passed straight through as a u8. No range check is
      applied at the call site (unlike `0x3040`/`0x3103`, which clamp to <= 7).
      **[UNKNOWN] meaning.** Named `selector` for its position only — the plausible readings
      (news category, page index, or a "give me everything" constant) are not distinguished
      by anything in the sender, and no live capture of `0x2008` has been logged with its
      payload bytes. The `0x2009`/`0x200a`/`0x200b` reply triple carries no matching field.
