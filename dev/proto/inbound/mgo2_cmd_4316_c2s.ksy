meta:
  id: mgo2_cmd_4316_c2s
  title: "MGO2 0x4316 — create game (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd43ccc`. One write primitive:
  `bl 0xd5c86c` (write-u8) at `0xd43cdc` from stack `1328(r1)` (corrected 2026-07-26 from
  `0xd5c8a0`; the two are write-u8 twins, so the conclusion is unaffected). Seal at `0xd43ce8`; wait slot
  `0x25` (`li r4,37`). [ELF]

  **This corrects PROTOCOL.md's phrasing.** It says "Request payload is **not read at all**",
  which is true of our handler but reads as though the packet is empty. It is not: the client
  sends one byte. PROTOCOL.md's own numbered finding 23 ("`0x4316` does not read its request
  payload at all") should likewise be read as a statement about the server, not the wire.
  Nothing here changes the conclusion that the *settings* arrive on `0x4310` — one byte cannot
  carry them.
doc-ref: dev/docs/PROTOCOL.md "0x4316 — create game"
seq:
  - id: lobby_subtype
    type: u1
    doc: |
      [CONFIRMED, ELF 2026-08-01; renamed from `unknown_00`] Position and width exact. **The
      lobby subtype the game is being created in** — the same value `0x4310` carries at its wire
      `0xA2` and `0x4313` reports at `0x09a`, and the key our server already stores
      `chara_host_settings` under, per (character, lobby subtype).

      This file previously called that the "strongest candidate on position", untested, and asked
      for a capture of a `0x4316` next to its preceding `0x4310` to settle it. **No capture is
      needed: the two bytes are produced by the same four instructions on the same struct field,
      and the byte-for-byte agreement the experiment was meant to observe is forced by the
      code.** The `0x4310` builder and this sender both compute the value inline; neither takes it
      from a caller.

      The computation, identical in both, in program order:

      | step | `0x4316` sender | `0x4310` builder (`0xD447xx`) |
      | --- | --- | --- |
      | default 0 into the slot | `0xd43c34` | (slot pre-set) |
      | connection guards, abort `-36` | `0xd43c40`/`0xd43c50` | `0xd447b8`/`0xd447c8` |
      | **`= 1`** | `0xd43c68` | (slot already 1) |
      | `if (0xD4908C(session))` | `0xd43c70` | `0xd447e0` |
      | ` if ((blk = 0xD491F8(session)))` | `0xd43c84` | `0xd447f4` |
      | ` **`= blk[608]`** | `0xd43c94` -> `0xd43c98` | `0xd44804` -> `0xd44808` |
      | `if (0xD5BDA0(session)) **`= 2`** | `0xd43ca0` -> `0xd43cb4` | `0xd44810` -> `0xd44820` |

      `0xD491F8(s)` returns `s + 0x10000 - 9944`, `0xD4908C(s)` is the null test on the `u32` at
      that same address, and `0xD5BDA0(s)` tests the `u8` at `s + 0x10000 + 5280`. The `0x4310`
      arm writes its result to `168(r29)` — which is exactly `src+168`, the offset this schema's
      sibling `mgo2_cmd_4310_c2s.ksy` already documents as `lobby_subtype`. Same source byte, same
      guards, same fallbacks: the two fields are the same quantity.

      Reachable values, therefore: **1** (no game block yet), **`gameBlock+608`**, or **2** (forced
      whenever `session[0x10000+5280]` is set, which overrides both). The `0` the slot is
      initialised to at `0xd43c34` is unreachable, because the only path that leaves it in place
      aborts before the builder runs.

      A third sender computes the same byte the same way — `0xD452Cx`, which builds `0x4320`
      (`li r4,17184` at `0xd45320`) — and then additionally forces the byte to its own `r28` when
      that is 1, 2, 7 or 8, caching it at `session[0x10000+5472]`. Recorded because it is the only
      place in the image that enumerates a subtype value set, and because it means `0x4320` and
      `0x4316` can disagree by design.
