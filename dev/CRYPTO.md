# Cryptography reference

Every cipher, key and hash this server uses, and where each is applied.

**None of it is a security boundary.** The keys ship on the game disc and are reproduced here so
the server can talk to an unmodified client. Treat all of it as an encoding whose purpose is
compatibility, not protection. The one place that genuinely matters — TLS to the console — is
noted as such.

Companion documents: `dev/PROTOCOL.md` for the TCP command protocol, `dev/STUN.md` for the UDP port
check (which uses none of this).

## Where each method is used

| method | applies to | implementation |
| --- | --- | --- |
| Whole-packet XOR | every game packet, header included | `GameCrypto.XOR_KEY` |
| HMAC-MD5 | every game packet header | `GameCrypto.checksum` |
| Blowfish (`packet.key`) | payloads of six inbound commands, one outbound | `GameCrypto.packet()` |
| Blowfish (`session.key`) + custom chaining | the check-session field | `SessionField` |
| Blowfish (`auth.key`) | **nothing — dead** | `GameCrypto.auth()` |
| MD5 | account passwords, hashed by the client | `AccountService.findByCredentials` |
| TLS | the HTTPS login and version-check endpoints | `probe-https` container |

The port check (STUN) uses none of these. Its packets are plaintext.

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

### The three schedules

| file | bytes | used for |
| --- | --- | --- |
| `packet.key` | 4168 | payload encryption for the command sets below |
| `session.key` | 4168 | the check-session field transform |
| `auth.key` | 4168 | nothing in production — see below |

`auth.key` was the schedule behind the old `SessionIds` class, which modelled the check-session
field as an invertible transform. That model was wrong and the class is gone. The schedule is still
loaded by `GameCrypto.auth()` and still referenced by `BlowfishTest`, but **no production code path
uses it**. It is retained only because it is a genuine artefact extracted from the game; it can be
deleted whenever the tests are repointed.

### Which payloads are encrypted

```
inbound  (client -> server):  0x3003, 0x4310, 0x4320, 0x43c0, 0x4700, 0x4990
outbound (server -> client):  0x4305
```

Of the inbound set we currently handle `0x3003`, `0x4700` and `0x4990`. The outbound set contains
one command that **nothing in this server ever sends** — it is carried for parity with the
reference implementations and is untested.

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

The context is mode 6 of a keyed table inside the client, itself produced by running this same
transform over a 64-byte blob with a master context. That blob is zero in the game image and is
materialised at runtime, so it was read out of a live client; the resulting key schedule ships as
`session.key` and the IV is a constant in `SessionField`.

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

The PS3's TLS stack is from 2008, so the server must also permit TLS 1.0 and legacy ciphers.
`probe-https` terminates TLS and proxies through to the web service; `NOMAD_TLS_CERT` selects the
chain, which allows swapping in a deliberately expired one — the client reports that as `070B`
rather than `090B`, which is how the certificate branch was originally identified.

## Provenance

`packet.key` and `auth.key` were extracted from the game. `session.key` was derived from a context
read out of a live client, as described above. The XOR key and the HMAC key are constants in the
game binary. Nothing here was invented, and nothing here should be regenerated — a changed key
means an unmodified client can no longer talk to the server.
