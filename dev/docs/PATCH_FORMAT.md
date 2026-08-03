# The MGO2 auto-patch format — a build/extract specification

This describes the on-disk and on-the-wire format of the Metal Gear Online 2 in-game patch
mechanism, as implemented by the retail MGS4 disc executable (`MGO2.elf`, BLUS30109), completely
enough to **construct a patch from scratch and extract one back again** without reference to any
other code in this repository.

Everything here was derived by disassembling the client and then confirmed by serving real rounds
to a real client. Where something is read from the binary but has not been exercised live, it says
so.

**This document has been tested as a specification, not just written as one.** A ~90-line
implementation was written from it alone, importing nothing from this project's tooling; it
round-trips a patch it builds itself (including the placement rules of
[§6](#6-placement-the-name-decides-where-a-file-lands)) and independently decodes the `.inf`s and
archives a live server is serving, reproducing all 660 scan-A entries and matching the archive
prefix byte for byte. If something below is ambiguous enough to break that, it is a bug in this
document.

**Scope note.** One value in here is *not* universal: the HMAC key the client demands for the
outer integrity tag comes from a runtime key provider, and on a stock retail executable that key
is Konami's and unknown. See [§3.3](#33-the-two-server-supplied-keys). Every other rule — layouts,
ordering, the cipher chain, the name grammar — is a property of the format itself.

---

## 1. Overview

A patch is delivered in three tiers of file:

```
checkver.html      the POST reply that says "an update exists", carries the base URLs,
                   the version range, and the two encrypted key blobs
   |
   +-- <record>inf     one per announced record: a manifest listing what to download
   |                   and what to extract
   |
   +-- <record>        one per announced record: the archive itself, containing many files
```

Two ideas do most of the work and are easy to conflate:

- **Scan B** — the list of files to **download**. In practice one entry per record: the archive.
- **Scan A** — the list of files to **extract** from that archive, in order.

Both live inside the same `.inf`. The real 1.36 patch has 660 files in scan A but only two
downloadable archives, which is what the split is for.

The archive and the `.inf` share an identical **crypto envelope** ([§3](#3-the-crypto-envelope))
and an identical **prefix** ([§5.1](#51-the-prefix-shared-with-the-inf)). Get either wrong and the
client fails silently — see [§9](#9-failure-modes-all-of-them-quiet).

---

## 2. Transport

The client POSTs to `<host>/<region>/mgo2/patch/checkver.html` with a body of `%d,%s,%u`:
packed client version, disc id (`"BLUS30109"`), and a nonce. It reads a **binary** reply from that
`.html` path.

**Version packing**, used in the POST body, in the reply's TO field, and in the staging directory
name: `major << 24 | minor << 16 | revision`. So 1.0.0 is `0x01000000` and 1.36.0 is `0x01240000`
— which is why the client's own staging directory for that upgrade is named `1000000_1240000`
(the format string is `%x_%x`).

> **The client never checks whether it is already up to date — the server must.** The only version
> test in the client compares its current version against each record's **FROM** version, and it
> passes when the client is **at or above** it. Nothing anywhere compares against the TO version.
> Serve an unconditional "update available" and an already-patched client will be offered the same
> upgrade forever, in a loop, having installed it perfectly.
>
> A correct server parses the POSTed packed version and answers with the single byte `00` when it
> is greater than or equal to the version the reply would otherwise offer.

Once a record is accepted, the client builds three more URLs, where `%s` is *string A* from the
reply and `%u.%u.%u` is the TO version:

| what | format | example |
| --- | --- | --- |
| release note | `%s/%u.%u.%u/relnote.txt` | `…/patch/1.36.0/relnote.txt` |
| manifest | `%s/%u.%u.%u/%sinf` | `…/patch/1.36.0/BLUS30109.1.0.0to1.36.0inf` |
| archive | `%s/%u.%u.%u/%s` | `…/patch/1.36.0/BLUS30109.1.0.0to1.36.0` |

**There is no dot before `inf`.** The format string is literally `%sinf`, and the record text must
not supply a trailing dot either — the real filenames are `BLUS30109.1.0.0to1.36.0inf` and
`1.0.0to1.36.0inf`. The `.torrent` URL in the same directory settles it independently: it is
record text + `.torrent`, so a trailing dot would have produced `…1.36.0..torrent`.

The final `%s` of the archive URL is taken from the **scan-B entry name**, so the archive file is
named after the record text itself.

### 2.1 Server requirements

- **Answer `HEAD`**, not just `GET`. The client treats any non-200 as failure, and a server that
  returns 501 for `HEAD` fails invisibly.
- **Honour `Range: bytes=N-` with a 206.** The client sends it to resume. A server that ignores
  the header and replies 200-with-the-whole-body will have its data written at the resume offset,
  corrupting the staged archive — which surfaces much later as an integrity failure.
- **Do not serve a fallback page for unknown paths.** A 200 carrying HTML where ciphertext is
  expected is indistinguishable, server-side, from a correct response.
- Archives are large (the real generic one is ~1.9 GB); stream rather than buffering.

---

## 3. The crypto envelope

Identical for the `.inf` and for every archive. Reading direction (what the client does):

```
served bytes
   ->  verify HMAC-MD5 trailer     last 16 bytes, key = slot 8
   ->  Blowfish-CBC decrypt        key = slot 7, split 8 + 56
   ->  strip PKCS#7                pad byte must be 1..8
   ->  zlib inflate                RFC1950 (zlib wrapper, windowBits 15)
   ->  the plaintext of §4 / §5
```

Building is that run backwards:

```
plaintext
   ->  zlib deflate  (RFC1950 — NOT raw deflate, NOT gzip)
   ->  PKCS#7 pad to a multiple of 8
   ->  Blowfish-CBC encrypt
   ->  append HMAC-MD5 of the ciphertext
```

### 3.1 Order matters and is not negotiable

The integrity tag covers the **ciphertext**, not the plaintext, and is appended raw — no header,
no magic, no length field. The file is exactly `ciphertext || tag16`.

### 3.2 The details that bite

- **zlib is mandatory and is the stage most likely to be missed.** It is a genuine RFC1950
  stream: a 2-byte header and an adler32 trailer. Raw deflate fails. This layer is invisible in
  the failure mode — see [§9](#9-failure-modes-all-of-them-quiet).
- **PKCS#7 with pad values 1..8, and 0 is rejected.** A plaintext already a multiple of 8 still
  needs a **full 8-byte block of `08`**.
- **Blowfish-CBC key material is a 64-byte blob split 8 + 56**: bytes `[0:8]` are the initial CBC
  register (the IV), bytes `[8:64]` are an ordinary 56-byte Blowfish key. A stock Blowfish-CBC
  implementation given that key and IV reproduces this exactly.
- **Both HMAC keys are exactly 64 bytes**, the MD5 block size, so a stock HMAC uses them verbatim
  with no pre-hashing. A shorter key zero-padded to 64 is equivalent.

### 3.3 The two server-supplied keys

The reply carries two 64-byte blobs which the client files into key slots 7 and 8:

- **slot 7** — the Blowfish-CBC key blob (envelope stage 2), for both the `.inf` and the archives.
- **slot 8** — the HMAC-MD5 key for the envelope's outer tag.

**They travel encrypted.** The client's key-fetch is a decrypt, not a copy: whatever the reply
carries is Blowfish-CBC-decrypted under a master key baked into the executable before use. So to
make the *effective* key be `K`, the reply must carry `BlowfishCBC_Encrypt(K)` under that master
key. Sending `K` raw makes the client key its crypto with `D(K)` — deterministic garbage.

The master key blob, 64 bytes, is an executable constant (same 8 + 56 split):

```
74f66dc28598f5d1                                            <- IV
72ac2dcace5544d665f11d05bea20568e76c529deb35890ec332ff24
fe5d9c3fb34189cf47055b26f9e4cc639a46b5465404df41e65b8e4e    <- 56-byte Blowfish key
```

> **The one non-portable value.** On a *stock* retail executable the key provider returns Konami's
> own material and the slot contents are not a free choice. The client this format was reverse
> engineered against runs a modified executable whose provider is stubbed, returning a chosen
> 16-byte ASCII string zero-padded to 64. Everything else in this document is a property of the
> format; this is a property of the executable you are talking to. If you are targeting a stock
> client you must recover its real slot-8 key by other means.

### 3.4 The one key you do not choose

The `.inf`'s **inner** tag ([§4.3](#43-the-inner-tag)) is keyed by a constant resident in the
executable, not supplied by the server:

```
9357a9dfb8eb8d03b843cd025f2a30ce   (16 bytes, zero-padded to the 64-byte HMAC block)
```

The same 16 bytes are reused elsewhere in the patch subsystem as a digest key.

---

## 4. The `.inf` plaintext

After the envelope of §3 is stripped, an `.inf` decodes to:

```
offset 0    header          12 bytes
offset 12   scan A          variable — the extract list
offset L-16 inner tag       16 bytes   (L = hdr[4])
offset L    scan B          variable — the download list
end         trailing slack  >= 16 bytes
```

### 4.1 Header (12 bytes, big-endian)

| offset | size | meaning |
| --- | --- | --- |
| 0 | 4 | unused — provably never read back. Use `0`. |
| 4 | 4 | **`L`**: the length of `header + scanA + innerTag`, i.e. where scan B starts |
| 8 | 4 | unused — same. Use `0`. |

There is no magic number and no version field. `L = 12 + len(scanA) + 16`.

### 4.2 Scan A — the extract list (stride: NUL + 6)

Occupies `[12, L-16)`. Repeated, no padding, no count field:

```
<name bytes> 00 <u32 size, big-endian> <u8 flags>
```

- `size` is the **extracted** length of that file — its real byte count, not a compressed size.
- Entries are read in order, and that order must match the order the members are concatenated in
  the archive ([§5.2](#52-the-members)).
- `name` decides **where the file lands** — see [§6](#6-placement-the-name-decides-where-a-file-lands).

**An empty scan A is the single most expensive mistake available.** With `L = 28` the list is
empty, the archive downloads, the envelope verifies, no error is raised — and nothing is ever
extracted, because the installer's loop bound equals its cursor and the whole loop is skipped.

#### Flags byte

| bit | meaning |
| --- | --- |
| `0x0F` | ordering-pass index, consumed only by the 16-pass finalize loop (see `0x20`) |
| `0x10` | output stream selector |
| `0x20` | destination: **clear** = install directly; **set** = write to a staging directory and enable the finalize loop |

`0x00` — direct install, no finalize pass — is the shortest path to bytes on disk and is what the
rounds described here use. The `0x20` path has not been exercised live.

### 4.3 The inner tag

16 bytes at `[L-16, L)`: `HMAC-MD5(elf_key, plaintext[0 : L-16])` using the key from
[§3.4](#34-the-one-key-you-do-not-choose) — i.e. it covers the header and scan A. This is
verification only; nothing is transformed by it.

### 4.4 Scan B — the download list (stride: NUL + 5)

Starts at offset `L`. **Note the different stride** — there is no flags byte here:

```
<name bytes> 00 <u32 size, big-endian>
```

- `size` is the size of the file **as served**, i.e. the length of the complete envelope
  (`ciphertext + 16`). Because deflate's output length is not a function of its input length,
  this cannot be computed ahead of time — **build the archive first, measure it, then declare
  that number.**
- `name` is the archive's filename, which is also the record text.
- **At most 31 entries**, a checked bound.

The two scans cannot be the same table: their strides differ by one byte, so a list parsed
correctly at stride 6 desynchronises at stride 5 and vice versa.

### 4.5 Trailing slack

Append **at least 16 bytes** of anything after scan B. Scan B's bound is
`total_plaintext - 16`, so without the slack the final entry falls outside the bound and is
silently dropped. The contents are never read.

### 4.6 Size limit

The decompressed `.inf` plaintext is capped at **256 KB**. A 660-entry scan A comes to roughly
22 KB, so this is generous in practice.

---

## 5. The archive plaintext

After the same envelope is stripped, an archive decodes to:

```
<prefix — byte-identical to the .inf's first L bytes>
<member[0] bytes><member[1] bytes>…
```

### 5.1 The prefix, shared with the `.inf`

The archive's plaintext **must begin with exactly the same `L` bytes as its `.inf`'s plaintext** —
header, scan A, and the inner tag. The client reads `L` bytes from the archive and `memcmp`s them
against the `.inf`'s copy.

Generate this region once and use it in both files. Deriving it twice is how the two drift apart.

### 5.2 The members

Immediately after the prefix, every member's bytes are laid end to end, **in scan-A order**, with
no padding, no per-member header, and no alignment. The client reads each member's declared size
off the same open stream, which is why the concatenation order and the scan-A order must agree —
the prefix read leaves the stream positioned exactly on the first member.

A well-formed archive therefore satisfies:

```
len(plaintext) == L + sum(size for every scan-A entry)
```

---

## 6. Placement: the name decides where a file lands

By default a member named `foo.bin` is written to `<base>/foo.bin`, where `<base>` is the patch
data directory (`dl/p/` relative to the game's content root). Subdirectories work — `bgm/x.bgm`
lands at `<base>/bgm/x.bgm`, and **the client creates missing directories itself**, walking the
path components and tolerating "already exists".

To place a file *outside* that directory, the name uses an escape:

```
".." <single digit N> "/" <rest>          N must be 0..3
```

which means **go up N directory levels from the base**, then append `<rest>`. All four leading
bytes are required in exactly that shape.

With a base of `<root>/dl/p/`:

| scan-A name | lands at |
| --- | --- |
| `MGO2.SELF` | `<root>/dl/p/MGO2.SELF` |
| `..0/MGO2.SELF` | `<root>/dl/p/MGO2.SELF` (N=0 is a no-op) |
| `..1/.p` | `<root>/dl/.p` |
| `..2/MGO2.SELF` | `<root>/MGO2.SELF` |

> **The trap.** A name that merely *begins* with a dot is **not** special. `.p` reaches the
> leading-dot test, fails the "second byte is also a dot" test, and falls through to the plain
> path — landing in `dl/p/.p` rather than `dl/.p`. This produced a patch that installed every one
> of 660 files byte-perfectly and still did nothing useful, because the two files whose location
> actually mattered were both in the wrong place.

Two limits: only the **parent** directory is created, so a name ending in `/` leaves its leaf
directory uncreated; and the parent path is truncated at **127 bytes** when directories are
created, so very deep paths will build the wrong tree.

---

## 7. Building a patch — the whole procedure

Given a set of files and where each should land:

1. **Choose the two 64-byte key blobs** (slot 7, slot 8). Encrypt each under the master key of
   [§3.3](#33-the-two-server-supplied-keys) for transmission; use the *plaintext* forms for
   everything below.

2. **Decide the records.** One record per archive. Each record has a text name, which becomes both
   the archive's filename and its `.inf`'s filename (+ `inf`).

3. **For each record, assemble its member list**: ordered `(scan-A name, source file)` pairs. Apply
   the `..N/` escape ([§6](#6-placement-the-name-decides-where-a-file-lands)) to any member that
   belongs outside the data directory.

4. **Build the prefix**:
   - `scanA` = concat of `name || 00 || u32be(real size) || flags` for each member, in order
   - `L = 12 + len(scanA) + 16`
   - `header` = `u32be(0) || u32be(L) || u32be(0)`
   - `innerTag` = `HMAC-MD5(elf_key, header || scanA)`
   - `prefix` = `header || scanA || innerTag`

5. **Build the archive**: `plaintext = prefix || member[0] || member[1] || …`, then wrap it in the
   envelope of [§3](#3-the-crypto-envelope). **Write it out and measure the result.**

6. **Build the `.inf`**: `plaintext = prefix || scanB || slack`, where `scanB` is
   `archiveName || 00 || u32be(measured archive size)` and `slack` is 16+ bytes. Wrap it in the
   same envelope. Note the prefix is the *same object* from step 4.

7. **Write the checkver reply** ([§8](#8-the-checkver-reply)).

8. **Verify before serving** ([§10](#10-round-trip-verification)).

Note the ordering constraint: the `.inf` depends on the archive's *size*, and the archive depends
on the prefix, which the `.inf` also embeds. So: prefix → archive → measure → `.inf`.

---

## 8. The checkver reply

A binary blob served from the `checkver.html` path.

**No update available** — the entire reply is a single byte:

```
00
```

**Update available:**

| bytes | meaning |
| --- | --- |
| 1 | `01` — status: update available |
| 4 | opaque u32, never read back — zero is safe |
| var | **string A**: the patch base URL, NUL-terminated (≤255 chars) |
| var | **string B**: the HTTP-fallback base URL, NUL-terminated (≤255 chars) |
| var | one or more **records** (below) |
| 1 | `00` — record terminator, call this position **T** |
| 2 | opaque u16, read but never branched on |
| 4 | packed TO version: `major<<24 \| minor<<16 \| revision` |
| 64 | slot 7 blob, encrypted per §3.3 |
| 64 | slot 8 blob, encrypted per §3.3 |

Minimum total length is `T + 135`.

### 8.1 Records

Each record is a **NUL-terminated ASCII string**, parsed as:

```
<from major>.<from minor>.<from rev>to<to major>.<to minor>.<to rev>
```

optionally prefixed by anything (the disc id, in practice) and followed by anything. The literal
`to` is checked byte by byte.

- The name is truncated to **31 characters**.
- `major` and `minor` must be ≤ 255. `revision` is **not** range-checked.
- At most **8 records** — this is an unchecked buffer limit, not a validated bound, and a 9th
  record silently overwrites the record count.
- The version gate compares the client's current version against the record's FROM version, but
  only the **last** parsed record is tested — from/to are stored in single fields that each record
  overwrites.
- A malformed version number skips the record; a failed `to` literal or a failed version gate is
  **fatal**.

In practice two records are used — one disc-qualified, one generic — mirroring the real patch
tree. That pairing appeared to be load-bearing in testing: dropping to a single record made the
client fail *earlier*, before it even fetched the release note.

### 8.2 The release note

`relnote.txt` is fetched into a 64 KB buffer and is genuinely **displayed** — word-wrapped to up
to 62 lines and rendered 5 at a time with scroll arrows. It is plain text, no envelope.

---

## 9. Failure modes, all of them quiet

This format has very little error reporting, and almost every way to get it wrong looks identical
from the server side. In rough order of how much time each one costs:

| symptom | cause |
| --- | --- |
| Downloads, verifies, installs **nothing**, no error | scan A empty (`L = 28`) — the install loop's bound equals its cursor and the loop is skipped entirely |
| Downloads, verifies, extracts **nothing**, no error | **zlib layer missing** from the archive. Inflate fails on the first read and returns -1; a read of ≤ 0 simply exits the compare loop |
| Installs everything perfectly, achieves nothing | placement — every member landed in the data directory, including ones that belong elsewhere ([§6](#6-placement-the-name-decides-where-a-file-lands)) |
| Patches successfully, then offers the same patch again, forever | the server replied unconditionally. The client cannot tell it is already current — see [§2](#2-transport) |
| Generic error, no detail | a failed HMAC (either one), a bad PKCS#7 pad, or an inflate error — all route to the same state |
| Last entry silently missing | trailing slack shorter than 16 bytes |
| Integrity failure late in a large download | server ignored a `Range:` request and restarted at byte 0 |

A failed install can also leave a lock file behind that makes **every subsequent attempt** report
corrupt data until it is deleted. If you are testing repeatedly, clear the patch directory's lock
file between runs.

---

## 10. Round-trip verification

Because the failure modes above are silent, verify offline before serving. Two distinct checks,
and the second is the one that catches real-world problems:

**A. Does what I built decode?** Replay the client's chain over the bytes you just produced:
verify the trailer, decrypt, check the pad is 1..8, inflate, and confirm the plaintext is exactly
what you fed in. Refuse to ship anything that fails.

**B. Does what the server *serves* decode?** Start from the URL, not the file. This is what
catches a stale file left in the document root, a truncated write, a server answering with a
fallback page, or a declared size that disagrees with what is actually sent.

A complete check walks the whole structure:

1. Fetch and decode the `.inf`. Read `L` from the header; parse scan A at stride 6 within
   `[12, L-16)`; verify the inner tag over `plaintext[0 : L-16]`; parse scan B at stride 5 from
   `L` to `len - 16`.
2. Fetch and decode the archive, streaming.
3. Assert its first `L` bytes equal the `.inf`'s first `L` bytes. *(This is the client's `memcmp`.)*
4. Walk scan A, splitting the decoded stream on member boundaries, and hash each member against
   its source file.
5. Assert the stream is fully consumed: `len(plaintext) == L + sum(sizes)`.
6. Assert scan B's declared size equals the number of bytes the server actually sent.

An extractor is the same walk with step 4 writing files out instead of hashing them, applying the
name rules of [§6](#6-placement-the-name-decides-where-a-file-lands).

---

## 11. Worked example

A two-record patch delivering an executable and a data tree — the shape the real 1.36 patch uses:

```
record 0:  "BLUS30109.1.0.0to1.36.0"     (disc-qualified: the executable differs per disc)
  scan A:  ..2/MGO2.SELF                 19,615,992     -> <root>/MGO2.SELF
  scan B:  BLUS30109.1.0.0to1.36.0        9,158,184     (the archive, as served)

record 1:  "1.0.0to1.36.0"               (generic: the data tree is shared across discs)
  scan A:  ..1/.p                            29,647     -> <root>/dl/.p
           bgm/bgm_mgo_10mga1_alart.bgm   2,725,888     -> <root>/dl/p/bgm/…
           …657 more…
  scan B:  1.0.0to1.36.0               1,895,998,328     (the archive, as served)
```

Files served:

```
<base>/1.36.0/relnote.txt
<base>/1.36.0/BLUS30109.1.0.0to1.36.0inf          104 bytes
<base>/1.36.0/BLUS30109.1.0.0to1.36.0       9,158,184 bytes
<base>/1.36.0/1.0.0to1.36.0inf                  4,616 bytes
<base>/1.36.0/1.0.0to1.36.0             1,895,998,328 bytes
```

Note the ratios: 660 files and 2 GB of content behind two URLs and two small manifests, and the
manifests carry no content at all — only names, sizes, and where things go.
