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

### `0x2003` entry — 46 (`0x2e`) bytes

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

**Client → server**, `NewsGameController.getNewsItems`. Request payload is not read. No
authentication check — the gate has no session yet.

| command | payload |
| --- | --- |
| `0x2009` | 4 bytes: `00000000` |
| `0x200a` | one per news item, 1023 bytes |
| `0x200b` | 4 bytes: `00000000` |

### `0x200a` item — 1023 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x000` | 4 | u32 | news id |
| `0x004` | 1 | u8 | important flag (0/1) |
| `0x005` | 4 | u32 | timestamp, Unix seconds |
| `0x009` | 128 | ISO-8859-1 | title, NUL-padded |
| `0x089` | 886 | ISO-8859-1 | body, NUL-padded |

886 is not a round number and no rationale for it is recorded — it is what makes the payload
exactly the 1023-byte maximum. Unverified: no client has been observed rendering a news item.

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
| `0x06` | 1 | u8 | zero — the client reads this as `selectedSlot` |
| `0x07` | 16 | ISO-8859-1 | first character's name, **written twice**; this copy lands in the client's header `name[16]` |
| `0x17` | 1 | u8 | zero — becomes entry 0's `slot` byte |
| `0x18` | 4 | u32 | entry 0 character id |
| `0x1c` | 16 | ISO-8859-1 | entry 0 name |
| `0x2c` | 28 | — | entry 0 appearance block (below) |
| `0x48` | 4 | u32 | entry 1 index (`1`) — top three bytes complete entry 0's trailing u32, low byte is entry 1's slot |
| … | 52 | — | entries 1..7, each `u32 index, u32 charaId, name[16], appearance[28]` |
| `0x1b4` | 35 | — | fixed trailer |

The two shapes reconcile exactly: because an index is `00 00 00 nn`, its three leading zeros
complete the previous entry's final u32 and its low byte lands where the client expects the slot.
That is why the writer looks inconsistent (name for the first entry, index for the rest) and is
nevertheless right.

Eight full entries end at exactly `0x1b4`, so with a full account no padding is written at all;
with fewer, the gap is zero-filled.

### Appearance block as written here — 28 bytes

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
| +27 | 1 | zero — first byte of the client's trailing u32 |

The main character is listed first and its name is prefixed with `*`. Ordering is
`CharacterService.listForAccount`: by id, with the main character moved to the front.

### The 35-byte trailer

```
00 00 00 00 07 00 03 00  00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
00 00 00
```

**Unknown.** The `07` and `03` at offsets +4 and +6 are non-zero and nobody knows why; both Nomad
upstreams and mgo2-server send these exact bytes. The first three bytes complete the eighth entry's
trailing u32 and the remaining 32 are the client's `tail[32]`. This was 32 bytes here until
recently, making the payload 468 — the client would have read its last three tail bytes out of
stale buffer contents, because its read primitives bound-check only the 0x400 receive buffer and
never compare consumed bytes against the payload length.

## `0x3101` — create character

**Client → server**, `CharacterGameController.createCharacter`.

### Request

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 16 | ISO-8859-1 | name, NUL-terminated within the field |
| `0x10` | 27 | — | appearance, read by `readAppearance` (below) |

Confirmed from the binary as "16 name bytes then the appearance bytes". The exact appearance length
the client sends is **not** confirmed; we require at least 27 readable bytes and read exactly 27.

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
| +9 | 4 | **skipped, purpose unknown** |
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

The four bytes at +9 remain **skipped, purpose unknown**. They sit where the write path emits four
zero bytes, so nothing is known to be lost, but nothing confirms that either.

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
| `0x00` | 1 | u8 | index into the list last sent by `0x3049` |

The client bounds-checks the index ≤ 7 before sending (confirmed from the binary). We clamp an
out-of-range index to **0**. Reply `0x3104` is 4 bytes: `00000000`, `C0FFEE02` (no session) or
`C0FFEE20` (the account has no characters).

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

