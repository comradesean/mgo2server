meta:
  id: mgo2_cmd_43e1_s2c
  title: "MGO2 0x43e1 — start automatching result (server -> client)"
  endian: be
doc: |
  Reply to `0x43e0`. **Six bytes on success, four on failure** — the parser reads the two trailing
  bytes only when the result is zero (`0xD5BF98`), so a failure must not carry them.

  Result 0 does two things nothing else does: it sets the **loaded flag** and it **registers push
  channel 60**. Anything pushed before this is parsed into memory and dropped on the floor.

  The discriminated failures, all of which must be sent as **official** codes or they mask to
  something the client's table does not contain:

  | code | sentence |
  | --- | --- |
  | `-970` | Automatching is currently not open. |
  | `-950` | Unable to start automatching. |
  | *(any other nonzero)* | falls through to "Unable to start", with our number printed inside it |

  ## Evidence

  GAME dispatcher `0xD387C8` (compare tree `0xD38804`) matches `cmpwi 0x43E1` at `0xD38A34` -> stub
  `0xD39D3C` -> parser **`0xD5BF98`**. Request-status slot **50**. Destination base
  `A = ctx+0x10000`.

  `0xD32E08(ctx, 50, 2)` / `0xD32E70(ctx, 50, result)` run on **either** branch, so a nonzero result
  completes the slot cleanly rather than choking the client; the nonzero branch additionally calls
  `0xD5B41C`, the automatch teardown helper shared with `0x4311` and `0x43E3`.

  The two success bytes land at `A+0x14A1` / `A+0x14A2`, behind a **"loaded" flag at `A+0x14A0`**.
  The same two bytes are written by the unsolicited `0x43E4` push, which additionally fills
  `A+0x14A3`, `A+0x14A4` and the two 16-byte arrays at `A+0x14A5` / `A+0x14B5`. So this packet is a
  *partial* view of a larger automatch status block — see `AUTOMATCH.md` section 4.

seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] 0 = accepted. **Only on 0 are the next two bytes read** (`0xD5BF98`)."
  - id: band
    type: u1
    if: result == 0
    doc: |
      [PARTIAL] The searcher's level half-width, clamped `[0,22]`. The client lights
      `[centre - band, centre + band]` on the gauge, around a centre **it computes for itself** from
      its own record — so this is a half-width, never an absolute range.

      Still inference-only as of 2026-07-29 in the sense that no capture of the *original* server
      sending a nonzero value exists; our own client renders ours correctly.

      Note the gauge is clamped at 0 and at the level cap, so equal bands on a low-level and a
      high-level searcher **look** asymmetric while being identical. See `AUTOMATCH.md`.
  - id: players_needed
    type: u1
    if: result == 0
    doc: |
      [CONFIRMED LIVE 2026-07-28] Nonzero prints through disc string 917 as `"%d"`; **zero selects
      string 48, the `"????"` placeholder** for "no figure yet". A search with one player queued and
      a minimum of 2 sent `0x01` here and the client displayed "Players Needed: 1".

      **The recipient counts themselves** [tier 2, from video of the original service]: a lone
      searcher against a 12-player requirement sees **12**, not 11. It therefore reaches 1 rather
      than 0 at a complete group — which is necessary anyway, since 0 renders as `"????"`.
