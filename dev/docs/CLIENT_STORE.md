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

## 3a. Records 1–24: the scoreboard row, and the keys that build it

**Confirmed live 2026-07-28.** Sending the worn title at `0x4122` wire `0xef` made the animal-rank
badge appear on the scorecard, which validates this whole publishing path — a server byte reaching a
P2P-replicated per-slot record and being drawn from it.

The per-slot player blobs are what the in-game scorecard draws each row from. Identified
2026-07-28 while chasing a missing animal-rank badge:

| key | len | what |
| --- | --- | --- |
| 350 | 1 | a 4-bit field from `0x4101` wire `0x028` (charBlock + `0x3328`), low nibble plus a bit from `0x9066FC` |
| 356 | 2 | announce +0 |
| **358** | **1** | **the worn title / animal rank**, 1-based. Byte `0x166` of the blob, i.e. `0x1610568 + slot*0x510 + 0x166` — a link-time constant, so a usable RPCS3 watchpoint |
| 359 | 23 | announce +16 |

The publishing chain, all read: `0x4122` wire `0xef` → charBlock + `0x1EA5` → the 356-byte
player-announce struct at +3 (`0x88407C`, store at `0x8842A4`) → `RecordSet(rec slot+1, 358, 1)` at
`0x276374` for your own slot, `0x2780E4` for peers. Readers are `0x9BFA68` (the `title_32_NN_alp`
sprite) and `0x9BF618` (the title text), both doing `RecordGet(rec slot+1, 358, 1)` then matching
against a 22-entry table.

**The announce struct puts title (+3), clan-emblem flag (+4) and clan id (+8) adjacent**, which is
why the badge sits immediately left of the emblem on a row — and why the emblem rendered while the
badge did not: we filled the emblem's source byte correctly and the title's with a dead field.

## 4. The hosted-game name, and why automatch depends on it

- **Read** at `0x93D354` — automatch screen state 12 does `GET(rec25, 140, 16)` into the
  create-game struct at `+4`, which is `0x4310` wire offset `0x00`.
- **Written** at `0x947B94`, in state 4 of screen coroutine `0x946F00` (12 states, jump table
  `0x946F5C`, OPD `0x101CC48`), copying from `session + 0x57D8 + 4`.
- **Gated** at `0xD44730`: the `0x4310` builder refuses to send when the name's `strlen` is outside
  3..16, and `0xD44744` additionally runs a charset check (`0xD32DD0`). The refusal returns `-24`,
  which the builder's only caller `0x8CA178` routes to **error dialog 3845** — see below; this was
  previously recorded as failing with no dialog, which was wrong.

**Settled 2026-07-28: it is the CHARACTER NAME.** `0xD3A094` returns `session + 0x57D8`, and the
`0x4101` parser (`0xD3C120`) fills that base with the character id at `+0` and a **16-byte character
name at `+4`** (`+0x57DC`), matching `PROTOCOL.md` field for field with one base register and one
contiguous payload. An earlier reading of this region as a "current game block with a game name at
+4" was wrong.

So `0x947B94` copies **the character name** into the hosted-game-name record, and it can never be
under three characters or fail the charset check. A live capture agrees: a real automatch-initiated
`0x4310` carried `"Sean"`, that character's own name — a client-side seed, not something typed and
nothing to do with what the server sent in `0x4305`.

The `0x4310` linkage is three-point verified: `0x93D354` writes `obj+116`; `0x93D440` spawns the
builder coroutine with `r3 = obj+112`; the builder uses `args+4`, `+19`, `+21`, `+150/151`, `+168`,
and `obj+116/131/280` line up with `args+4/19/168` exactly.

**The refusal is not silent.** `0xD44730` gates on `strlen` 3..16 and `0xD44D14` returns `-24`; the
builder's only caller `0x8CA178` routes a nonzero result to **error dialog 3845**. Earlier notes in
this project said this path fails with no dialog at all — that was wrong.

**What remains open** is narrower: key 140 is zeroed at boot, `0x946F00` state 4 is its only filler,
and **the automatch menu item does not spawn `0x946F00`**. The two screens are siblings — automatch's
constructor `0x93B4D0` is installed as a confirm callback by the menu builder and constructs nothing
of `0x946F00`'s. So a player who reaches automatching without having passed through the Create-Game
settings screen this session has an empty name.

The next thing to settle: `0x946D70` (the `0x946F00` constructor) has five callers — `0x890DCC`,
`0x892E44`, `0x8936A0`, `0x9363C8`, `0xAC7D14`. Four write `RecordSet(rec25, key 254, 2)` first, an
entry-mode selector; **`0x890DCC` does not**, and it is reached from state dispatch `0x893C10` of the
55-state lobby coroutine `0x892B08`. If that state is an automatic lobby-entry step rather than a
menu selection, the gap closes completely.

## 5. Persistence — settled: it is NOT persisted

A first investigation concluded this by searching for the buffer address `0x16181A0` and finding it
only in its own descriptor. **That reasoning was invalid** — a save routine would walk the descriptor
table and use `desc->buffer` indirectly, never naming the buffer. The conclusion was nevertheless
right, and here is the argument that holds:

