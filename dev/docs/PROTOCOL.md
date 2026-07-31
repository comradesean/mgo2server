# Protocol reference

What this server actually sends and parses, command by command, byte by byte.

This is a working reference for someone with a live client in front of them, so it documents **our
code** — `src/main/java/nomad/game/**` — and not what the protocol "should" be. Where a field's
meaning comes from somewhere else it says so, and where nothing is known it says that instead. A
confident-sounding guess in a file like this is worse than a blank, because the next person spends
a day proving it wrong.

Three levels of confidence are used throughout:

- **Confirmed** — verified against the real client (`BLUS30109` on RPCS3), and `dev/docs/OBSERVED.md`
  records how.
- **Ours** — this is what our code does. It may still be wrong for the client; it is simply what
  goes on the wire today.
- **Reference** — the meaning came from echo (Java, `@Command(0x....)`), mgo2-server (TypeScript,
  `@GameCommandHandler(0x....)`) or the Nomad servers, recorded here when it was read. Those repos
  are **not vendored** — do not go re-read them; what was learned is already written down here.
  **Unverified against our client** unless separately marked.

Companion documents: **`dev/docs/OBSERVED.md`** records what was observed and verified against the real
client, including the hypotheses that turned out to be wrong. **`dev/docs/STUN.md`** covers the UDP port
check, which is not part of this protocol at all — different transport, different thread, no shared
framing. **`dev/docs/CRYPTO.md`** is the reference for every cipher, key and hash, and where each is
applied; the transport section below summarises what this protocol uses.

That last distinction matters more than it looks. The references are not specifications: they were
written for different client builds and have been wrong for `BLUS30109` six separate times (the policy path, the gate hostname, the gate port, the version-check byte, the login perks field, and the two appearance bytes character creation discarded
— see `dev/docs/OBSERVED.md`, "How this file gets things wrong"). The perks field is the instructive one,
because it was transcribed *correctly* from a source that did not apply. Faithful copying of the
wrong reference looks exactly like diligence.

## Transport

### Framing

Every packet is a 24-byte header followed by a payload. `nomad.game.packet.GamePacketCodec`.

| offset | size | field |
| --- | --- | --- |
| `0x00` | 2 | command id, big-endian |
| `0x02` | 2 | payload length as it appears on the wire — for encrypted commands this is the **padded** length |
| `0x04` | 4 | sequence number |
| `0x08` | 16 | HMAC-MD5 checksum |
| `0x18` | n | payload |

Everything is big-endian. Maximum payload is `0x3ff` (1023) bytes; the decoder throws
`CorruptedFrameException` above `0x400`. That ceiling is why every list command in the protocol is
split into a start packet, N entry packets and an end packet.

The declared length is the padded one on our outbound path, because that is what the original
server sent. A peer that instead declares the unpadded length still decodes, since the receiver
re-derives the padding from whatever length it was given (`GamePacketCodec.paddingFor`).

### Whole-packet XOR

The finished packet, header included, is XORed with the repeating four-byte key
`5a 70 85 af` (`GameCrypto.XOR_KEY = 0x5a7085af`). The decoder un-XORs just the command and length
words first so it can size the frame, then un-XORs the whole frame once it has it.

### Checksum

HMAC-MD5 over the first **8** header bytes (command, length, sequence — not the checksum field
itself) followed by the payload. The key is 16 bytes that happen to be ASCII: `Z7/biJ46TzGF-8yx`.

Two details that are easy to get wrong:

- The checksum covers the payload **as it appears on the wire** — that is, the *ciphertext* for
  encrypted commands, not the plaintext. Outbound it covers the padded ciphertext; inbound it
  covers the ciphertext truncated to the declared length, and decryption happens afterwards.
- Comparison is constant-time (`MessageDigest.isEqual`), so it cannot be turned into an oracle. A
  bad checksum is fatal to the frame.

### Sequence numbers

Counted independently per direction per connection, starting at **1**. A mismatch is logged at
debug and the expectation is resynced to whatever arrived — it is not fatal. The reasoning
(`GamePacketDecoder`) is that mgo2-server tracks the inbound sequence without ever validating it
and notes that a real client's first packet is sequence 0, so rejecting on mismatch risks dropping
a legitimate client over bookkeeping. The checksum is what actually authenticates a packet.

### Blowfish payload encryption

Only some commands encrypt their payload. Our sets, from `GameCrypto`:

```java
DECRYPT_COMMANDS = { 0x3003, 0x4310, 0x4320, 0x43c0, 0x4700, 0x4990 };  // client -> server
ENCRYPT_COMMANDS = { 0x4305 };                                          // server -> client
```

The inbound set is exactly the set the references use, and of those six we currently handle only
`0x3003`, `0x4700` and `0x4990`. The outbound set contains one command, `0x4305`, which **nothing
in this server ever sends** — it is carried for parity with the references and is untested.

Note the asymmetry: a request being encrypted says nothing about its reply. `0x3003` arrives
encrypted and `0x3004` goes back in the clear; same for `0x4700`/`0x4701` and `0x4990`/`0x4991`.

The cipher (`nomad.common.crypto.Blowfish`) is **standard 16-round Blowfish**. Its loop reads as
`ROUNDS = 8`, which is easy to misread as a deviation, but each iteration applies the round
function *twice* — sixteen Feistel rounds in total. This was settled empirically, not by reading
the loop: a textbook 16-round implementation fed our shipped schedule reproduces this class's
output exactly, and the same implementation reproduced a session field captured off a real client.
Treat "it's a Konami variant" as folklore; the only real deviation is that the key ships as an
already-expanded 4168-byte schedule (18 P-array entries then four 256-entry S-boxes) rather than a
passphrase. Two schedules ship in `src/main/resources/crypto/`: `packet.key` (payloads) and `session.key` (the
check-session transform). A third, `auth.key`, was removed -- see `dev/docs/CRYPTO.md`. Payloads are zero-padded up to
an 8-byte boundary before encryption and the padding is dropped after decryption.

None of this is a security boundary. The keys are on the game disc.

### Dispatch and unhandled commands

`GameServerHandler` holds one flat command → handler map per lobby, built by
`GameServerFactory.createGameServer` from the controllers registered for that lobby type. An
unknown command is logged (`No handler for command %04x; ignoring.`) and dropped.

**Dropping is not harmless — see "Commands we do not handle" at the end of this file.**

On the client's side dispatch is not a flat map and **not a linear comparison chain**. The GAME
lobby's reply dispatcher is a function starting at `0xD387C8`; `0xD38804` is the head of its
**compare tree**, and the `bgt` at `0xD3880C` shows the tree is a binary search over command ids,
not a chain walked in order. Corrected 2026-07-26: this file previously described the region
`0xD388A8`–`0xD38948` as "a comparison chain over reply ids". Those addresses are interior nodes
of the tree, not its entry, and nothing can be inferred from the *order* in which ids appear
there.

### The packet-reader primitives

Every client-side parser in this protocol is a sequence of calls into one small reader library,
bracketed by a READ_BEGIN/READ_END pair. Reading a parser in isolation is misleading without the
library, so it is collected here. All addresses traced from `MGO2.elf` 2026-07-26.

| primitive | width | notes |
| --- | --- | --- |
| `0xD5CB54`, `0xD5CB8C` | u8 | instruction-identical twins |
| `0xD5CBC4`, `0xD5CC14` | u16 | instruction-identical twins |
| `0xD5CC64`, `0xD5CCD8` | u32 | instruction-identical twins |
| `0xD5CD4C`, `0xD5CDC0` | u64 | instruction-identical twins |
| `0xD5CE34` | string | **delimiter-terminated**, delimiter supplied by the caller in `r5` |
| `0xD5D018` | fixed block | `memcpy` of `r5` wire bytes, then a NUL written at `dest[r5]` |
| `0xD49230` | 6-byte header | u32 + u16, validated against the open object; returns −1018 on mismatch. Used by eight parsers |

Four things follow, and each of them has been got wrong here before:

- **There is no signed/unsigned distinction among the read primitives, at any width.** Every pair
  above is instruction-identical — verified 2026-07-26 by whole-function compare. **Signedness is
  established by the caller** (e.g. reloading the stored value with `lwa`), never by which
  primitive read it. Do not infer a field's signedness from a primitive address.
- The same holds on the write side, where there are **three** u32 primitives, not a pair:
  `0xD5C95C` (`sraw`), `0xD5C9BC` (`srw`), `0xD5CA1C` (`sraw`). The `sraw`/`srw` difference is
  **semantically inert** — both operate on a value already masked by `and r0,r4,r0` with
  `r0 = 255 << shift`, so the operand is non-negative either way. Any rule of the form "the lower
  address is the signed accessor" is false; one was drafted here on 2026-07-26 and withdrawn the
  same day.
- **The string reader consumes its terminator.** `0xD5CE34` (the entry point — the preceding
  function's `blr` is at `0xD5CE30`, and `0xD5CE3C` is two instructions into the body) loops at
  `0xD5CE78` comparing each byte against `r5` with NUL as a secondary stop, and advances past the
  terminator at `0xD5CEA4`. A string field of length *n* therefore costs **n+1 wire bytes**, and
  is variable-width, not padded. The fixed-block reader `0xD5D018` is the opposite: it takes
  exactly `r5` wire bytes and writes `r5+1` struct bytes — which is why 17-byte struct strides
  sit over 16-byte wire reads all through this protocol.
- **The bound checks encode the width unambiguously**: a read primitive that compares the cursor
  against 1023/1022/1020/1016 is reading 1/2/4/8 bytes. They bound-check the **1023-byte receive
  buffer**, never the declared payload length — the reason a short payload reads stale buffer
  instead of failing, which this file flags repeatedly below.

The sealing side: `0xD5C828` (SEAL) stores the cursor to `obj+4`, sets state 2 and zeroes the
cursor; `0xD5C844`/`0xD5C858` set state 8/9 and zero the cursor. `0xD5CEB0` is exactly
`cursor < obj+4 ? cursor : -1`.

### Where a list's count comes from

**There is no house style.** Traced 2026-07-26; single-source ELF trace, not confirmed against a
client. Four different mechanisms are in use, and assuming the wrong one produces a list the
client silently truncates or mis-frames:

- **No count at all, size-driven.** `0x4398` enters its loop mid-body at `0xD410EC` — `u32 host
  ping`, then pairs until the payload runs out. `0x4982` is also size-driven but with
  **variable-length records**: bit 2 of the flag byte gates an extra 16-byte string, so a record
  is 35 or 51 bytes with no length prefix.
- **Count on the wire.** `0x43A4` re-reads its count from `r1+1480` at `0xD41A34`, caps it at 127,
  and takes 3 wire bytes per entry from a 12-byte source stride.
- **Count from client state.** Four of the `0x4Axx` lists take the entry count from the client's
  own state rather than the wire.
- **Index-addressed.** `0x4E11` leads each record with a u2 index and strides 52; a duplicate
  index **silently overwrites the earlier record while still bumping the count**. Worth a server
  WARN if we ever emit one.

### Client-side list caps

All of these are **hard aborts in the client**, not truncations. Traced from the ELF 2026-07-26 —
single-source, none of them confirmed by a capture.

| list | cap | note |
| --- | --- | --- |
| `0x2003` | **32 entries total across packets** (`0xD363FC`) | our 22-per-packet batching is policy and sits inside it, but **more than 32 lobbies breaks the client regardless of batching** |
| `0x200a` | 10 | |
| `0x4212` | 1000 | |
| `0x4124`, `0x4133` | 129 records | |
| `0x4125`, `0x4129` | 128 | |
| `0x4302` | 999 | the 18-per-packet figure elsewhere in this file is the `0x400` transport limit, not a client cap |
| `0x4582` | 32 | vs `0x4602`'s 100 — the two records are the same width and the caps are not. **Divergence found 2026-07-26**: `0x4583` drops any record whose u16 at wire `0x14` is zero (`0xD466D4`); `0x4603` does no such pass. Same layout, different survival rules — they are not interchangeable |
| `0x4602` | 100 | |

## Lobby types

`GameServerFactory` registers a different controller set per lobby type. The type is also what the
client keys its connection table on: three slots at stride `0x44`, types 0/1/2 only.

| type | id | controllers |
| --- | --- | --- |
| GATE | 0 | Common, Echo, Lobby, News |
| ACCOUNT | 1 | Common, Echo, Account, Character |
| GAME | 2 | Common, Echo, Account, CharacterConnect, GameList, Message, Hub, PersonalInfo, Host |

The client contacts them in the order gate → account → game. The account lobby is where a
character is chosen; the game lobby is entered with one already selected, which is why
check-session behaves differently in each (below).

---

# Common commands (every lobby)

`nomad.game.controller.CommonGameController`, plus the echo controller.

## `0x0001` — echo

**Client → server**, `EchoGameController.echo`. Not part of the real protocol; a smoke test for a
connection. The payload, whatever it is, is written straight back as `0x0001`.

## `0x0003` — disconnect

**Client → server**, `CommonGameController.disconnect`. Empty payload. No reply: the handler
flushes anything already queued and closes the channel.

Confirmed: the real client sends this after the gate's lobby-list exchange (`dev/docs/OBSERVED.md`,
"Protocol, confirmed working").

## `0x0005` — ping

**Client → server**, `CommonGameController.ping`. Reply is `0x0005` with an **empty** payload —
the request payload is not echoed. Reference-derived; not observed from our client.

**Settled from the ELF 2026-07-26** (single-source trace): the client's `0x0005` reply parser has
READ_BEGIN at `0xD35A24` and READ_END at `0xD35A30`, back to back — **the reply body is never
read**. Echoing the request would be harmless, and equally pointless. This retires the open
question at the end of this file about whether the empty reply is a divergence; it is not
observable to the client either way.

---

# GATE lobby

## `0x2005` — get lobby list

**Client → server**, `LobbyGameController.getLobbyList`. Request payload is empty and is not read.

Answered with three packet kinds:

| command | payload |
| --- | --- |
| `0x2002` | 4 bytes: `00000000` (result, `GameError.NONE`) |
| `0x2003` | 22 entries max per packet, `0x2e` bytes each |
| `0x2004` | 4 bytes: `00000000` |

One `0x2003` per batch of 22 (`ENTRIES_PER_PACKET`); with no lobbies, none at all.

**Cap, from the ELF 2026-07-26:** the client aborts above **32 entries counted across all
packets** (`0xD363FC`) — the 22-per-packet batching is our policy and sits inside that ceiling,
but a lobby table with more than 32 rows breaks the client however it is batched.

### `0x2003` entry — 46 (`0x2e`) wire bytes, 52 struct bytes

**Both numbers are right and they are about different things** (settled 2026-07-26). The wire
record is 46 bytes, as tabulated below and as this file has always said. The client's *struct* is
52 (`0x34`) bytes, which is the figure `LOBBIES.md` quotes and the stride the list was read back
at out of client memory. The struct is larger because the fixed-block reader `0xD5D018` writes
`r5+1` struct bytes for `r5` wire bytes (see "The packet-reader primitives"), so each of the two
NUL-padded strings costs an extra struct byte; the remaining slack is layout, not wire. Neither
document was wrong — each named a different quantity without saying which.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | list index, counting from 0 across all packets |
| `0x04` | 4 | u32 | lobby type: 0 gate, 1 account, 2 game |
| `0x08` | 16 | ISO-8859-1 | lobby name, NUL-padded |
| `0x18` | 15 | ISO-8859-1 | lobby IP as a dotted-quad string, NUL-padded |
| `0x27` | 2 | u16 | port |
| `0x29` | 2 | u16 | player count — players currently **in games** in that lobby, derived from `game_player`. Operator policy: idle lobby members are not counted (see BACKLOG) |
| `0x2b` | 2 | u16 | lobby id |
| `0x2d` | 1 | u8 | restriction bits: `0b1` beginners only, `0b1000` expansion required, `0b10000` no headshots |

**Confirmed end to end.** `dev/docs/OBSERVED.md` records this list being read back out of the client's
own memory at `ctx+0x75C` in `0x34`-byte strides with every field correct, and the client's own
`0x2002`/`0x2003`/`0x2004` parser arms traced. This is the only part of the protocol verified from
inside the client rather than from our logs.

One ordering rule, learned the hard way: **the list must be ordered by lobby id, not by name**, so
that list index and lobby type coincide (index 0 = gate, 1 = account, 2 = game). Whether the
client requires the identity is not proven, but ordering by name broke it in practice.

## `0x2008` — get news

**Client → server**, `NewsGameController.getNewsItems`. **The request is one u8, not empty** —
the builder at `0xD36888` calls the u8 writer (`bl 0xD5C86C` at `0xD36898`, into slot `0x0C`) and
then seals. Established from the ELF 2026-07-26. This file previously said only "request payload
is not read", which is true of *us* but reads as though the wire were empty; it is not. We
discard the byte and its meaning is unknown. No authentication check — the gate has no session
yet.

| command | payload |
| --- | --- |
| `0x2009` | 4 bytes: `00000000` — a **result code**, not a count |
| `0x200a` | one per news item, **trimmed to the item's real length** — see below |
| `0x200b` | 4 bytes: `00000000` — a result code |

`0x2009` (`0xD36504`) and `0x200b` (`0xD36710`) each read one u32 and signal it as an error if
nonzero; neither carries an item count. Zeros are correct.

