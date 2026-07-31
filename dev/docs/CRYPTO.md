# Cryptography reference

Every cipher, key and hash this server uses, and where each is applied.

**None of it is a security boundary.** The keys ship on the game disc and are reproduced here so
the server can talk to an unmodified client. Treat all of it as an encoding whose purpose is
compatibility, not protection. The one place that genuinely matters — TLS to the console — is
noted as such.

Companion documents: `dev/docs/PROTOCOL.md` for the TCP command protocol, `dev/docs/STUN.md` for the UDP port
check (which uses none of this).

## Where each method is used

| method | applies to | implementation |
| --- | --- | --- |
| Whole-packet XOR | every game packet, header included | `GameCrypto.XOR_KEY` |
| HMAC-MD5 | every game packet header | `GameCrypto.checksum` |
| Blowfish (`packet.key`) | payloads of six inbound commands, one outbound | `GameCrypto.packet()` |
| Blowfish (`session.key`) + custom chaining | the check-session field | `SessionField` |
| MD5 | account passwords, hashed by the client | `AccountService.findByCredentials` |
| TLS | the HTTPS login and version-check endpoints | `probe-https` container |
| Rolling 8-byte XOR | the body of every ranking HTTP reply | `RankingScramble` |
| Path-keyed asset cipher | disc stage data, HDD saves, `d/testhk` | `dev/tools/solideye/Solideye.exe` |

The port check (STUN) uses none of these. Its packets are plaintext.

## The path-keyed asset cipher

**This one is not ours and never touches the wire** — it is how the game encrypts its own files on
disc and on the HDD. It matters here because the server-address override, `d/testhk`, goes through
it; see [HOSTS.md](HOSTS.md) and [ASSETS.md](ASSETS.md).

**The key is the directory component of the path the game opens** — `stage/lobby`, `online`,
`clanemblem`, `d`. Established 2026-07-29 from the opener at `0x2EE48`, which calls
`strrchr(path, '/')` and truncates there.

Key derivation, as read from the ELF and corroborated independently by Solideye's own source
(MIT, `Jayveer/Solideye`) — two sources agreeing on the same shape:

1. A 64-byte key blob is fetched from the crypto object (selector 3). Solideye builds the same
   blob by Blowfish-decrypting a stored table under a base key and XOR-chaining the result.
2. `digest = MD5(directory string)`, 16 bytes.
3. `key[i] ^= digest[i & 15]` for `i` in 0..63 — the loop is at `0x2EF70`–`0x2EF90`.
4. Two 64-byte salts come off that key by XOR with `0x36` and `0x5C`, the HMAC inner/outer pads.

The stream itself is an 8-byte-block XOR chain with ciphertext feedback:

```
plain[i] = cipher[i] ^ K[i] ^ (cipher[i-8] if i >= 8 else 0)
```

Encrypt and decrypt run the identical XOR; the only difference is which value feeds the chain
(ciphertext when encoding, plaintext when decoding). That feedback is why a 4-byte plaintext edit
moves ~18 kB of ciphertext, and why the transform is nonetheless perfectly reversible.

Container: the payload is PKCS#7-padded to 8 bytes and a 16-byte digest of the form
`MD5(key64 || MD5(ciphertext))` is appended — **24 bytes of overhead**, which is exactly the
1374092 → 1374068 seen decrypting `scenerio.gcx` and the 426 → 450 seen encrypting a `testhk`.

**Verified round-trip:** `Solideye -dec` then `-enc` on `o/stage/lobby/scenerio.gcx` with key
`stage/lobby` reproduces the original **bit for bit**, header included (md5
`532af9a1596a5f9a6a0517a62bbf3803`).

Three things worth knowing before using it:

- **Encryption is opt-in per call site.** `helpdisp.sav` sits with four encrypted saves and is
  written in the clear. The caller sets bit 31 of the open mode; `0x280F0` diverts to `0x2EE48`
  and tags the handle `0x08000000` so `0x26ED8` / `0x258E0` use the decrypting reader and closer.
- **Solideye silently drops the last 24 bytes of every file it writes out**, so the tail has to be
  recovered with the chain above if you need it.
- **Solideye's cipher has not been compared byte for byte with the game's.** What is established is
  that the shapes match and that `stage/lobby` works in the field. If a new key ever fails, that
  gap is the first place to look.

## The ranking scramble

The Rankings screens fetch over HTTP, not over the lobby protocol, and their replies carry their
own obfuscation — unrelated to the packet XOR above, and applied to a plain HTTP body.