**Flagged: the reply shape is inferred, not read.** `dev/docs/OBSERVED.md` lists `0x3108` among the
replies parsed as a single s32, on the strength of its sibling result packets (`0x3004`, `0x3102`,
`0x3104`, `0x3106`) all being parsed that way, and of the request-status arm marking id `0x12`
complete. The `0x3108` parser itself was not read out of the binary. It works in practice.

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
| `0x00` | 1 | privacy A: bit 0 always **1** (unknown why), bits 4–5 online-status mode, bit 6 email-friends-only |
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
| `0x14` | 1 | bit 0 lock-on enabled, bits 4–7 BGM volume **+1** |
| `0x15` | 1 | radar: bit 0 lock north, bit 4 hide floor |
| `0x16` | 1 | HUD: bits 0–1 display size, bit 4 hide name tags |
| `0x17` | 9 | zero, purpose unknown |
| `0x20` | 16 | codec entries 1–4, four bytes each (`a`,`b`,`c`,`d`) — meaning of the four bytes unknown |
| `0x30` | 256 | four codec names, 64 bytes each, ISO-8859-1 |
| `0x130` | 32 | **unknown** fixed trailer (below) |

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
| `0x00` | 4 | u32 | clan id — always 0, clans are not modelled |
| `0x04` | 16 | ISO-8859-1 | clan name — always empty |
| `0x14` | 25 | — | **unknown** fixed block (below) |
| `0x2d` | 4 | u32 | current time, Unix seconds |
| `0x31` | 9 | — | appearance bytes 0–8 (gender … pitch), same order as `0x3049` |
| `0x3a` | 4 | — | zero, purpose unknown |
| `0x3e` | 14 | — | appearance bytes head … accessory-2 colour |
| `0x4c` | 4 | 4 × u8 | equipped skills 1–4 |
| `0x50` | 1 | u8 | zero, purpose unknown |
| `0x51` | 4 | 4 × u8 | equipped skill levels 1–4 |
| `0x55` | 1 | u8 | zero, purpose unknown |
| `0x56` | 16 | 4 × u32 | per-skill experience — **fixed `0x600000` each**; skill progression does not exist |
| `0x66` | 5 | — | zero, purpose unknown |
| `0x6b` | 4 | u32 | character id again — "the original sends the character id here; its purpose is not documented" |
| `0x6f` | 128 | ISO-8859-1 | comment |
| `0xef` | 1 | u8 | rank |
| `0xf0` | 1 | u8 | emblem flag — 3 when the clan has one; always 0 here |
| `0xf1` | 4 | — | **unknown** suffix `00 A7 00 0D` |

The 25-byte prefix:

```
01 00 00 00 0C 00 01 00  00 00 00 00 00 00 00 00
01 00 01 00 00 00 00 00  01
```

Undocumented; reproduced byte for byte.

### `0x4124` — gear catalogue, 651 bytes

**The 123 item ids are a data table, not a derivable sequence.** They are listed in
`nomad.game.LoadoutWriter` and are not reproduced here; a reimplementation needs that table, which
was taken from the original server's gear catalogue. Note `0x86` appears twice in it — unchecked
whether that is faithful or a transcription slip.

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | item count — 123 |
| `0x04` | 615 | 123 × 5 | per item: `u8 item id`, `u32 colour mask` |
| `0x26b` | 32 | — | terminator: 32 bytes of `0xff` |

Not per-character state: every item is advertised as owned, in every colour (`0xffffffff`).
Progression does not exist, and a partial invented one would be worse than granting everything.
The item ids come from `LoadoutWriter.GEAR_ITEMS` and their meaning lives in the game's own tables.

**Flagged:** the list contains `0x86` **twice** (`0x85, 0x86, 0x86, 0x87`). Whether that is a
faithful copy of the original or a transcription slip in this project has not been checked.
Whether the 32 `0xff` bytes are a terminator or a fixed-size trailing field is also a guess.

### `0x4125` — skill catalogue, 104 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | skill count — 25 |
| `0x04` | 100 | 25 × 4 | per skill: `u8 skill id` (1..25), `u16 experience`, `u8` zero |

Experience is `0x6000` for every skill except ids **17, 20 and 22**, which get `0x2000`. Why those
three are lower is **unknown**; it is what the original advertises.

### `0x4140` — skill sets, 3 × `0x4d` = 231 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| +0 | 4 | u32 | modes bitmask — which game modes this set applies to. Bit meanings not documented here |
| +4 | 4 | 4 × u8 | skills 1–4 |
| +8 | 1 | u8 | zero, purpose unknown |
| +9 | 4 | 4 × u8 | levels 1–4 |
| +13 | 1 | u8 | zero, purpose unknown |
| +14 | 63 | **UTF-8** | set name |

Three sets per character, materialised empty on first use. Note the charset: set names are the only
UTF-8 strings in the protocol, which is why `BufferUtil.writeString` has a separate path that
truncates on a character boundary.

### `0x4142` — gear sets, 3 × `0x57` = 261 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| +0 | 4 | u32 | stages bitmask — which maps/stages this set applies to |
| +4 | 20 | 20 × u8 | face, head, upper, lower, chest, waist, hands, feet, accessory 1, accessory 2, head colour, upper colour, lower colour, chest colour, waist colour, hands colour, feet colour, accessory 1 colour, accessory 2 colour, face paint |
| +24 | 63 | **UTF-8** | set name |

Note the field order differs from every other appearance block in the protocol — colours are
grouped at the end and face paint is last.

## `0x4130` — update personal info

**Client → server**, `PersonalInfoController.updatePersonalInfo`. Sent when the player changes
clothes or edits their comment.

The client blocks on the reply: with nothing sent back it stalls and fails with
**`1031:FFFFFF60`**.

### Request — at least 158 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 19 | 19 × u8 | upper, lower, face paint, upper colour, lower colour, head, chest, hands, waist, feet, accessory 1, accessory 2, head colour, chest colour, hands colour, waist colour, feet colour, accessory 1 colour, accessory 2 colour |
| `0x13` | 4 | 4 × u8 | skills 1–4 |
| `0x17` | 1 | u8 | skipped, purpose unknown |
| `0x18` | 4 | 4 × u8 | skill levels 1–4 |
| `0x1c` | 2 | — | skipped, purpose unknown |
| `0x1e` | 128 | ISO-8859-1 | comment |

