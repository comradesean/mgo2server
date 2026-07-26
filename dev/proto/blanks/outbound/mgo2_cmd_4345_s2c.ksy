meta:
  id: mgo2_cmd_4345_s2c
  title: "MGO2 0x4345 — server -> client: peer-register ack for 0x4344 peer-register phase 2"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` -> stub `0xD39250` -> parser **`0xD42B40`**.

  **Not a bare ack.** The four peer-register replies `0x4341` / `0x4343` / `0x4345` /
  `0x4347` share one byte-identical 268-byte parser body (laid out back to back from
  `0xD42A34` to `0xD42E60`, one per id) that reads **two u32s** and, crucially, uses the
  second as a **dynamic request handle** rather than a fixed status slot:

  1. verify `hdr.command == 0x4345` (else `-70`);
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

  COMMANDS.md/mgo2-server call `0x4344` "set team"; the ELF says otherwise, or at least says
  more. The host's per-peer P2P state machine (`0x276F60`) issues **three** blocking
  register-with-server round-trips — `0x4340`, `0x4344`, `0x4346` — and their three reply
  parsers are byte-identical. An empty or 4-byte ack stalls the machine here until its
  30-second (`0x7530`) deadline fires and it disconnects the peer with `0x4342`: the ~28 s
  connect/retry loop observed against two clients. So the second u32 is load-bearing, and
  "set team" is at best an incomplete name.
doc-ref: dev/docs/COMMANDS.md; src/main/java/mgo2server/game/controller/HostGameController.java
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD42B40] wire 0x00. 0 = success."
  - id: key
    type: u4
    doc: |
      [ELF 0xD42B40] wire 0x04. The request handle to complete — looked up in the client's
      pending-request list by value, **not** used as a table index. Must match what the
      client is waiting on; a wrong value completes nothing and the FSM times out.
      Read unconditionally, before `result` is examined, so it is required even on failure.