Key `8b 75 2c 90 3a 5e 4d f1`, read from the immediates the client stores inline at `0xBC2D80`.
Byte `i` is XORed with `key[((i / 4) % 5) + (i % 4)]`: the offset walks a four-byte block, the
block index advances every four bytes and wraps at five, so the keystream repeats every twenty
bytes and touches all eight key bytes. The client applies it at `0xBC2D78` before reading a single
field, so a **cleartext reply is not rejected — it is silently misparsed**, and every column shows
garbage with no error.

XOR is its own inverse, so the server scrambles with the same routine. [ELF] throughout; no
capture of a genuine Konami ranking response exists to corroborate it.

## Whole-packet XOR

The finished packet — header included — is XORed with the repeating four-byte key
`5a 70 85 af`. The decoder un-XORs the command and length words first to size the frame, then
un-XORs the whole frame once it has it.

This is obfuscation, not encryption: a fixed, published key applied by XOR.

## HMAC-MD5 checksum

Header bytes `0x08`–`0x17` carry an HMAC-MD5 over the first **8** header bytes (command, payload
length, sequence — not the checksum field itself) followed by the payload.

The key is 16 bytes which happen to be ASCII: **`Z7/biJ46TzGF-8yx`**.

Two details that are easy to get wrong:

- It covers the payload **as it appears on the wire** — ciphertext for encrypted commands, not
  plaintext. Outbound that is the padded ciphertext; inbound it is the ciphertext truncated to the
  declared length, with decryption happening afterwards.
- Comparison is constant-time (`MessageDigest.isEqual`). A bad checksum is fatal to the frame.

The checksum, not the sequence number, is what authenticates a packet — sequence mismatches are
logged and tolerated.

## Blowfish

One primitive underlies all three key schedules.

It is **standard 16-round Blowfish**. The loop in `Blowfish.java` reads `ROUNDS = 8`, which invites
misreading, but each iteration applies the round function twice. This was settled empirically: a
textbook implementation fed our shipped schedule reproduces the class's output exactly, and also
reproduced a session field captured from a real client. "It's a Konami variant" is folklore.

The only real deviation from textbook use is that keys ship **pre-expanded**. Each `.key` resource
is a 4168-byte key schedule — 18 P-array entries then four 256-entry S-boxes, all big-endian —
rather than a passphrase to be run through key setup. Block size is 8 bytes; payloads are
zero-padded up to a block boundary before encryption and the padding dropped after.

### The two schedules

| file | bytes | used for |
| --- | --- | --- |
| `packet.key` | 4168 | payload encryption for the command sets below |
| `session.key` | 4168 | the check-session field transform |

A third schedule, `auth.key`, was **removed**. It backed the old `SessionIds` class, which modelled
the check-session field as an invertible transform — a model that turned out to be wrong and whose
class has been deleted. Nothing in production ever loaded it, nothing verified it was the game's
key, and it was inherited rather than derived here.

It is recoverable if ever needed: byte-identical copies live in mgo2-server at
`src/core/constants/crypto-keys-constants.ts` (`BLOWFISH_KEY_AUTH`) and in Nomad at
`src/main/java/savemgo/nomad/crypto/Constants.java` — both on GitHub, not vendored here. Both were
checked against our copy before deletion and matched exactly, all 4168 bytes.

### Which payloads are encrypted

```
inbound  (client -> server):  0x3003, 0x4310, 0x4320, 0x43c0, 0x4700, 0x4990
outbound (server -> client):  0x4305
```

**Both sets come from the reference servers, not the binary.** The client decides per call site
rather than consulting a table, so there is nothing to read off — searching the image for these ids
as a contiguous table finds nothing, and they do not cluster.

Of the inbound set we handle `0x3003`, `0x4700` and `0x4990`, and only `0x3003` is confirmed: its
payload decrypts to a correct account id, which neither a wrong list nor a wrong key could produce.

The outbound set is **entirely unverified**. Nothing here sends `0x4305`, so this cipher has never
encrypted a byte the client has seen, and whether the client expects it encrypted is unknown. The
encrypt direction of `packet.key` is therefore exercised only by unit vectors, never in production.

A request being encrypted says nothing about its reply. `0x3003` arrives encrypted and `0x3004`
goes back in the clear; likewise `0x4700`/`0x4701` and `0x4990`/`0x4991`.

## The check-session field

The one construction here that is not a stock primitive, and the one most likely to be
misunderstood, because it is neither ECB nor CBC.