Only the appearance and the comment are persisted; the skills and levels are read and echoed back
but not stored. **Note this request carries `lower` and `hands_color`, which `0x3101` skips** — the
strongest evidence that the creation-time skip is wrong.

### Reply `0x4131` — 186 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | s32 | result, zero |
| `0x04` | 19 | — | the 19 clothing bytes, echoed |
| `0x17` | 4 | — | skills, echoed |
| `0x1b` | 1 | — | zero |
| `0x1c` | 4 | — | levels, echoed |
| `0x20` | 1 | — | zero |
| `0x21` | 16 | 4 × u32 | per-skill experience — fixed `0x600000`, as in `0x4122` |
| `0x31` | 5 | — | zero, purpose unknown |
| `0x36` | 128 | ISO-8859-1 | comment, echoed |
| `0xb6` | 4 | u32 | face-paint colour unlock mask — **`0xffffffff`**, all colours |

The client wants its own values back rather than a bare result code, which is why this is not a
four-byte reply like its neighbours. Errors are 4 bytes (`C0FFEE02`, `C0FFEE01`).

## `0x4110` — update gameplay options

**Client → server**, `HostGameController.updateSettings` (the constant name predates the
identity being settled). The write-back half of `0x4120`: first observed live 2026-07-22 as a
**304-byte** push — the `0x4120` layout minus its 32-byte trailer — sent by a *joiner* in one
burst with two `0x4114`s when saving options. The body is acknowledged (`0x4111 {u32 0}`,
required) but **not yet parsed into `chara_settings`**, so option edits do not persist across
sessions; the layout to parse is `0x4120`'s own, already documented above. An earlier theory
that this command carried the Common Settings toggles in a 48-byte rules header was wrong — see
OBSERVED.md.

## `0x4114` — update chat macros

**Client → server**, `CharacterConnectController.updateChatMacros`. The write-back half of
`0x4121`, first observed live 2026-07-22 (two packets, one per macro type, in the options-save
burst): `u8 type`, then twelve 64-byte ISO-8859-1 texts — the exact `0x4121` layout. Persisted
into `chara_chat_macro`, so macro edits survive sessions. Reply `0x4115 {u32 0}` — **shape
inferred from the sibling result packets, not read from the binary**; the client observably does
not stall on it. Notably the client fires `0x4110` + both `0x4114`s in a single burst without
waiting between them.

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

Title history and award ("medal") history on the same screen are **not** fed by this burst, by
any command, or by the record tables earlier suspected (`T+0x26d14` and `T+0x3330` turned out
to be match-history list storage for `0x4682`/`0x4212` records) — they are **computed
client-side from the stat values**, against a 22-title resource table (VA `0xe14eb0`) and a
39-row medal threshold table (VA `0xe139c0`, `{u32 id, u32 name-hash, u32 threshold}`,
13 medals × 3 tiers). The thresholds are transcribed in OBSERVED.md; the server's only job is
honest stats.

## `0x4132` — outfit commit

**Client → server**, `PersonalInfoController.commitOutfit`. First observed live 2026-07-23: closing
the outfit screen fires the `0x4130` updates (answered) and then this, **empty payload** (confirmed
from the sender `0xd3a844` — zero appends), blocking on wait slot `0x1b`.

The `0x4133` reply is **not a result code**. The parser (`0xd3c77c`) zeroes the client's loadout
table (`0x60c` bytes) and then reads: u32 **entry count**, `count ×` `{u8 slot, u32 value}`
loadout entries (12-byte records into `charTable+0x26a0+slot*0xc`, slot ≤ `0x80`), then a fixed
**fifteen** `{u8 slot, u8 bit}` equipped-bit pairs — total `34 + 5·count` bytes. A nonzero first
u32 would be read as a count, not an error, and the read primitives do not check payload length
(the `0x4101` caveat again). We send the 34-byte empty readback (count 0, zero pairs); what the
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
| `0x4302` | up to 18 entries, `0x37` bytes each |
| `0x4303` | 4 bytes result |

### `0x4302` entry — 55 (`0x37`) bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | game id |
| `0x04` | 16 | ISO-8859-1 | game name |
| `0x14` | 1 | u8 | host options: bit 0 password set, bit 1 dedicated |
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
| `0x34` | 2 | — | zero, purpose unknown |
| `0x36` | 1 | u8 | **unknown**: always `0x63` |

## `0x4304` — get host settings

**Client → server**, `HostGameController.getHostSettings`. Sent when Create Game opens, so the
screen can be pre-filled with whatever the player hosted last time. Empty request.

### Reply `0x4305` — 128 bytes empty, `0x163` populated

**The only payload this server encrypts on the way out.** Until this command was implemented
nothing sent `0x4305`, so the Blowfish encrypt direction had never produced a byte the client saw.
The empty path is confirmed working: the Create Game screen opens.

A host with nothing saved gets 128 zero bytes, which is what both references send and what the
client reads as "no saved settings".