### `0x200a` item

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x000` | 4 | u32 | news id |
| `0x004` | 1 | u8 | important flag (0/1) |
| `0x005` | 4 | u32 | timestamp, Unix seconds |
| `0x009` | **128, fixed** | ISO-8859-1 | title, NUL-padded. `0xD5D018` advances the cursor by exactly 128 whatever the content. |
| `0x089` | `len(body)` | ISO-8859-1 | body, **no padding** |
| `0x089+len` | 1 | u8 | **one NUL terminator — required** |

**The payload must be trimmed to `137 + len(body) + 1` and never padded.**

### The padding bug, and why "harmless" was wrong

This file used to say the body was NUL-padded to 886 bytes to make the payload total 1023, and
that this was "a documentation error, not a live bug" because "a NUL-padded body terminates at its
first NUL". The first half is right and the second half does not follow.

The parser at `0xD365C8` **loops inside a single packet**. Its termination test is `0xD5CEB0`,
which compares the read cursor against the *payload length* at `packet+4` and returns -1 only when
the cursor reaches it. So the client keeps parsing records until the packet is drained. The body
terminating at its first NUL does not consume the remaining padding — it hands the padding to the
next iteration.

A record with an empty body costs **138 bytes**: 137 fixed plus a lone terminator. Every padded
item therefore manufactured about six phantom entries with id 0, time 0 and an empty title.

[OBSERVED 2026-07-27] Two rows with bodies of 19 and 134 characters. Records start at cursor 0,
then every 138 bytes; the fixed-128 title read bounds at `pos <= 896` (`0xD5D03C`), which is what
ends each run:

| item | real record ends | phantom starts | last one that fits | entries |
| --- | --- | --- | --- | --- |
| body 19 | 157 | 157, 295, 433, 571, 709, 847 | 847 (title at 856) | **7** |
| body 134 | 272 | 272, 410, 548, 686, 824 | 824 (title at 833) | **6** |

13 entries, capped at the client's limit of 10, second real item at position **8**. The client
showed exactly 10 pages with real items on 1 and 8 — predicted to the page before the fix.

The same arithmetic settles two things this file had only assumed. The **title is genuinely a
fixed 128-byte field**: were it terminated like the body, a phantom would cost 11 bytes and there
would have been ~89 of them. And the **terminator is exactly one byte**.

### Two limits that are the client's, not ours

- **At most 10 items.** `cmpwi r3,9; bgt` at `0xD366D0` aborts the *entire reply* with `-71` on the
  eleventh. An eleventh row does not get dropped; it loses the whole news screen.
- **Body at most 774 bytes.** Each table entry is 920 bytes with the body at offset 145, so the
  destination holds 775 including the terminator. `0xD5CE34` bounds only its **source**
  (`pos+i <= 1023`) and never its destination, so a longer body **overruns a stack temporary in
  the client**. Our `news.body` column is `varchar(886)`, wider than the client can hold, so the
  server caps it.

The page total the screen shows is the record counter at `newsTable+4`, copied to the UI at
`0x93FE4C` (`stw r0,188(r3)`) — the same counter the 10-item cap tests.

## `0x2006` / `0x2007` — undocumented gate pair

**Undocumented everywhere until 2026-07-26** — absent from this file, `OBSERVED.md`, `LOBBIES.md`
and `COMMANDS.md`. Single-source ELF trace; never observed live, never handled by us.

`0x2007` is the reply half and is the part that is actually pinned: parser `0xD36498` reads **one
u32**, widens it to a u64 at `ctx+0xDD8`, and signals notify slot **11**.

The request half is **an open question, not a finding**. `0x2006` is the presumed pairing: it has
an empty payload, waits on slot `0x0B` (which matches `0x2007`'s notify slot), and its sender at
`0xD36900` is a near-clone of `0x2005`'s. That is circumstantial — no capture pairs them, and
nothing in the binary names the request from the reply. Treat "`0x2006` asks for `0x2007`" as a
conjecture worth one capture.

---

# ACCOUNT lobby

## `0x3003` — check session

**Client → server, payload Blowfish-encrypted.** `AccountGameController.checkSession`. Also
registered on the GAME lobby, where it behaves differently — see below.

### Request — 20 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | claimed id: the **account id** on an account lobby, the **character id** on a game lobby |
| `0x04` | 16 | bytes | session field derived from the login token |

Confirmed from the binary: the client builds this from `ctx+0x150` (the id) and `ctx+0x154` (the
16 bytes). The game-lobby sender at `0xD39F18` additionally appends a **trailing flag byte** taken
from `+0x294` of another object — we never read it, and its meaning is unknown.

The 16 bytes are not the login token. The client keeps the token as its 16 ASCII characters and
runs them through a crypto service at login; the result is what ships here. The transform is
`nomad.common.crypto.SessionField`:

```
context = 8-byte IV || 56-byte key       (56 = Blowfish's maximum key length)
C[i] = blowfish_decrypt(P[i]) XOR P[i-1],  P[-1] = IV
```

Note the block is *decrypted* and the XOR is against the previous **plaintext** block — neither ECB
nor CBC, which is why it resisted being guessed from captured pairs. Traced in `MGO2.elf` and
confirmed against a live client: the server applies the same forward transform to the token it
issued and compares, so nothing is inverted. Mode 6's key blob is zero in the image and
materialised at runtime; the schedule shipped as `crypto/session.key` was read out of a running
client.

### Reply `0x3004` — 4 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result |

`00000000` on success, `C0FFEE02` (`INVALID_SESSION`) otherwise. The client parses this as a single
s32 and ignores anything after it (confirmed from the binary).

Checks performed, in order: payload at least 20 bytes; some account holds the presented session;
and then, by lobby type —

- **ACCOUNT**: `account.id == claimedId`. On success the current character selection is **cleared**,
  because entering an account lobby means choosing one.
- **GAME**: `account.currentCharaId == claimedId`, with a null selection rejected. The selection is
  left alone.

The client maps this result straight onto an error screen. From the binary: `0` advances,
`-0xF0` → `0x924`, `-0x192` → `0xA50`, `-0x193`/`-0x194` → `0x933`, and **everything else** →
`0x925`. Our masked `C0FFEE02` is in "everything else", so a rejected session shows as `0x925`.

## `0x3048` — get character list

**Client → server**, `CharacterGameController.getCharacterList`. Request payload is not read.

Reply is `0x3049`, **always `0x1d7` = 471 bytes**, or 4 bytes carrying `C0FFEE02` if the connection
has not checked in.

The client (`0xD3732C`) parses a **fixed grid regardless of how many characters exist**:

```
s32 result; u8 slots; u8 count; u8 selectedSlot; u8 name[16];   23-byte header
8 entries x 52 bytes: u8 slot; u32 charaId; u8 name[16];
                      u8 appearance[9]; u32; u8 appearance[14]; u32
u8 tail[32]                                                     total 0x1d7
```

What we actually write:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result, `00000000` |
| `0x04` | 1 | u8 | character slots the account owns |
| `0x05` | 1 | u8 | number of characters that follow |
| `0x06` | 1 | u8 | **`selectedSlot`** — the slot of `account.current_chara_id` |
| `0x07` | 16 | ISO-8859-1 | the **selected** character's name; lands in the client's header `name[16]` |
| `0x17` | 52 | — | entry 0 (below) |
| `0x4b` | 52 | — | entry 1 — **uniform**, same shape as entry 0 |
| … | 52 | — | entries 2..7 |
| `0x1b7` | 32 | — | fixed tail |

Each entry is **uniform, 52 bytes**, with no per-entry variation:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| +0 | 1 | u8 | slot index |
| +1 | 4 | u32 | character id |
| +5 | 16 | ISO-8859-1 | name |
| +21 | 27 | — | appearance region (below) |
| +48 (`+0x30`) | 4 | u32 | **delete cooldown in seconds** |

**Corrected 2026-07-27 — two errors that cancelled.** This section previously described the writer
as introducing the first entry with its name and every later one with a 4-byte index, reconciling
the two shapes on the observation that an index `00 00 00 nn` has three leading zeros that complete
the previous entry's trailing u32. That reading was wrong, and it survived because a second error
compensated for it: the appearance block was written as 28 bytes where the layout has 31 (27
appearance bytes plus the 4-byte cooldown, of which the old block wrote one pad byte). The two
cancelled to exactly 52 bytes **for a single-character account** and stopped cancelling the moment
a second character existed, at which point every entry after the first ran three bytes long and the
character-select screen was corrupt. The entries are uniform; there is no index form.

**`selectedSlot` is load-bearing** (live 2026-07-27). It was hardcoded to 0 with the first
character's name beside it. The client sends `0x3103` with the slot it picked, we record it, and
then the client **re-fetches this list and takes its selection back from this header** — so a zero
here quietly undid every choice, and picking the second character entered the lobby as the first.
This is the same shape of bug as the entry-size error above: every field in a single-entry list
looks right whether or not it means what we think it means.

### The trailing `u32` at `+0x30` — the delete cooldown

**Not part of the appearance block** (corrected 2026-07-27; this file previously filed it there,
and the `0x3049` spec had it as "read but never identified; we send zero"). It is the
**per-character delete cooldown in seconds**: how long until this character may be deleted.

The client reads it at wire `+0x30` of each entry (parser `0xD372F8`, stored to
`sess+0x55D4 + 60*slot + 56`) and the character-management screen formats it itself at `0x9510B4` —
non-zero rounds up to whole minutes and produces *"Characters cannot be deleted for a fixed amount
of time after being registered. You must wait %d hours %d minutes"* (lobby strings 11848 / 11854);
zero lets the deletion proceed.

It is the **one cooldown of the three** this build can actually display. The clan-disband and
emblem-re-display countdowns are orphaned strings the client cannot reach (see the clan section and
`ERRORS.md`).

### Character slots — operator policy, not protocol

The `slots` byte defaults to **1**, bounded 1..4 by a database constraint. The packet has room for
8 and would carry more without complaint, so nothing here is fixed by the game; retail sold the
extra slots, and three was an inherited default from another server. Grant per account with an
`UPDATE`; it is read on every list fetch.

### Appearance region as written here — 27 bytes

| offset | size | field |
| --- | --- | --- |
| +0 | 1 | gender |
| +1 | 1 | face |
| +2 | 1 | upper |
| +3 | 1 | lower |
| +4 | 1 | face paint |
| +5 | 1 | upper colour |
| +6 | 1 | lower colour |
| +7 | 1 | voice |
| +8 | 1 | pitch |
| +9 | 4 | zero, purpose unknown |
| +13 | 1 | head |
| +14 | 1 | chest |
| +15 | 1 | hands |
| +16 | 1 | waist |
| +17 | 1 | feet |
| +18 | 1 | accessory 1 |
| +19 | 1 | accessory 2 |
| +20 | 1 | head colour |
| +21 | 1 | chest colour |
| +22 | 1 | hands colour |
| +23 | 1 | waist colour |
| +24 | 1 | feet colour |
| +25 | 1 | accessory 1 colour |
| +26 | 1 | accessory 2 colour |

The delete cooldown `u32` follows immediately, at entry `+48`.

The main character is listed first and its name is prefixed with `*`. Ordering is
`CharacterService.listForAccount`: by id, with the main character moved to the front.

### The 32-byte tail (written as a 35-byte trailer)

**It is not a 35-byte read** (ELF 2026-07-26, single-source trace). The client's parser takes a
**32-byte block plus three separate u8 fields**; 35 is the number of bytes *we write* after the
eighth entry, not the width of any structure in the binary. Worth knowing only so that nobody
goes looking for a 35-byte field — there isn't one.

```
00 00 00 00 07 00 03 00  00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
00 00 00
```

**Unknown.** The `07` and `03` are non-zero and nobody knows why; both Nomad upstreams and
mgo2-server send these exact bytes, which per `CLAUDE.md` makes them tier 4 — a thing we copy, not
a thing we understand. The client's `tail[32]` begins at `0x1b7`, so within that block they sit at
`+1` and `+3`.

This was 32 bytes here until recently, making the payload 468 — the client would have read its last
three tail bytes out of stale buffer contents, because its read primitives bound-check only the
`0x400` receive buffer and never compare consumed bytes against the payload length.

**Resolved 2026-07-29, from the parser side.** `0xD3732C` copies exactly **32** bytes
(`li r5,32` at `0xD3774C`) to `ctx+22452`, independently confirming the 32-byte reading. And the
trailer is not inert: **index 3 bit 0 unlocks the 32 CODEC / preset messages.** (An earlier trace
read these as "32 of the 91 selectable loadout items" — disproved live 2026-07-29: clearing the
bit removed codec messages and left gear and outfits entirely unchanged. Almost certainly the
day-one paid "MGO Codec Pack", 32 additional voice tracks.) Readers
`0x9B9E30` (`(byte & 1) << 4`) and `0x9BADA4` (`byte & 1`) feed the availability predicate
`0x9B9DF0`, which walks an 85-entry table at `0xE1812C` and refuses any item whose gate exceeds the
threshold; 32 entries gate on exactly 16, 23 gate on 0, 27 defer to an ownership check. Bit 1 of that
byte, the `0x07` at index 1, and indices 0, 2 and 4..31 all have **no reader**.

**Prior loose end (2026-07-27).** The writer still zero-fills to `0x1b4` and then emits 35 bytes, which
is a leftover from the misaligned-entry era. Now that entries are uniform, eight of them end at
`0x1b7` and the tail is 32 bytes. The two forms produce byte-identical output only because the
first three trailer bytes are zero, and only while an account holds **fewer than eight**
characters — at eight the zero-fill length goes negative. Slots are capped at 4, so it cannot fire
today; it is still the wrong framing and should become `0x1b7` + 32.

## `0x3101` — create character

**Client → server**, `CharacterGameController.createCharacter`.

### Request

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 16 | ISO-8859-1 | name, NUL-terminated within the field |
| `0x10` | 27 | — | appearance, read by `readAppearance` (below) |

Confirmed from the binary as "16 name bytes then the appearance bytes". **The payload is exactly
43 bytes** (ELF 2026-07-26, single-source trace) — 16 name + 27 appearance, with no trailing
field. This retires the "the exact appearance length the client sends is not confirmed" caveat
that stood here; we require at least 27 readable appearance bytes and read exactly 27, which is
all of them.

### `readAppearance` — what we actually store

| offset | size | field |
| --- | --- | --- |
| +0 | 1 | gender |
| +1 | 1 | face |
| +2 | 1 | upper |
| +3 | 1 | lower |
| +4 | 1 | face paint |
| +5 | 1 | upper colour |
| +6 | 1 | lower colour |
| +7 | 1 | voice |
| +8 | 1 | pitch |
| +9 | 4 | **a single u32, skipped; purpose unknown** |
| +13 | 1 | head |
| +14 | 1 | chest |
| +15 | 1 | hands |
| +16 | 1 | waist |
| +17 | 1 | feet |
| +18 | 1 | accessory 1 |
| +19 | 1 | accessory 2 |
| +20 | 1 | head colour |
| +21 | 1 | chest colour |
| +22 | 1 | hands colour |
| +23 | 1 | waist colour |
| +24 | 1 | feet colour |
| +25 | 1 | accessory 1 colour |
| +26 | 1 | accessory 2 colour |

**Resolved — this was a real bug, now fixed.** Offsets +3 and +22 were skipped for years on an
inherited comment claiming the original server discarded them, so `lower` and `hands_color` were
stored as 0 for every character ever created. That claim was wrong.

`0x4130` carries the same fields in the same order and names them: the byte after `upper` is
`lower`, and the byte after `chest colour` is `hands colour`. Confirmed against a live client — a
character created with `lower = 0` gained a real value the instant `0x4130` was implemented and the
player changed clothes in the lobby. Both are now read at creation.

The four bytes at +9 remain **skipped, purpose unknown** — but they are now known to be **one u32,
not four bytes** (ELF 2026-07-26, single-source trace): the sender emits them with a single
`bl 0xD5C9BC` from a 4-aligned `src+0x1C`. They sit where the write path emits four zero bytes, so
nothing is known to be lost, but nothing confirms that either.

### Reply `0x3102`

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result |
| `0x04` | 4 | u32 | new character id — **the client ignores it** (confirmed from the binary) |

8 bytes on success; 4 bytes carrying only the error code otherwise. Errors: `C0FFEE02` no session,
`C0FFEE01` short payload, `C0FFEE10/11/12` name invalid / reserved prefix / reserved name, and
`FFFFFEFC` (decimal −260, sent **unmasked**) for a name already taken.

Name validation is `nomad.common.CharacterNames`. The same check backs `0x3107`, deliberately: a
pre-check more lenient than the create behind it would only move the failure one screen later.

## `0x3103` — select character

**Client → server**, `CharacterGameController.selectCharacter`.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 1 | u8 | **slot index** into the list last sent by `0x3049` — *not* a character id |

**It is a slot, one byte** (confirmed live 2026-07-27). The client bounds-checks the index ≤ 7
before sending (confirmed from the binary). We clamp an out-of-range index to **0**. Reply `0x3104`
is 4 bytes: `00000000`, `C0FFEE02` (no session) or `C0FFEE20` (the account has no characters).

The selection this records is then read back **through `0x3049`'s `selectedSlot` header field**, not
held only on the server — see `0x3048` above. The two commands are one loop, and a server that
records the slot but reports 0 in the next list is indistinguishable from one that ignored the
selection entirely.

**Check-in validates ownership, not equality** (live 2026-07-27). Creating a character and then
entering the lobby as a *different* one failed with `0925:C0FFEE02` — our own `INVALID_SESSION`,
masked — because creation points `account.current_chara_id` at the new character and check-in
demanded the client's claim equal that pointer. The client is what decides which character is
entering; the server's job is to confirm it **exists, belongs to this account, and is active**, and
then adopt it as the current selection. A leaked token is no more useful than before: it still
cannot name a character it does not own.

## `0x3105` — delete character

**Client → server**, `CharacterGameController.deleteCharacter`. Same one-byte request as `0x3103`.

Reply `0x3106` is 4 bytes: `00000000`, `C0FFEE02`, `C0FFEE20`, or `C0FFEE14` if the character is
too young to delete (`CharacterService.canDelete`).

Note the asymmetry with select: an out-of-range index clamps to the **last** character here, not
the first. The comment says this matches the original; unverified.

## `0x3107` — check character name

**Client → server**, `CharacterGameController.checkCharacterName`. Name availability, asked before
the client will offer a name for creation.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 16 | ISO-8859-1 | candidate name |

Confirmed from the binary as 16 bytes of name.

**This is not optional, however it may look.** savemgo's Nomad names it only in a commented-out
case and ships without it. Our client blocks on the reply: with nothing sent back it waits about
forty seconds, never sends `0x3101`, and fails with **`0A41:FFFFFF60`**.

### Reply `0x3108` — 4 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result — `00000000`, or the same rejection codes `0x3102` uses |

**The flag is retired — the guess was right** (ELF 2026-07-26, single-source trace). The parser
exists at `0xD37154`: a single u32, notify slot 18. Until then this file flagged twice that the
shape "was never disassembled — it is a guess", inferred from the sibling result packets
(`0x3004`, `0x3102`, `0x3104`, `0x3106`) and from the request-status arm marking id `0x12`
complete. The inference happened to be correct; it is now read rather than assumed.

---

# GAME lobby

`0x3003` is registered here too — see the ACCOUNT section; the only difference is that the claimed
id is a character id and the selection is not cleared.

## `0x4100` — character connect

**Client → server**, `CharacterConnectController.connect`. Empty payload.

This is the burst: one request, nine packets back. Sent in this order:

| # | command | payload |
| --- | --- | --- |
| 1 | `0x4101` | character info, `0x142` bytes |
| 2 | `0x4120` | gameplay and interface settings, `0x150` bytes |
| 3 | `0x4121` | chat macros, type 0 — 769 bytes |
| 4 | `0x4121` | chat macros, type 1 — 769 bytes |
| 5 | `0x4122` | personal info, `0xf5` bytes |
| 6 | `0x4124` | gear catalogue, 651 bytes |
| 7 | `0x4125` | skill catalogue, 104 bytes |
| 8 | `0x4140` | three skill sets, 231 bytes |
| 9 | `0x4142` | three gear sets, 261 bytes |

If the connection has no account or no selected character, a **4-byte** `0x4101` carrying
`C0FFEE02` or `C0FFEE20` is sent instead of the whole burst. **Flagged**: `0x4101` has no result
field — a 4-byte payload puts an error code where the character id goes, and the client's read
primitives do not compare consumed bytes against the payload length, so it will read the rest of
the grid out of stale buffer. What the client actually does with that has not been checked.

**Divergences from mgo2-server, deliberate:**

- mgo2-server sends **seven** packets — `0x4101, 0x4120, 0x4121, 0x4122, 0x4125, 0x4140, 0x4142` —
  with a single `0x4121` and **no `0x4124`** at all. We send `0x4124` and two `0x4121`s.
- echo-upstream sends the same nine we do, including `0x4124` and two `0x4121`s of `0x301` bytes
  each. Where the two references disagree we followed echo.
- `0x4101` is `0x142` here where mgo2-server sends `0x243` — see below.

Confirmed: state 3 of the client's `0x946F00` machine sends `0x4100` with request-status id `0x15`
and state 4 waits for it with error `0x1037:FFFFFF60` on timeout. So the burst is required. The
individual burst payload **layouts** are still unverified against the client's parsers.

**`0x4125` is the burst's terminal packet, and the order is therefore load-bearing** (ELF
2026-07-26, single-source trace). It alone fires `notify(21)` at `0xD3CDF0` — slot `0x15`, the one
`0x4100` blocks on. `0x4101`, `0x4120`, `0x4121`, `0x4122` and `0x4124` notify nothing at all.
Moving `0x4125` earlier in the burst would release the client's wait before the remaining packets
were parsed, which is a race nobody would find by reading the sending code.

### `0x4101` — character info, `0x142` = 322 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x000` | 4 | u32 | character id |
| `0x004` | 16 | ISO-8859-1 | character name |
| `0x014` | 8 | 4 × u16 | **unknown**: `0x16AE, 0x0338, 0x013E, 0x0150` — fixed constants, reproduced from the original byte for byte |
| `0x01c` | 4 | u32 | experience (account's main exp if this is the main character, else alt exp) |
| `0x020` | 4 | u32 | previous login, Unix seconds — we send `now - 1` |
| `0x024` | 4 | u32 | current login, Unix seconds |
| `0x028` | 1 | u8 | zero, purpose unknown |
| `0x029` | 128 | 32 × u32 | friend ids — always zero; friends are not modelled |
| `0x0a9` | 128 | 32 × u32 | blocked ids — always zero |
| `0x129` | 25 | — | tail: u8, 16 bytes, two u32s per the client's parser. Always zero |

**The `0x142` size is a deliberate divergence.** The client's parser at `0xD3C120` consumes a fixed
`0x142`-byte grid and never reads past it. Every reference server sends `0x243` with 256-byte
friend and blocked regions — under which the client's "blocked list" was actually friend ids 33–64
and its tail came out of the blocked region, which happened to be zeros. Ours matches the parser.

### `0x4120` — gameplay settings, `0x150` = 336 bytes

`GameplaySettingsWriter`. Almost every setting shares a byte, and several are stored one higher
than they go on the wire.

| offset | size | contents |
| --- | --- | --- |
| `0x00` | 1 | privacy A: bit 0 = **"settings already initialised" — LOAD-BEARING, must be 1** (see note below), bits 4–5 online-status mode, bit 6 email-friends-only |
| `0x01` | 1 | normal view: bit 0 invert Y, bit 1 invert X, bits 4–7 speed (**stored 1-based, sent 0-based**) |
| `0x02` | 1 | shoulder view, same packing |
| `0x03` | 1 | first-person view: bit 0 invert Y, bit 1 invert X, bit 2 player direction, bits 4–7 speed |
| `0x04` | 1 | view-change speed, 0-based |
| `0x05` | 6 | zero, purpose unknown |
| `0x0b` | 1 | switch modes: low nibble weapon, high nibble item |
| `0x0c` | 1 | zero, purpose unknown |
| `0x0d` | 1 | voice chat A: bit 0 always **1** (unknown why), bits 4–7 recognition level |
| `0x0e` | 1 | voice chat B: low nibble chat volume, high nibble headset volume |
| `0x0f` | 1 | weapon switch: low nibble A, high nibble B |
| `0x10` | 1 | weapon switch C, low nibble |
| `0x11` | 1 | weapon recall: low nibble "before", high nibble "now" |
| `0x12` | 1 | first-view memory: bit 1 |
| `0x13` | 1 | privacy B: bit 0 receive notices, bit 4 receive invites |
| `0x14` | 1 | bit 0 lock-on enabled, bits 4–7 BGM volume **+1** — *the BGM half is disputed, see below* |
| `0x15` | 1 | radar: bit 0 lock north, bit 4 hide floor — *disputed, see below* |
| `0x16` | 1 | HUD: bits 0–1 display size, bit 4 hide name tags — *disputed, see below* |
| `0x17` | 9 | zero, purpose unknown |
| `0x20` | 16 | codec entries 1–4, four bytes each — **each byte is a 1-based message id, 0 = unset** |
| `0x30` | 256 | four codec names, 64 bytes each, ISO-8859-1 |

**Byte `0x00` bit 0 is an "already initialised" marker and sending 0 discards this whole packet.**
[ELF 2026-07-30] `0x9472CC` does `clrldi. r0,r3,63` / `bne 0x94753C`: if the bit is **clear**, the
client memsets the 33 list-preference bytes and overwrites roughly thirty settings with hardcoded
defaults the first time the options screen is entered. So the long-standing "always 1 (unknown why)"
was load-bearing — it is not a constant we happen to send, it is the flag that tells the client our
settings are real.

**The codec entry bytes are message ids.** Each is 1-based with 0 meaning unset: the screen does
`addi r31,r3,-1` and validates through `0x9B9DF0`, which searches an **82-entry, 6-byte table at
`0xE1812C`** of `{u16 id, u16 gate, u16 str}`. Thirty-two of those rows are gated on `0x3049`
trailer byte 3 bit 0 — the paid Codec Pack — which is the same 32 messages `AWARDS.md` and the
entitlement migrations already track. The 4×4 grouping is read from the client (four slots, each
fetching its own 64-byte name before its four indices), not assumed from the layout.

**Bytes `0x14` bits 4–7, `0x15` and `0x16` are disputed** [flagged 2026-07-30, not resolved]. The
accessor family `0x906xxx` is contiguous and stops at byte `0x14`'s **low** nibble; there is no
accessor for byte `0x14` high, `0x15` or `0x16`, and no direct load or store at the corresponding
`profile+4956/4957/4958`. Because `0x4110` echoes the raw 48 bytes back, **a live slider test cannot
settle this** — the values round-trip whether or not the client reads them. Needs an argued check of
its own. Two further gaps found at the same time: byte `0x0d` has **three** accessors (bits 0–1,
2–3, 4–7) where this table lists two fields, and byte `0x10` has a **high**-nibble accessor
(`0x90681C`, called three times) where this table says low nibble only.
| `0x130` | 32 | **list preferences** — filter / sort / search, sixteen 4-bit fields in bytes 0-7 (below) |

Trailer:

```
01 00 10 00 00 00 00 10  11 10 00 00 00 00 00 00
00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
```

Undocumented; reproduced from the original byte for byte. The off-by-one adjustments above are the
reason this is a separate tested class — a wrong one moves a slider by one notch and nothing ever
fails visibly.

### `0x4121` — chat macros, 769 bytes each, two packets

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 1 | u8 | macro type: 0 or 1 |
| `0x01` | 768 | 12 × 64 | macro text, ISO-8859-1, 64 bytes each |

`CharacterService.getChatMacros` materialises the full 2 × 12 grid, so the length is fixed even for
a character that has never set one. What the two types mean (echo calls them only "type") is not
documented anywhere we have.

### `0x4122` — personal info, `0xf5` = 245 bytes

`PersonalInfoWriter`.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | **clan id** — the character's real clan since 2026-07-27, 0 when they are in none |
| `0x04` | 16 | ISO-8859-1 | **clan name** |
| `0x14` | 1 | u8 | **clan membership state** -> `profile+6837`: 0 pending, 1 member, 2 leader, **99 not in a clan**. The client writes these itself (`li r0,99; stb r0,6837` at `0xD56B44`/`0xD56C7C`/`0xD56D68`); readers test `state-1 <= 1`. We send the character's real state |
| `0x15` | 24 | u16 × 12 | element 0 = the **clan privilege / notification word** -> `profile+6838` (bit 0 tested at `0x8F9944`, bit 8 at `0xAB3480`). Elements 1–11 have no reader in the binary. **All zero, and it must stay that way** — see the clan section |
| `0x2d` | 4 | u32 | current time, Unix seconds |
| `0x31` | 9 | — | appearance bytes 0–8 (gender … pitch), same order as `0x3049` |
| `0x3a` | 4 | u32 | appearance struct +12. Written by `0x4103`/`0x4122`, **read by nothing**, and omitted from `0x4130`/`0x4131`. Meaning unknown; inert. Send 0 |
| `0x3e` | 14 | — | appearance bytes head … accessory-2 colour |
| `0x4c` | 5 | 5 × u8 | equipped skills 1–**5** |
| `0x51` | 5 | 5 × u8 | equipped skill levels 1–**5** |
| `0x56` | 20 | 5 × u32 | per-skill experience for the equipped slots, from `chara_skill`. The old fixed `0x600000` was `0x6000 << 8`, 256x the client's legal maximum of 24576. Skill progression **does exist**: see `0x43a4` |
| `0x6a` | 1 | u8 | appearance struct +60. Meaning unknown, but **round-tripped**: `0x4130` sends it back (`0xD3BD88`) and `0x4131` reads it (`0xD3C6AC`). Send 0 — and preserve whatever came back |
| `0x6b` | 4 | u32 | character id again — "the original sends the character id here; its purpose is not documented" |
| `0x6f` | 128 | ISO-8859-1 | comment |
| `0xef` | 1 | u8 | **worn title (animal rank), 1-based, 0 = none** — the badge on the in-game scorecard. Corrected 2026-07-28; was labelled "rank" and we sent `chara.rank`, which is dead. See below |

### The worn title at `0xef`, and why the scorecard was blank

**Confirmed live 2026-07-28**: with this byte carrying the worn title, the animal-rank badge appears
on the in-game scorecard. It had never appeared while the byte carried `chara.rank`, which is dead.
The chain below is therefore observed end to end, not merely traced.

**This byte is the animal-rank index, not a separate "rank" quantity.** Traced end to end
2026-07-28:

1. Parser `0xD3D078` stores it to **charBlock + `0x1EA5`** (`0xD3D5EC`), the *local* character record
   at `ctx + 0x57D8`.
2. `0x88407C` copies it into the **P2P player-announce struct at +3** (`0x8842A4`), immediately
   beside the clan emblem flag (+4) and clan id (+8) — which is why the badge renders directly left
   of the emblem on a scorecard row.
3. `0x2762A0` publishes that as **`RecordSet(record slot+1, key 358, len 1)`** into the per-slot
   player blob (see [CLIENT_STORE.md](CLIENT_STORE.md)); peers receive it at `0x2780E4`.
4. The scorecard's sprite reader `0x9BFA68` resolves `title_32_01_alp` … `title_32_22_alp` from it,
   and `0x9BF618` resolves the title text.

**Values must be 1..22.** The readers' match loop runs 21 iterations over a 22-entry table, so 0 is
"none" and anything above 22 falls through with no sprite drawn.

**`0x4129` writes the same slot.** Its parser `0xD3C9A8` stores its first payload byte to
charBlock + `0x1EA5` at `0xD3CA30`. So the post-round reply must carry the same value — sending
`rank` there resets the badge to nothing after the first match, which presents as a different bug
entirely.

**Why Personal Stats worked while the scorecard did not:** `0x4103` and `0x4221` write their own
`+0x1EA5` into a *scratch* block (`*(ctx+0x11904)`), not the local character record. Only the local
one is published to peers. Two blocks, two screens, one of them wrong.

## `0x4130` — update personal info

**Client → server**, `PersonalInfoController.updatePersonalInfo`. Sent when the player changes
clothes or edits their comment.

The client blocks on the reply: with nothing sent back it stalls and fails with
**`1031:FFFFFF60`**.

### Request — exactly 158 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 19 | 19 × u8 | upper, lower, face paint, upper colour, lower colour, head, chest, hands, waist, feet, accessory 1, accessory 2, head colour, chest colour, hands colour, waist colour, feet colour, accessory 1 colour, accessory 2 colour |
| `0x13` | 5 | 5 × u8 | skills 1–**5** |
| `0x18` | 5 | 5 × u8 | skill levels 1–**5** |
| `0x1d` | 1 | u8 | skipped, purpose unknown |
| `0x1e` | 128 | ISO-8859-1 | comment |

**Corrected 2026-07-26** (ELF, single-source trace): the skill and level arrays are **five**
elements each, read by two 5-iteration loops over `src+30..34` and `src+35..39`. This file
previously wrote them as four-plus-padding — one skipped byte at `0x17` and two at `0x1c`. Total
width is unchanged at 158 bytes and the comment still starts at `0x1e`; only the names moved.

Only the appearance and the comment are persisted; the skills and levels are read and echoed back
but not stored. **Note this request carries `lower` and `hands_color`, which `0x3101` skips** — the
strongest evidence that the creation-time skip is wrong.

### Reply `0x4131` — 182 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result, zero |
| `0x04` | 19 | — | the 19 clothing bytes, echoed |
| `0x17` | 5 | 5 × u8 | skills 1–**5**, echoed |
| `0x1c` | 5 | 5 × u8 | skill levels 1–**5**, echoed |
| `0x21` | 20 | 5 × u32 | per-skill experience for the equipped slots, from `chara_skill`, through the same floor-and-clamp helper `0x4122` uses. Was a fixed `0x600000` until 2026-07-29 |
| `0x35` | 1 | u8 | zero, purpose unknown |
| `0x36` | 128 | ISO-8859-1 | comment, echoed |

**Two corrections, both 2026-07-26, both from the ELF (single-source trace).**

- **Five skill slots, not four.** The parser's loops are bounded `cmpdi 5` at `0xD3C644`,
  `0xD3C66C` and `0xD3C694`. The old "4 skills / zero / 4 levels / zero / 4 × u32 / 5 zero"
  reading covered the same 31 bytes with the padding in the wrong places — wire unchanged, names
  wrong. Same mistake and same fix as `0x4122`.
- **The payload is 182 bytes (`0xb6`), not 186 — and since 2026-07-29 that is what we send.**
  The parser goes straight from the 128-byte comment (`0xD3C6E0`) to READ_END (`0xD3C6F4`). The
  trailing `0xffffffff` at `0xb6`, long documented here as a face-paint colour unlock mask, was
  never read at all: no instruction in the text span touches the struct slots it would occupy.
  **The label was impossible, not merely unevidenced** — face paint is a single byte at struct
  `+4`, so a one-bit-per-colour mask has no colour axis. Removing it was previously called
  "untested"; it is now safe on evidence, since READ_END does no length check and the readers bound
  against the 1024-byte receive buffer rather than the payload — the parser never knew the packet's
  length either way. Colour unlocks travel as the
  `{item_id, bit_index}` pairs in `0x4124`/`0x4133`, not as a mask.

The client wants its own values back rather than a bare result code, which is why this is not a
four-byte reply like its neighbours. Errors are 4 bytes (`C0FFEE02`, `C0FFEE01`).

## `0x4110` — update gameplay options

**Client → server**, `HostGameController.updateSettings` (the constant name predates the
identity being settled). The write-back half of `0x4120`: first observed live 2026-07-22 as a
**304-byte** push — the `0x4120` layout minus its 32-byte trailer — sent by a *joiner* in one
burst with two `0x4114`s when saving options. The body is acknowledged (`0x4111 {u32 0}`,
required) and, **since 2026-07-29, parsed into `chara_settings`** — so option edits persist. Until
then it was acked and discarded, which is why Lock-On and every other Gameplay Option reverted after
each session; `0x4120` had always sent the stored row correctly, so the round trip was broken on
exactly one side. The layout is `0x4120`'s own, already documented above, and the reader
(`GameplaySettingsReader`) is the writer inverted — the two must change together. An earlier theory
that this command carried the Common Settings toggles in a 48-byte rules header was wrong — see
OBSERVED.md.

**The 304 is now derivable from the binary, not just observed** (ELF 2026-07-26): the sender emits
one 48-byte block and then four 64-byte blocks — a loop bounded `cmpwi r28,3` at `0xD3BFF8` with
`r5 = 48` on the first pass and `r5 = 64` on the rest. 48 + 4×64 = **304** = `0x4120[0:0x130]`,
exactly the live capture. Two independent sources now agree, which is worth more than either.

## `0x4114` — update chat macros

**Client → server**, `CharacterConnectController.updateChatMacros`. The write-back half of
`0x4121`, first observed live 2026-07-22 (two packets, one per macro type, in the options-save
burst): `u8 type`, then twelve 64-byte ISO-8859-1 texts — the exact `0x4121` layout. Persisted
into `chara_chat_macro`, so macro edits survive sessions. Reply `0x4115 {u32 0}` — **shape
inferred from the sibling result packets, not read from the binary**; the client observably does
not stall on it. Notably the client fires `0x4110` + both `0x4114`s in a single burst without
waiting between them.

**Why it cannot stall now has a tier-1 cause** (ELF 2026-07-26, single-source trace): `0x4114`
**registers no wait slot at all** — there is no `li r4,<slot>` / `bl 0xD32E08` pair after the
flush. It is fire-and-forget by construction, so `0x4115` has nothing to answer and no timeout to
trip. "The client observably does not stall on it" was an observation about one session; this is
the reason.

## `0x4112` — connect-family write-back, contents unknown

**Client → server.** 32 opaque bytes, and — unlike its neighbour `0x4114` — **the client blocks on
it**: it registers wait slot `0x18` (`li r4,24` at `0xD3BEDC`). Observed live 2026-07-27 right
after a player search; unanswered, the screen stalls in the usual way.

Reply `0x4113` is a bare `{u32 result}`, so the command is acknowledged and the body dropped.

The 32-byte payload observed live was:

```
0000 1000 0000 0000 1110 0000 0000 0000 0000
```

**Contents [UNKNOWN].** Whatever setting those bytes carry will not persist until someone works out
what they are; answering it only stops the stall. It sits in the connect family beside `0x4110`
(gameplay options) and `0x4114` (chat macros), both of which are write-backs of a burst packet, so
a third write-back is the obvious reading — but nothing has been traced to say which one.

## `0x4102` — get personal stats

**Client → server**, `PersonalStatsController`. First observed live 2026-07-23 (the personal-stats
screen; stalled unanswered), then traced in full from the binary the same day. Payload: one u32
character id — the viewer's own (pulled from the connect-burst record) or, in principle, any id.
Sender `0xD3BA3C` (single build site `0xd3bab0`), wait slot `0x16`.

The reply is a **three-packet burst into one struct**, all keyed to slot `0x16`; there are no
`0x4104`/`0x4106` requests (no builders exist — `0x4105`/`0x4107` only ever arrive as part of this
burst):

| command | parser | size | role |
| --- | --- | --- | --- |
| `0x4103` | `0xd3e9ac` | `0x288` = 648 | status u32, then character info, comment, ratings |
| `0x4105` | `0xd3e53c` | `0x248` = 584 | status u32, **page u32 (must be 0 or 1)**, then the per-mode stat grid: 8 modes × 18 u32, mode-major |
| `0x4107` | `0xd3db1c` | `0x24C` = 588 | status u32, then two 73-u32 records; **terminal** — sets slot `0x16` complete (`0xd3e4b0`), so it must be sent last |

**Byte-exact, machine-checkable layouts for all three replies live in `dev/proto/*.ksy`**
(Kaitai Struct; compiles clean, every byte assigned, per-field confidence tags). The prose
below is the summary; the `.ksy` files are the canonical field-level truth.

`0x4103` opens with a real status code: nonzero error-completes the slot and skips the body
(`0xd3ea38`), so a bad id is answered with a 4-byte `0x4103` alone. Head (wire order): u32 status,
u32 char id, 16-byte name, the `0x4101` constant block (4×u16), u32 experience, 2×u32 login
times, u8, 32×u32 friend ids, 32×u32 blocked ids (both confirmed flat id arrays from the parser
loops, not stats) — 301 bytes. The 347-byte tail is a **flat, packed field sequence** (no tables,
no conditional layouts; full second trace 2026-07-23), in wire order:

u8 · u32 · 16-byte string · u8 · 12×u16 · u32 · 9×u8 · u32 · 14×u8 · 10×u8 · 5×u32 · u8 · u32 ·
**128-byte comment** (wire offset 413, `T+0x1E24` — confirmed live by fingerprint) · u8 · 9×u8 ·
9×u32 (the block the stats screen reads at `T+0x32D0`) · u32 (stored to `obj+0x30`, not the
struct) · 16-byte string · u32 · u32 · 16-byte string · u8 · 3×u32 · u32.

Semantic labels for the tail integers (Host Rating, Instructor Score, "generation", etc.) are
positioned but not yet named — that needs an aligned capture; the live fingerprint session
(OBSERVED.md) is working through them.

**`0x4105`'s second u32 is a page selector, not a count: any value > 1 makes the parser bail
(error −0x47) and skip the whole matrix.** Page 0 zeroes then fills the grid region; the wire
carries 8 modes (the parser's 12-slot mode loop skips indices 6/8/9/10) × 18 u32 stats each.
This matrix — not `0x4103` — is what the per-mode grids on the stats screen render (reader
cluster `0x9193BC`+, striding `0x48`/mode and `0x360`/page). Capture-proven map (fingerprint v5,
OBSERVED.md): modes in wire order are Deathmatch, Team Deathmatch, Rescue, Capture, Sneaking,
Base, a hidden seventh included in the client's computed totals (no page of its own — plausibly
a slot reserved for a mode that never shipped; identity parked, not pursued — **serve zeros** so
the visible pages account for every Total), and an unused eighth; columns:
0/1/4/5 the OTHER-derivation minuends (below), 2 Lockon Kills, 3 Score, 6–9 HS
Kills/Deaths/Stuns/Stuns-Received, 10 Lockon Stuns, 11 Lockon Deaths, 12 Lockon Stuns-Received,
14 Rounds, 16 Wins, 17 Play-time-seconds; 13 and 15 are unmapped (markers surfaced nowhere).
Columns 0/1/4/5 have exactly one proven role: the client renders each category's OTHER row as
that column − HS − lockon, clamped at 0, and never renders the column itself (v6+v8 probes). A
server wanting OTHER to show x must therefore send x + HS + lockon; whether the original server
semantically treated the column as a "total" is unknown, and the specs deliberately name these
`*_minuend` rather than assert a meaning. The Total page, the header time and title/award unlocks are likewise
computed client-side. Page 0 is cumulative and page 1 is weekly — the stats screen's
cumulative/weekly toggle switches page, paired with `0x4107` record 1 (cumulative) / record 2
(weekly), which share one slot layout (capture-proven). Send both pages and both records.

Title *history* and award *history* on the same screen are **not** fed by this burst, by any
command, or by the record tables earlier suspected (`T+0x26d14` and `T+0x3330` turned out to be
match-history list storage for `0x4682`/`0x4212` records).

> **CORRECTED 2026-07-28: the medals and titles THEMSELVES are server-driven, and this section
> previously said the opposite.** It claimed they were "computed client-side from the stat values …
> the server's only job is honest stats". That is false and it cost real confusion — a live
> character showed "500 Mk.II destructions" against zero Mk.II kills and kept the award after every
> stat was zeroed.
>
> **Medals are gated ONLY by a 16-byte bitfield at `0x4103` wire 615.** `0x916E20` reads the row
> id, tests the bit via `0xD5C2A8`, and skips the row when clear; there is no stat load in
> `0x916E20`..`0x916FD0`. The `threshold` word in `0xE139C0` is loaded *after* the gate and
> `sprintf`'d into the description as its `%d` — it is display text, not a condition. The bitfield
> is medal-id-keyed, not row-indexed, LSB-first, with bits 3 and 7 of each byte and bytes 13–15
> unused.
>
> **Titles are gated by a 22-bit mask at wire 563** (rating-block entry 3). Never set bit 22 or
> above: the client's popcount loop runs 23 times for 22 titles.
>
> The 22-title table `0xE14EB0` is 66 strings (22 titles × 3 forms) and `0xE152D0` is the *title*
> sprite table; medals have no sprite. See `GATES.md` §5a.

## `0x4132` — outfit commit

**Client → server**, `PersonalInfoController.commitOutfit`. First observed live 2026-07-23: closing
the outfit screen fires the `0x4130` updates (answered) and then this, **empty payload** (confirmed
from the sender `0xd3a844` — zero appends), blocking on wait slot `0x1b`.

The `0x4133` reply is **not a result code**. The parser (`0xd3c77c`) zeroes the client's loadout
table (`0x60c` bytes) and then reads: u32 **entry count**, `count ×` `{u8 slot, u32 value}`
loadout entries (12-byte records into `charTable+0x26a0+slot*0xc`, slot ≤ `0x80`), then a fixed
**sixteen** `{u8 slot, u8 bit}` equipped-bit pairs — total `36 + 5·count` bytes. A nonzero first
u32 would be read as a count, not an error, and the read primitives do not check payload length
(the `0x4101` caveat again).

**Corrected 2026-07-26 from "fifteen pairs / `34 + 5·count`"** (ELF, single-source trace). The
loop bound at `0xD3C8D4` is `cmpwi r31,15`, but it is evaluated **before** the `addi r31,r31,1`,
so the loop runs **16 times**. Corroborated arithmetically by `0x4124`, whose known-good 651 bytes
= 4 + 615 + 32 and only balances with 16 pairs in the same trailing block.

~~**Live consequence:** `PersonalInfoController.commitOutfit` writes `COMMIT_TRAILER_PAIRS = 15`~~
— **fixed, and the constant no longer exists.** Both `0x4124` and `0x4133` now go through
`LoadoutWriter.writeGear`, which writes 32 bytes / 16 pairs, so the short-by-one-pair bug (34 bytes
where the parser reads 36, the 16th pair coming from stale receive-buffer contents) is gone.

**And the pairs grant nothing anyway** [ELF `0xD3CFBC`-`0xD3CFE4`]: a pair is ORed into record
`+16` **only if that bit is already set** in the colour mask at `+12`, so it can only produce a
subset of what the record already carried. `+16` feeds a wardrobe highlight (`0x92740C`,
`0x927744`), not availability. The two real gates are record `+8` for item ownership (`0x927350`)
and record `+12` for colour (`0x925538`, `0x92772C`).

We send the empty readback (count 0, zero pairs); what the
original filled the entries with — presumably the skill/gear loadout — awaits a capture, and note
the zero pairs redundantly touch bit 0 of slot 0, as no distinct no-op encoding is known.

## `0x4300` — get game list

**Client → server**, `GameListGameController.getGameList`.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | filter type — read and logged, **then ignored** |

The original distinguishes clan rooms from ordinary games by a name prefix; clan rooms are not
modelled, so every game in the lobby is listed whatever was asked for.

| command | payload |
| --- | --- |
| `0x4301` | 4 bytes result (`00000000`, or `C0FFEE02` with no session and nothing further) |
| `0x4302` | up to 18 entries per packet, `0x37` bytes each |
| `0x4303` | 4 bytes result |

**The client's array cap is 999, not 18** (ELF 2026-07-26, single-source trace: a `bgt` to −71
above 999). 18 is the **per-packet** ceiling that falls out of the `0x400` transport limit, and
this file previously conflated the two. Nothing stops a longer list spread over more packets.

### `0x4302` entry — 55 (`0x37`) bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | game id |
| `0x04` | 16 | ISO-8859-1 | game name |
| `0x14` | 1 | u8 | host options: bit 0 password set, bit 1 dedicated, **bit 2 — expanded into the struct like the other two; meaning unrecorded** |
| `0x15` | 1 | u8 | **unknown**: always `0x08` |
| `0x16` | 1 | u8 | rule |
| `0x17` | 1 | u8 | map |
| `0x18` | 1 | u8 | zero, purpose unknown |
| `0x19` | 1 | u8 | max players |
| `0x1a` | 1 | u8 | stance |
| `0x1b` | 1 | u8 | common A: bit 0 idle kick, **bit 2 always set (unknown)**, bit 3 friendly fire, bit 4 ghosts, bit 5 auto-aim, bit 7 uniques |
| `0x1c` | 1 | u8 | common B: bit 0 team switch, bit 1 auto-assign, bit 2 silent mode, bit 3 enemy nametags, bit 4 level limit, bit 6 voice chat, bit 7 team-kill kick |
| `0x1d` | 1 | u8 | current player count |
| `0x1e` | 4 | u32 | ping |
| `0x22` | 1 | u8 | friend/block: bit 0 contains a friend, bit 1 contains a blocked player — **always 0**, neither list is modelled |
| `0x23` | 1 | u8 | level-limit tolerance |
| `0x24` | 4 | u32 | level-limit base |
| `0x28` | 4 | u32 | average experience across current players |
| `0x2c` | 4 | u32 | host score |
| `0x30` | 4 | u32 | host votes |
| `0x34` | 1 | u8 | zero, purpose unknown |
| `0x35` | 2 | u16 | **unknown**: always `0x0063` |

**The entry tail is `u8` + `u16`, not "2 zero bytes then a u8 `0x63`"** (corrected 2026-07-26 from
the ELF, single-source trace: parser `0xD43D48`, 20 reads totalling the same 55 bytes). The
famous `0x63` at `0x36` is the **low half of a halfword `0x0063`** starting at `0x35`. The bytes
on the wire are identical either way — this changes nothing we send — but it means the constant is
99 as a 16-bit value, and that any future attempt to give it meaning should look for a u16, not a
byte and a pad.

## `0x4304` — get host settings

**Client → server**, `HostGameController.getHostSettings`. Sent when Create Game opens, so the
screen can be pre-filled with whatever the player hosted last time. Empty request.

### Reply `0x4305` — 128 bytes empty, **348 (`0x15C`)** populated

**The only payload this server encrypts on the way out.** Until this command was implemented
nothing sent `0x4305`, so the Blowfish encrypt direction had never produced a byte the client saw.
The empty path is confirmed working: the Create Game screen opens.

A host with nothing saved gets 128 zero bytes, which is what both references send and what the
client reads as "no saved settings".

**The size is 348 (`0x15C`), not 355 (`0x163`) — and the 355 was a tier-4 leak** (corrected
2026-07-26). The client's parser is at `0xD4548C`: 46 straight-line reads plus a 16-iteration
rotation loop (`cmpdi r27,16` at `0xD45648`) scattering triples to `+752`/`+768`/`+784`, and it
inlines the same 204-byte settings block that `0x4313` reads through the standalone reader
`0xD4364C`, **minus eight fields** — the named omission being current player count (block+67).
The total the parser consumes is `0x15C`.

**`0x163` was never a client figure. It is the reference server's struct length**, transcribed
here and then reasoned about as though it described the wire. That is the exact failure mode this
project keeps paying for: a correctly-copied number from a source that does not apply. The seven
extra bytes are inert — the parser stops at `0x15C` and the surplus is ignored — so this is a
documentation error, not a live bug. It is written down anyway because the *next* borrowed
constant might not be inert.

**Populated (implemented 2026-07-22, verified against a live client the same day):** the raw
`0x4310` blob the character last pushed is stored per (character, lobby subtype) and re-mapped
into the reply shape transcribed from Nomad's `Hosts.getSettings()` — a structure
that is *not* the request blob echoed: the subtype byte is dropped, two constants are inserted
(`0x02` at `0x0ED`, `0x20` at `0x147`) and every offset is re-based. Full mapping in
`mgo2server.game.HostSettingsReply` and its test. **Live evidence** (OBSERVED.md, "Where the
Common Settings toggles live"): the Create Game screen re-opened pre-filled with the saved
settings, and the two injected constants came back in the next `0x4310` push at the request
offsets corresponding to their reply positions — the client parses this reply at these offsets
and stores those fields. (mgo2-server instead sends `u32 type` + a blob it stored as JSON text,
which is garbage by construction; disregarded.)

## `0x4310` — check host settings

**Client → server**, `HostGameController.checkHostSettings`. Carries the settings just configured —
name, conditions, comment, match type, map, rules — pushed immediately before the game is created.

**Payload arrives Blowfish-encrypted.** This was the first command other than check-session to
exercise the inbound decrypt path.

**There is no leading "type" field — the blob starts with the game name at offset 0.** The earlier
"settings type `1399153006`" was `name[0:4]` read as an int: `1399153006` = `0x5365616E` = ASCII
`"Sean"`, the game name of that capture. savemgo Nomad's `Hosts.checkSettings` reads the name from
offset 0; mgo2-server makes the same misread we did.

**The payload is 345 bytes; 352 is the Blowfish-padded ciphertext** (ELF 2026-07-26,
single-source trace). This file recorded "352 bytes (observed)" without distinguishing the two —
352 is 345 rounded up to the 8-byte cipher boundary, and the seven trailing bytes are padding,
not fields. Layout below (offsets from the name at 0; per savemgo `Hosts.checkSettings`
cross-checked with the `0x4313` layout and, where marked, with the ELF):

| offset | size | field |
| --- | --- | --- |
| `0x00` | 16 | name (ISO-8859-1, NUL-padded) |
| `0x10` | 128 | comment |
| `0x90` | 1 | password enabled |
| `0x91` | 15 | password |
| `0xA1` | 1 | dedicated |
| `0xA2` | 1 | **lobby subtype** — a standalone u8 read at `0xD448FC`, confirming the rotation starts at `0xA3`. The builder validates it against **{1, 2, 7, 8}** at `0xD44834` — exactly the subtypes a player can host in. `0x4316`'s single u8 and `0x4320`'s trailing u8 are the same field. Confirmed 2026-07-28; it is **not** an automatch marker, see [AUTOMATCH.md](AUTOMATCH.md) §4 |
| `0xA3` | 48 | rotation: `[rule, map, flags]` × **16**, stride 3; `rule==0 && map==0` ends it |
| `0xE5` | 1 | max players |
| `0xE6` | 4 | briefing time |
| `0xFC` | 68 | **seventeen u32s, decoded 2026-07-28.** SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r. Times are minutes (the client ×60s exactly those eight indices at `0x8CA470`). Confirmed against client defaults in four stored blobs — full table in [AUTOMATCH.md](AUTOMATCH.md). Then uniques, commonA/B bitfields, kicks |

**Partly stored now.** `HostGameController.checkHostSettings` parses **round 0** of the rotation
(`rule, map, flags` at `0xA3`) into the connection, and `createGame` writes them onto the game, so
the browser shows the real match type/map/mode instead of DM/map-0. Since 2026-07-22 the **raw
blob is also persisted** per (character, lobby subtype) in `chara_host_settings.blob`, which is
what the populated `0x4304` reply and the `0x4392` rotation advance read.

**The one-byte caveat is retired: the rotation starts at `0xA3`** (ELF 2026-07-26, single-source
trace). It was previously recorded here as ambiguous between the two reference models (A = `0xA2`,
B = `0xA3`), with a live experiment proposed to settle it. The binary settles it instead: `0xD448FC`
reads `src+168` (`0xA2`) as a **standalone u8** — the subtype byte — and the rotation loop begins
after it. We were already using `0xA3`, so nothing changes in code; the caveat simply goes away.

**The rotation is 16 triples, not 15** (same trace: `cmpdi cr7,r27,16` at `0xD44958`), 48 bytes
rather than 45, interleaved from three 16-byte source arrays. This matches `0x4313`, whose parser
also reads 16 triples where the reference splits the region as 15 + 5 zeros.

### Weapon restrictions — the 16-byte bitfield at `0xD5`

One bit per item, **1 = locked**; byte `0xD5` bit 0 is the master "restrictions enabled" flag.
The server never decodes individual weapon bits — the block is copied opaquely into the game row
and replayed by `0x4313`/`0x4305` — so this table is documentation, not code. Two provenance
tiers in one map: bits marked ✓ were **confirmed one weapon at a time against the live client**
(2026-07-22 sweep, OBSERVED.md "The weapon-restriction table, confirmed weapon by weapon");
everything else is **transcribed from Nomad and unverifiable on `BLUS30109`** — expansion-era
weapons and attachments this build's UI cannot express, dark in every capture. Do not treat the
unverified names as fact for another build without re-testing.

| byte | confirmed on this build ✓ | Nomad-only (expansion/attachments, unverified) |
| --- | --- | --- |
| `0xD5` | `0x01` enable ✓, `0x02` Knife ✓, `0x04` Mk.2 ✓, `0x80` GSR ✓ | `0x08` Operator, `0x10` Mk.23 |
| `0xD6` | — | `0x01` Desert Eagle, `0x80` G18 |
| `0xD7` | `0x10` P90 ✓, `0x80` Vz.83 ✓ | `0x04` MP5, `0x40` Patriot |
| `0xD8` | `0x01` M4 Custom ✓, `0x02` AK-102 ✓ | `0x04` G3A3, `0x40` Mk.17, `0x80` XM8 |
| `0xD9` | `0x20` M870 Custom ✓ | `0x08` M60, `0x40` Saiga, `0x80` VSS |
| `0xDA` | `0x08` Mosin-Nagant ✓, `0x10` SVD ✓ | `0x02` DSR-1, `0x04` M14 |
| `0xDB` | `0x10` Grenade ✓, `0x40` Stun G. ✓, `0x80` Chaff G. ✓ | `0x04` RPG, `0x20` WP |
| `0xDC` | `0x01` Smoke G. ✓, `0x80` E.Locator ✓ | `0x02/0x04/0x08` colored smokes (r/g/y) |
| `0xDD` | `0x01` Claymore ✓, `0x20` Magazine ✓ | `0x02` SG-mine, `0x04` C4, `0x08` SG-satchel |
| `0xDE` | `0x02` Shield ✓ | `0x04` Masterkey, `0x08` XM320, `0x10` GP30, `0x20` Suppressor |
| `0xDF` | — | Nomad derives `0x0E` from !suppressor on its encode side only; we echo raw |
| `0xE0` | — | `0x10` Scope, `0x20` Sight, `0x80` Light (LG) |
| `0xE1` | — | `0x01` Laser, `0x02` Light (HG), `0x04` Grip |
| `0xE2` | — | `0x04` Drum |
| `0xE3` | — | `0x40` ENVG |
| `0xE4` | — | no bits named anywhere |

**Resolved by capture 2026-07-22** (OBSERVED.md, "Where the Common Settings toggles live"):
`0x142`/`0x143` are the **commonA/commonB toggle bitfields** — same bit map as the `0x4302`
entry — and level-limit base is a **u32 at `0xF8`** (tolerance at `0xF7`); flipping only friendly
fire moved exactly `0x142` bit 3. `applyHostSettings` decodes the toggles into their columns,
zeroes the idle/team-kill counts when their enable bits (commonA bit 0 / commonB bit 7) are off,
and reads non-stat from the host-options byte at `0x155` bit 1. An earlier read of a u16 base at
`0x142` was a bug that stored toggle bits as the base.

**The kick counts are `u16`s at `0x145` and `0x147`, not bytes at `0x146` and `0x148`** (ELF
2026-07-26, single-source trace: `0xD44BF8` idle kick, `0xD44C0C` team-kill kick). This does not
contradict the capture — a u16 at `0x145` has its low byte at `0x146`, and the sweep varied values
small enough to live entirely in the low byte, so `0x146`/`0x148` are exactly what moved. The ELF
supplies the width the capture could not.

> **Fixed 2026-07-26** (`GameService` now reads a u16 via `blobU16`; `HostSettingsReply` copies
> two bytes per timer). Kept for the lesson: our own `GameDetails` already wrote these back as
> shorts at these exact offsets, so the two halves of this server disagreed about the width and
> nothing caught it. The original text follows.
>
> **Live code bug, open as of 2026-07-26.** `GameService.java:539-540` reads
> `blob[0x146]`/`blob[0x148]` — the low byte only. Any idle-kick or team-kill-kick value above 255
> is silently truncated modulo 256, and the high byte at `0x145`/`0x147` is discarded. Whether
> this build's UI can even offer such a value is unchecked; the read is wrong either way.

### Reply `0x4311` — empty

**Sufficient, but not known to be complete.** Both references send an empty payload and this client
accepts it and proceeds, so nothing more is *required*. That is weaker than it was previously
written here ("the client only waits for the acknowledgement"), which asserted an intent nobody had
checked.

Against that reading: the client's reply dispatcher (the compare tree headed at `0xD38804`) routes
`0x4311` to a real handler at `0xD43550`, not a no-op.

**"Whether it reads any field beyond the header is undetermined" is now answered** (ELF
2026-07-26, single-source trace): `0xD43550` reads **exactly one u32**, and a **nonzero** value
takes a teardown path (`0xD5BDA0` → `0xD5B41C`). Wait slot 35. So the original server did send
something here — a result word — and we send nothing. The empty reply survives only because the
read primitives bound-check the receive buffer rather than the payload, so the absent word is read
out of whatever the buffer last held. **That is not zero by construction.** A stale nonzero would
put the client down the teardown path. Sending an explicit `{u32 0}` costs four bytes and removes
the hazard; until that is done, the empty reply is a latent bug, not merely an incomplete one.

## `0x4150` — lobby disconnect

**Client → server**, `HubGameController.lobbyDisconnect`. Sent when the player backs out of a lobby
to the previous screen. Empty `0x4151` reply.

**The request is one u8, not empty** — established from the ELF 2026-07-26: the builder at
`0xD3859C` calls the u8 writer (`bl 0xD5C8A0` at `0xD385AC`) into slot `0x74` and seals at
`0xD385B8`. This file said "empty request, empty `0x4151` reply"; the first half was wrong. We
discard the byte and its meaning is unknown.

Unanswered this hangs on the way **out** rather than the way in, which reads as an unrelated bug —
everything works until you press cancel. Nothing is torn down server-side: lobby membership is not
tracked, and the connection stays open because the client reuses it.

Same caveat as `0x4311`: empty is sufficient, not known to be complete. `0x4151` dispatches to a
handler at `0xD3943C` which verifies the id and calls on, so it is not a no-op; what it reads is
undetermined.

## `0x4312` — get game details

**Client → server**, `GameListGameController.getGameDetails`. Sent by Game Details, Player List
and the first step of Join Game; all three stalled into `0B10:FFFFFF60` while it went unanswered,
with the client retrying every ~2 s.

Request: **one u32 game id, now read from the binary** (ELF 2026-07-26, single-source trace). The
sender is `0xD413C0` — `bl 0xD5CF40` (begin packet), one u32, wait slot `0x24`. This file
previously said "the sender has not been located in the binary" and rested the 4-byte parse on
the two reference servers agreeing. That was a tier-4 dependency for a fact the binary states
outright; it is now tier 1 and the agreement is irrelevant.

### Reply `0x4313` — **exactly** 372 bytes plus 28 per player

**The layout below is read from the binary**: the reply dispatcher (compare tree headed at
`0xD38804`) routes `0x4313` to the parser at `0xD44388`, whose read calls (with the settings
sub-structure at `0xD4364C`) fix every size and position. **372 is exact, not approximate**
(confirmed 2026-07-26): `0xA8` of header plus the 204-byte settings block is `0x174`, with no
slack anywhere, and the field table below matches the parser byte for byte — including `0x098`
and `0x099` being two separate u8 reads rather than a halfword. The parser reads the fixed 372
bytes unconditionally — **a short payload
is a parse error and the client keeps waiting**, so unknown fields must be present as zeros.
Player entries are then read while payload remains, at most 18; a truncated entry is an error,
never a shorter list. The packet-reader caps payloads at `0x400`, and 372 + 18×28 = 876 fits.

Field *names* are echo's, whose `GameDetailsPacket` matches this parser byte for byte (their
buffer is `0x36D` — one spare byte past the parser's maximum read, harmlessly ignored).
mgo2-server's 192-byte reply does **not** fit this parser — its leading game id lands in the
result slot and trips the error branch — so it targets some other build and was disregarded.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x000` | 4 | s32 | result — nonzero aborts the parse and surfaces the error |
| `0x004` | 4 | u32 | game id; if a game is currently selected the client requires this to match |
| `0x008` | 16 | ISO-8859-1 | game name |
| `0x018` | 128 | ISO-8859-1 | comment |
| `0x098` | 1 | u8 | **password_enabled** — `0xD444E0` → obj+150, the same destination as `0x4310`'s `src+150` |
| `0x099` | 1 | u8 | **dedicated** — `0xD444FC` → obj+167, ditto `src+167`; consumed at `0xD494F0` → T+0x16 |
| `0x09a` | 1 | u8 | lobby subtype |
| `0x09b` | 4 | s32 | average experience across current players |
| `0x09f` | 4 | u32 | host score |
| `0x0a3` | 4 | u32 | host votes |
| `0x0a7` | 1 | u8 | echo writes `1` verbatim; meaning unknown |
| `0x0a8` | 48 | u8×3 ×16 | round rotation: 16 triples of (rule, map, flags). We fill round 0 from the stored rule and map; the rest are zero until the `0x4310` blob is persisted. Echo splits this region as 15 triples + 5 zeros; the parser reads 16 triples and wins |
| `0x0d8` | 2 | u8, u8 | two separate reads; echo zeroes both, meaning unknown |
| `0x0da` | 16 | — | weapon restrictions (echo's `WeaponRestrictions.toBytes()`); zeros until stored |
| `0x0ea` | 1 | u8 | max players |
| `0x0eb` | 1 | u8 | current player count |
| `0x0ec` | 4 | u32 | briefing time |
| `0x0f0` | 22 | u32,u32,u16,u16,u32,u32,u16 | seven fields the parser reads and echo zeroes; unknown |
| `0x106` | 1 | u8 | stance |
| `0x107` | 1 | u8 | level-limit tolerance |
| `0x108` | 4 | u32 | **level-limit base** (see the note below) — echo writes `0x16` = 22 verbatim |
| `0x10c` | 68 | u32 ×17 | per-rule timers and rounds (echo: SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r); zeros until stored |
| `0x150` | 2 | u8, u8 | unique characters red/blue (+`0x80` when random); zeros until stored |
| `0x152` | 7 | u16, u32, u8 | parser reads, echo zeroes; unknown |
| `0x159` | 1 | u8 | common A — same bitfield as the `0x4302` entry |
| `0x15a` | 1 | u8 | common B — same bitfield as the `0x4302` entry |
| `0x15b` | 1 | u8 | zero |
| `0x15c` | 2 | u16 | idle kick |
| `0x15e` | 2 | u16 | team-kill kick |
| `0x160` | 4 | u32 | echo writes `0x2e` verbatim; meaning unknown — **regression guard only** |
| `0x164` | 2 | u8, u8 | capture extra time; **sneaking SNAKE count (1-5)** — clamped to [1,5] by the create-game adjuster at `0x8A1AC8` and **rendered as a number** at `0x89D7B8`, which is what rules out the older "Snake side" reading: a side index would be drawn as a name or sprite. Default 3. That the count is specifically *kills of Snake* is not decidable from the binary — that label lives on the disc. Was "Snake side" until 2026-07-28; corrected against the client's own default and four stored blobs. Zeros until stored |
| `0x166` | 8 | u8 ×8 | byte-sized timers (echo: SDM t/r, INT t, DM r, SCAP t/r, RACE t/r); zeros until stored |
| `0x16e` | 1 | u8 | zero |
| `0x16f` | 1 | u8 | extra-time flags; bit 1 = non-stat game (echo) |
| `0x170` | 4 | — | zero |

Then, per player, host's entry first:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | character id |
| `0x04` | 16 | ISO-8859-1 | character name |
| `0x14` | 4 | u32 | ping — not tracked, sent as 0 |
| `0x18` | 4 | u32 | experience — **per character** since V59 (`chara.experience`). It was an account main/alt pool, which made two alts on one account share a level; the wire has always carried it per entry |

**The `0x108` row was stale** (corrected 2026-07-26). It read "echo writes `0x16` verbatim;
meaning unknown — **regression guard only**", which was already contradicted by this file's own
`0x4310` prose and by `OBSERVED.md`'s single-variable hosting sweep. Three things line up:

- the sweep pinned the `0x4310` pair as **`u8` tolerance at `0xF7`, `u32` base at `0xF8`**, and
  the observed base value was **22**;
- `0x4313` has the identical adjacency — `u8` tolerance at `0x107`, `u32` at `0x108` — at a
  constant `0x10` offset from the `0x4310` pair;
- the value the references write into it is `0x16` = **22**, the same number the capture saw.

The `0x4302` game-list entry carries the same pair in the same order (`0x23` tolerance, `0x24`
base), making three occurrences of one field. **This is inference from a capture plus field
adjacency, not an ELF read** — nobody has traced where `0xD4364C` stores block+96 — so it is
labelled as inference. It is nonetheless a great deal better than "meaning unknown", and treating
the field as a regression guard was actively misleading: it is a value the host chose.

**Untested against a live client** as of writing — implemented from the parser the same evening
the missing handler was identified; the first two-machine session should retire this caveat.

## `0x4316` — create game

**Client → server**, `HostGameController.createGame`. **The request is one u8**, which *we* do not
read at all — established from the ELF 2026-07-26 (`0xD43CDC`). The old wording, "request payload
is **not read at all**", is true of our handler but reads as though the wire were empty. It is
not; we discard the byte and its meaning is unknown.

Settings come from the character's stored host-settings row (`getOrCreateHostSettings`), which is
materialised with defaults named after the host. The client also pushes settings with `0x4310`
and reads them back with `0x4304`; both are handled now, though the blob is not stored, so what the player configured on the host
screen is lost and the defaults are used.

### Reply `0x4317`

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result |
| `0x04` | 4 | u32 | new game id |

8 bytes on success; 4 bytes with `C0FFEE02`, `C0FFEE20` or `C0FFEE01` otherwise.

**The 4-byte failure form reads past the payload** (ELF 2026-07-26, single-source trace). The
parser reads the second u32 **before** it tests the result, so on an error reply it takes the game
id out of stale receive-buffer contents and only then discards it. Harmless as observed — the
value is thrown away — but there is no reason to rely on that: 8 bytes always is free, and the
contrast with `0x43c9` below (which tests its result *first*) shows the client has no house style
here. Check the polarity per command; do not assume it.

Untested against a live client — nothing has reached the host screen yet.

## `0x4700` — update connection info

**Client → server, payload Blowfish-encrypted.** `CharacterConnectController.updateConnectionInfo`.
The endpoint the client wants other players to reach it on, sent right after joining a game lobby.
Matches are peer-to-peer, so this is what a joining client is eventually handed.

The client blocks on the reply: with nothing sent back it fails with **`092E:FFFFFF60`**.

### Request — exactly 22 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 2 | u16 | private port |
| `0x02` | 16 | ISO-8859-1 | private IP, dotted quad, NUL-padded |
| `0x12` | 2 | u16 | public port |
| `0x14` | 2 | u16 | **client-populated**, from the caller's `r7`. **Not read by us**; meaning unknown |

**Corrected 2026-07-26** (ELF, single-source trace). This said "at least 20 bytes", with the
trailing pair described as "present in echo's parser, which skips it, purpose unknown" — which
made it sound like a reference artefact that might not be on the wire at all. It is: the builder
writes it as a **u16** via `0xD5C918` at `0xD38708`, from a value the caller passes in `r7`. The
request is exactly 22 bytes. What the u16 carries is still unknown, but it is a real field with a
real source, not padding.

The public **address** is deliberately not taken from the payload — the reference servers read it
off the socket, and so would we.

### Reply `0x4701` — 4 bytes

`00000000`, or `C0FFEE02` / `C0FFEE01`.

**Persisted since 2026-07-21.** The private port, private IP and public port are stored in
`chara_connection` keyed by the character; the public IP is taken from the socket. `0x4320` serves
this row back to a joining player. A registration with no selected character or no socket address
is acknowledged but not stored (logged as a warning), since the client blocks on the reply.

## `0x4320` — join game

**Client → server, payload Blowfish-decrypted.** `GameListGameController.joinGame`. The player has
picked a game in the browser and asked to join; the reply hands over the host's peer-to-peer
endpoints so the two connect directly. Unanswered, all three of Join, Game Details and Player List
stall on `0B10:FFFFFF60` — this is the command whose absence blocked them.

### Request

**21 bytes** (ELF 2026-07-26, single-source trace: sender `0xD451C8`, builder call `0xD45324`).

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | game id |
| `0x04` | 16 | ISO-8859-1 | password, NUL-padded — **written unconditionally** |
| `0x14` | 1 | u8 | join mode / slot selector, built at `0xD452A0`–`0xD45308`; **unknown meaning** |

**Corrected 2026-07-26.** This section said "**Sender not yet located in the binary**, so the
exact request width is unconfirmed", and gave the request as 20 bytes with the password read only
if the payload extended that far. Both parts are now settled:

- The password field is **always present**. The builder writes from a zero-filled staging buffer
  and `strcpy`s into it only when a password is set, so an unprotected game sends 16 NULs rather
  than omitting the field. Reading it "only if the payload extends that far" is harmless but was
  never the condition.
- There is a **trailing u8** nobody had noticed. It defaults to 1, may instead be loaded from
  `lbz r3+608`, and is replaced by the sender's fourth argument when that argument is 1, 2, 7 or
  8. It is latched into `ctx+0x11560`, and **`0x43B0` re-sends the same slot** (`0xD44DF8` reads
  `+0x11558`, `+0x11560` and `+0x11568`) — which is the strongest lead on what it means, since
  whatever `0x43B0` is for, this byte is part of it. We do not read it.

### Reply `0x4321`

Read by the parser at `0xD440DC`, which on a nonzero result reads nothing further — so a failure
is a bare 4-byte result (`C0FFEE01`), returned for a missing game, a wrong password, or a host
that never registered an endpoint. On success:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result |
| `0x04` | 16 | ISO-8859-1 | host public IP |
| `0x14` | 2 | u16 | host public port |
| `0x16` | 16 | ISO-8859-1 | host private IP |
| `0x26` | 2 | u16 | host private port |
| `0x28` | 1 | u8 | one byte the parser reads; echo writes `0` |

The parser stops at offset `0x29` (41 bytes). Echo writes two further bytes (current rule, current
map) for a 43-byte (`0x2b`) reply; **this client reads neither** — they are reproduced only because
echo is known-good and trailing bytes are harmless. We write the same 43.

**Verified against a live client 2026-07-21:** the client accepts the reply and proceeds to
attempt the peer connection. It does *not* mean the peer connection succeeds — see `0x4322`.

## `0x4322` — join failed

**Client → server**, empty payload. `GameListGameController.joinFailed`. The client sends this
after `0x4321` when it **could not establish the peer-to-peer connection to the host** — the
loader keeps spinning until it gives up, and unanswered this ends in `0B08:FFFFFF60`. Observed
live 2026-07-21: `4320 → 4321` succeeds, then ~40 s later the client sends `4322`.

The reply parser at `0xD40904` reads a single u32 result, so `0x4323` is a bare acknowledgement.
The joiner is removed from the game they failed to enter.

| command | payload |
| --- | --- |
| `0x4323` | 4 bytes result |

**Note this is a symptom handler, not a fix.** It converts the hang into a clean failure; it does
not make the join succeed. The peer connection itself is the open frontier — see BACKLOG.md.

# In-match host commands

The commands the host's client sends while staging and running a match. All were originally
ack-only ("answered because the client blocks, not because the work is done"); since 2026-07-22
the payloads are parsed and the match state tracked, **with layouts transcribed from
GHzGangster/Nomad (tier 4)** at the user's request — fetched for these specific named questions
after the docs and the audit both confirmed the gap. Live standing after two captured sessions
(2026-07-22, including an admin-action sweep): **`0x4398`, `0x43a0`, `0x4392` and `0x4390` are
all confirmed against the client, payload and effect**; `0x43ca` has **never been observed on
any path** and is presumed absent from this build's normal vocabulary. `0x43a2` was presumed
absent too until 2026-07-23, when live round ends sent it (the 2026-07-22 sweep that missed
it predates packet tracing; it fires in every mode). Since fully decoded: **one per scoring
player**, sent immediately after that player's `0x4390`, carrying that player's per-weapon
kill/headshot/faint tallies — see its own section and `dev/proto/inbound/mgo2_cmd_43a2_c2s.ksy`. We ack
`0x43a3`, result 0; storing the tallies is backlogged.

What the host admin menu actually sends, mapped action by action against a live client:

| admin action | server traffic |
| --- | --- |
| Restart (Round) / Restart (Stage) | nothing — P2P, plus the `0x4440`/`0x4344` re-register pair |
| Restart (Next) | `0x4392` rotation advance |
| Kick (executed) | `0x4510`+`0x4500` ADDLIST churn, then the usual teardown (`0x4390` stats, `0x4342`) |
| Pass host | `0x43a0` |
| Edit name/comment/password | `0x43c0` |
| Team change (accepted) | `0x4440` exchanges |
| Any joiner *request* (kick, restart, team) | nothing — requests ride the P2P channel; the server hears only executed outcomes |

mgo2-server was checked too and answers all of these as unparsed acks, so Nomad is the only
layout source; where the two disagree it is noted.

## `0x4392` — set game (advance the rotation)

**Client → server**, `HostGameController.setGame`. **Confirmed against a live client 2026-07-22,
twice** — sent by the host on executing "Restart (Next)", one byte, the rotation index; the
handler applied it and the browser followed. The game row's `current_game`, `rule`, `map` and
`flags` are updated from the stored blob's triple at `0xA3 + 3×index`. Reply `0x4393`, 4-byte
result 0 (Nomad sends the same; its error paths are silent, ours always ack after logging).

## `0x4398` — update pings

**Client → server**, `HostGameController.updatePings`. Request: `u32` host ping, then repeated
`{u32 chara id, u32 ping}` pairs; a zero id is skipped (as in Nomad). **There is no count field
and there never was one** — the client's loop is entered mid-body at `0xD410EC` and runs until the
payload is exhausted (ELF 2026-07-26). Of the four count mechanisms in this protocol (see "Where a
list's count comes from"), this is the size-driven one. The host ping lands on the
game row (`0x4302` offset `0x1e`), each player's on their roster row (`0x4313` player entry offset
`0x14`), and the game's `last_update` is touched — in Nomad this report doubles as the heartbeat
that keeps a game from being reaped; we track the timestamp but do not reap on it (host
disconnects already tear the game down).

**The empty `0x4399` should become an explicit 4-byte zero — and the reasoning that kept it empty
was wrong** (corrected 2026-07-26). This file said: "Reply stays the **empty** `0x4399` that is
live-verified; Nomad sends a 4-byte 0 instead, and reshaping a working ack on reference evidence
is exactly the mistake this project keeps regretting." The instinct was right and the conclusion
was not, because there is now tier-1 evidence that has nothing to do with Nomad. The parser at
`0xD40530` reads **a u32 unconditionally**, and bails with −71 — **without signalling slot 44** —
if that read fails. The empty reply works only because the read primitives bound-check the
1023-byte receive buffer rather than the declared payload, so the missing word is satisfied out of
stale buffer contents. "Live-verified" here meant "observed not to break", which is a weaker claim
than it looked: it verified one buffer state, not the protocol. Send an explicit `{u32 0}`.

## `0x43ca` — start round (never observed)

**Client → server**, `HostGameController.startRound`. **Never observed from this client on any
path** — its handler (which snapshots the roster into `game_round` to gate `0x4390`) is
Nomad-derived and effectively dormant here: without the snapshot, stat application relies on the
current-membership check, which drops reports for players who already left (observed live: a
crashed joiner's straggler report was rejected). See BACKLOG, "The round snapshot never
populates". Reply `0x43cb`, result 0, if it ever arrives.

> **Switches and refusals live in `GATES.md`** — the feature bits we send, the per-round
> Headshots-Only / Drebin-Points flag, the player-count thresholds, and the values that make
> the client discard a packet or stall. This section is the byte layout; that one is the
> index of what turns things on and off.

## `0x4390` — update stats

**The reporting model — two established truths (2026-07-23, per-connection verified across 14
live reports; the server actively flags deviations):**

1. **One packet = one player.** A report is 167 bytes about a single target character; a
   round's results are N packets back to back, never a roster in one frame. Only the host
   sends them — joiners have no reporting channel (verified: an active joiner sent zero).
   Timing: present players at round end; a mid-round quitter immediately at quit (real
   values, 84 ms after the leave command, twice reproduced) and **not again** at round end.
2. **No in-frame game identifier; attribution is connection-implicit — now BINARY-PROVEN
   (ELF trace 2026-07-23).** Nothing in the frame names the game or lobby — the server
   resolves the game as "the one this connection's character hosts", and a character hosts
   at most one. The start-round reply's token is stored at one client location
   (`session+0x57d8+0x32f8`) and read exactly once in the whole binary — into a local UI
   record via memory-copy helpers, never a packet writer; the `0x43c8`, `0x43a2` and
   `0x4390` builders provably never touch it. The `0x43c8` request itself is two config
   bytes, not an id. `round_report.game_id`/`host_chara_id` are stamped from connection
   context, not parsed.

**`0x43c9` independently confirms the model from the writer's side** (ELF 2026-07-26,
single-source trace). `0xD3FEAC` is the **sole writer** anywhere in the binary of the round token
at session `+0x32F8`, and it writes only when `result == 0` **and** `token != 0`. Reading the
model from the `0x4390` builder established that nothing *reads* the token; this establishes that
almost nothing *writes* it either, and that a `{0, 0}` `0x43c9` reply leaves the slot untouched
rather than clearing it. The two traces meet in the middle, which is as close to a proof as this
gets without a capture.

Deviation tripwires in `updateStats`: a `0x4390` on a non-host connection and a nonzero
trailing word each log a WARN with payload hex — if either fires, these truths need revisiting.

**Client → server**, `HostGameController.updateStats`, one player per packet, sent by the host at
round end and on kick teardown. **Confirmed against a live client 2026-07-22** — this build sends
**167-byte** reports, and two rounds of captures pinned the fields against known ground truth:

**TRACED END TO END, 2026-07-27.** The caveat that used to sit here — "the positions are read
from the binary, the labels are not" — no longer applies: the gameplay writers have now been
found, and `dev/proto/inbound/mgo2_cmd_4390_c2s.ksy` is the authority for every field. What changed:

- **The frame's source is one 152-byte per-player blob** of 76 u16 counters (index `n`), live at
  blob `+0x1a + 2n`, baseline at `+0xb2 + 2n`, blob base `0x1610568 + slot*0x510`. Struct A
  carries n00..n15, struct B carries n17..n74 **through a permutation**. The serializer
  `0xD42178` is dumb; the semantics live in its only caller `0x27D5B0`.
- **Gameplay bumps counters through a wrapper `0x6A9758(base, key, len, u16)`** whose key is a
  constant one frame up — which is why earlier constant-key sweeps of the record API found
  nothing. Every bump computes `min(v+1, 0xFFFF)`: **counters SATURATE, they do not wrap.**
- **`0x19`/`0x1d` are lock-on stuns dealt/received** (handler `0x6EDC90`, `hitClass==2`; the
  enum is pinned by four already-confirmed labels). The "rounds played" guess on `0x1d` is dead.
- **`0x23` is a TEAM WIN flag, not a team slot index** — see its row below.
- **`0xa3` is a hardcoded zero** (`li r7, 0` at the sole call site). Closed.
- **The score is not a bank**: `ComputeScore` (`0x6FA408`) recomputes it every tick from the
  other counters and `0x71B470` clamps to [0, 65535].
- **Five struct-B slots are Team Sneaking** (rule 7, named from the UI jump table at `0x9C2864`),
  which is why they read 0 across the whole archive.
- **b14 has no writer anywhere** — permanently zero on this build, not merely unexercised.

The full 167-byte frame, from the ELF builder `0xD42178` (the `statB`-present path, cross-checked
against the three live-pinned offsets):

| offset | size | type | meaning | confidence |
| --- | --- | --- | --- | --- |
| `0x00` | 4 | u32 | target character id | live-pinned |
| `0x04` | 1 | u8 | **Snake-role marker** — 1 on the Snake's report in both observed Sneaking rounds **including a loss** (the discriminator, 2026-07-24), 0 in every non-SNE report ever. Makes time-as-Snake and kills-as-Snake servable directly (Σ seconds / Σ kills over flag=1 reports). Whether other modes ever set it (or other bit values appear) is open | live-confirmed (SNE) |
| `0x05` | 2 | s16 | **kills** | live-confirmed |
| `0x07` | 2 | s16 | **deaths** (suicides included) | live-confirmed |
| `0x09` | 2 | s16 | **lock-on kills** — single-variable round 2026-07-23: exactly 3 in a 3-lock-on-kill round, zero across five kill rounds without | live-confirmed |
| `0x0b` | 2 | s16 | **score** — signed; like every counter it is the **delta of a store that clamps at 0**, and the store's banked scope is **the current game or stage, not the career** (a player with ~+22 career sum but a fresh game wired 0 on a −6 round; game-vs-stage scope still undetermined). Demonstrated mid-flight 2026-07-24: raw round points −10 on a +7 bank wired **−7** (store 7→0, clamped). **Suicides DO deduct −2 like any death** — settled by a 5-kill round whose only death was the player's own catapult fall: 29 = 15 − 2 + 10 + 6 exact; the 2026-07-23 "suicides deduct nothing" was pure clamp artifact | live-confirmed |
| `0x0d` | 2 | s16 | **knockouts dealt** (all types — melee slams that faint, tranq, sleep) — requires an actual faint; slams that don't knock out tick struct-B pairs instead | live-confirmed |
| `0x0f` | 2 | s16 | **knockouts received** (all types) — mirror of `0x0d`: victim's 3 in the 3-slam round, 2 in the 2-tranq round, exactly opposite the dealer's `0x0d` each time (2026-07-24) | live-confirmed |
| `0x11` | 2 | s16 | **headshots dealt** (bullets only — knife stabs and tranq darts to the head do not count, 2026-07-23/24) | live-confirmed |
| `0x13` | 2 | s16 | **headshot deaths** — across three rounds (two TDM, one Rescue) it exactly equalled the enemy's headshot count (5/5/1); strong, but a 3+ player match would make it airtight | medium-high |
| `0x15` | 2 | s16 | **stun headshots dealt** (non-lethal headshots — tranq darts to the head): 5/2/1 in the dart-headshot rounds, **0 in a 3-body-dart-stun round** (2026-07-24, the discriminator — so it is the hit location, not the weapon class; the interim "ranged/tranq knockouts dealt" label was wrong). The screen's HEADSHOTS row = `0x11` + this, both ·2. (An earlier OBSERVED.md note claimed this stayed 0 on the dealer; the wire falsified that too) | live-confirmed |
| `0x17` | 2 | s16 | **stun headshots received** — mirror of `0x15`: 2 on the dart-headshot victim, 0 on the body-dart victim (whose `0x0f` still counted 3), 0 in melee-slam rounds. The sleep-stab round's 1 suggests the neck syringe counts as one (or that round had an unnoticed dart headshot) | live-confirmed |
| `0x19` | 2 | s16 | **lock-on stuns dealt** — live n10. Stun handler `0x6EDC90` switches on a hit-class arg: `==1` writes the confirmed stun-headshot pair, `==2` writes this and `0x1d`. The same enum in the kill handler `0x6EEAF0` selects headshot vs lock-on, so four confirmed labels pin it. 0/517 archived (no round combined a lock-on with a stun weapon) | ELF-traced |
| `0x1b` | 2 | s16 | **deaths to lock-on** — received mirror of `0x09`, as `0x13` mirrors `0x11` (3 in the lock-on round, zero elsewhere) | live-confirmed |
| `0x1d` | 2 | s16 | **lock-on stuns received** — live n12, the victim side of `0x19`, same handler. **Retires the capture-era "rounds played" label**, which was already implausible: a once-per-round counter would wire 1 in every report under delta semantics, not 0 in all 517 | ELF-traced |
| `0x1f` | 2 | s16 | 1 for every player of a normally-completed round, 0 in mid-game teardown reports — "round completed" | medium |
| `0x21` | 2 | s16 | **zero-death round flag, mode-scoped condition**: TDM/DM = did not lose AND died zero times (won-but-died-twice 0; survive-but-lose 0; draws flag both zero-death players); **Rescue, Base and Capture = simply died zero times** (10/10 incl. losing-team survivors). Refits every prior anomaly | live-confirmed |
| `0x23` | 2 | u16 | **TEAM WIN flag — CORRECTED 2026-07-27, previously "team slot index"**. Live n15, an ordinary delta. It is column 5 of the score table, worth **5 in Rescue/Capture/Sneaking/Base/TSNE** and 0 in DM/TDM — the wire source for the "TEAM WIN ×5" category every mode table already listed. The old reading is refuted twice: a slot index is constant per player per game, but this flips 50/22/32 times for ch1/ch2/ch3 over 239 rounds, and in the 105 rounds where players disagree the top scorer holds the 1 in **96 cases against 5**. Both readings predict 0 in DM (no teams), which is how the old one survived | ELF + archive |
| `0x25` | 2 | u16 | **seconds in game/round** — not a counter: elapsed ms from `0x26DE10` divided by 1000 at send time (`0x27D80C`..`0x27D828`) | live-confirmed |
| `0x27` | 4 | u32 | **experience, absolute total** — but a **zero-extended u16** from blob key `0x164`, so the top two bytes are structurally 0 and the value wraps at 65535 (archive max already 49900). Read straight through, no baseline subtraction | ELF-traced |
| `0x2b` | 4 | u32 | extra-block flag/count (1 when the detail block is present) | high |
| `0x2f` | 116 | 58 × s16 | detailed stat block (struct B) — an itemised event breakdown, **not** the scoreboard categories, which live in struct A above. Partially mapped by the 2026-07-23 single-variable rounds (OBSERVED.md, "The OTHER-field experiment"); slot table below | positions high, labels per slot |
| `0xa3` | 4 | u32 | **hardcoded zero — closed 2026-07-27.** The serializer emits it from arg5; the sole call site in the binary passes `li r7, 0` (`0x27DC44`). No data path exists behind it. The WARN-if-nonzero tripwire can stay as a mis-parse guard, but it cannot fire from this client | ELF-traced |

**The running-max family (cracked 2026-07-24 against 66 stored reports + the server's own stage
rotation log).** Several B slots are not per-round counts. The client keeps a **per-stage
best-round record** (store-if-greater, zeroed on stage rotation — DM rotates every round, the
observed TDM rotation every 2) and the wire carries the **delta of that record**, like every other
counter. So a slot reads as the round's count only the first time that count is a new stage best;
an equal round later in the same stage sends 0, a better one sends the difference (observed: B0 =
2,0,2,0 across a 4-round/2-stage TDM with constant 2 kills; B2 = 1 when a 3-headshot round followed
a 2-headshot round). **Accumulation caveat (corrected 2026-07-24 late):** summing these deltas
reconstructs the record only *within one stage* — across stages the sum inflates without bound
(two separate 5-streak stages sum to 10; the career best is 5). A career record slot must be
served as a max over per-stage records, or derived directly from the ordered per-round rows —
never as a plain sum. The same warning applies to B24, which is an absolute per-stage snapshot,
not a delta at all. How the original backend accumulated these is unobservable; only the screen
semantics ("consecutive", a record) constrain the choice.
This retroactively explains every old "matched kills N/N" read: those captures were one round per
stage, where max ≡ count.

Struct B slots (0-based; everything not listed has never been observed nonzero). Per the
no-duplicates rule, "matched X" means exact correlation in N/N observed rounds, not identity:

| slot | evidence | reading |
| --- | --- | --- |
| B0 | max-family; **streak-vs-total split 2026-07-24**: a 2-kills-with-deaths-between round wired 1, not 2 — it tracks the best unbroken run, which equalled round kills in all earlier rounds only because testing killed in unbroken streaks | **best consecutive kills this stage** (streak record, running-max delta) — feeds Personal Stats "Consecutive Kills" |
| B1 | max-family, deaths side (includes suicides); a 2-deaths-never-consecutive round wired 1 | **best consecutive deaths this stage** (streak record) — Personal Stats "Consecutive Deaths" |
| B2 | max-family; 2 separated headshot kills wired 1; tranq headshots don't count (bullets only, like `0x11`); NOT terminal blows (0x43a2 showed 3 terminal vs B2=1) | **best consecutive headshots this stage** (streak record) |
| B3 | 3 in a 3-grenade-suicide round, 5 in a 5-suicide round; **3 in the 3-falling-death round — environmental self-deaths count** | **suicides** (incl. falls) |
| B13 | **= total time using ENVG, seconds** — 28 after ~30 s wearing a map-pickup ENVG (2026-07-24) | **ENVG time (s)** (Personal Stats slot 14) |
| B15 | **= catapult uses** — 3 in the 3-catapult round (2026-07-24) | **catapult uses** (Personal Stats slot 16) |
| B16 | **= boosts given** — 4 in the 4-boost round | **boosts given** (Personal Stats slot 17) |
| B17 | **= falling deaths** — 3 in the 3-fall gesture round (2026-07-24) | **falling deaths** (Personal Stats slot 18) |
| B18 | **= times caught in trap** — 6 triggers with only 2 fatal wired 6 (catches, not deaths); the trap owner's kills credit as ordinary kills | **trap catches** (Personal Stats slot 19) |
| B5 | **= friendly kills** — 3 in the FF round (2026-07-24); they do NOT count in `0x05` kills, and are score-neutral (no penalty, no credit) | **friendly kills** (Personal Stats slot 6) |
| B6 | **= friendly stuns** — 2 in the FF round; not counted in `0x0d`; the victim's received-side counters (`0x07`, `0x0f`) tick normally, friend or foe | **friendly stuns** (Personal Stats slot 7) |
| B7 | **= salutes** — 3 in the 3-salute gesture round (2026-07-24); the hack round's 1 was a pre-scan salute | **salutes** (Personal Stats) |
| B8 | **= preset radio message uses** — 2 in the 2-radio gesture round; the plain-rifle round's stray 1 was a radio call | **preset radio uses** (Personal Stats) |
| B10 ↔ B11 | dealt/received **pair** (exact both sides, three times); moved by CQC grabs (4), barrels (3), grab practice (11 received), and the hold-up-heavy hack round (11); NOT by grenades/knife/rifle kills | CQC-contact-flavoured (grabs/hold-ups) |
| B12 | **= rolls** — 4 in the 4-roll gesture round (2026-07-24); the whole history refits (1 in an otherwise-empty round = one roll; 7 in the body-dart round = dodge-rolling; 3 per grenade round = rolling from blasts; 0 in the stationary lock-on round and practice). Plain per-round count, NOT max-family — 1-roll rounds in the same stage each wired 1 (the earlier max classification over-read a 1-then-0 pair) | **rolls** (Personal Stats) |
| B19 | **= hacking count, screen-confirmed ·5** (2026-07-24): first nonzero ever — 3 with 3 successful SOP scans, screen HACKING=3x5, total exact. Each hack also credited an assist (B37 ticked 3 in the same 1v1 round) | **hacks (SOP scans)** |
| B20 | **= time in cardboard box, seconds** — 66 after sitting in a box "a little more than 60 seconds" (2026-07-24) | **box time (s)** (Personal Stats) |
| B21 | **= cardboard box uses** — 1 in the box round (equipped once); the earlier "1 alongside the slam-faint / stun-adjacent" sighting was almost certainly an unremembered box use, that reading retracted | **box uses** (Personal Stats) |
| B22 ↔ B23 | dealt/received **pair** (exact both sides, twice); slams/knockdowns incl. practice (8 received) — ticks without a faint, unlike A `0x0d` | slam/knockdown-flavoured |
| B24 | TDM only (0 across every DM round incl. wins); the event is exactly `0x21` (survive-but-lose and win-but-die both proven inert); resets on rotation; quit-teardown snapshots the pre-round value. **Settled by a 6-round stage (2026-07-24)**: pattern F,F,F,death,F,F wired 1,2,3,3,3,3 — a count would read 4,5 at the end; the best-run record holds at 3 | **TDM Consecutive Survivals** (the screen's name; ksy field `tdm_consecutive_survivals`): the **longest run of back-to-back survivals this stage** — the most survival rounds in a row, NOT a count of survival rounds (F,F,death,F,F,F has five survivals but wires 3). Survival = won + zero deaths. Absolute snapshot; resets on rotation so runs cannot span stages; career slot 25 = max(career, B24). Predictively confirmed: a second 6-round stage's 1,2,2,2,2,3 was called in advance |
| B35 | **= wakes (waking a stunned teammate), screen-confirmed ×2** (2026-07-24): a 3-wake round wired B35=3 and score 2 = wake·2·3 − deaths·2·2 exactly — wake pays into the wire score | **wakes** |
| B36 | **combo points: Σ streak·(streak−1)/2 over each unbroken kill run** — settled 2026-07-24 when streaks 2,2,1 wired 2 (not the round-total triangular 10) with the score exact. Deaths DO reset it; the earlier "pure function of round kills" read survived only because every test round was one unbroken streak (the 4-kill/5-death row was a genuine 4-run). Plain per-round value (repeats, unlike max-family). Screen-confirmed as the OTHER row's kill component — but OTHER is a superset; a much-stunned player showed OTHER=5 with B36=0 (see the formula notes) | **feeds the OTHER score category** — kill-combo bonus, ·1 |
| B37 | **= assists, screen-confirmed ·3** (2026-07-24): screen ASSIST row 3×3 with B37=3 on the wire, total exact; previous round's B37=2 (two tranq setups before teammate kills) decomposes its score exactly at ·3 too. Stun-setups earn it; two pure health-damage setups earned nothing (B37=0, score 0) — damage alone may not qualify | **assists** |
| B39 | matched the KILL 1ST PC screen line 4/4 (incl. a 0) | **kill-1st-place count** |

**Slots named 2026-07-27 by finding their gameplay writers** (all previously `[UNKNOWN]`, all
0/517 on the wire — which turned out to mean "the mode was never played" or, for B14, "no writer
exists"). Full evidence per slot in the `.ksy`:

| slot | writer evidence | reading |
| --- | --- | --- |
| B14 | **identically zero, re-audited.** Three sites *do* write byte `0x58` — `0x27D4DC` (init zero) and `0x71B3B8`/`0x71BDC0` (host-only loop copying baseline over live) — so the original "no writer anywhere" was false. But none can make `live[n31] ≠ baseline[n31]`, and the wire field is that difference (`subf` at `0x27D9xx`) | **permanent zero, safe to treat as such.** The conclusion survived; its stated reason did not, and the sweep behind it was right by luck rather than method. n16 gets the same verdict but is a different nothing — unread *and* unwritten, where n31 is read every round and wires the zero. The slot 15 label genuinely *is* "Time as Dedicated Host" and the live falsification stands on its own; whatever feeds it, it is not this |
| B31 | round-end award code, else-branch of B30 fully_defended | **Rescue solo team wipe** — every member of a losing team of 4+ last killed by the same player |
| B32 / B33 | `0x6FB8A0(spotter, spotted)`, keys `0x8c`/`0x8e`, reached from the melee/spot handler `0x6ED088` under `cmpwi 7`; the sibling arm is the Snake-spotting writer of B53/B54 | **Team Sneaking spot / spotted pair** — the TSNE twins of B53/B54. B32 scores ×3; B33 scores nothing |
| B38 | **event 8** of the host-only dispatcher `0x6ED650` (write `0x6ED784`, key `0x72`), raised only at `0x778D20` after `kill(slot, slot, 0, 0)`; branch `player->[0x90] == 191` in the death-cause classifier `0x778380`; gated on round-flags bit `0x4` | **deaths caused by the HEADSHOTS ONLY penalty** — named 2026-07-28. Bit `0x4` is the per-round "Headshots Only" host toggle (bit `0x2` is "Drebin Points"; the two are a three-way radio, 0/2/4), and state 191 has one entry point in the binary, reachable only under that flag. 0/551 because every archived round carried `flags = 0`. Predictions: b38 and B03 move together, the death names no killer and no weapon, and it stays 0 in Normal/Drebin rounds |
| B43 | `0x706BB8` key `0x90` at `0x706E90` under `cmpwi 7`, against the mode-2 arm's key `0x88` = B41 | **TSNE first pickup**, ×5 |
| B44 | `0x7070CC`/`0x707174`/`0x708584`/`0x70862C` key `0x92`, quantum `0x1770` = 6000 | **TSNE carry time**, in 2-second ticks. Scores nothing |
| B45 | `0x706A10` key `0x94` at `0x706BAC` under `cmpwi 7`, against the mode-2 arm's key `0x7e` = B27 gako_saved | **TSNE goal delivered**, ×3. **Kills the `training_mode_time_s` label** — it is a per-goal count, not a duration |
| B52 / B57 | same role-tested path as B51 snake_kills, different role byte | **kills of / knockouts dealt while holding the second Sneaking special unit.** Mechanism confirmed; the Mk.II identity is `[PREDICTED]` from the ×4 score column matching the screen's `MK.II KILL ×4`, the `%d Mk.II destructions` award family and the `MK2_SKILL` string |

**Rule 7 is Team Sneaking**, read from the UI's rule-name jump table at `0x9C2864` (cases land on
`Rule_Eng_DM`/`_TDM`/`_RESCUE`/`_CAP`/`_SNEAK`/`_BASE`/`_TSNE`/`_COOP`), which also gives
2 = Rescue — independently corroborated by the mode-2 branch writing B27.

**Two Rescue slots gained mechanisms in the same pass, and one reading was then refuted live.**
The "objective picked up" method `0x706BB8` keeps a per-round latch (bit `0x100` of
`[this+0x668]`): the **first** grab takes the unlatched path and bumps B41, later grabs fall to
`0x706D7C` and bump B29. That was published as a partition — B41 = first grab, B29 = subsequent
grabs. **Two live Rescue rounds with exactly one pickup each wired B41 = 1 AND B29 = 1**, where a
partition predicts B29 = 0, so it is not a partition: the first pickup feeds both, and B29 counts
every pickup including the first (restoring the original capture-era note). A fall-through fits
the counts; the control flow has not been re-read to confirm it, so the counts are the fact and
the mechanism is open. Same failure mode as the `0x6ED650` shared-tail mis-attribution — two arms
of a branch read as exclusive when they share a continuation.
And **B42's units are 2-second ticks, not seconds**
(quantum 6000 against the 3000-per-second used by the confirmed durations B13/B20/B40), so the
archived 7 and 21 are **14 s and 42 s**.

**The SNE dogtag scoring question is answered**: both of the pair feed it, at different rates —
**B47 ×3 and B48 ×5** in Sneaking. The old note expected to settle this with a round where the
two differ; the score table settles it without one.

**Formula scope (2026-07-24):** the formula below is confirmed for **TDM and DM only**;
each mode retunes multipliers over shared categories. **Sneaking's table is named but not
fully decomposed** (screens + partial wire confirmation): `DOGTAG SCORE×1 (per-tag values
vary — no direct slot), HOLDUP(B50)×2, KILL×3, DEATH×−2, HEADSHOT(0x11+0x15)×2,
SNAKE KILL(B51) 6/kill, TEAM WIN×5, HACKING×5, MK.II KILL×4 (never exercised), OTHER×1` —
the early-round scores 94/27 remain undecomposed pending dogtag values, and B36 feeds
something beyond the kill-combo there (5 from 4 kills is unreachable). **Rescue's table is mapped from a
live screen + one exact decomposition** (18 = kill·7 + headshot·3 + target-defence(B28)·3 +
team-win·5): `KILL×7, HEADSHOT×3, STUN×7, TEAM WIN×5, ASSIST×5, GOAL(B27)×3,
TARGET DEFENCE(B28)×3, OTHER×1` — note Rescue HAS a team-win bonus where TDM has none, and
its OTHER row tracks the B42 carry stat imperfectly (18 vs 21, gap open); deaths deduct
silently (5 = 7 − 2 in the no-delivery round) though the screen shows no deaths row.
**Base's table (first round, both screens exact)**: `KILL×3, SOP DESTAB(B26)×10, TEAM WIN×5,
CONTROL(B25 bases conquered)×5, STUN×3, WAKE×3, ASSIST×3, OTHER×1` — wake pays ×3 here vs
TDM's ×2, and OTHER carried B40 (a hidden capture-points counter, exactly captures×4).
**Capture's table (first round, exact)**: `KILL×5, HEADSHOT×3, PUT COUNT(B46)×1, STUN×5,
TEAM WIN×5, WAKE×5, GOAL(B34)×5, OTHER×1` — kills pay ×5 here; the observed OTHER=5 with one
goal had NO carrier slot (client-computed 5-per-goal candidate, open).

The scoreboard labels were **confirmed 2026-07-22** by a two-round TDM capture whose per-player
totals (kills/deaths/score/headshots/stuns) matched the summed slots exactly — see OBSERVED.md,
"The 0x4390 scoreboard". The score formula was **settled 2026-07-24** when a result screen was
read alongside its own wire reports; the screen's category rows are
`KILL×3, DEATHS×−2, HEADSHOTS×2, HACKING×5, ASSIST×3, STUNS×2 (TDM), WAKE×2, OTHER×1` (the
capture-era "wake·2" guess is real: a later 3-wake round confirmed WAKE = B35, paying ×2 on
the wire) and the reader's own row summed to the wire score exactly (1·3 + 6·2 + 3·3 + 5·2 = 34):

`kills·3 − deaths·2 + (headshots 0x11+0x15)·2 + hacking·5 + assist(B37)·3 + stun·M + wake(B35)·2 + other(B36)·1`

> **SETTLED 2026-07-27 — the table itself was found, and the formula above is superseded.**
> `ComputeScore(rule, playerSlot)` at `0x6FA408` walks a **37-column × 11-row table of s8
> coefficients** (row = game rule, `mulli r25,r3,37` at `0x6FA448`; a jump table at `0x6FA4C4`
> maps each column to the live counter it reads). The table is **not static in the ELF** — its
> base is `*(0xFDE2AC) = 0x1659F24` in `.bss`, filled at runtime by the GCX native command at
> `0x6FA1B8` from `-rule N -score <37 ints>` directives in the stage script. The values were
> read off the disc (`o/stage/n002a|n003a|n004a/scenerio.gcx`, `proc23`) and are byte-identical
> across stages. Rows: 0 DM, 1 TDM, 2 Rescue, 3 Capture, 4 Sneaking, 5 Base, 7 Team Sneaking;
> rules 6, 8, 9, 10 are never emitted and score nothing. **The six playable rule ids are
> live-confirmed (2026-07-27)**: one game created per mode in a known order, reading the rule
> byte from the client's own host settings (`0x4310`) — TDM 1, Rescue 2, Capture 3, Sneaking 4,
> Base 5, DM 0 (games 219-224). Six single-variable observations; the earlier "identified by
> matching coefficients to decomposed mode tables" is retired for rows 0-5.
>
> **The missing stun deduction exists, and the guess was half right.** The term is on
> `knockouts_received` — **−2 in DM, −1 in TDM, −1 in Sneaking, 0 elsewhere** — and **B4
> self-stuns have NO coefficient in any row**, so that half is refuted. Frame 319 needs no
> extra term: TDM raw = 2·2 + 2·2 − 1 = 7, wired 4 because the clamped total was at its floor.
> **165 of 172 nonzero-score frames in the archive reproduce exactly**; the residuals are clamp
> effects and the off-wire OTHER column.
>
> **The OTHER row is not reconstructable from the wire.** Column 36 reads live **n75**, which
> the 0x4390 frame does not serialise anywhere, and pays ×1 in Rescue, Capture and Team
> Sneaking. Every attempt to decompose OTHER as "B36 + knockouts-received + mode extras" was
> fitting around a counter that is not present. B42, long suspected of feeding the Rescue OTHER
> row, has a coefficient of **zero in every rule**.
>
> Full coefficient table by wire field: `dev/proto/inbound/mgo2_cmd_4390_c2s.ksy` header doc. The raw rows as
> the stage script emits them, verbatim from `o/stage/n002a/scenerio.gcx` `proc23` (identical in
> `n003a` and `n004a`), 37 s8 columns each:
>
> ```
> rule 0 DM    3 -2  3 -2 2 0  0 0 0 5 0 0 5 0 0  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
> rule 1 TDM   3 -2  2 -1 2 0  0 5 2 5 3 0 0 0 0  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
> rule 2 RES   7  0  7  0 3 5 -5 0 0 0 5 0 0 0 0  0 3 3 2 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3
> rule 3 CAP   5  0  5  0 3 5  0 3 5 0 3 0 0 0 0  0 0 0 0 0 0 0 0 0 0 0 5 1 0 0 0 0 0 0 0 0 3
> rule 4 SNE   3 -2  2 -1 2 5  0 5 2 2 3 0 0 0 0  0 0 0 0 0 0 0 0 0 0 0 0 0 3 5 5 3 0 6 4 2 0
> rule 5 BASE  3  0  3  0 0 5 -5 0 3 0 3 0 0 1 5 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
> rule 7 TSNE  5  0  5  0 0 5  0 0 5 0 0 0 0 0 0  0 0 0 0 0 0 3 0 5 0 3 0 0 0 0 0 0 0 0 0 0 5
> ```
>
> Column → live counter → wire field (`—` = not on this wire):
>
> ```
>  0 n00 kills      1 n01 deaths     2 n04 ko_dealt   3 n05 ko_recv
>  4 n06+n08 headshots (summed)      5 n15 team_win   6 n22 B05      7 n36 B19
>  8 n37 B35        9 n42 B36 *     10 n43 B37       11 n44 B38     12 n45 B39
> 13 n47 B40       14 n48 B25       15 n49 B26       16 n50 B27     17 n51 B28
> 18 n52 B29       19 n55 B41       20 n56 B42       21 n57 B32     22 n58 B33
> 23 n59 B43       24 n60 B44       25 n61 B45       26 n62 B34     27 n63 B46
> 28 n64 B47       29 n65 B48       30 n66 B49       31 n74 B57     32 dead column
> 33 n68 B51       34 n69 B52       35 n67 B50       36 n75 —  OTHER, off-wire
> ```
>
> `*` Columns 9 and 36 are special: the loader clamps their coefficient to 0/1 and stores the raw
> value into a side array. Column 9's raw is the *step size* for B36 (`0x6EEE4C`), which then
> scores ×1 — which is why DM/TDM show 5 in the row above but pay 1 per combo point.
>
> Worked example, live DM round 2026-07-27 (game 226, chara 1): 5 kills, 2 lethal headshots,
> B36 = 10, B39 = 1, no deaths or knockouts → `5·3 + 2·2 + 10·1 + 1·5 = 34`, wire score **34**.
> The same round's loser wired **0** against a raw −10 (5 deaths, nothing banked) — the clamp.
>
> **Decompose against CUMULATIVE counters, not round counters (live-confirmed 2026-07-27).**
> `ComputeScore` reads the LIVE counters, which accumulate across the whole game — only the
> baseline is rewritten per report. So the wire score is
> `clamp(ComputeScore(cumulative)) − clamp(ComputeScore(as of last report))`, and a per-round
> decomposition is right only for a game's first round. Base game 229 round 2, a player with
> 3 kills, 3 headshots, 1 team-kill, 2 captures, capture-time 8, who had also team-killed in
> round 1: per-round (B05 = 1) predicts `3·3 + 1·5 − 1·5 + 2·5 + 8·1 = 27`; cumulative
> (B05 = 2) predicts **22**, and the wire says 22. Round 1 wired 0 from a raw −5 clamped at 0,
> so the delta is 22 − 0. The other two players in that round reproduce identically
> (`1·5 + 1·5 + 4·1 = 14`, wire 14; and all-zero, wire 0).
>
> That round also **confirms the friendly-kill −5** — the two readings differ by exactly one
> application of it — and shows **headshots scoring nothing in Base** (column 4 is 0 for
> rule 5; three headshots contributed zero).

- **Stun multiplier M is mode-specific: 2 in TDM (screen-confirmed), 3 in DM** (DM round
  8 = 3+1·3+2 exact). The 2026-07-23 `stun·3` revision came from DM-only rounds and the
  capture-era `stun·2` was TDM — both right for their mode.
- **The headshot category = `0x11` (lethal) + `0x15` (stun) headshots, ·2 — settled 2026-07-24
  by the body-dart round**: 3 body-shot dart stuns + 5 headshot kills scored 41 = 15 + 5·2 +
  3·2 + 10 exactly (body darts added nothing beyond stun·2, and `0x15` itself wired 0). The
  screen's HEADSHOTS row shows the sum (6 = 1+5 in the dart-headshot round; 5 = 5+0 here);
  wire `0x11` and B2 are bullets-only.
- **Assists pay ·3 and land in B37** — the earlier "assist inert" reads were wrong (see
  OBSERVED.md); stun-setups before a teammate kill earn them, pure health-damage setups did not.
- **`other` is B36 (kill-combo points: Σ streak·(streak−1)/2 per unbroken run — deaths reset
  it) plus a knockouts-received component ·1 — WIRE-PROVEN 2026-07-24**: a Sneaking round's
  screen OTHER=3 equalled the player's 3 knockouts received (B36=0) and his wire score 22
  included it with no clamp anywhere; the two earlier clamp-hidden sightings validate
  retroactively. (A Snake-side OTHER=6 alongside 3 stuns dealt suggests stuns·2 may also
  route through OTHER in SNE — single sighting, open.)
- **`hacking·5` = B19, live-confirmed** (3 hacks → 15 points, total exact). It is distinct from
  B39's kill-1st-place ·5, which has only ever appeared in DM rounds — both ·5 categories are
  real, resolving the capture-era ambiguity. **A successful hack also credits an assist** (B37
  ticked 3 alongside B19=3 in a 1v1 round with no teammate to earn them otherwise).

**The wire score is the delta of live n03, and n03 is NOT an accumulator** (corrected
2026-07-27; the "banked store, resets per game or per stage?" question was malformed and is
retired). `ComputeScore` recomputes the whole score from the player's other live counters each
tick, and `0x71B470` clamps it to **[0, 65535]** at `0x71B510`..`0x71B534` before the single
store into n03 — the only write to that field in the binary. A negative on the wire therefore
means the recomputed clamped total came out below where it stood at the last baseline, not that
a bank absorbed a loss. **Suicide-class deaths deduct −2 like any death** (settled 2026-07-24,
catapult-fall decomposition). No round-win bonus exists in DM/TDM; the other five rules pay 5 for
a team win via `0x23`.

Each report is one round for one player; a kill-less round sends the frame with these slots zero.
A **short 51-byte** form exists in the serializer (selected by a NULL struct-B pointer at
`0xD42400`), but it is **unreachable from the only caller**, which always passes a stack address
— 517/517 archived frames are the 167-byte long form. Parse it, never expect it.

**Counters saturate, they do not wrap.** Every gameplay bump goes through `0x6A9758` and computes
`min(v+1, 0xFFFF)`, so the previous note here ("u32 values truncated to u16, so any above 65535
wrap") is wrong: a wrapped low word is not a possible wire value. The wire value is
`(s16)(u16)(live − baseline)` over zero-extending loads, so a counter that goes *down* still
wires negative.

**What we consume (since 2026-07-23):** experience is applied to the character (per character
since V59; it was an account main/alt pool) with the aborted-dock policy, and the **whole decoded frame is stored as one
`round_report` row** — struct A by slot (confirmed labels named, the rest by wire offset),
struct B as a 58-element array, seconds, totals, flags. Every stats and history surface
derives from these rows at query time (the met-players history is a self-join on `game_id`);
the earlier `chara_stats` lifetime accumulator was write-only and is dropped. The unlabelled
counters — hacking, assist, wake, "other", `0x0f`, and the `0x2f` detail block — were all zero
in the capture, so they
are dropped rather than guessed; a match exercising them would let them be labelled. Experience
and stats apply when the target is in the game or the round-membership set (`game_round`). Reply
`0x4391`, result 0 always; validation failures are logged, not surfaced.

(Nomad's `0xB8`-minimum layout was another build's — its aborted byte at `0xB7` does not exist in
a 167-byte report; mgo2-server's single-byte struct fits neither the length nor the fields. Both
disregarded.)

## `0x43a0` — pass host

**Client → server**, `HostGameController.passHost`. **Confirmed against a live client
2026-07-22**: a real host change arrived as `00000001 00000002` — `u32` sender's own chara id
(unused, as in Nomad), `u32` new host's chara id — the game was re-keyed to the target, the old
host left the roster and returned to the browser, and the new host's client took over the
`0x4398` heartbeat and re-registered, all without a hiccup. Joins keep working because `0x4320`
reads the host endpoint from `chara_connection` by the game's host id at join time and the new
host registered its own on lobby entry. The target must be another player in the game or the
request is logged and dropped. Reply `0x43a1`, result 0. (Naming caveat: mgo2-server calls
`0x43a0` "pass round" and has a separate `0x4348` "host pass"; Nomad's `0x43a0` is the pass we
implement.)

## `0x43a2` — per-player weapon tallies (fully decoded 2026-07-24)

**Client → server**, acked `0x43a3` (result 0). **One packet per scoring player**: at round
end the host sends each player's `0x4390` stat report immediately followed by that player's
`0x43a2` weapon breakdown; players with an empty list are skipped (the caller's count==0
early return). A three-scorer round therefore emits three, interleaved with the reports.
The 2026-07-22 "never sent" verdict predates packet tracing; it fires in every mode
including DM. ELF: builder `0xD41AC0`, caller `0x27CC78`. Beware the history recorded in
OBSERVED.md: a night of winner/MVP/top-scorer/finishing-blow "confirmations" for the leading
u32 were all artifacts of reading only the last packet per round.

```
u32 chara id          — THIS packet's player. 0x43a2 is PER-PLAYER (one per player with a
                        non-empty list, sent right after their 0x4390; empty lists are
                        skipped). The night of winner/MVP/finisher theories (2026-07-24)
                        was a sampling artifact — only the last packet per round was being
                        read. A three-scorer round emits three, ids+tallies matching each
                        player's own stats.
u32 count             — number of entries (builder caps 0x7f; caller caps 50)
count × { u8 weapon id, u16 kills, u16 headshots (terminal blows), u16 faints caused }
```

The caller walks the player's 127-slot, 3-bytes-per-slot round table and emits one entry
per non-zero slot. **The slot index is the weapon id and the triple is {kills, headshots,
faints} — live-confirmed 2026-07-24**: a deliberate AK102 round of one headshot + one body
kill produced exactly `{AK102: 2,1,0}`, splitting kills from headshots; other anchors
`{ST KNIFE: 1,0,0}` (the sleep-stab) and `{MOSIN N: 0,1,1}` (the tranq dart — dart
headshots count here though not in the scoreboard's lethal-bullets-only slot); and in the
three-scorer round each player's packet carried exactly their own kills. Semantics proven
alongside: entries require a terminal event (wounding shots tally nothing) and melee/CQC
events never appear (they live in the `0x4390` stun pair). Weapon names: the ELF's
141-entry master table, `dev/docs/WEAPONS.md`. It carries **no token, no game/room id, and
no round counter** (the caller references none of the token storage; see the
reporting-model note under `0x4390`). **Stored since 2026-07-28** in `round_weapon_tally`
(one row per weapon per report, `rule` copied at write time like `round_report`), which is
what feeds `0x4107` slot 64 Knife Kills and every future weapon line; storing per-player
per-weapon tallies is backlogged.

## `0x43c0` — edit game name / comment / password

**Client → server**, sent by the host's admin menu on "Edit name/comment/password" (the admin
sweep of 2026-07-22 mapped the action to this command). **Blowfish-encrypted**, like the other
host-settings pushes. Decoded from the ELF 2026-07-26 — single-source trace, never captured.

**162 bytes:**

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 16 | ISO-8859-1 | game name |
| `0x10` | 128 | ISO-8859-1 | comment |
| `0x90` | 1 | u8 | password enabled |
| `0x91` | 16 | ISO-8859-1 | password |
| `0xa1` | 1 | u8 | unknown |

The field identities are not guessed from the widths — they come from the **sender's own
validation** at `0xD41668`–`0xD416FC`, which checks each field before building the packet. Note
the password field is **16** bytes here where `0x4310` gives it 15; that is what the builder
writes, and the discrepancy is not explained.

Unhandled by us. It is a real gap: a host who renames a running game will have the browser keep
showing the old name.

## `0x4341` / `0x4343` / `0x4345` / `0x4347` — peer-register acks

Replies to the host's three blocking peer-registration round-trips (`0x4340`, `0x4344`, `0x4346`)
plus the disconnect ack, all `{u32 result, u32 key}`. Parsers `0xD33344`, `0xD33448`, `0xD33248`;
javadoc in `HostGameController.java:79-107`, which the ELF trace of 2026-07-26 agrees with.

**The second word is a dynamic request handle, not a fixed status slot** — and this is the part
worth writing down, because it is unlike every other ack in the range. The parsers **search a
pending list by value** (`0xD33178`, returning −266 if the value is absent). Everywhere else in
`0x43xx` an ack indexes its transaction by a literal id compiled into the parser. Here the key
must be **echoed from the request**.

The failure mode is nasty: a mismatched key **parses cleanly** — right length, right shape, no
error surfaced — and simply fails the list lookup, leaving the host's per-peer state machine to
sit until its 30-second (`0x7530`) deadline and then disconnect the peer. Nothing in the log says
why. Anyone tempted to answer these with a constant should read that sentence twice.

# ADDLIST — friend / blocked relationships (`0x4500` / `0x4510` / `0x4580`)

The in-game player list lets a player set another as **friend** or **blocked**, or clear it back
to **none**. Fully mapped from the ELF and confirmed against a live client 2026-07-22 — a player
cycled none → friend → blocked → none through the whole loop in one session with every transition
sticking. All three send/reply pairs are handled in `HostGameController`; the relationships are
stored in `chara_relation` and replayed into the `0x4101` login arrays.

**Two things make this exchange unlike every other list in the protocol**, both read straight
from the binary (parsers at `0xD47110`, `0xD46B60`, entries at `0xD467C0`):

- **A change is a remove followed by an add.** Setting friend→blocked sends `0x4510 {state 0}`
  (remove the friend) then `0x4500 {state 1}` (add the block); clearing to none sends `0x4510`
  alone. Every `0x4510` blocks on its reply — silently dropping it (as we did until the parser
  was traced) locks the ADDLIST UI, which was the whole mystery.
- **The add/remove replies are single packets, not start/entries/end triples.** The client has
  **no parser for `0x4501`/`0x4503`** (they hit the −0x46 no-handler default); only the bulk
  roster fetch `0x4580` uses a real triple.

## `0x4500` — add / change relationship

Request `{u8 state, u32 target chara id}`, state **0 friend, 1 blocked** (confirmed both live).
Persists the relation and replies with the added entry as one **`0x4502`** packet — 25 bytes:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | lead word — **0** to carry a body; nonzero = empty/count-only frame |
| `0x04` | 4 | u32 | target character id |
| `0x08` | 1 | u8 | state (0 friend, 1 blocked) |
| `0x09` | 16 | ISO-8859-1 | target name, NUL-padded |

## `0x4510` — remove relationship

Request `{u8 state, u32 target chara id}`, the state being the one **removed**. Deletes the
relation and replies with one **`0x4512`** packet — 9 bytes, **field order differs from
`0x4502`** (state before id, no name):

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | lead word — 0 to carry a body |
| `0x04` | 1 | u8 | state removed |
| `0x05` | 4 | u32 | target character id |

## `0x4580` — bulk roster fetch (answered empty)

The standalone Friends/Blocked menu (distinct from the in-game ADDLIST), request a single
`{u8 state}`. Reply is a real triple: `0x4581` start (4-byte result), N × `0x4582` entries
(**59-byte** records — u32 id, char[16] name, u16 at `0x14`, char[16], u32, char[16], u8; only id
and name are of known meaning), `0x4583` end. **Never observed live**, and we cannot fill the
59-byte record honestly, so it is answered **empty** (start then end) — enough that the menu
cannot hang. The client's table caps at **32** entries.

**The subsystem index is not fixed: it is `0x51 + the u8 state` from the request** (ELF
2026-07-26, single-source trace, `0xD46ABC`). Friends and blocked are therefore **separate
transactions** with separate wait slots, not one list with a filter. A reply must be keyed to the
state that was asked for; answering a blocked-list request against the friends slot leaves the
friends screen waiting.

> **Read this before populating the list.** The end handler `0xD466D4` copies a record into the
> display array **only if the u16 at record offset `0x14` is nonzero**. Every record with a zero
> there parses perfectly, is counted, and is then silently dropped — producing an empty roster
> screen with no error anywhere. We currently send nothing at all so it cannot bite yet, but the
> obvious first implementation (fill id and name, zero the fields whose meaning is unknown) fails
> in exactly this way. Traced 2026-07-26; single-source ELF, not confirmed live.
>
> **The sibling `0x4603` does no such filtering** — byte-identical record family, different
> behaviour. Per the no-duplicates rule these two have matched shape in the one comparison made;
> this is the first observed *divergence* between them, and it is a behavioural one.

## `0x4600` / `0x4680` / `0x4684` — player search and match history

**Client → server**, `SocialGameController`. All three observed live 2026-07-23 (each stalled its
screen unanswered) and traced from the binary the same day. All three are **start / item / end
list triples** like the game browser, each keyed to a subsystem index the client blocks on
(`0x53`, `0x1D`, `0x1E` respectively). The start and end packets each carry a
`{u32 result code}` — **0 for success, not a count**. An earlier reading of these as counts was
wrong and only *looked* right because every live answer had been the empty triple (count 0 ≡
result 0); the first non-empty history produced `1032:00000005` — our count of 5 echoed as an
error (OBSERVED.md, "Error 1032:00000005"). Traced mechanics, common to all three (status setter
`0xD32E08`, result setter `0xD32E70`, per-subsystem slots):

- A **nonzero start** completes the transaction as failed immediately; the value is stored
  verbatim and rendered `%08X` in the screen's error dialog (screen codes: search `0x0C13`,
  history `0x1032`, details `0x1034`). A zero start resets the entry count and proceeds.
- The **end packet's u32 is stored into the same result slot unconditionally** and marks
  completion — the end value is the operative result on the success path, so **both start and
  end must be 0**.
- The client **counts item records itself** (table caps: search 100, history 64, details 32).
  Item packets are records back to back with **no per-packet count** — the parser reads until
  the payload ends, so records may be split across item packets freely.
- Player search alone also treats `-611` (`-0x263`) as an accepted "no results found" sentinel
  (start handler `0xD45DF0` branches on it; dialog screen `0x0C11` pairs with it). Traced but
  never tested live; we send the plain empty success triple instead.

A missing session gets an empty success list, not an error.

### `0x4600` — player search (sender `0xD46128`, replies `0x4601`/`0x4602`/`0x4603`)

Request, 18 bytes: `u8` match criteria (0 = partial, 1 = full — the builder rejects other values),
`u8` **ignore case**, then a 16-byte name.
The client does no matching of its own — **all four semantics combinations are server policy**;
ours is substring for partial, SQL-escaped.

**The second byte means IGNORE CASE, and `1` is the ignoring one** (live 2026-07-27; this file and
the spec previously called it "case sensitive", which is the opposite). Searching for `bob` with
**Case Insensitive** selected on screen arrived as `{0, 1}` and matched nothing against a character
named `Bob`; the client reported *"Unable to locate that character"* — correctly, because we ran a
case-sensitive query. The polarity is **the client's, not a per-screen quirk**: the clan-search
screen (`0x4b90`) sends the same `{0, 1}` from its own toggles, so both searches read `1` as
ignore-case and a case-sensitive search is still reachable with `0`.

An integration test had asserted the old reading. Its only authority was the field's own name — no
capture, no disassembly — which per `CLAUDE.md` is a regression guard, not a correctness check. Result records (`0x4602`, parser `0xd45f38`,
59 bytes each, client table caps at **100**): u32 id, 16-byte name, u16, 16 bytes (likely clan
name), u32, 16 bytes, u8 — tail fields inferred only from width; we send zeros there. The
SaveMGO Nomad dev-era test payload (`search-player.bin`, tier 4, decoded 2026-07-23 —
OBSERVED.md) fills the record as a **presence card**: {u32 chara id, 16B name, u16 = 36
(level/rank?), 16B current lobby name, u32 = 1 (in-game flag?), 16B current game name,
u8 = 4 (lobby id?)} — plausible labels worth a fingerprint pass if search results ever
need to show location.

### `0x4680` — match history list (sender `0xD3B864`, replies `0x4681`/`0x4682`/`0x4683`)

Request: u32 character id. Records (`0x4682`, parser `0xd3b5fc`, 25 bytes each, table caps at
**64**): u32, u32, 16-byte string, u8 — positions from the ELF; labels are **candidates only**
(tier 4): the SaveMGO Nomad repo's dev-era test payload (`match-history.bin`, decoded
2026-07-23, OBSERVED.md) fills them as {u32 Unix timestamp, u32 id, 16-byte player/host name,
u8 0}. The client's history UI has a `%Y/%m/%d %H:%M:%S` format resource in the ELF menu blob
(found during the title/medal extraction), so a timestamp field is expected; the `0x4684`
request needs one field to be the selectable entry id. The first fingerprint attempt
(2026-07-23) put the row count in the start/end packets and the client refused the screen with
`1032:00000005` before reading any record — that is what exposed the result-code semantics
above; the corrected triple (result 0 both ends) is what is served now.

**Live fingerprint results (2026-07-23, same day):** the screen is a **met-players history** —
one row per player encountered, not per match. The leading u32 is **confirmed** a Unix
timestamp (sent 2001-01-02 01:01:01 UTC, rendered "01-02-2001 04:01:01" — date exact, time
+3h, emulated-clock timezone unresolved; rendered format MM-DD-YYYY, not the `%Y/%m/%d` ELF
resource). The 16-byte string is **confirmed** the row's player-name label. The second u32 is
a candidate character id: selecting a row opens a player context menu (Player Details /
Create Mail / Add to Friend List / Add to Block List), all player-scoped. "Player Details"
sends **`0x4220`** (player-card family — see its section), NOT `0x4684`; what triggers
`0x4684` is unknown again. Since 2026-07-23 the list is served for real: rows derive from
`round_report` (see `0x4390`) — every other character with a report in a game the viewer has
a report in, newest encounter first, capped at the client's 64. Pairing is per game, not per
round (the report frame carries no round counter). Soft-deleted characters appear under their
placeholder name. The u8 is sent 0 (cosmetically inert in the fingerprint).

### `0x4684` — match detail (sender `0xD3B778`, replies `0x4685`/`0x4686`/`0x4687`)

Request: u32 entry id selected from the `0x4682` list. Records (`0x4686`, parser `0xd3b42c`,
93 bytes each, table caps at **32**): u32, 64-byte string, 16-byte string, u8, u32, u32 —
plausibly per-player lines of one match. TEMPORARY fingerprint rows are served (result 0 both
ends), but the trigger is unknown: the history row's "Player Details" menu item sends
`0x4220`, not `0x4684` (live, 2026-07-23), so no UI path to `0x4684` has been observed yet.

## `0x4220` — player details (sender `0xD3B950`, single reply `0x4221`)

**Client → server**, `SocialGameController`. Observed live 2026-07-23 (the met-players history
row's "Player Details" menu item, unhandled at first — `No handler for command 4220`) and
traced from the binary the same day. Request: one u32, the selected player's id (both traced
call sites pass a stored per-row id — which history-record field that is gets confirmed by our
request log). Subsystem index `0x1C` (status/result setters `0xD32E08`/`0xD32E70`, as with the
list triples).

Reply `0x4221` is a **single packet, not a triple** (the dispatcher has no `0x4222`/`0x4223`):
201 bytes — `{u32 result}` (0 = success; nonzero skips every field read, completes the
transaction as failed, and the open screen's poll raises the error dialog — no fixed screen
constant in this path) followed by 197 bytes of fields, parser `0xD3D874`: u32 id echo,
16B **name** (confirmed), u32, u8, u8, u32, u32, u8, 128B **comment** (confirmed), u32,
16B **clan name**, u8 **membership state**, u32, u32, u8, u32 — with the u32 at wire
0x22 confirmed as **play time in seconds** (fingerprint 9503 → "02:38:23"). Its square button
("more details") sends `0x4102` for the card's character. Byte-exact layout with client struct
destinations: `dev/proto/outbound/mgo2_cmd_4221_s2c.ksy`.

**It carries real data since 2026-07-27.** This was still the fingerprint payload — `FP-DTL-NAME`,
`FP-DTL-CLAN` and numbered constants, sent to find out which offset drove which label. It did its
job and then nobody filled it in, which is why the clan read `----` until the player opened More
Details (which fetches `0x4103`, and *that* does carry a clan) and the value looked like it was
arriving late when this packet simply never had it.

- **The clan is a triple, not a name.** Wire `0xa7`/`0xab`/`0xbb` are `{u32 id, char name[16],
  u8 state}` — the same shape a clan takes in the session record at `session_ctx+0x1AA0`, in
  `0x4122`'s block, in `0x4b47`, in `0x4b21`'s head and in `0x4103`'s tail. **Sending only the name
  is not enough:** every reader traced so far checks the **id first** and treats 0 as "no clan"
  whatever the name says. That is what the `---` was.
- **Play time is the sum across game modes**, i.e. the same figure the personal-stats screen shows,
  because the client totals the per-mode column itself. Sending the raw stored aggregate read
  **six times short**. Separately, and still open: that total is inflated at all because the server
  stores one number and writes it into every mode row — there is no per-mode accounting.
- **`comment` renders correctly.**
- **LEVEL renders as 0 and is an open question.** Four candidate fields sit between the name and the
  play time — wire `0x18` (u32), `0x1c` (u8), `0x1d` (u8), `0x1e` (u32) — and are currently carrying
  a **live probe**: the values 1450 / 250 / 130 / 500, chosen so each maps to a *distinct* level
  (10 / 2 / 1 / 4) through the client's own experience table. Whichever level the card renders names
  the field. This is the probe design, **not an answer**; nothing here has been confirmed yet.

Sibling, **not yet observed**: `0x4210` (sender `0xD3A7D4`, no payload, subsystem `0x20`)
expects a reply triple `0x4211`/`0x4212`/`0x4213` (parsers `0xD3B01C`/`0xD3B2D0`/`0xD3AF24`,
records not yet decoded) — the "own player card / overview" family, distinct from `0x4220`'s
by-id detail. Unhandled; the no-handler log now dumps payload hex if it ever fires.

## `0x4128` — get post-game info

**Client → server**, `HostGameController.postGameInfo`. Reply `0x4129` is the `0x8b`-byte results
card (reply shape ELF-confirmed — see the constant's javadoc). Populated since 2026-07-22 at
reference parity: both references source exactly two fields from storage — the character's
**rank** and **experience** (grade points mirror experience) — and fabricate the rest; the
25-entry skill table repeats what the `0x4125` catalogue advertises (`0x6000`, or `0x2000` for
skills 17/20/22), the clan fields stay 0, and the trailing u32 echoes the character id.

**What `0x4129` is, identified by where its fields land** (ELF 2026-07-26, single-source trace).
Every field in the tail writes a slot that `0x4101` or `0x4122` already owns —
`ctx+22776` experience, `ctx+29304` clan id, `ctx+30333` rank. So this is not a results card in
its own right: it is a **partial re-send of the connect-burst character record after a match**,
overwriting the parts a match can change.

That has a consequence for the burst. The `0x4101`/`0x4122` slots those three land in were being
treated as fixed per-session values; if `0x4129` rewrites them at match end, they are
**match-mutable values, not constants**, and any of the still-unknown slots in those two packets
that `0x4129` also touches should be read the same way. Worth a pass over the unknown fields in
both, looking for `0x4129` destinations.


### The full field map, and the two fields it silently overwrites (2026-07-29)

The parser is **`0xD3C9A8`**, reached from the dispatcher `0xD387C8` (`cmpwi 16681` at `0xD388B4`).
Its destination base is `r29 = r27 + 22488` (`0xD3CA3C`) — exactly what `getLocalProfile` at
`0xD3A094` returns, i.e. **the same profile the connect burst filled**. Thirteen fields, none
cleared first, so this packet wins at the end of every round. The complete map is in
`dev/proto/outbound/mgo2_cmd_4129_s2c.ksy`; the summary:

| wire | width | -> profile | field |
| --- | --- | --- | --- |
| `0x00` | s4 | — | result; **non-zero skips the entire body** (`bne 0xD3CC1C`) |
| `0x04` | u1 | `+7845` | worn title |
| `0x05` | u4 | `+288` | experience |
| `0x09` | u1 | `+13097` | [UNKNOWN] |
| `0x0a` | u4 | — | skill count `N` |
| `0x0e` | 4N | `+11444 + idx*12` | skills `{idx, u2 value, flag}`; capped at 128, `idx` skipped unless signed-positive |
| `B+0` | u4 | `+13100` | [UNKNOWN] |
| `B+4` | u4 | `+292` | grade points (a second experience-scale quantity) |
| `B+8` | u4 | `+1172` | [UNKNOWN] |
| `B+12` | u4 | `+6816` | clan id |
| `B+16` | u2 | `+6838` | privilege mask |
| `B+18` | u1 | `+6837` | clan membership state |
| `B+19` | u1 | **`+6872`** | **clan emblem flag** — the last byte, stored at `0xD3CC0C` |

`B = 0x0e + 4N`; total payload `0x22 + 4N`. **This server emits five further bytes** (a u4 chara id
and a zero u1) that the parser never reads; harmless, and it is unknown whether the original sent
them.

**Two fields here have already cost real debugging**, three lines apart in the same function:

- the **worn title** was sent as `chara.rank`, which blanked the scorecard's animal-rank badge after
  the first match;
- the **emblem flag** was hardcoded to 0, which cleared the clan emblem mid-session — the player
  started with their emblem and lost it the moment the first round ended. Fixed 2026-07-29.

The rule: **every field here must agree with what `0x4122` sent.** Nothing later corrects it.

**A prior finding is corrected by this trace.** The worn title was recorded at wire `0xef`; this
parser reads it at wire `0x04`, before the variable-length array, so no `N` can place it at `0xef`.
The struct offset (`+7845`, `charBlock+0x1EA5`) is sound — the `0xef` belongs to `0x4122`, which
writes the same slot.
## `0x4440` — unknown

**The request is exactly one u8** (ELF 2026-07-26, single-source trace: sender `0xD52A44`, the
u8 write at `0xD52AC8`). This file said the request shape was unknown; the width, at least, is
not. What the byte means still is — but note that mgo2-server's "GetPlayerOptions" registration
also reads a u8, which is now the one thing about it that is not contradicted by the binary.

Still ack-only (`0x4441`, result 0, echo's shape). The references now *name* it but do not agree:
Nomad's comment says "Set Team" (nothing parsed), mgo2-server registers it twice — once as
unknown-ack, once as "GetPlayerOptions" reading a u8 and replying 5 bytes `{u32 0, u8 0}` —
with whichever loads last winning. Neither is evidence worth acting on.

## `0x4820` — get messages

**Client → server**, `MessageGameController.getMessages`. The mailbox, read as soon as the client
joins a game lobby. Blocks on the reply — **`092E:FFFFFF60`** without one.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 1 | u8 | mailbox: `0x0f` mail, `0x10` clan applications. Anything else is logged and treated as mail |

**The two selector *values* are tier-1 confirmed** (ELF 2026-07-26, single-source trace): there
are two builders, each writing a compile-time literal — `0xD53414` writes `0x10`, `0xD53518`
writes `0x0F`. So `0x0f` and `0x10` are exactly the values the client sends, and the previous
note that they are "named after the reference servers and are unverified" was too pessimistic
about the numbers. **The naming is settled since 2026-07-27** and it was right: `0x10` really is
clan applications and `0x0f` really is ordinary mail. It was settled the informative way round —
by implementing clans and finding that **a clan application IS a mail**, delivered into the `0x10`
mailbox rather than appearing as a roster entry. That also explains a hole in the clan family:
**there is no applicant-list command**, which is why the client never sent one no matter what we
answered. See the clan section below.

| command | payload |
| --- | --- |
| `0x4821` | 4 bytes result |
| `0x4822` | 266 bytes, one entry per packet — **served since 2026-07-26** |
| `0x4823` | 4 bytes result |

**Superseded 2026-07-26: mail is implemented.** `0x4800` stores, `0x4820` lists both received and
sent, `0x4840` opens, `0x4880` deletes. See OBSERVED.md, "The mailbox, live". Three things that
paragraph assumed turned out to be wrong and are worth keeping visible:

- **One entry per `0x4822` packet.** The parser has no loop — no `0xD5CEB0` cursor test, no
  back-edge — so a packet carrying three entries delivers one and discards the rest.
- **Wire byte 0 is a routing index, not a type.** Echoing the `0x4820` selector (`0x0f`) into it
  wrote 280 bytes past the end of a client heap block. Valid values are 0..3 (4 = flat view).
- **The cap is 16 per category**, enforced silently at `0xD34858`; entries past it are dropped
  with no error.

The original text follows. Start then end with nothing between is a real answer, not a stub: a
player with no mail is the ordinary case — and it is also all either reference does for the *mail*
selector (`0x0f`): Nomad never stores mail and never emits a `0x4822` for it, mgo2-server
likewise. So an empty mailbox was reference parity, not a gap.

For the record (transcribed from Nomad 2026-07-22, used for **clan applications**, selector
`0x10`), a `0x4822` entry is 266 bytes: `u8 mtype(0), u8 index, u8 1,
name[128], comment[128], u32 time, u8 0, u8 important, u8 read`. Reference-derived and never sent
by us. **The ELF confirms this transcription** (2026-07-26, single-source trace): the `0x4822`
record's widths and field order match the parser exactly, 266 bytes. So does `0x4801`'s. That is
worth recording — a tier-4 transcription that survives a tier-1 check is the good case, and it
means the mailbox layouts can be trusted if clan applications are ever modelled.

The rest of Nomad's mailbox: `0x4800` send implements only clan applications (reply
`0x4801` = `{u32 status, u8 0, u32 error count, then name[16]+u32 code per error}`), `0x4840`
get-contents replies with **command `0x4341`, empty** — almost certainly a Nomad typo for
`0x4841`; do not copy it — and `0x4860` is a no-op `0x4861 {0}`.

**Two polarity traps in this family, and they point opposite ways.** Both from the same trace:

- **`0x4801` reads its count and records only when the status word is NONZERO.** That is the
  reverse of `0x4502`, `0x4512`, `0x4841` and `0x4905`, all of which carry a body on **zero**.
  There is no house style — state the polarity per command, and check it before writing a reply
  in this range.
- **`0x4841` is not an ack.** It is documented elsewhere as one; the parser reads **708 bytes
  after the result word when `result == 0`** (`0xD5363C`, `r5 = 708`). A bare `{u32 0}` therefore
  copies 708 bytes of stale receive buffer into the client and reports **success** — the worst
  possible failure shape, since nothing errors. Answer `0x4840` with **712 bytes**, or with a
  **nonzero result**. We do not answer it at all today, which is safe; the trap is for whoever
  implements it. The 708-byte body's layout has not been decoded.

---

# Clans — the `0x4bxx` family

The client sends **23 commands** in this range and we answered none of them until 2026-07-27, so
every clan screen stalled with `1933:FFFFFF60`. All 23 are answered now. Byte-exact layouts live in
`dev/proto/{inbound,outbound}/mgo2_cmd_4b*.ksy`; this section is the map and the rules that
are not derivable from any one packet.

## The clan record — one struct, five commands

A clan is `{u32 id, char name[16], u8 state}` and that triple appears in five places, always in the
same order and always read the same way:

| where | note |
| --- | --- |
| `session_ctx+0x1AA0` | the client's own cached record |
| `0x4122` wire `0x00` | inside the connect burst |
| `0x4b47` | the on-demand refresh |
| `0x4b21` head | the clan profile |
| `0x4103` tail | personal stats |
| `0x4221` wire `0xa7` | the player-details card |

**Every reader traced so far checks the id first and treats 0 as "no clan" whatever the name
says.** Sending a name with a zero id renders as `----`. That single fact accounts for two separate
"the clan is blank" bugs.

Membership states: **0 pending, 1 member, 2 leader, 99 not in a clan.** The client writes these
itself; readers test `state - 1 <= 1`. "No clan" is a *record*, not a failure — `0x4b47` must send
it with `result = 0` and state 99, because a nonzero result ends the payload after four bytes and
leaves whatever record the client already had in place.

## The privilege word must be ZERO

`profile+6838`, the first of the twelve u16s in `0x4122`/`0x4103`. Two experiments, both live
2026-07-27:

- **All sixteen bits, for a leader.** Put a saluting-soldier "!" badge on the clan and sent the
  client into a hard poll loop, re-sending `0x4b46` every ~73 ms. `0xAB0074` ands the word with
  `-1`, or with `-257` when the player is the leader (`0xAB004C`), and **returns without advancing
  its state machine if anything survives**. `-257` is `~0x0100`, so bit 8 is the only bit a leader
  may hold at all; every other bit stalls, and a non-leader tolerates nothing.
- **Bit 8 alone.** No stall and no poll loop, as the tolerance mask predicts — but it produced
  *only* the "!" badge and no new menu row anywhere, and emblem loading worked with or without it.

So bit 8 is a **pending-notification** bit, the whole word is a notification mask the client drains
to zero rather than a permission mask, and **no privilege bit gates applying an emblem**. That is
keyed off membership state 2 alone (`0xAD409C` tests `ctx+788 & 4`, which is set purely from the
state). The narrow lesson is not "leave the mask alone" — it is **do not turn on unknown bits in
bulk**.

## Command map

| in | out | meaning |
| --- | --- | --- |
| `0x4b00` `{name[16], description[128]}` | `0x4b01` `{u32 result, u32 clan_id}` | create |
| `0x4b04` no payload | `0x4b05` | disband (leader) |
| `0x4b10` `{u8 kind, s32 amount, u8}` | `0x4b11` header, `0x4b12` records, `0x4b13` end | clan list |
| `0x4b20` `{u32 clan id}` | `0x4b21`, 777 bytes | clan profile (**your own clan only**) |
| `0x4b30` / `0x4b32` `{u32 chara id}` | `0x4b31` / `0x4b33` | accept / decline applicant |
| `0x4b36` `{u32 chara id}` | `0x4b37` | banish |
| `0x4b40` **no payload** | `0x4b41` | **cancel join / leave** |
| `0x4b42` `{u32 clan id}` | `0x4b43` | apply to join |
| `0x4b46` `{u16}` | `0x4b47`, 28 bytes | clan record refresh |
| `0x4b48` `{u32 clan id}` | `0x4b49` `{s4, byte[768]}` | emblem, own clan |
| `0x4b4a` `{u32 clan id}` | `0x4b4b` `{s4, byte[768]}` | emblem, display fetch |
| `0x4b4c` `{u32 clan id}` | `0x4b4d` `{s4, byte[768]}` | emblem, second fetch (in-game, mode 9) |
| `0x4b50` `{u8 mode, byte[768]}` | `0x4b51` | **emblem upload** |
| `0x4b52` `{u32 clan id}` | `0x4b53` / `0x4b54` / `0x4b55` | roster |
| `0x4b60` / `0x4b62` `{u32 chara id}` | `0x4b61` / `0x4b63` | transfer leadership / set emblem editor |
| `0x4b64` `text[128]` | `0x4b65` | set clan comment |
| `0x4b66` `text[512]` | `0x4b67` | set clan notice |
| `0x4b70` | **one** `0x4b71` (584) then `0x4b72` (580) | clan stats |
| `0x4b73` `{u32 clan id}` | `0x4b74` / `0x4b75` / `0x4b76` | applicant list — **never sent by the client** |
| `0x4b80` `{u32 clan id}` | `0x4b81`, 217 bytes | **Clan Info for a clan you are not in** |
| `0x4b90` `{u8 exact_only, u8 ignore_case, name[16]}` | `0x4b91` / `0x4b92` / `0x4b93` | clan search |

On `0x4b01` with `result == 0` the client stores the second word as its clan id and **makes itself
leader**: `0xD56E84` (`lwz r9,116(r1)` / `stw r9,6816`) and `0xD56E90` (`li r0,2; stb r0,6837`).

### The emblem bitmap: `EMBD`, 768 bytes, 32x32 at 16 colours

The 768-byte block carried by `0x4b49`/`0x4b4b`/`0x4b4d` and uploaded by `0x4b50` is a single
decodable image format, not an opaque blob. The only decoder in the binary is **`0xA9B3E8`** (17 call
sites), and it validates as follows:

| offset | size | meaning |
| --- | --- | --- |
| 0 | 4 | magic, `memcmp` against **`"EMBD"`** (string `0xE1E6A8`, compare `0xA9B458`) |
| 4 | 1 | must be **signed-negative** — high bit set (`extsb` / `bge -> fail`, `0xA9B470`) |
| 5 | 48 | **16 palette entries**, 3 bytes RGB each, expanded to `0xRRGGBBFF` (`0xA9B47C`-`0xA9B6E4`) |
| 53 | 512 | **packed 4-bit palette indices, high nibble first** (unrolled 512x at `0xA9B718`) |
| 565 | 203 | unused padding |

512 packed bytes are 1024 pixels, and the target texture width is asserted `== 32` at `0xA9B744`, so
the image is **32x32**. A block failing either check is dropped silently — the in-game path has no
error dialog, only a 6000-tick backoff at `0x9D4A34`.

Verified against a live upload: the emblem stored for clan 2 begins `45 4D 42 44 80`, i.e. `EMBD`
followed by `0x80`, and is exactly 768 bytes.

**Do not confuse the `"%s/%s%d.emb"` string (`0xE1E680`) with a network path.** It sits in the emblem
*editor*'s literal pool beside `"clanemblem"`, `"emblemeditor"` and `"brush_x1"`, and the errors
around it are *"Not enough space on the hard disk. Could not save emblem"* (6561-6565). It is the
local HDD save path for the editor's work in progress. **No URL and no HTTP verb exists on the
emblem fetch path** — the image is a TCP lobby command, full stop.

### Who fetches whose emblem, in a game

The in-game emblem manager `0x9D4500` walks all 24 player slots, and for each occupied slot with a
nonzero clan id issues a fetch **keyed on that peer's clan id** — not the viewer's. Results are kept
in a 30-entry cache at `0x166F8F4` (stride 776: `{u32 clanId, byte[768], pad}`).

**So the server must be able to serve any clan's emblem, not just the requester's.** All three
senders append a `u32` clan id: `0xD57838` (`0x4b48`), `0xD56704` (`0x4b4a`), `0xD56618` (`0x4b4c`).
Which of the latter two is used depends on the round mode: `0x9C2918` returns 1 iff `0x6A9A38` is 9,
and at `0x9D47C0` that selects `0x4b4c` and the `conn+0xFBC9` buffer, versus `0x4b4a` and
`conn+0xF8C7` otherwise. Modes 9 and 10 are not identified by name in the binary.

The **flag** that decides whether a fetch happens at all is read at `0x9C2C00`, and **3 is not its
only accepted value**: `slot+92 == 3` passes unconditionally, and `slot+92 == 2` also passes when the
mode is 9 (mode 10 always fails). That byte reaches the slot **peer-to-peer**, not from us: the
announce builder `0x88407C` copies `profile+6872` verbatim to announce `+4` (`0x88415C`), the
announce is serialized to peers at `0x272474`-`0x272684`, and `0x2762A0`/`0x278068` apply `+4` to
`slot+92` (slot array at `gameObj+212`, stride 116, 24 slots).

**The consequence for the server is a split.** The *flag* can only be fixed in the login burst
(`0x4122`), because nothing in-game can correct it afterwards; the *image* is a live request during
the match and must be answered for arbitrary clan ids.

## `0x4b46` blocks — the correction

`dev/proto/inbound/mgo2_cmd_4b46_c2s.ksy` said *"the live trace proves the client does not
wait for one"* and warned against replying speculatively. **That is true of the connect burst,
where it fires unprompted and the player walks on, and false from the clan menu, where it stalls
and fails with `Unable to update clan information (1933:FFFFFF60)`** (live 2026-07-27). One
command, two contexts, and only one of them had ever been tested. The sender `0xD58510` advances
flow state via `0xD32E08(session, 98, 1)` either way, so the difference is in what the screen does
next, not in the request.

`0x4b48` is the same shape of trap in reverse: it appears **only once a character has a clan**, and
it blocks character select. Every field we start populating truthfully unlocks a branch that was
previously dormant.

## The clan list and its "%d/%d"

`0x4b11` is `{u32 result, u32 offset, u32 total}` — **offset first, total second.** They were
swapped, which is the whole "2 out of 1" bug. The client stores them at `block+0x08` and
`block+0x0C` and renders its page indicator (format string `0xE11518`, drawn at `0xAC11A4` and
`0xAC2958`) as:

```
left  = A <= 0 ? 1 : (A - 1) / 100 + 2
right = (B - 1) / 100 + 1
```

**The record count never enters that text**, which is why changing the rows changed nothing.
Corroborated by the sibling clan-search triple, which fills the same two slots itself: `0x4b93`
sets `block+0x08 = 0` and `block+0x0C =` the record count (`0xD54D64`, `0xD54D78`).

`0x4b10`'s `kind` selects an arm stepping ±100 (1 back, 2 forward, 4 absolute, 0 and 3 the first
page) and **`amount` is a 1-based entry index, not a page number** — after being shown one entry the
client asked for 101. It pages optimistically, without knowing whether the next 100 exist, so the
server must **clamp** rather than honour it literally: answering "0 clans, starting at 101, out of a
total of 1" is self-contradictory and corrupts the list on the next scroll. Page size is 100
(`cmpwi r4,99` at `0xD561E4`).

`0x4b12` records are **48 bytes**: `{u32 clan id, char name[16], u32 member count,
char leader_name[16], u32 pad, u32 founded_at}`, size-driven with no count (`0xD5CEB0` at
`0xD560BC`). **The 101st record makes the parser fail with `-71`** — it is *not* silently dropped,
which is what the spec used to say.

## `0x4b21` — the clan profile, 777 bytes

4 bytes on failure (`0xD58C04` jumps straight to end-read). Offsets are into the client's clan
struct `T`:

| offset | meaning |
| --- | --- |
| `T+0x00` | clan id — **cross-checked against the id the client holds; packet dropped on mismatch** |
| `T+0x04` | clan name[16] |
| `T+0x15` | membership state |
| `T+0x18` | **leader's character id** — *not* a founding date, corrected 2026-07-29 |
| `T+0x1c` | leader name[16] |
| `T+0x48` | **[ELIMINATED]** — see below |
| `T+0x58` | member count |
| `T+0x76` | **2 when a work-in-progress emblem exists** |
| `T+0x378` | **3 when a published emblem exists** — the client will not fetch or offer an emblem while this is 0 |
| `T+0x67A` | clan comment, 128 bytes — the same offset `0x4b00`'s create request reads *its* description from, and what `0x4b64` writes |
| `T+0x6FC` | **the emblem editor's character id** — compared against the client's own to decide whether to offer "set as the clan's emblem" |
| `T+0x700` | the clan **notice**, 512 bytes — what `0x4b66` writes |
| `T+0x904` | the **notice's timestamp** |
| `T+0x908` | the notice's **author name**[16] |

**Two corrections to earlier readings here.**

### `T+0x18` is the leader's character id, and there is no founding date in this struct (2026-07-29)

**READ from the ELF**, and it settles a contradiction that had been shipping: the code sent the
leader's chara id here while the schemas called it a founding date, and *both* claimed
`[CONFIRMED 2026-07-27]`.

The parsers (`0x4b21` → `0xD587AC`, `0x4b81` → `0xD58C74`) read it as a u32 into the shared struct at
`session+0x10000-1968`. It has **exactly five readers**, five clones of one routine — `0xAC8F9C`,
`0xACA5B4`, `0xACAA04`, `0xACBA84`, `0xACD9AC` — each walking the roster scroll-list and comparing the
value for **equality against each row's member id** to select one row and light its icon. The next
instruction compares that same row id against `T+0x6FC`, a confirmed character id.

**It reaches no date formatter.** Never passed to `0x8843CC`, never divided or modded, never
sign-tested. `T+0x904` is the struct's only timestamp-shaped consumer, and it is the *notice's* date —
so **this struct contains no founding-date field at all.**

The old label came from swapping this slot with `T+0x58` and watching the member count render
`1785129141`. That constrains **`T+0x58`** and nothing else; the epoch value simply happened to be
what landed in the other slot. The label was then mirrored to the sibling packet as "same slot, same
meaning" — true about the slot, false about the meaning. Third invalid elimination in this packet
family, and the same shape as the one below.

- `T+0x904` was documented as the **founding date**. That was a guess about meaning layered on a
  real observation — the field was found by sending every candidate slot the date offset by a
  different number of days and reading which one the screen showed, so *the field is right and the
  label was wrong*. It is the notice's date. ~~The founding date is `T+0x18`.~~ **Wrong too** — `T+0x18` is the leader's character id, and this struct has no founding-date field at all (2026-07-29).
- `T+0x700` was recorded as an unknown "long text block or packed table". It is the notice,
  confirmed live by typing into **Clan Notice** and watching `0x4b66` carry 512 bytes to the same
  offset. Likewise `0x4b64`'s 128 bytes and **Clan Comment**.

**`T+0x48` is not the emblem cooldown. [ELIMINATED live 2026-07-27.]** It is the only
timestamp-shaped slot we send that the client never renders (a u32 read stored with `std` as 64
bits at `0xD5899C`), so it was the obvious candidate for the countdown behind lobby string 17247.
Sending the real display time changed nothing — the emblem could still be re-displayed immediately
with a fresh `0x4b21` in hand. The confirming observation would have been the countdown appearing,
and it did not.

**Never send a zero timestamp.** The renderer `0xAAB2D8` has no conditionals at all — it always
draws the date, the author and the notice body, so the line cannot be suppressed. But the formatter
`0x8843CC` tests the value at `0x884420` and takes a fallback branch when it is **negative**,
printing the literal `XXXX-XX-XX XX:XX:XX`. Zero is not special-cased: `localtime(0)` succeeds and
yields 12-31-1969. Send **-1**, which is this binary's own convention for an absent timestamp
(`0x91E4C0` tests another one the same way).

## `0x4b80`/`0x4b81` — the clan you are *not* in

217 bytes, and it is the counterpart to `0x4b20`, which **cannot** serve a non-member: that reply's
id is cross-checked against the client's own clan id and the packet is dropped on a mismatch. This
one's `subject_id` is explicitly **not** cross-checked. Same slot meanings as `0x4b21` for id, name,
`T+0x18` leader chara id, `T+0x1c` leader name, `T+0x58` member count, `T+0x378` emblem flag and
`T+0x67A` comment. `T+0x58` is the member count and **not** the
other way round: swapped, the info screen showed *1785129141 members* — the epoch seconds,
verbatim.

It also unblocks joining. `0x4b42`'s sender refuses to transmit unless the session clan record at
`session_ctx+0x1AA0` holds a non-zero id, returning `-24` (`FFFFFFE8`) **without sending
anything** — which is exactly the error Apply produced while this reply was 217 zero bytes.

## Emblems — `0x4b48`/`0x4b4a`/`0x4b4c` and `0x4b50`

All three fetches return `{s4 result, byte[768]}` and **the 768-byte block is the clan emblem**, not
an opaque blob. `0x4b49`'s copy lands at `profile+6873` (parser `0xD56F24`, `addi r0,r27,57` off the
clan record at `0xD56EDC`); `0x4b4a`/`0x4b4b` is the display fetch. Neither parser looks inside —
both NUL-terminate at `+768` into a 769-byte buffer — so the bytes are opaque *to the parser* while
being semantically the emblem, and the server stores and returns them verbatim.

**Falsified:** the block was briefly filled with pending applicant names on the theory that
768 = 48 × 16 made it a name table. It is not; that was writing text into the client's emblem
buffer.

`0x4b50` is the **upload**: `{u8 mode, byte[768]}`, sender `0xD5804C`, reached from the emblem
screen through task kind 25. **Mode 3 = "put on display"** and is the only mode the client
post-processes; 2 and 4 also occur and are [UNKNOWN]. On success the client copies the block to
`profile+6873` and sets `profile+6872` to the mode.

Refusal codes on `0x4b51` (routing `0xAD3E20`): `-1216` *"A fixed amount of time must pass in order
for the emblem to be updated"* (what we send on cooldown), `-1202` *"Unable to update clan
emblem"*, `-1207` *"Unable to locate designated clan"*, `-1215` *"Use of the clan emblem is
currently forbidden"*, `-1218` *"You do not have emblem editing rights"*.

**An unresolved disagreement, left on the record deliberately.** An earlier trace concluded that
only `-1207` and `-1202` reach a dialog and that **every other non-zero value memsets the client's
768-byte emblem buffer**, destroying a work-in-progress emblem. A later, deeper trace could not
reproduce that: every branch of that dispatcher raises a dialog, and neither it nor the `0x4b51`
handler (`0xD555D4`) contains a memset — so the wipe, if it happens, lives in the emblem screen's
event-104 consumer, which nobody has located. If a refusal is ever seen clearing a work-in-progress
emblem, `-1202` is the fallback.

The re-display cooldown itself is **operator policy, not protocol**: nothing client-side enforces it
on this build, and the countdown string (17247) is orphaned. Either the retail servers refused the
upload themselves, or the countdown is fed by something not yet found.

## The roster — `0x4b52`/`0x4b53`/`0x4b54`/`0x4b55`

Start and end carry a **result code, never a count** — a count there produced the live
`1032:00000005` error on the sibling social path, and the client counts the item records itself.

The `0x4b54` record is **68 wire bytes**: `{u32 chara id, char name[16], u8 isMember, u32, u32,
then game-location fields}`. **`isMember` is 1 for joined members and 0 for pending applicants**,
and members and applicants go out as **one batch with the flag set per row**. Two other
combinations were tried and both failed visibly: two separate `0x4b54` packets put both groups on
the wire but the client rendered only the first, so the applicant vanished; and mixing applicants
into the members query with the flag set per *batch* made them appear as full members. The trailing
game-location fields (lobby id, lobby name, game id, host name, subtype) are unpopulated.

## Clan stats — one `0x4b71`, then `0x4b72`

`0x4b71` is 584 bytes (`4 + 4 + 8*18*4`) and its **second word must be 2 or 3**; any other value
fails the whole packet with `-71` and discards the grid (`0xD599C8`), which the screen reports as
"no records". Then `0x4b72`, 580 bytes (`4 + 2*72*4`).

**Send exactly one `0x4b71`.** Sending two — by analogy with `0x4105`'s cumulative/weekly pair —
completes the request slot on the first reply, and the second arrives unexpected: that is the
`unable to acquire clan information (1931:FFFFFF60)` stall on Clan Affiliation.

## Search, applications, and the two rules that are the game's

**`0x4b90`'s second byte is IGNORE CASE**, `1` = ignore. Same polarity as `0x4600`; see that
section for how it was falsified. Records are **44 bytes**: `{u32 id, char name[16], u32 leader
chara id, char leader_name[16], u32 founded_at}`. Another server writes 48 — adding a flag byte and
three pad bytes before the trailing u32 — which is a **different client build**, and per `CLAUDE.md`
another implementation is tier 4 and not a specification. Our parser reads 44.

**A clan application is a mail.** It arrives in mailbox type `0x10` on `0x4820` (`0x0f` is ordinary
mail), not as a roster entry, and **there is no applicant-list command** — which is why the client
never sent one. `0x4b73`'s triple is unexercised.

**Clan founding requires 20 hours of play time and level 3, and that is the game's rule, not ours.**
The client carries the text — "You must have 20 hours of playing time and a Level of at least 3 to
create a clan" — as ordinal 81 of string group `0x333C8E` (control base 16524, text base 16738).
**It is not reachable as a result code**, and it is not the only tier: ordinal 82 immediately beside
it says **5 hours and Level 2**.

**Which tier this build uses is unknown, and our 20h/level-3 is operator policy on community
report.** Nothing in `MGO2.elf` chooses between them — neither item hash (`0xE5EEC8`, `0x3E91BB`)
is referenced in the binary or in `scenerio.gcl`, and there is no selector table.

That absence is *not* an elimination, and the reason is worth keeping. Only **24 of that group's
153 strings** are referenced by literal hash anywhere; the unreferenced 129 include "Create Clan",
"Clan List", "Disband" and "Create a clan using these settings?" — strings that unquestionably
render. The group is addressed through an indirection in the packed UI resources that nobody has
decoded. So the same "no reference found" test that is decisive for the error table proves nothing
here. Do not promote it to a finding.

**What is settled: the client never checks either rule.** The create-clan sender `0xD579AC`
validates name length (>2, <=16), character class (`0xD32DD0`), comment length (<=128),
connectivity (`0xD3844C`) and whether you are already in a clan (`0xD57750` -> `-1201`), then
sends. It reads no play time and no level. Nor does anything else: 18000 and 72000 (5h and 20h in
seconds) occur as **no immediate anywhere in the binary**, and the only two `{20,3}` comparison
adjacencies are unrelated switch dispatches. So the server is the sole enforcer whichever tier is
correct, and choosing the stricter one is a choice, not a reading.

Settling it needs either a decoder for the packed UI resource — to see whether ordinal 81 or 82 is
bound to a screen — or a live capture of a real server refusing a create.

Disband inside its cooldown refuses with `-1205`, *"A fixed amount of time must pass in order to
disband the clan."* The countdown strings beside it (17312/17318) are orphaned exactly as the
emblem's are; this says the same thing without the number.

## What was removed, and must not come back

There was an **acknowledge-only table** here: a dozen ids answered with a bare success while doing
nothing. It stopped the screens hanging, which was worth having, but it turned "unimplemented" into
"silently reports success" — disband, banish, transfer leadership and set-emblem-editor all
reported working while doing nothing at all. Every id is implemented now. A command with no
implementation should **stall visibly, or return an error**; it must not lie.

---

# GAME lobby, continued

## `0x4900` — get game lobby info

**Client → server**, `HubGameController.getGameLobbyInfo`. The hub screen's list of game lobbies.
Request payload is not read. Blocks on the reply — **`0A21:FFFFFF60`** without one.

| command | payload |
| --- | --- |
| `0x4901` | 4 bytes result (`C0FFEE02` and stop, with no session) |
| `0x4902` | up to 8 entries, 99 bytes each |
| `0x4903` | 4 bytes result |

Only lobbies of type GAME are listed.

### `0x4902` entry — 99 (`0x63`) bytes

Read out of the parser at `0xD47E18`, field by field, 2026-07-25. It reads with the same
primitives as every other command (`0xD5CCD8` u32, `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5D018` raw)
into a 120-byte struct, appends it to a 64-entry array at `ctx+0xB790`, and loops until the read
cursor passes the payload length. The four addresses listed here are **not the whole library** —
each has an instruction-identical twin and there are further primitives besides; see "The
packet-reader primitives" under Transport, and in particular do not read `0xD5CCD8` versus
`0xD5CC64` as an unsigned/signed distinction. There isn't one.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | index |
| `0x04` | 1 | u8 | **lobby subtype** — the only field the hub menu dispatches on |
| `0x05` | 1 | u8 | unknown |
| `0x06` | 1 | u8 | unknown; read for subtype 5, which wants the value 3 |
| `0x07` | 1 | u8 | bit flags, expanded one bit per field into the struct |
| `0x08` | 2 | u16 | lobby id |
| `0x0a` | 16 | ISO-8859-1 | lobby name |
| `0x1a` | 64 | ISO-8859-1 | text block, rendered only by the subtype-5 category |
| `0x5a` | 4 | u32 | open time — always 0 |
| `0x5e` | 4 | u32 | close time — always 0 |
| `0x62` | 1 | u8 | open flag — always 1 |

The first eight bytes are what the reference servers write as `index` plus an `attributes` u32
with the subtype in its top byte; that packing is right, because the top byte of a big-endian u32
is the u8 at `0x04`. The 64-byte text block is what they omit, and **omitting it is why only the
first lobby ever appears in Lobby Select**: the readers bound-check against the 1023-byte buffer,
not against the payload length, so a short entry does not fail — the parser simply resumes 64
bytes into the next entry and reads rubbish from there on.

### The hub menu is a fixed set of categories, one row per subtype

`0x890410`–`0x8905d8` builds Lobby Select by scanning the parsed array once per subtype — 2, 1,
7‑or‑8, 5, 3, 4 — and **stopping at the first entry that matches**. Each match writes one menu row
whose label comes from the client's own string table (`0x8E0C24`; ids 251/260 for subtype 2,
245/261 for 1, 249/262 for 7 and 8, 246/263 for 3, 248/265 for 4) and whose action code is fixed
(9, 10, 11, 13, 14). Two consequences, both protocol rather than policy:

- **The lobby name in the entry is never shown on this screen.** Naming a lobby "Basic Training"
  does not make the row say that; the row says whatever the client's string for that subtype says.
- **A second lobby with the same subtype adds no second category row** — but it is not lost. The
  list behind a category is built separately, at `0x89147C`: it walks every parsed entry, accepts
  any whose subtype matches the current lobby's (with 7 and 8 treated as one group), and separates
  them **by lobby id**. Two subtype-7 lobbies both appear there. Confirmed on echo, 2026-07-25.
  **This grouping applies to listing only.** The menu *inside* a training lobby is gated row by row
  by `0x884584(n)`, which matches the lobby's own subtype exactly — so Basic and Combat Training
  must still be 7 and 8 or the second renders the first's menu. See `LOBBIES.md`.

### Every category this build has

The six scans in the menu builder, in the order they run, with the string-table ids each row is
labelled from and the action code it stores. This is the complete set — there is no scan for any
other subtype, so a lobby with one can never produce a row:

| subtype | scan | row emitted at | string ids | action |
| --- | --- | --- | --- | --- |
| 2 | `0x8904CC` | `0x89097C` | 251 / 260 | 9 |
| 1 | `0x89044C` | `0x890908` | 245 / 261 | 10 |
| 7 or 8 | `0x890488` | `0x890894` | 249 / 262 | 11 |
| 5 | `0x8904CC` | inline `0x890504` | 264 + the entry's 64-byte text | 12 |
| 3 | `0x890578` | `0x890820` | 246 / 263 | 13 |
| 4 | `0x8905B4` | `0x8907AC` | 248 / 265 | 14 |

**Subtypes 3, 4 and 5 are present in this binary.** Their branches are ordinary — same shape as
the three we use, no expansion check, no DLC flag, reached purely by a matching entry being in the
list. What they are *called* cannot be settled from the ELF: `0x8E0C24` resolves an id against an
external message resource, not a table in the binary, so the labels are on the disc. Subtype 5 is
the one with a precondition — the entry's byte at `0x06` must be 3 — and the only one that renders
the 64-byte text. Subtype 6, 9 and 10 (the "registration" id in reference schemas) have **no scan
at all**.

Selecting a row stores its subtype at `+0x294` of the object behind `0x883F20` (`0x890640`) —
which is the same byte the game-lobby `0x3003` appends as its trailing flag. **The check-session
trailing byte is the subtype of the lobby being entered**, not an unknown flag.

### Which lobby the port check dials

Not the one the player picks, and this constrains the `lobby` table. The waiting machine's state 0
(`0x946F8C`) counts type-2 entries in the **gate** list, reads a 2-byte client setting — group 25,
id `0xFE`, zero-initialised before the read — and passes it to the connect-by-ordinal wrapper
(`0xD384A4`), which resolves the ordinal to a list index and opens a socket to that entry's ip and
port. So the game lobby at that ordinal must have a server behind it or login fails with *unable
to connect to lobby*, whatever the rest of the table says. Inserting a game-lobby row ahead of the
others moves the target.

## `0x43d0` — training parameter fetch

**Client → server**, `HubGameController.getTrainingParams`. Traced and implemented 2026-07-25 after
it was observed unanswered in both training lobbies.

Sent from one state of the lobby-entry state machine (`0x897758`) — the same machine that branches
on the selected subtype at `+0x294` — with a **single u8 argument, value 8** (builder `0xD3A680`).
The state blocks on the reply and takes an error exit if it fails, so an unanswered `0x43d0` is
another `FFFFFF60` waiting to happen on whichever screen sends it.

### Reply `0x43d1` — 10 bytes

Parser `0xD3A560`: a loop of **five u16 reads** (`0xD5CC14`) into a 10-byte block, copied wholesale
(`lswi`/`stswi` 10) to `ctx+0x117EC` and signalled as request-status id 31. Nothing else about the
values is known. mgo2-server answers with the fixed bytes `00 0A 00 15 00 3A 00 08 00 61` (u16s
10, 21, 58, 8, 97), which is tier 4 — the *shape* is confirmed from the binary, the *values* are
somebody's constant — and we send the same, because **the first halfword is rendered to the
player**: `0x8978C8` loads it and passes it to the string formatter with message id 847, so a zero
would put a zero on screen. The reset path at `0xD35780` zeroes all five, which is what an
unanswered `0x43d0` leaves behind.

Answering it did **not** make the training Graduate action work; that is gated on player state
elsewhere (see below).

## `0x43e0` — start automatching

**Renamed 2026-07-28.** This was documented as a "status fetch sent on entry to the automatching
lobby"; both halves were wrong. The full flow, the nine failure modes, the four commands we still
do not send, and the disc's own UI strings are in **[AUTOMATCH.md](AUTOMATCH.md)** — read that
rather than this section, which is kept only for the `0x43e1` byte layout.

**Client → server**, `HubGameController.getAutomatchStatus`. Sent **on confirm** from state 4 of
the automatch screen (`0x93CD58`), not on entry — the screen constructor `0x93B4D0` makes no
network call at all. The **single u8 argument** (observed 11) is a **rule filter**: 0–5 are rule
ids, 7 is Team Sneaking behind its feature bit, and **11 is the "Do not specify rules" sentinel**,
deliberately outside the 0–10 range the label mapper accepts.

That it is *start* rather than *status* is settled by the client's own error table: a timeout on
this command's request slot raises 4931 *"…Unable to **start** automatching"* (`0x93CDD4`).

### Reply `0x43e1` — 6 bytes

Parser **`0xD5BF98`** (the `0xD5BFC0` cited here before is an address *inside* that
function): a u32 result, and **only if that result is zero**, two u8s — stored at
`+0x114A1`/`+0x114A2` behind a "loaded" flag set at `+0x114A0`. Request-status 50 is signalled
either way.

**A nonzero result is not "nothing to report" — it is an error dialog.** −970 prints "Automatching
is currently not open", −950 "Unable to start automatching", −541 "You are currently banned from
creating and joining games", and every other nonzero value also lands on "Unable to start" with our
number printed in it. Result 0 is also the *only* thing that registers the push channel, so nothing
in the `0x43f*` family reaches the client until we send it.

The two bytes are now identified, by crossing the ELF's reads against the disc's string table:
**byte 1 is a level band half-width** (clamped 0–22, lighting a window on the 23-column "Entry
Status" gauge centred on the player's own level) and **byte 2 is "Players Needed"**, printed
through string 917 `%d` when nonzero and replaced by string 48 when zero. We send result 0 and two
zero bytes, which is harmless but renders an empty panel.

## `0x4990` — get game entry info

**Client → server, payload Blowfish-encrypted.** `HubGameController.getGameEntryInfo`. Entry
conditions for the current lobby. Request payload is not read. Blocks on the reply —
**`0A21:FFFFFF60`** without one.

### Reply `0x4991` — **236 bytes**, not 172

**Corrected 2026-07-26; this is a live bug in what we send.** The old entry read:

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | **unknown**: always 0 |
| `0x04` | 4 | u32 | **unknown**: always 1 |
| `0x08` | 164 | — | **unknown**: `0xa4` zero bytes. The comment says the client "only skips" this block, which is itself unverified |

— a 172-byte fixed answer, `bo.writeInt(0).writeInt(1).writeZero(0xa4)`, which is what both
references send byte for byte. The client does not "only skip" it. The parser is `0xD48D40`, and
it is established (independently re-derived from the ELF the same day) that:

- it reads a u32 into `rec+0x120`, and **memsets a 296-byte record area** — so the destination is
  a structure, not a discard;
- it then runs a **hardcoded 4-iteration loop** — bound `cmpwi r20,3` at `0xD48F84`, stride 72 at
  `0xD48F88` — of records that are **11 reads = 57 wire bytes each**;
- 4 + 4 + 4×57 = **236 bytes**. That is the true payload size.

And the second word is not free either: at `0xD48FB0` the client compares it against 4 and, if it
differs, **overwrites it with 4** (`li r0,4; stw r0,288(r3)` at `0xD48FC0`). Whatever we put
there, the client's own value ends up 4 — so the reference servers' `1` is not merely unexplained,
it is discarded.

**Fixed 2026-07-26: `HubGameController` now sends 236 bytes**, four zeroed 57-byte records, and
the second header word as 4 rather than 1 (the client overwrites it with 4 regardless). The
record layout is still undecoded, so the reply is correct in shape and empty in content. The
original finding follows.

We sent 172 bytes where the client reads 236. The missing 64 came out of stale receive buffer, as
always, which is why nothing has visibly failed: entry conditions parsed from four garbage records
land in a structure whose use has not been traced. The 57-byte record layout has not been decoded
and is the obvious next question. Nobody knows what the first word means.

---

# Commands we do not handle

An unhandled command is logged and dropped. **That is not benign.** The client waits on a reply,
gives up after roughly forty seconds, and fails with detail **`FFFFFF60`** under whatever screen
was open at the time:

| screen | error |
| --- | --- |
| registering a character | `0A41:FFFFFF60` |
| connecting to a lobby | `092E:FFFFFF60` |
| character select / hub | `0A21:FFFFFF60` |
| updating character info | `1031:FFFFFF60` |
| the `0x4100` burst specifically | `1037:FFFFFF60` |

**This is the single most useful debugging fact in this file.** The code tells you only that a
reply was missing, never which one — the screen code is the screen, and `FFFFFF60` is the timeout.
So when a client stalls and then throws an `FFFFFF60`, the first move is always the same: read the
server log for `No handler for command ....` immediately before the stall. Every command in the
GAME section above was found exactly that way.

## The complete sendable set, from the ELF (2026-07-22)

An exhaustive scan of the binary's packet builder (`0xD5CF40`, the single "begin packet" call)
found **115 send sites, every one using a literal command id** — the client never computes or
table-dispatches a command id, so this list is complete for the lobby packet library. (The
pre-lobby handshake, where `0x0001` lives, uses a separate path outside this library and is not
in the scan.) 110 unique ids can be sent; we answer 45 of them. The other **65 are potential
`FFFFFF60` stalls if their menu is ever reached** — but reachability varies wildly, so they are
grouped by how likely normal play is to hit them, not listed flat.

**Two corrections the scan forced, both worth acting on:**

- **`0x43ca` is never sent — the client sends `0x43c8`** (builder `0xD40CB4`, payload `{u32,
  u8}`). Our "start round" handler *was* bound to `0x43ca`, which has no builder anywhere —
  dead code that kept the `game_round` snapshot empty. **Resolved 2026-07-23:** the handler is
  renumbered to `0x43c8`/`0x43c9`, and the snapshot now populates on game create and join
  regardless (BACKLOG, marked resolved).
  `0x43c8` is the likely real trigger. This reads as a two-off transcription slip inherited from
  a reference. Do not blindly repoint — capture a `0x43c8` and confirm its semantics first — but
  it is the strongest lead on the round-lifecycle gap.
- **`0x3040` has a live builder** (`0xD37B6C`, one u8) — it *can* be sent, correcting the earlier
  "normal flow never sends it" note. Still unanswered by every reference; reply shape unknown.

**Reachable in ordinary flow (highest priority to resolve):** the in-match/host family we have
only partly covered — `0x4348`, `0x4394` (large struct), `0x43a4`, `0x43a6`, `0x43b0`, `0x43c4`,
`0x43c8`, `0x43e0`, `0x43e2` — plus connect-family write-backs `0x4112`,
`0x4210`, `0x4220`. (`0x4102` and `0x4132` were on this list until 2026-07-23, when both surfaced
as live stalls and were traced and handled — see their sections. `0x4400` left it 2026-07-26 when
in-game chat was decoded from four live captures — see OBSERVED.md "0x4400 — in-game chat"; it is
still unhandled, but its shape and meaning are settled.) The rest have not surfaced in
testing yet, so each is conditional on a specific action/menu we have not exercised.

**Reply shapes traced 2026-07-26 for three of the gaps.** All single-source ELF traces, none
confirmed against a client. They are recorded because each one is a case where the obvious
"answer it with a bare result word" would be wrong, which is the lesson the ADDLIST already
taught once:

- **`0x4401` is not a result single.** It is `{u32, NUL-terminated string}` — the string read by
  the delimiter-terminated primitive `0xD5CE34` with delimiter 0 into a 129-byte buffer. The
  string is **terminated on the wire, not padded to width**, and the reader consumes the
  terminator, so a fixed-width 128-byte field is the wrong encoding.
  Its counterpart `0x4400` is now capture-proven as the **in-game chat send** (2026-07-26), which
  makes `0x4401` the chat line coming back for display — [INFERRED] from the pairing plus the
  parser storing the string at `ctx+0x14D0` and firing UI event `0x30`, not confirmed. If that is
  right, `0x4401` has to be **pushed to every player in the game**, not just answered to the
  sender, and the server has no mechanism for that: no channel registry, no `writeAndFlush`
  anywhere in `src/main/java`, connections held only as Netty channel attributes. Note also
  `BufferUtil.writeString` is fixed-width NUL-*padded* only — there is no variable-length
  terminated-string writer, so `0x4401` needs one written by hand.
- **`0x4905` is an 822-byte record**, not a result single: 46 bytes, then a **204-byte** block
  through the standalone reader `0xD4364C` (the same one `0x4313`'s settings block uses), then the
  remainder including a 512-byte text block. **The block was documented here as 159 bytes until
  2026-07-28; that was stale.** An itemised trace of every read in `0xD4364C..0xD43BF4` totals 204
  with no gaps in the destination offsets, and three independent sums agree: `0x43f1` is `19 + 204 =
  223`, `0x4313` is `0xA8 + 204 = 372`, and the `0x4310` builder emits the same block minus eight
  fields for `163 + 182 = 345`. The field map is in [AUTOMATCH.md](AUTOMATCH.md) §3. If 822 was
  derived using 159, the leftover figure needs re-deriving too. It also **discards the entire packet** unless its echo id
  equals the u32 at `ctx+0x6D04` (`0xD4820C`) — so a reply must echo the request's id or it is
  dropped in silence.
- **`0x4841`** — see the `0x4820` mailbox section; 708 bytes of body on a zero result, and a bare
  ack reports success over stale buffer.

**Whole unmodelled subsystems (only reached if that feature's menu is opened):**

| block | ids | subsystem |
| --- | --- | --- |
| ~~`0x4bxx`~~ | ~~23 consecutive (`0x4b00`–`0x4b90`)~~ | **Superseded 2026-07-27 — all 23 are answered. See the clan section.** |
| `0x49xx` extended | `0x4904`–`0x49c2` (~18) | game-lobby / roster / GHQ |
| `0x4axx` | `0x4a25`, `0x4a30`, `0x4a40` | unidentified |
| mailbox rest | `0x4840`, `0x4860` | read / file mail (`0x4800` send and `0x4880` delete are implemented) |
| ~~social~~ | ~~`0x4600`, `0x4680`, `0x4684`, `0x4220`~~ | **Superseded — player search, met-players history and player details are all served** |
| misc | `0x2006`, `0x4e00` | lobby-layer / isolated. `0x2006`'s presumed reply `0x2007` is traced — see the GATE section |

Builder addresses and best-effort payload shapes for every gap id are recorded in the enumeration
task output; they are **not** transcribed here as field layouts, because an unparsed shape written
as documentation is exactly the plausible-looking wrong spec this file exists to avoid. Reply
shapes matter: the ADDLIST proved a bare ack does not satisfy commands that expect a bodied reply,
so each gap needs its own parser trace (as `0x4500`/`0x4510` got) before implementation, not a
blanket empty ack.

---

# Unknowns and things to revisit

Collected so none of them get lost. Roughly in order of how likely they are to bite.

### Certainly worth a second look

1. ~~**`readAppearance` skips three positions**~~ — **RESOLVED, it was a bug.** `lower` and
   `hands_color` were stored as 0 for every character ever created, on an inherited comment
   claiming the original server discarded them. `0x4130` carries the same fields in the same order
   and names them, and a live client confirmed it: a character created with `lower = 0` gained a
   real value the moment `0x4130` was implemented and the player changed clothes. Both are now read
   at creation. The four bytes at +9 are still skipped and still unexplained, though the write path
   emits zeroes there.

   Kept in this list as the worked example: an inherited "the original server did X" claim was
   wrong, and it silently discarded player data for as long as it stood.

2. ~~**The `0x3108` reply shape is inferred, not read.**~~ — **RESOLVED 2026-07-26, the inference
   was correct.** The parser is at `0xD37154`: single u32, notify slot 18. It had been modelled on
   its sibling result packets (`0x3004`, `0x3102`, `0x3104`, `0x3106`) without the arm itself ever
   being disassembled. Kept in the list because the *reasoning* was luck as much as method — a
   sibling-shape argument is not evidence, and this one being right does not make the next one so.

3. **`0x4700` connection info is parsed and logged but never persisted.** Whoever implements
   peer-to-peer joining will need it stored, and will have to decide then what the public address
   should be (we take it from the socket, as the references do). The 2 trailing bytes are a
   **client-populated u16** from the caller's `r7` (builder `0xD5C918` at `0xD38708`, ELF
   2026-07-26) — a real field, not a reference artefact as this entry previously implied. We still
   do not read it and nobody knows what it carries.

4. **The error path for `0x4101` sends 4 bytes into a 322-byte fixed grid.** `0x4101` has no leading
   result field, so an error code lands where the character id goes. The client's read primitives
   bound-check only the receive buffer, never the payload length, so it will happily read the rest
   of the grid out of stale memory. Untested — nobody has deliberately failed a `0x4100`.

### Fixed constants we emit without knowing why

5. **`0x3049`'s 35-byte trailer**, with `07` at +4 and `03` at +6. Both Nomad upstreams and
   mgo2-server send these exact bytes. The first three complete the eighth entry's trailing u32;
   the remaining 32 are the client's `tail[32]`. Meaning unknown.

6. **`0x4101`'s four u16 header constants** `0x16AE, 0x0338, 0x013E, 0x0150`. The client stores
   them. Nobody knows what they are.

7. **`0x4120`'s 32-byte trailer** `01 00 10 00 00 00 00 10 11 10 00…`, plus the two "always 1" bits
   in privacy A and voice chat A, and the 6-, 1- and 9-byte zero runs at `0x05`, `0x0c` and `0x17`.

8. **`0x4122`'s 25-byte prefix** (its 4-byte suffix is no longer unknown — it is the saved-instructor
   marker, see the `0x4122` table); and the character id repeated at `0x6b` for no documented
   reason. ~~The fixed per-skill experience `0x600000`~~ — **resolved 2026-07-29 and no longer a
   gap.** It was never an unknown so much as an inherited constant: `0x6000 << 8`, 256x the
   client's own legal maximum of 24576, which the validator at `0x93E418` zeroes rather than
   clamps. It was inert only because it reached a roster we do not send and because `>> 13` clamps
   to 3. Both `0x4122` and `0x4131` now carry the stored per-skill value.

9. ~~**`0x4990` answers `0, 1, then 0xa4 zero bytes`.**~~ — **superseded 2026-07-26, and it was a
   live bug.** The client reads **236 bytes**, not 172: a u32, a u32 it overwrites with 4 whatever
   we send, and **four 57-byte records** in a hardcoded loop (parser `0xD48D40`). "Whether the
   client reads any of it beyond skipping" is answered — it does. See the `0x4991` section. What
   the first word and the 57-byte record mean is still unknown.

10. **`0x4125`'s three low-experience skills** (ids 17, 20, 22 at `0x2000` where every other skill
    gets `0x6000`). Copied from the original; no rationale recorded.

11. **`0x4124` lists item `0x86` twice.** Possibly faithful to the original, possibly a
    transcription slip here. Unchecked. **The 32 trailing `0xff` bytes are not a terminator** —
    settled 2026-07-26, they are 16 `{item_id, bit_index}` colour-unlock pairs, and `0xff` is
    inert only because id 255 exceeds the parser's bound. The "called a terminator on the strength
    of nothing in particular" flag was right to be there.

12. **Game list entry constants**: `0x08` at offset `0x15`, bit 2 of common A always set, the
    zero byte at `0x34`, and the **u16 `0x0063` at `0x35`** (2026-07-26: the famous `0x63` is the
    low half of a halfword, not a byte after two pads). Also **bit 2 of the host-options byte at
    `0x14`**, which the parser expands like bits 0 and 1 and whose meaning is unrecorded. All
    written verbatim from the original.

13. **`0x4902`'s attribute word** — subtype in the top byte, 24 bits of nothing. Reference-derived.

### Divergences from the references, chosen deliberately

14. **`0x4101` is `0x142` where mgo2-server sends `0x243`.** Ours matches the client's parser at
    `0xD3C120`, which consumes a fixed `0x142` grid. This one is well-founded — but it is a
    divergence, and anyone diffing against a reference will trip over it.

15. **The `0x4100` burst sends nine packets, including a `0x4124` and two `0x4121`s.** mgo2-server
    sends seven with a single `0x4121` and no `0x4124` at all; echo sends the nine we do. Which is
    right for `BLUS30109` is **not established** — the burst reaches the client but its individual
    payload layouts have never been verified against the client's parsers.

16. **Sequence numbers are not enforced.** A mismatch resyncs silently. If a desync ever turns out
    to matter to the client, this is where it hides.

17. ~~**`ENCRYPT_COMMANDS = { 0x4305 }` outbound is dead code.** Nothing sends `0x4305`.~~
    **Wrong, and struck 2026-07-26.** `HostGameController.getHostSettings` sends `0x4305` on every
    Create Game open, and `MatchStateIT` asserts its Blowfish-padded wire length. It is the only
    payload this server encrypts outbound, so far from untested it is the sole exercise of the
    encrypt direction.

### Smaller loose ends

18. **`0x3003`'s trailing flag byte.** The game-lobby sender at `0xD39F18` appends one, from
    `+0x294` of the object behind `0x883F20`. We never read it. Meaning unknown.

19. **`0x4121`'s two macro types.** Both references also just call them "type".

20. ~~**`0x4820`'s mailbox selector *names*** are reference-derived~~ — **closed 2026-07-27.** The
    values `0x0f`/`0x10` were tier-1 confirmed on 2026-07-26 (two builders, each writing a
    literal — `0xD53414` → `0x10`, `0xD53518` → `0x0F`), and the *naming* is now settled too:
    implementing clans showed that a clan application arrives as a **mail in the `0x10` mailbox**.
    The reference-derived names were right. Mail itself has been served since 2026-07-26.

21. **`0x4300`'s filter type is read and discarded.** Clan rooms are distinguished by a name prefix
    in the original; unmodelled here.

22. **The empty reply `0x4311` is a latent bug, not merely unverified** (2026-07-26). Its handler
    `0xD43550` reads **one u32** and takes a teardown path on a nonzero value; with nothing sent,
    that word comes out of stale receive buffer. Send `{u32 0}`. `0x4151`'s handler `0xD3943C` has
    not been traced to the same depth and stays in the "sufficient but unverified" column.
    Correction while here: the dispatcher is **not** "a comparison chain at
    `0xD388A8`–`0xD38948`". It is a **compare tree** — function entry `0xD387C8`, tree head
    `0xD38804`, binary search (`bgt` at `0xD3880C`) — and those two addresses are interior nodes.
    Nothing follows from the order ids appear in.

23. **`0x4316` does not read its request payload at all** — a **one-byte** payload, as of the
    2026-07-26 trace (`0xD43CDC`); "no payload" and "a payload we ignore" are different claims and
    this entry used to blur them. The settings the player configured
    arrive on `0x4310` instead, which is parsed into the game row (`applyHostSettings`) and stored
    raw per character since 2026-07-22. Confirmed reachable: a game is created and the host
    enters it.

23. **`0x3103` clamps an out-of-range index to the first character and `0x3105` to the last.** The
    asymmetry is claimed to match the original. Unverified, and unreachable in practice since the
    client bounds-checks the index itself.

24. ~~**`0x200a`'s 886-byte body field.**~~ — **answered 2026-07-26: there is no 886-byte field.**
    The body is read by the delimiter-terminated string primitive `0xD5CE34` (called from
    `0xD366B0`), so it is variable-length and self-terminating; 886 was our padding choice to land
    the payload on 1023, and the question "where did 886 come from" had an answer nobody liked
    ("we made it up"). Our NUL-padded encoding still parses. No client has been observed
    rendering a news item, so the news path is still unverified end to end.

25. ~~**`0x0005` ping replies with an empty payload rather than echoing the request.**~~ —
    **moot as of 2026-07-26.** The client's reply parser has READ_BEGIN at `0xD35A24` and READ_END
    at `0xD35A30` with nothing between: the body is never read, so echoing and not echoing are
    indistinguishable to the client.

## UI events: how `0xD33CD8` dispatches, traced 2026-07-26

Many server → client parsers end by calling `0xD33CD8` with a small integer event id and a value.
This is the mechanism behind every "…then fires UI event N" line in the specs under `dev/proto/`.
It was traced while chasing in-game chat (`0x4401` fires event `0x30`) and applies to all 65 specs
that mention the helper.

`0xD33CD8` is generic — **"command N arrived"**, with no per-command meaning of its own. It does two
independent things on the net-session context:

1. **Callback table** at `netctx+0x11388 + 4*id`. If the slot is non-null it is called
   **immediately**, as `cb(id, value)` (`0xD33D24`–`0xD33D44`). This is synchronous, inside the
   parse, on the network thread.
2. **Pending counter** at `netctx+0x11468 + id`, one byte per event, incremented and **saturating at
   `0x7F`** (`0xD33D4C`–`0xD33D6C`). Read and cleared by the poller `0xD33F8C`.

Two consequences worth knowing before designing anything around an event:

- **Only ten ids are ever polled.** The 12 call sites of `0xD33F8C` cover ids `3`, `0x1C`, `0x1D`,
  `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37`. Any other event's only route to the game
  is the callback table — i.e. handled synchronously during the parse, or not at all.
- **The counter saturates and the payload does not queue.** The value is passed to the callback and
  otherwise dropped; only the count survives, and only up to 127. For an event whose parser also
  writes a single-slot record (chat is the example: one flag, one id, one 129-byte buffer at
  `netctx+0x114C8`), back-to-back packets overwrite each other unless a callback consumes each one
  synchronously. That is fine for chat's callback consumer (`0xCA0D50`) and would *not* be fine for
  a frame-polled one.

**One event id per command parser.** Enumerating every `bl 0xD33CD8` with its immediate `li r4,imm`
gives 49 sites, each a distinct id — so the id identifies which command arrived, and no two parsers
share one. Worked examples: `0x30` is fired only by the `0x4401` parser (`0xD52CB0`) and `0x31` only
by `0x4442`'s (`0xD52900`).

These two also show that the *shape* of the handling differs sharply per event even though the
dispatch is uniform, so an event id tells you nothing about what is rendered until its branch is
read: event `0x30` fills the chat display record and redraws, while event `0x31` — in the same
handler, `0xCA0060` — builds a canned system line from string-table ids `0x201B` and `-0x2D1` and
touches none of the chat fields.