The client never returns its login token. On receiving the login reply it keeps the token as its
**sixteen ASCII characters**, derives a sixteen-byte value from them, and presents *that* on
check-session. The server therefore applies the same forward transform to the token it issued and
compares — nothing is inverted.

```
context = 8-byte IV  ||  56-byte key        (56 is Blowfish's maximum key length)

C[i] = decrypt(P[i]) XOR P[i-1]             P[-1] = IV
```

Two things make this unguessable from captures alone: the block is **decrypted** rather than
encrypted, and the XOR is against the **previous plaintext** block rather than the previous
ciphertext.

**Not actually a separate mode.** Confirmed 2026-07-31 while tracing the auto-patch `.inf` cipher
(`ADDRESSES.md` §12): `0xD645C8`, the one-shot helper this scheme uses, is textbook CBC decrypt
(`P[i] = D(C[i]) XOR C[i-1]`) — the *same* routine `.inf`'s Blowfish-CBC stream (`0xD66CF0`) is
built on. `C[i] = decrypt(P[i]) XOR P[i-1]` here is just that decrypt primitive run with the roles
of plaintext and ciphertext swapped, not a second chaining mode implemented anywhere in the binary.

The IV is `b0 78 1d 53 65 e3 91 0e`, a constant in `SessionField`. The 56-byte key is not shipped
directly — `crypto/session.key` is the **4168-byte expanded schedule** built from it, which is what
the cipher actually consumes.

### Reproducing `session.key` from a live client

The context is mode 6 of a keyed table inside the client, produced by running this same transform
over a 64-byte blob with a master context. The blob is zero in the image and written at runtime, so
this is the one artefact a disc cannot give you. The full recipe, since "it was read out of a live
client" is not a procedure:

1. **Boot the game to the main menu** so the crypto service has initialised. Earlier is unreliable;
   the blob is written during startup.
2. **Dump 64 bytes at `0x10985F0`** — RPCS3's *Tools → Memory Viewer*. This is mode 6's key blob,
   encrypted. All zeroes means you dumped too early.
3. **Read 64 bytes at `0xE26DA8`** — the master context. This one is static, so
   `dev/tools/extract_keys.py` gets it from the disc; no dump needed.
4. **Decrypt the blob with the master context**, using the transform above: split the master into
   an 8-byte IV and a 56-byte Blowfish key, schedule the key, then run
   `C[i] = decrypt(P[i]) XOR P[i-1]` over the 64-byte blob. The result is the **derived context**.
5. **Split the derived context**: first 8 bytes are the IV (`b0 78 1d 53 65 e3 91 0e`), the
   remaining 56 are the Blowfish key.
6. **Expand those 56 bytes** through the standard Blowfish key schedule, seeded from the pi table at
   `0xE25AEC`, to get the 4168-byte `crypto/session.key`.

Sanity check the result rather than trusting it: `SessionField.of("1888e089ebe181fd")` must equal
`a5a0dd9199494cf00e06ae9dc4655563`. That pair was captured from a real client, and `SessionFieldTest`
asserts it.

Worth noting the object at `0x1698DA8` is worth dumping at the same time — `+4` is the master
context pointer and `+0x34` mode 6's key pointer, which is how those two addresses were found in
the first place, and how you would find them again on a different build.

Verified against two independent captures from a real client. `SessionFieldTest` pins it to those
bytes rather than round-tripping against ourselves, which would prove nothing.

Traced in `MGO2.elf`: the login parser calls the crypto service at `0xBB1800` with mode 6 and
stores the result where the `0x3003` builder ships it; the service vtable is at `0xfbbd00`, where
`+0x8` is the cipher and `+0xC` the wrapper.

## Passwords

The client MD5-hashes the password before sending it, so the login endpoint receives
`passwd=<md5 hex>` and that hash is what is stored and compared.

This is the game's scheme, not a choice available to us — the client cannot be made to send
anything else. MD5 is not acceptable for password storage in any other context, and no salting or
stretching is possible on top of it here without breaking the login. Accounts on this server should
be treated as disposable and their passwords never reused elsewhere.

## TLS

The console posts login and version-check requests over HTTPS, and **this is the one place the
cryptography is real** rather than obfuscation.

The PS3 validates the server certificate against its own store at `dev_flash/data/cert/CA*.cer` and
drops the connection before sending a request if the chain does not verify — which looks exactly
like the server never being contacted. A self-signed certificate is not enough.