**Populated (implemented 2026-07-22, verified against a live client the same day):** the raw
`0x4310` blob the character last pushed is stored per (character, lobby subtype) and re-mapped
into the reply shape transcribed from Nomad's `Hosts.getSettings()` — a `0x163`-byte structure
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

352 bytes (observed), laid out roughly (offsets from the name at 0; per savemgo `Hosts.checkSettings`
cross-checked with the `0x4313` layout):

| offset | size | field |
| --- | --- | --- |
| `0x00` | 16 | name (ISO-8859-1, NUL-padded) |
| `0x10` | 128 | comment |
| `0x90` | 1 | password enabled |
| `0x91` | 15 | password |
| `0xA1` | 1 | dedicated |
| `0xA2` | 1 | subtype byte (the `u8` before the rotation, as in `0x4313`) |
| `0xA3` | 45 | rotation: `[rule, map, flags]` × 15, stride 3; `rule==0 && map==0` ends it |
| `0xE5` | 1 | max players |
| `0xE6` | 4 | briefing time |
| `0xFC`… | … | per-rule timers/rounds/tickets, then uniques, commonA/B bitfields, kicks |

**Partly stored now.** `HostGameController.checkHostSettings` parses **round 0** of the rotation
(`rule, map, flags` at `0xA3`) into the connection, and `createGame` writes them onto the game, so
the browser shows the real match type/map/mode instead of DM/map-0. Since 2026-07-22 the **raw
blob is also persisted** per (character, lobby subtype) in `chara_host_settings.blob`, which is
what the populated `0x4304` reply and the `0x4392` rotation advance read. **One-byte caveat:** the
rotation start is ambiguous between the references (Model A = `0xA2`, Model B = `0xA3`); we use
`0xA3`. Confirm by hosting a game changing only the map and seeing whether byte `0xA4` or `0xA3`
changes.

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
entry — and level-limit base is a **u32 at `0xF8`**; flipping only friendly fire moved exactly
`0x142` bit 3. `applyHostSettings` decodes the toggles into their columns, zeroes the idle/team-kill
counts (`0x146`/`0x148`) when their enable bits (commonA bit 0 / commonB bit 7) are off, and reads
non-stat from the host-options byte at `0x155` bit 1. An earlier read of a u16 base at `0x142` was
a bug that stored toggle bits as the base.

### Reply `0x4311` — empty

**Sufficient, but not known to be complete.** Both references send an empty payload and this client
accepts it and proceeds, so nothing more is *required*. That is weaker than it was previously
written here ("the client only waits for the acknowledgement"), which asserted an intent nobody had
checked.

Against that reading: the client's reply dispatcher (`0xD388A8`–`0xD38948`, a comparison chain over
reply ids) routes `0x4311` to a real handler at `0xD43550`, not a no-op. It verifies the command id
and calls into the packet-reader library. Whether it reads any field beyond the header is
undetermined — if the original server sent something here, we are dropping it and the client is
tolerating the absence.

## `0x4150` — lobby disconnect

**Client → server**, `HubGameController.lobbyDisconnect`. Sent when the player backs out of a lobby
to the previous screen. Empty request, empty `0x4151` reply.

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

Request: read as one **u32 game id**. That is what echo and mgo2-server parse and it matches the
reply's echo of the id, but the sender has not been located in the binary — the handler logs a
warning if the payload is not exactly 4 bytes, which would be the first sign this is wrong.

### Reply `0x4313` — 372 bytes plus 28 per player

**The layout below is read from the binary**: the reply dispatcher at `0xD38954` routes `0x4313`
to the parser at `0xD44388`, whose read calls (with the settings sub-structure at `0xD4364C`) fix
every size and position. The parser reads the fixed 372 bytes unconditionally — **a short payload
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
| `0x098` | 2 | — | zero |
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
| `0x108` | 4 | u32 | echo writes `0x16` verbatim; meaning unknown — **regression guard only** |
| `0x10c` | 68 | u32 ×17 | per-rule timers and rounds (echo: SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r); zeros until stored |
| `0x150` | 2 | u8, u8 | unique characters red/blue (+`0x80` when random); zeros until stored |
| `0x152` | 7 | u16, u32, u8 | parser reads, echo zeroes; unknown |
| `0x159` | 1 | u8 | common A — same bitfield as the `0x4302` entry |
| `0x15a` | 1 | u8 | common B — same bitfield as the `0x4302` entry |
| `0x15b` | 1 | u8 | zero |
| `0x15c` | 2 | u16 | idle kick |
| `0x15e` | 2 | u16 | team-kill kick |
| `0x160` | 4 | u32 | echo writes `0x2e` verbatim; meaning unknown — **regression guard only** |
| `0x164` | 2 | u8, u8 | capture extra time; sneaking-mission Snake side. Zeros until stored |
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
| `0x18` | 4 | u32 | experience, from the account's main/alt pool per character |

**Untested against a live client** as of writing — implemented from the parser the same evening
the missing handler was identified; the first two-machine session should retire this caveat.

## `0x4316` — create game

**Client → server**, `HostGameController.createGame`. Request payload is **not read at all**.

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

Untested against a live client — nothing has reached the host screen yet.

