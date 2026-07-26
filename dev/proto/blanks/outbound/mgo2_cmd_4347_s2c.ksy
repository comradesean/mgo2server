meta:
  id: mgo2_cmd_4347_s2c
  title: "MGO2 0x4347 — server -> client: peer-register ack for 0x4346 peer-register phase 3"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) -> stub `0xD39260` -> parser **`0xD42A34`**.

  **Not a bare ack.** The four peer-register replies `0x4341` / `0x4343` / `0x4345` /
  `0x4347` share one byte-identical 268-byte parser body (laid out back to back from
  `0xD42A34` to `0xD42E60`, one per id) that reads **two u32s** and, crucially, uses the
  second as a **dynamic request handle** rather than a fixed status slot:

  1. verify `hdr.command == 0x4347` (else `-70`);
  2. `0xD5C844` open; `0xD5CC64` u32 -> `result`; `0xD5CCD8` u32 -> `key`; `0xD5C858` close.
     Either read failing gives `-71` and the request is never completed;
  3. `0xD33344(ctx, key, 2)` — mark **the pending request whose handle equals `key`**
     complete. Unlike the fixed-slot acks (`0xD32E08`, a table indexed by a literal id
     <= 116), `0xD33344` calls `0xD33178` to *search a list* for the handle and returns
     `-266` if no such request exists;
  4. if that succeeded, `0xD33448(ctx, key, result)` stores the result on that request;
  5. if either step failed, `0xD33248(ctx, key)` releases/cancels it.

  So **the second word must be echoed** — it is the correlation token the host's per-peer
  state machine is waiting on, and a mismatched or missing `key` leaves the request pending
  even though the packet parsed. This is the mechanism behind the observed peer-register
  stalls; nothing about it is visible from the request side.

  8 bytes total. The handle's origin (which field of the `0x434x` request carries it, or
  whether the client mints it locally and expects an echo) is not established from these
  parsers — that needs the builder side. **[UNKNOWN: handle provenance.]**

  Third round-trip of the same state machine (FSM state `0x217`, sender `0xD42E64`); reached
  only after `0x4344` completes. Unhandled, the machine times out and disconnects the peer.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md; src/main/java/mgo2server/game/controller/HostGameController.java
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD42A34] wire 0x00. 0 = success."
  - id: key
    type: u4
    doc: |
      [ELF 0xD42A34] wire 0x04. The request handle to complete — looked up in the client's
      pending-request list by value, **not** used as a table index. Must match what the
      client is waiting on; a wrong value completes nothing and the FSM times out.
      Read unconditionally, before `result` is examined, so it is required even on failure.