For RPCS3 this is solvable without patching the client: generate a CA, sign the server certificate
with it, and write the CA over one of the `CAxx.cer` files. The client was observed reading
`CA29`–`CA31`; installing at `CA30.cer` works.

The PS3's TLS stack is from 2008, so the server must also permit TLS 1.0 and legacy ciphers — and
on a modern OpenSSL that is not the default. Both knobs are required; without them the handshake is
refused before any request arrives, which looks **exactly** like a missing certificate and reports
the same `090B`. In Python:

```python
tls_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls_ctx.load_cert_chain(cert, key)
tls_ctx.minimum_version = ssl.TLSVersion.TLSv1   # modern default is TLS 1.2
tls_ctx.set_ciphers("ALL:@SECLEVEL=0")           # SECLEVEL 0 re-enables 2008-era suites
```

`SECLEVEL=0` is the one people miss: modern distributions compile OpenSSL with a security level
that removes these ciphers entirely, so `ALL` alone still offers the console nothing it can use.
`probe-https` terminates TLS and proxies through to the web service; `MGO2SERVER_TLS_CERT` selects the
chain, which allows swapping in a deliberately expired one — the client reports that as `070B`
rather than `090B`, which is how the certificate branch was originally identified.

## Offsets in `MGO2.elf`

Every constant that lives in the binary, with the address to read it from. `dev/tools/extract_keys.py`
pulls these from your own disc:

| vaddr | size | what |
| --- | --- | --- |
| `0xE25A18` | 56 | **raw packet key.** Expand through the standard Blowfish schedule to get `packet.key`. |
| `0xE25AD0` | 4 | whole-packet XOR key |
| `0xE25AD8` | 16 | HMAC-MD5 key (ASCII) |
| `0xE25AEC` | 4168 | Blowfish pi-init table |
| `0xE26DA8` | 64 | session master context: 8-byte IV then a 56-byte key |

Check your extraction rather than trusting it. The raw packet key at `0xE25A18` begins
`27 50 1f d0 4e 6b 82 c8`, and expanding all 56 bytes yields a schedule whose first P entries are
`b08e376f 3d82d63e 18ec1f44 673a86f5`. If those do not match, the expansion is wrong — most likely
a byte-order slip, since every step is silent on failure.

`vaddr = file offset + 0x10000`.

Runtime-only addresses, for the parts a disc cannot give you:

| vaddr | what |
| --- | --- |
| `0x1698DA8` | the crypto singleton; `+4` is the master-context pointer, `+0x34` mode 6's key pointer |
| `0xFFE6DC` | static global holding that singleton pointer |
| `0xfbbd00` | its vtable — `+0x8` the cipher, `+0xC` the wrapper |
| `0x10985F0` | mode 6's 64-byte key blob. **Zero on disc**, materialised at runtime — this is the one that needs a memory dump. |
| `0xBB1800` | the login parser's call into the crypto service, mode 6 |
| `0xD35704` | where the packet key pointer is loaded, `*(*(TOC-0x66d8) - 0x7fe8)` |

## Provenance

Worth stating precisely, because the three schedules have very different pedigrees and only one of
them is verified by anything.

**None of the three appears in `MGO2.elf`.** That is expected rather than suspicious: the standard
Blowfish pi-init table *is* in the binary (at `0xE25AEC`), so the game performs key expansion at
runtime from a key plus that table. An already-expanded schedule was never going to be stored in
the image, and searching for one there proves nothing either way.

| schedule | where it came from | how it is validated |
| --- | --- | --- |
| `packet.key` | savemgo Nomad's `Constants.java` | **In production.** Real client payloads decrypt correctly and the client accepts ours. Wrong bytes here would break every encrypted command. |
| `session.key` | derived here, from a context read out of a live client | **Pinned to two independent captures** in `SessionFieldTest`. |

`packet.key` arrived inherited from savemgo Nomad's `Constants.java`, but it no longer rests on
that: the game's own 56-byte key is at `0xE25A18`, and expanding it reproduces the shipped schedule
exactly. It is now a disc-derived constant that happens to agree with the upstreams, rather than an
upstream constant we hoped was right.

`session.key` remains the one artefact a disc cannot produce, because mode 6's key blob is zeroed
in the image and written at runtime. Everything around it is documented — the master context is at
`0xE26DA8`, the blob at `0x10985F0` — so a memory dump reproduces it, but nothing static will.

The XOR key and the HMAC key are constants in the game binary and are exercised by every packet.

Nothing here should be regenerated: a changed key means an unmodified client can no longer talk to
the server.