## `0x4700` — update connection info

**Client → server, payload Blowfish-encrypted.** `CharacterConnectController.updateConnectionInfo`.
The endpoint the client wants other players to reach it on, sent right after joining a game lobby.
Matches are peer-to-peer, so this is what a joining client is eventually handed.

The client blocks on the reply: with nothing sent back it fails with **`092E:FFFFFF60`**.

### Request — at least 20 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 2 | u16 | private port |
| `0x02` | 16 | ISO-8859-1 | private IP, dotted quad, NUL-padded |
| `0x12` | 2 | u16 | public port |
| `0x14` | 2 | — | present in echo's parser, which skips it. **Not read by us**; purpose unknown |

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

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | game id |
| `0x04` | 16 | ISO-8859-1 | password, NUL-padded — read when present; echo sends it, mgo2-server does not |

The leading game id is agreed by both references; the password field is echo's and read only if
the payload extends that far. **Sender not yet located in the binary**, so the exact request width
is unconfirmed — a mismatch shows up as a game-not-found error, not a hang.

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
absent too until 2026-07-23, when a natural **TDM** round end sent it — once per round end,
between the per-player `0x4390` reports (the 2026-07-22 sweep that missed it was DM-era).
Payloads (hex, undecoded — no reference parses this command): 15 B
`000000010000000119000100010000` twice for identical headshot rounds, and 22 B
`0000000100000002010001000000002b000000010001` for the round with a stun + sleeping-body
kill, so the length varies with round content. We ack `0x43a3`, result 0, and drop the data
knowingly; decoding it is parked until a reason appears.

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
`{u32 chara id, u32 ping}` pairs; a zero id is skipped (as in Nomad). The host ping lands on the
game row (`0x4302` offset `0x1e`), each player's on their roster row (`0x4313` player entry offset
`0x14`), and the game's `last_update` is touched — in Nomad this report doubles as the heartbeat
that keeps a game from being reaped; we track the timestamp but do not reap on it (host
disconnects already tear the game down). Reply stays the **empty** `0x4399` that is live-verified;
Nomad sends a 4-byte 0 instead, and reshaping a working ack on reference evidence is exactly the
mistake this project keeps regretting.

## `0x43ca` — start round (never observed)