- **Exactly 15 instructions in the whole text section** reach the record array base (`lwz rX,
  -31408(r2)` → `0x16182C8`), and every one is inside `0x27EE00`–`0x281000`. That is the entire
  subsystem, enumerated.
- The static descriptor addresses (`0x103BC18`, `0x103BC34`, `0x103BC4C`, `0x103BED4`) appear in the
  binary **only** as stored pointers at `0xFC2E80`–`0xFC2E8C`. No instruction materialises them as an
  immediate, so there is no descriptor walker outside the subsystem.
- The subsystem's complete external call list contains `memset`, `memcpy`, `memcmp` and a set of
  bit-cursor and peer helpers — and **none of the file primitives** (`0x280F0` open, `0x258E0` close,
  `0x26A90` write, `0x26ED8` read) that the `.sav` module uses.
- No `cellSaveData`, `savedata` or `SAVEDATA` string exists anywhere in the ELF.

Lazy loading is excluded by the same evidence: the subsystem contains no file I/O at all.

### What the dirty bitmap is actually for

It is **not** disk write-back. `0x27FDC8` iterates all 26 descriptors; `0x280838` walks 24 handles at
`regArray+104..200` building 256-byte bit buffers; `0x26E9C0` resolves a **peer** id against a 24×116
table, with 255 meaning broadcast; `0x27F428` closes all 24 handles and clears every dirty bitmap.

So the bitmap is a **per-peer delta mask for replicating the record store across the 24 P2P player
connections** — write-back over the network. That is why records 1–24 are the per-slot player blobs:
this store *is* the peer-to-peer state layer.

## 6. The single-player unlock question

**MGS4 unlocks items based on time played in MGO**, and the unlock is driven by real play time — so
something MGO writes must be read by the single-player game.

**Three candidates are now eliminated** (2026-07-28):

- **Not this record store.** It is not persisted at all (§5), and its dirty bitmap turned out to be
  P2P replication rather than write-back to disk.
- **Not `mgof.sav`.** Its module at `0x7F6CA8`/`0x7F6D98`/`0x7F6E58` moves exactly **4 bytes** — a
  single u32 flag. `scradj.sav` (`0x7F64B8`, `0x7F6528`) is likewise 4 bytes.
- **Not PS3 savedata.** There is no `cellSaveData`, `savedata` or `SAVEDATA` string anywhere in the
  ELF, and no savedata directory for the title in an observed RPCS3 install.

**`ac.sav` is answered, 2026-07-29: it is a flat 936-byte snapshot of record 25** — the local
player's settings record. So the answer to "is any of the store persisted" is *one record is, the
other 25 are not*, and the write-back the dirty bitmap was once suspected of doing really is only
P2P replication.

Decrypted (key `online`, see [ASSETS.md](ASSETS.md)) it is **19 non-zero bytes** in 936: `+0x001`
= 01, `+0x004` the account id as ASCII digits, `+0x048` a four-digit ASCII string, `+0x08F` = 03,
`+0x194` = `16 62 02`, `+0x1A1` = 01. The layout lines up with record 25's own field table —
`RecordGet(key 0, len 140)` at `+100` and `(key 176, len 24)` at `+496`.

*Inferred, not yet checked:* the remaining fields are nameable cheaply by diffing — change one
setting in game, re-dump, compare. Nothing else in the file is understood, and 917 zero bytes means
most of the record is simply unused on a fresh profile rather than hidden.

The whole `.sav` module lives at `0x7F6000`–`0x7F9300` with its own open/read/write/close, entirely
separate from the record store.

Two cautions for whoever picks this up:

- **The server cannot help.** The unlock is client-side and will never appear in a packet. Our
  `chara_training_time` and the `seconds_in_game` column are what *we* track for the stats screens
  and are a different quantity; do not conflate them.
- **The observed files are written at different times** (`helpdisp` mid-session, `mgof` days apart,
  `opt`/`scradj` older), so they are written by different triggers rather than dumped together at
  exit. Timestamps are evidence about which subsystem wrote what.

---

## Addresses, for the index

`0x27DD38` boot registration · `0x27EF90` RecordBuffer · `0x27F0E0` register one · `0x27F160`
RecordGet · `0x27F258` RecordSet · `0x27F428` close peers and clear dirty masks · `0x27FDC8`
iterate all 26 descriptors · `0x280838` build per-peer bit buffers · `0x103BC18` descriptor table ·
`0x103C544` record 25's field table · `0x16182C8` the 26 buffer pointers · `0x16181A0` record 25's
buffer · `0x161822C` the hosted-game name · `0x93D354` automatch reads it · `0x947B94` the sole
writer · `0x946F00` the Create-Game settings screen containing it · `0x946D70` its constructor ·
`0xD3A094` the character block · `0xD3C120` the `0x4101` parser · `0xD44730` the length gate ·
`0xD32DD0` the charset check · `0x7F6000`-`0x7F9300` the `.sav` module.
