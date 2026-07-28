# The client's record store

A small property store the client keeps in memory: **26 records**, each a flat byte buffer with a
field table describing which offsets are legal. Found 2026-07-28 while chasing why an automatch host
sometimes cannot create a game.

It matters for three reasons. It holds the **hosted-game name** that automatching depends on
(§4); records 1–24 are the **per-slot player stat blobs** this project already documents elsewhere;
and it is the most likely place to look for whatever MGO writes that the single-player game reads
back (§6).

---

## 1. Layout

Descriptors are **28 bytes**: `{fieldCount, fieldTable, buffer, dirtyBitmap, 0x103C6F4, size, flags}`.

| record | descriptor | buffer | size | what |
| --- | --- | --- | --- | --- |
| 0 | `0x103BC18` | `0x16104C8` | 144 | global |
| 1–24 | `0x103BC34 + i*0x1C` | `0x1610568 + slot*0x510` | 1296 | **the 24 player stat blobs** — the same per-slot records `ADDRESSES.md` §1 documents |
| 25 | `0x103BED4` | `0x16181A0` | 276 | the local player's own record |

Registration is at boot: `0x27DD38` → `0x27F0E0`, which **`bzero`s each buffer**.

## 2. The API

| VA | what |
| --- | --- |
| `0x27EF90` | `RecordBuffer(id)` → `table[id]->buffer`, table of 26 pointers at `0x16182C8` |
| `0x27F160` | `RecordGet(buf, key, len, dst)` — validates, then `memcpy` at `0x27F24C` |
| `0x27F258` | `RecordSet(buf, key, len, src)` — `memcmp` first (`0xDD37D0` at `0x27F364`), copies and sets a dirty bit **only when the value changed** |
| `0x27F0E0` | register one record |
| `0x27DD38` | boot-time registration of all 26 |

### The access rule, which makes writer searches conclusive

A field lookup requires **all three** of (`0x27F1E4`–`0x27F234`):

- `elemSize == len`
- `start <= key < start + elemSize * count`
- `(key - start) % len == 0`

So for a given offset, usually exactly one `(key, len)` pair can reach it and **every other
combination silently no-ops**. That is why "exactly one writer" results here are real rather than a
grep that might have missed an alias — the alias space is closed by construction.

## 3. Record 25's fields

Field table at `0x103C544`, **43 entries** of `{u16 start, u16 elemSize, u16 count, u32}`.
Identified so far:

| key | size | what |
| --- | --- | --- |
| **140** | 16 | **the hosted-game name** — at the fixed address `0x161822C`. A usable RPCS3 watchpoint |
| 200 | 40 | screen options, written from ~30 widget getters at `0x947D44` |
| 240, 244, 248, 250, 252, 264 | — | read and written by GCX natives at `0xC9FCA0`–`0xCA1DF4`; script-driven settings |

The other ~37 fields are unidentified because nothing has needed them.

## 4. The hosted-game name, and why automatch depends on it

- **Read** at `0x93D354` — automatch screen state 12 does `GET(rec25, 140, 16)` into the
  create-game struct at `+4`, which is `0x4310` wire offset `0x00`.
- **Written** at `0x947B94`, in state 4 of screen coroutine `0x946F00` (12 states, jump table
  `0x946F5C`, OPD `0x101CC48`), copying from `session + 0x57D8 + 4`.
- **Gated** at `0xD44730`: the `0x4310` builder refuses to send when the name's `strlen` is outside
  3..16, and `0xD44744` additionally runs a charset check (`0xD32DD0`). The refusal returns `-24`,
  which `0x8CA180` routes to error 3845 — but on the automatch path the screen falls back to state 1
  **with no dialog at all**.

**Open, and load-bearing:** what `session + 0x57D8 + 4` actually is. Two investigations disagree —
one traced the `0x4101` parser writing the **character id** at `+0x57D8` and the **character name**
at `+0x57DC`; the other called the same region the current-game block with a **game name** at `+4`.

If it is the character name, the hosted-game name defaults to it, can never be under three
characters, and **automatch cannot fail this way** — which is the only reading consistent with the
retail service, since players demonstrably went straight into automatching. A live capture supports
it: a real automatch-initiated `0x4310` carried the game name `"Sean"`, which is that character's
name. Do not build on the pessimistic reading until this is settled.

## 5. Persistence — genuinely unresolved

An investigation concluded the store is never persisted, on the grounds that the buffer address
`0x16181A0` appears nowhere but its own descriptor. **That does not prove it**: a save or load
routine would iterate the descriptor table and use `desc->buffer` / `desc->size` indirectly, never
naming the buffer.

Evidence pointing at persistence:

- Each descriptor carries a **dirty bitmap**, and `RecordSet` `memcmp`s so it only dirties on a real
  change. Dirty tracking is write-back machinery; there is no reason for it in a store discarded at
  exit.
- The game demonstrably writes savedata during play — `helpdisp.sav` was observed changing mid-session.

Evidence against:

- The five files under `o/online/` are **ac.sav 960, helpdisp.sav 16, mgof.sav 28, opt.sav 28,
  scradj.sav 36** bytes. None is 276, and none is an obvious container for a 276-byte record.
- No PS3 savedata directory exists for the title in the observed RPCS3 install.

So the question is open and the honest position is "not established either way". What would settle
it: find code that walks the descriptor table at `0x103BC18`, or reads a dirty bitmap at `desc+12`.

## 6. The single-player unlock question

**MGS4 unlocks items based on time played in MGO.** The unlock is driven by *real* play time, so
something MGO writes must be read by the single-player game — which makes this store, or the files
beside it, the natural place to look.

Nothing here is established yet. Starting points, in rough order of promise:

- **`mgof.sav`, 28 bytes.** The name suggests "MGO flags", the size suggests a handful of counters,
  and it sits in the game's own `o/online/` directory rather than in PS3 savedata — i.e. somewhere
  both halves of the disc can reach.
- **`ac.sav`, 960 bytes.** Larger, and the only file big enough to hold structured per-item state.
- **The record store itself**, if §5 resolves toward persistence.
- The server's own play-time accounting is a **separate** thing and must not be confused with it:
  `chara_training_time` and the `seconds_in_game` column of the `0x4105` grid are what *we* track for
  the stats screens. The unlock is client-side and needs no server involvement, so it will not appear
  in any packet.

Worth knowing before starting: the observed file timestamps show these files are written at
different times (`helpdisp` today, `mgof` a week ago, `opt`/`scradj` older still), so they are
written by different subsystems on different triggers rather than as one blob at exit.

---

## Addresses, for the index

`0x27DD38` boot registration · `0x27EF90` RecordBuffer · `0x27F0E0` register one · `0x27F160`
RecordGet · `0x27F258` RecordSet · `0x103BC18` descriptor table · `0x103C544` record 25's field
table · `0x16182C8` the 26 buffer pointers · `0x16181A0` record 25's buffer · `0x161822C` the
hosted-game name · `0x93D354` automatch reads it · `0x947B94` the sole writer · `0x946F00` the
screen containing that writer · `0xD44730` the length gate · `0xD32DD0` the charset check.