**Client → server**, `HostGameController.startRound`. **Never observed from this client on any
path** — its handler (which snapshots the roster into `game_round` to gate `0x4390`) is
Nomad-derived and effectively dormant here: without the snapshot, stat application relies on the
current-membership check, which drops reports for players who already left (observed live: a
crashed joiner's straggler report was rejected). See BACKLOG, "The round snapshot never
populates". Reply `0x43cb`, result 0, if it ever arrives.

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

Deviation tripwires in `updateStats`: a `0x4390` on a non-host connection and a nonzero
trailing word each log a WARN with payload hex — if either fires, these truths need revisiting.

**Client → server**, `HostGameController.updateStats`, one player per packet, sent by the host at
round end and on kick teardown. **Confirmed against a live client 2026-07-22** — this build sends
**167-byte** reports, and two rounds of captures pinned the fields against known ground truth:

The full 167-byte frame, from the ELF builder `0xD42178` (the `statB`-present path, cross-checked
against the three live-pinned offsets). The counter *positions* are read from the binary; their
*labels* (which u16 is kills vs deaths vs score) are **not** — that needs tracing where the stat
structs are incremented during gameplay, which has not been done, so the block is documented as
structure, not meaning.

| offset | size | type | meaning | confidence |
| --- | --- | --- | --- | --- |
| `0x00` | 4 | u32 | target character id | live-pinned |
| `0x04` | 1 | u8 | flag byte (aborted / result) | high |
| `0x05` | 2 | s16 | **kills** | live-confirmed |
| `0x07` | 2 | s16 | **deaths** (suicides included) | live-confirmed |
| `0x09` | 2 | s16 | **lock-on kills** — single-variable round 2026-07-23: exactly 3 in a 3-lock-on-kill round, zero across five kill rounds without | live-confirmed |
| `0x0b` | 2 | s16 | **score** — **clamped at 0**, observed twice where categories implied negative; the earlier "can go negative" note was never actually observed (that capture landed on exactly 0) | live-confirmed |
| `0x0d` | 2 | s16 | **stun / knockout count** — requires an actual faint; slams that don't knock out tick struct-B pairs instead | live-confirmed |
| `0x0f` | 2 | s16 | unknown (a loser-side 1 twice; a player had 1 in the original capture) | low |
| `0x11` | 2 | s16 | **headshots dealt** (bullets only — knife stabs to the head do not count, 2026-07-23) | live-confirmed |
| `0x13` | 2 | s16 | **headshot deaths** — across three rounds (two TDM, one Rescue) it exactly equalled the enemy's headshot count (5/5/1); strong, but a 3+ player match would make it airtight | medium-high |
| `0x15`–`0x19` | — | s16 | zero in every observed round | — |
| `0x1b` | 2 | s16 | **deaths to lock-on** — received mirror of `0x09`, as `0x13` mirrors `0x11` (3 in the lock-on round, zero elsewhere) | live-confirmed |
| `0x1d` | 2 | s16 | rounds played? — **never observed nonzero across 9 live reports 2026-07-23**; the capture-era label is doubtful | low |
| `0x1f` | 2 | s16 | 1 for every player of a normally-completed round, 0 in mid-game teardown reports — "round completed" | medium |
| `0x21` | 2 | s16 | **round won** — winner-only across seven rounds, then transferred to the other player on the reporter's first loss | live-confirmed |
| `0x23` | 4 | 2 × u16 | **two fields, not one u32** (decoded 2026-07-23 late): hi u16 = **team slot index** (0/1; constant per player per game, 0 for everyone in DM, grouped killers correctly in a 3-player TDM — the "garbage seconds" were this bit); lo u16 = **seconds in game/round** (equal for both players of a fully-played round) | live-confirmed |
| `0x27` | 4 | u32 | **experience, absolute total** | live-pinned |
| `0x2b` | 4 | u32 | extra-block flag/count (1 when the detail block is present) | high |
| `0x2f` | 116 | 58 × s16 | detailed stat block (struct B) — an itemised event breakdown, **not** the scoreboard categories, which live in struct A above. Partially mapped by the 2026-07-23 single-variable rounds (OBSERVED.md, "The OTHER-field experiment"); slot table below | positions high, labels per slot |
| `0xa3` | 4 | u32 | trailing value | low |

Struct B slots (0-based; everything not listed has never been observed nonzero). Per the
no-duplicates rule, "matched X" means exact correlation in N/N observed rounds, not identity:

| slot | evidence | reading |
| --- | --- | --- |
| B0 / B1 | matched kills / deaths 7/7 rounds (B1 includes suicides, B0 does not) | kill/death event counters; relation to A-slots undetermined |
| B3 | 3 in a 3-grenade-suicide round, 0 elsewhere | **suicides** |
| B8 | 1 in the plain-rifle round only (same gun as the lock-on round, which had 0) | one-off, open |
| B10 ↔ B11 | dealt/received **pair** (exact both sides, twice); moved by CQC grabs (4), barrels (3), grab practice (11 received); NOT by grenades/knife/rifle kills | CQC-contact-flavoured (grabs?) |
| B12 | 3 in each explosive-kill round, exactly 1 in knife/rifle/CQC rounds, 0 in the lock-on round and practice | explosions caused? one-off component unexplained |
| B21 | 1 alongside the one slam-faint | stun-adjacent |
| B22 ↔ B23 | dealt/received **pair** (exact both sides, twice); slams/knockdowns incl. practice (8 received) — ticks without a faint, unlike A `0x0d` | slam/knockdown-flavoured |
| B36 | matched kills 7/7 incl. plain-bullet rounds; NOT special-kills; stayed 0 for suicides | kill-correlated; the old "≈ Other" coincidence is dead |
| B39 | matched the KILL 1ST PC screen line 4/4 (incl. a 0) | **kill-1st-place count** |

The scoreboard labels were **confirmed 2026-07-22** by a two-round TDM capture whose per-player
totals (kills/deaths/score/headshots/stuns) matched the summed slots exactly — see OBSERVED.md,
"The 0x4390 scoreboard". The score formula, **revised 2026-07-23** after five DM rounds
decomposed exactly:
`kills·3 − deaths·2 + headshots·2 + stun·3 + kill1st·5 + combo·1 (+ unprobed categories), clamped at 0`
— the capture-era `stun·2` read came from an ambiguous `1·2` term that was likely the wake
counter, and `hacking·5` may equally have been the kill-1st-place ·5 (both unprobed since).
No round-win bonus exists. Each report is one round for one player; a kill-less round sends
the frame with these slots zero. When stat struct B is absent the builder emits a **short
~51-byte** form (`u32=0` at `0x2b`, then the trailing word). Counters are u32 values truncated
to u16 on the wire, so any above 65535 wrap.

**What we consume (since 2026-07-23):** experience is applied to the account pool (main/alt
split) with the aborted-dock policy, and the **whole decoded frame is stored as one
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

## `0x43a2` — round-end slot-tally list (observed and ELF-decoded 2026-07-23)

**Client → server**, acked `0x43a3` (result 0). The 2026-07-22 "never sent" verdict was DM-era:
natural **TDM** round ends send it, once per round, between the per-player `0x4390` reports.
ELF-decoded the same day it was first observed (builder `0xD41AC0`, caller `0x27CC78`):

```
u32 MVP chara id      — the round's overall top performer, team outcome irrelevant
                        (losing-team 4-kill player beat the winning team's 3-kill player
                        and the round-ending killer, 2026-07-24). The tally entries are
                        the MVP's alone. Mechanically the cached 0x4101-shaped character
                        record the client snapshots per round (ELF).
u32 count             — number of entries (builder caps 0x7f; caller caps 50)
count × { u8 weapon id, u16 kills, u16 headshots (terminal blows), u16 faints caused }
```

The caller walks a 127-slot, 3-bytes-per-slot client table and emits one entry per non-zero
slot. **The slot index is the weapon id and the triple is {kills, headshots, faints} —
both live-confirmed 2026-07-24**: a deliberate AK102 round of one headshot + one body kill
produced exactly `{AK102: 2,1,0}`, splitting kills from headshots; earlier anchors
`{ST KNIFE: 1,0,0}` (the sleep-stab) and `{MOSIN N: 0,1,1}` (the tranq dart — dart
headshots count here though not in the scoreboard's lethal-bullets-only slot). Weapon
names: the ELF's 141-entry master table, `dev/docs/WEAPONS.md`. So `0x43a2` is a fully
decoded per-weapon round breakdown — currently acked and dropped; storing it is
backlogged. It carries **no token, no game/room id, and no round counter**
(the caller references none of the token storage; see the reporting-model note under
`0x4390`). We ack and store nothing; decode-and-store is future work once the slot table's
meaning is pinned.

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
(**59-byte** records — u32 id, char[16] name, u16, char[16], u32, char[16], u8; only id and name
are of known meaning), `0x4583` end. **Never observed live**, and we cannot fill the 59-byte
record honestly, so it is answered **empty** (start then end) — enough that the menu cannot hang.
Populate once a real `0x4580` is captured.

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
`u8` match case (both toggles are packed nibbles of one UI control byte), then a 16-byte name.
The client does no matching of its own — **all four semantics combinations are server policy**;
ours is substring for partial, SQL-escaped. Result records (`0x4602`, parser `0xd45f38`,
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
16B string (clan? sent but rendered "---"), u8, u32, u32, u8, u32 — with the u32 at wire
0x22 confirmed as **play time in seconds** (fingerprint 9503 → "02:38:23"). The card also
renders a LEVEL never sent literally (likely table-derived from an exp-like u32; candidates
at wire 0x18/0x1E). Its square button ("more details") sends `0x4102` for the card's
character. Byte-exact layout with client struct destinations and per-field fingerprint
results: `dev/proto/mgo2_cmd_4221.ksy`. TEMPORARY fingerprint markers are served (id echoed,
u32s 95xx, u8s 61–65, `FP-DTL-*` strings).

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

## `0x4440` — unknown

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

The selector values are named after the reference servers and are unverified.

| command | payload |
| --- | --- |
| `0x4821` | 4 bytes result |
| `0x4822` | never sent — the mailbox is always empty |
| `0x4823` | 4 bytes result |

Start then end with nothing between is a real answer, not a stub: a player with no mail is the
ordinary case — and it is also all either reference does for the *mail* selector (`0x0f`): Nomad
never stores mail and never emits a `0x4822` for it, mgo2-server likewise. So an empty mailbox is
reference parity, not a gap.

For the record (transcribed from Nomad 2026-07-22, used only for **clan applications**, selector
`0x10`, which we do not model), a `0x4822` entry is 266 bytes: `u8 mtype(0), u8 index, u8 1,
name[128], comment[128], u32 time, u8 0, u8 important, u8 read`. Reference-derived and never sent
by us. The rest of Nomad's mailbox: `0x4800` send implements only clan applications (reply
`0x4801` = `{u32 status, u8 0, u32 error count, then name[16]+u32 code per error}`), `0x4840`
get-contents replies with **command `0x4341`, empty** — almost certainly a Nomad typo for
`0x4841`; do not copy it — and `0x4860` is a no-op `0x4861 {0}`.

## `0x4900` — get game lobby info

**Client → server**, `HubGameController.getGameLobbyInfo`. The hub screen's list of game lobbies.
Request payload is not read. Blocks on the reply — **`0A21:FFFFFF60`** without one.

| command | payload |
| --- | --- |
| `0x4901` | 4 bytes result (`C0FFEE02` and stop, with no session) |
| `0x4902` | up to 8 entries, 35 bytes each |
| `0x4903` | 4 bytes result |

Only lobbies of type GAME are listed.

### `0x4902` entry — 35 bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | index |
| `0x04` | 4 | u32 | attributes: **the lobby subtype in the top byte**, the remaining 24 bits unused/unknown |
| `0x08` | 2 | u16 | lobby id |
| `0x0a` | 16 | ISO-8859-1 | lobby name |
| `0x1a` | 4 | u32 | open time — always 0 |
| `0x1e` | 4 | u32 | close time — always 0 |
| `0x22` | 1 | u8 | open flag — always 1 |

Whether "attributes" really is subtype-in-the-top-byte is reference-derived and unverified; the
other 24 bits have no known meaning.

## `0x4990` — get game entry info

**Client → server, payload Blowfish-encrypted.** `HubGameController.getGameEntryInfo`. Entry
conditions for the current lobby. Request payload is not read. Blocks on the reply —
**`0A21:FFFFFF60`** without one.

### Reply `0x4991` — 172 (`0xac`) bytes

| offset | size | type | meaning |
| --- | --- | --- | --- |
| `0x00` | 4 | u32 | **unknown**: always 0 |
| `0x04` | 4 | u32 | **unknown**: always 1 |
| `0x08` | 164 | — | **unknown**: `0xa4` zero bytes. The comment says the client "only skips" this block, which is itself unverified |

Both references send this exact fixed answer — `bo.writeInt(0).writeInt(1).writeZero(0xa4)` in
echo, byte for byte — so no restriction is expressed here by anyone. Nobody knows what the two
words mean or why the block is `0xa4` long.

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
`0x43c8`, `0x43d0`, `0x43e0`, `0x43e2`, `0x4400` — plus connect-family write-backs `0x4112`,
`0x4210`, `0x4220`. (`0x4102` and `0x4132` were on this list until 2026-07-23, when both surfaced
as live stalls and were traced and handled — see their sections.) The rest have not surfaced in
testing yet, so each is conditional on a specific action/menu we have not exercised.

**Whole unmodelled subsystems (only reached if that feature's menu is opened):**

| block | ids | subsystem |
| --- | --- | --- |
| `0x4bxx` | 23 consecutive (`0x4b00`–`0x4b90`) | clans / GHQ — nothing clan-related is modelled |
| `0x49xx` extended | `0x4904`–`0x49c2` (~18) | game-lobby / roster / GHQ |
| `0x4axx` | `0x4a25`, `0x4a30`, `0x4a40` | unidentified |
| mailbox rest | `0x4800`, `0x4840`, `0x4860`, `0x4880` | send / read / file / manage mail (we do only `0x4820` get) |
| social | `0x4600`, `0x4680`, `0x4684`, `0x4220` | player search, met-players history, player details |
| misc | `0x2006`, `0x4e00` | lobby-layer / isolated |

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

2. **The `0x3108` reply shape is inferred, not read.** It is modelled on its sibling result packets
   (`0x3004`, `0x3102`, `0x3104`, `0x3106`), all of which *are* confirmed as single-s32 parses. The
   `0x3108` arm itself was never disassembled. It works, so the risk is low, but it is a guess.

3. **`0x4700` connection info is parsed and logged but never persisted.** Whoever implements
   peer-to-peer joining will need it stored, and will have to decide then what the public address
   should be (we take it from the socket, as the references do). The 2 trailing bytes of the
   request are not read by us and echo only skips them; nobody knows what they carry.

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

8. **`0x4122`'s 25-byte prefix** and its 4-byte suffix `00 A7 00 0D`; the fixed per-skill experience
   `0x600000`; and the character id repeated at `0x6b` for no documented reason.

9. **`0x4990` answers `0, 1, then 0xa4 zero bytes`.** Both references send exactly that. What the
   two words mean, why the block is `0xa4` long, and whether the client reads any of it beyond
   skipping, are all unknown.

10. **`0x4125`'s three low-experience skills** (ids 17, 20, 22 at `0x2000` where every other skill
    gets `0x6000`). Copied from the original; no rationale recorded.

11. **`0x4124` lists item `0x86` twice.** Possibly faithful to the original, possibly a
    transcription slip here. Unchecked. The 32 trailing `0xff` bytes are called a terminator on the
    strength of nothing in particular.

12. **Game list entry constants**: `0x08` at offset `0x15`, bit 2 of common A always set, the
    2 zero bytes at `0x34`, and `0x63` at `0x36`. All written verbatim from the original.

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

17. **`ENCRYPT_COMMANDS = { 0x4305 }` outbound is dead code.** Nothing sends `0x4305`. It is
    untested and carried only for parity.

### Smaller loose ends

18. **`0x3003`'s trailing flag byte.** The game-lobby sender at `0xD39F18` appends one, from
    `+0x294` of the object behind `0x883F20`. We never read it. Meaning unknown.

19. **`0x4121`'s two macro types.** Both references also just call them "type".

20. **`0x4820`'s mailbox selectors** `0x0f` and `0x10` are reference names. We still never send a
    `0x4822`; Nomad's clan-application entry layout is transcribed in the `0x4820` section as
    reference material, but no *mail* entry layout exists anywhere — Nomad never sends one either.

21. **`0x4300`'s filter type is read and discarded.** Clan rooms are distinguished by a name prefix
    in the original; unmodelled here.

22. **The empty replies `0x4311` and `0x4151` are sufficient but unverified.** Both references
    send nothing and the client proceeds, so nothing more is required — but each dispatches to a
    real handler (`0xD43550`, `0xD3943C`) rather than a no-op, so whether the original server sent
    a payload there is unknown. The dispatcher is a comparison chain at `0xD388A8`–`0xD38948`,
    which is the place to start if this ever matters.

23. **`0x4316` does not read its request payload at all.** The settings the player configured
    arrive on `0x4310` instead, which is parsed into the game row (`applyHostSettings`) and stored
    raw per character since 2026-07-22. Confirmed reachable: a game is created and the host
    enters it.

23. **`0x3103` clamps an out-of-range index to the first character and `0x3105` to the last.** The
    asymmetry is claimed to match the original. Unverified, and unreachable in practice since the
    client bounds-checks the index itself.

24. **`0x200a`'s 886-byte body field.** Chosen to make the payload exactly 1023 bytes. No client has
    been observed rendering a news item, so the whole news path is unverified.

25. **`0x0005` ping replies with an empty payload rather than echoing the request.** Reference
    behaviour; never observed from our client.
