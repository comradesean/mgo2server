# Protocol reference

What this server actually sends and parses, command by command, byte by byte.

This is a working reference for someone with a live client in front of them, so it documents **our
code** — `src/main/java/nomad/game/**` — and not what the protocol "should" be. Where a field's
meaning comes from somewhere else it says so, and where nothing is known it says that instead. A
confident-sounding guess in a file like this is worse than a blank, because the next person spends
a day proving it wrong.

Three levels of confidence are used throughout:

- **Confirmed** — verified against the real client (`BLUS30109` on RPCS3), and `dev/OBSERVED.md`
  records how.
- **Ours** — this is what our code does. It may still be wrong for the client; it is simply what
  goes on the wire today.
- **Reference** — the meaning comes from `upstream/echo-upstream` (Java, `@Command(0x....)`),
  `upstream/mgo2-server-upstream` (TypeScript, `@GameCommandHandler(0x....)`) or the Nomad
  upstreams. **Unverified against our client** unless separately marked.

Companion documents: **`dev/OBSERVED.md`** records what was observed and verified against the real
client, including the hypotheses that turned out to be wrong. **`dev/STUN.md`** covers the UDP port
check, which is not part of this protocol at all — different transport, different thread, no shared
framing. **`dev/CRYPTO.md`** is the reference for every cipher, key and hash, and where each is
applied; the transport section below summarises what this protocol uses.

That last distinction matters more than it looks. The references are not specifications: they were
written for different client builds and have been wrong for `BLUS30109` five separate times (the
policy path, the gate hostname, the gate port, the version-check byte, and the login perks field —
see `dev/OBSERVED.md`, "How this file gets things wrong"). The perks field is the instructive one,
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
passphrase. Three schedules ship in
`src/main/resources/crypto/`: `packet.key` (payloads), `auth.key` (unused by the current session
code, retained), and `session.key` (the check-session transform). Payloads are zero-padded up to
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

Confirmed: the real client sends this after the gate's lobby-list exchange (`dev/OBSERVED.md`,
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
| `0x29` | 2 | u16 | player count — **always 0**; we do not track occupancy |
| `0x2b` | 2 | u16 | lobby id |
| `0x2d` | 1 | u8 | restriction bits: `0b1` beginners only, `0b1000` expansion required, `0b10000` no headshots |

**Confirmed end to end.** `dev/OBSERVED.md` records this list being read back out of the client's
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

**Flagged: the reply shape is inferred, not read.** `dev/OBSERVED.md` lists `0x3108` among the
replies parsed as a single s32, on the strength of its sibling result packets (`0x3004`, `0x3102`,
`0x3104`, `0x3106`) all being parsed that way, and of the request-status arm marking id `0x12`
complete. The `0x3108` parser itself was not read out of the binary. It works in practice.

---

# GAME lobby

`0x3003` is registered here too — see the ACCOUNT section; the only difference is that the claimed
id is a character id and the selection is not cleared.

## `0x4100` — character connect

**Client → server**, `CharacterConnectController.connect`. Empty payload.

This is the burst: one request, ten packets back. Sent in this order:

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

## `0x4316` — create game

**Client → server**, `HostGameController.createGame`. Request payload is **not read at all**.

Settings come from the character's stored host-settings row (`getOrCreateHostSettings`), which is
materialised with defaults named after the host. The client can also push settings with `0x4310`
and read them back with `0x4304`; we handle neither, so anything the player configured on the host
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

**Flagged: parsed but not persisted.** The values are logged and thrown away. Nothing serves them
to another player until hosting and joining are wired up, and columns nothing reads would only be
a guess at what that path needs. Anyone implementing peer connection will have to add storage here.

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
ordinary case. **`0x4822`'s payload layout is therefore entirely undocumented here** — we have
never written one.

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

Known-sendable, currently unanswered:

| command | reference name | notes |
| --- | --- | --- |
| `0x3040` | (account) | Sender confirmed in the binary at `0xD37B00`, one u8 slot; reply `0x3041` = s32, then if 0 a u32 and 16 bytes. **No reference implementation answers it** — Nomad v1, v2, mgo2-server and ours all lack a handler. SaveMGO ran without it, so the normal disc flow presumably never sends it |
| `0x4102` | get personal stats | |
| `0x4110` | update gameplay options | The write-back half of `0x4120` |
| `0x4112` | update UI settings | |
| `0x4114` | update chat macros | The write-back half of `0x4121` |
| `0x4128` | get post-game info | |
| `0x4141` | update skill sets | The write-back half of `0x4140` |
| `0x4143` | update gear sets | The write-back half of `0x4142` |
| `0x4150` | lobby disconnect | echo answers with a bare response packet |
| `0x4220` | get character card | |
| `0x4304` | get host settings | |
| `0x4310` | check host settings | Payload arrives **encrypted** |
| `0x4312` | get game details | |
| `0x4320` | join game | Payload arrives **encrypted** |
| `0x4340`–`0x4398` | in-game player and round events | |
| `0x43c0` | (reference name varies) | Payload arrives **encrypted** |
| `0x43d0` | training connect | |
| `0x4400` | send chat | |
| `0x4500`/`0x4510`/`0x4580` | friends and blocked list | Would also fill the empty regions in `0x4101` |
| `0x4600` | search player | |
| `0x4680` | match history | |
| `0x4800`/`0x4840`/`0x4860` | send / read / file a message | The rest of the mailbox |
| `0x4b00`–`0x4b90` | clans, ~30 commands | Nothing clan-related exists here |

Every name in that table is a **reference name** from echo or mgo2-server and is unverified for our
client. Their payload layouts are deliberately not reproduced here: writing down a layout we have
never parsed would create exactly the kind of plausible-looking wrong documentation this file
exists to avoid.

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

20. **`0x4820`'s mailbox selectors** `0x0f` and `0x10` are reference names. And since we have never
    sent a `0x4822`, the message payload layout is entirely undocumented.

21. **`0x4300`'s filter type is read and discarded.** Clan rooms are distinguished by a name prefix
    in the original; unmodelled here.

22. **`0x4316` does not read its request payload at all**, and we handle neither `0x4310` nor
    `0x4304`, so host settings the player configures never reach the server. Untested — nothing has
    reached the host screen.

23. **`0x3103` clamps an out-of-range index to the first character and `0x3105` to the last.** The
    asymmetry is claimed to match the original. Unverified, and unreachable in practice since the
    client bounds-checks the index itself.

24. **`0x200a`'s 886-byte body field.** Chosen to make the payload exactly 1023 bytes. No client has
    been observed rendering a news item, so the whole news path is unverified.

25. **`0x0005` ping replies with an empty payload rather than echoing the request.** Reference
    behaviour; never observed from our client.
