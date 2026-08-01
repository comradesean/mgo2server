# `dl/.p` — the `DLT2` download manifest

The local index the game's patch subsystem reads to decide which files under `USRDIR/o/dl/p/`
are missing or out of date. The subsystem calls itself **ptsys** in its own log strings.

Sample used throughout: the user's genuine 1.36 archive, 29,647 bytes, at
`/mnt/d/rpcs3-.../dev_hdd0/game/BLUS30109/USRDIR/o/dl/.p`. Regenerate the dump with
`dev/tools/parse_dl_manifest.py`; the current output is `dev/analysis/dl_manifest.txt`.

**This file supersedes nothing.** `PATCH_INVESTIGATION.md` §2 already had the layout below,
derived independently against the same sample; this document re-derived it from the bytes and
agrees field for field. What is new here is the **digest algorithm**, which §2 recorded as
unidentified, and the payload cross-check that proves it.

## Endianness

**Big-endian throughout**, as you would expect on PPC64.

The `14 00 00 00` run that appears after every filename, and that reads as a little-endian 20,
is an artifact of where the eye lands. It is not a field. It straddles two big-endian words:

```
bgm_mgo_10mga1_alart.bgm 00   00 01   00   01 14 00 00   00 29 98 00   7c c0 92 45 ...
                         ^    ^       ^    ^             ^             ^
                         NUL  parent  flg  version       size          digest
                                           0x01140000    0x00299800    (16 bytes)
                                              = "1.20"      = 2725888
```

`0x14` there is the **minor version byte**, and the three zeros after it are the version word's
low half plus the size word's top byte. Reading it as a length prefix for a 20-byte SHA-1 field
is the trap this format sets, and it is wrong twice over: the field is 16 bytes, not 20, and
there is no length prefix anywhere in the format.

The size field settles the endianness on its own — read big-endian it matches the real on-disk
file length for 235 files exactly; read little-endian it matches none.

## Header

| Offset | Size | Field | Value in the sample |
| --- | --- | --- | --- |
| `0x00` | 4 | magic `"DLT2"` | `44 4C 54 32` |
| `0x04` | 16 | **digest** of the rest of the file | `8e9cb6ab163a0719b1716579830f6ca9` |
| `0x14` | 4 | archive version, u32 BE | `0x01240000` → 1.36 |
| `0x18` | 4 | timestamp, u32 BE | `0x4805E58C` → 2008-04-16 11:39:56 UTC |
| `0x1C` | 13 | five NUL-terminated strings | `""`, `".p"`, `"p"`, `""`, `"patch"` |
| `0x29` | — | first entry record, no padding | |

The header digest covers **`[0x14 .. EOF]`** — version word onward, i.e. everything except the
magic and the digest field itself. Verified: recomputing it reproduces the stored bytes exactly.

`DLTB` is a second magic sitting 0x148 bytes before `DLT2` in the ELF's string pool. Per
`ADDRESSES.md`, it selects a 96-byte archive subclass (`0xD60AF8`) that **is never instantiated
anywhere in the binary** — a dead format. Only the `DLT2` subclass (`0xD641E8`) is ever built.

### The five header strings — confidence: low

Their *bytes* are certain; their *meaning* is not. The neighbouring ptsys log string
`ptsys:%s : flag %x, localpath %s,` / `ptsys:     remotepath %s, dispname %s` names four
per-entry concepts, and `".p"` / `"p"` are exactly the manifest's own filename and its payload
directory, so "localpath / remotepath / dispname"-style fields are the obvious reading. That is
inference from adjacency, not from instructions. Two of the five strings are empty, which no
reading yet explains. Reported positionally by the parser and left labelled unknown.

## Entry record

The entry array is **flat and ordered**. There are no depth bytes, no terminators, and no
child-count fields — the tree is carried entirely by a parent index.

```
name     cstring, NUL-terminated, ASCII
parent   u16 BE   index into this same array; 0xFFFF = archive root
flags    u8       bit 0 set -> directory, and THE RECORD ENDS HERE
--- the following 24 bytes are present only when bit 0 is clear ---
version  u32 BE   0xMMmm0000
size     u32 BE   length of the file's PLAINTEXT
digest   u8[16]   HMAC-MD5, see below
```

Directory records are 3 bytes past the name; file records are 27.

### Why the u16 is a parent index — confidence: high

Three independent checks, all of which would have failed on a wrong reading:

1. Every non-`0xFFFF` value points at an entry **earlier in the array** whose flags bit 0 is
   set. Parents are always directories, always already defined. The parser asserts both.
2. The reconstructed paths match the real `p/` directory tree: 659 of 660 declared files exist
   on disk at exactly the reconstructed path, and all 31 declared directories exist and are the
   only directories there. The exceptions run one way only — `MGO2.SELF` is declared and absent,
   and two undeclared `MGO2-136-Syringe-ps3*.self` files are present (see open question 2).
3. The array parses to EOF with zero slack — the last entry's digest ends on the final byte.

### The flags byte — confidence: mixed

| Value | Count | Meaning |
| --- | --- | --- |
| `0x00` | 659 | ordinary file — **established**, the 24-byte tail is present |
| `0x01` | 31 | directory — **established**, the record ends after the flags byte |
| `0x06` | 1 | `MGO2.SELF` only — **unknown** |

Bit 0 is definitely "this is a directory": it is the bit that decides the record length, and
mis-reading it desynchronises the whole array immediately. Bits 1 and 2 (`0x06`) appear on
exactly one entry in one sample, which is not enough to say what either does. Since `MGO2.SELF`
is the executable rather than an asset, "the boot image / handle specially" is the plausible
guess — but a guess with n=1 is not a finding, and no other bit combination is observed anywhere.
Bits 3-7 are never set in this sample.

### The version word — confidence: medium-high

Always `0x01XX0000`. Reading the second byte as a **decimal** number reproduces the published
MGO2 version ladder exactly, and every one of the eleven distinct values lands on a legal minor:

| Word | Reading | Files |
| --- | --- | --- |
| `0x01010000` | 1.01 | 2 |
| `0x010A0000` | 1.10 | 93 |
| `0x010B0000` | 1.11 | 4 |
| `0x010C0000` | 1.12 | 2 |
| `0x01140000` | 1.20 | 134 |
| `0x01150000` | 1.21 | 15 |
| `0x011E0000` | 1.30 | 307 |
| `0x011F0000` | 1.31 | 7 |
| `0x01200000` | 1.32 | 36 |
| `0x01220000` | 1.34 | 11 |
| `0x01240000` | 1.36 | 49 |

Note this is **not** BCD — `0x1E` is not a valid BCD byte. The byte is a plain binary minor
version that happens to be printed as `%d`. The header's own version word is `0x01240000`, the
highest value any entry carries, consistent with "the archive is at 1.36". The low half is
always zero; whether it is a revision field or padding is unknown. The ptsys log string
`ptsys:U %s v %x->%x` prints two of these when it updates a file.

The reading is corroborated by, not derived from, the ladder — treat "1.36" as a label.

## The digest — HMAC-MD5, proven

**`digest = HMAC-MD5(key, payload)`, 16 bytes.**

```
key = 9357a9dfb8eb8d03b843cd025f2a30ce      (MGO2.elf VA 0xE26D78)
```

- **Header digest**: payload is `manifest[0x14:]`.
- **Entry digest**: payload is the file's **plaintext** bytes, in full, nothing prepended or
  appended. The `size` field is that plaintext's length.

The key is not a guess. `ADDRESSES.md` records `0xE26D78` as "the 16-byte key used by the DLT2
archive's own digest check (`0xD640C4`-`0xD6410C`, `memcmp` on mismatch → `ptsys:digest errror`,
archive discarded)". The same 16 bytes head the `.inf` stage-3 HMAC key block at `0xE20000`.
What was open was the *construction*; standard HMAC-MD5 under that key is what matches.

### Verification — 258 payloads, not an inference from field length

Method: for every entry whose file exists under the sibling `p/`, recompute the digest over the
real bytes and compare with the stored 16.

| Result | Count |
| --- | --- |
| Header digest over `[0x14 .. EOF]` | 1 verified |
| Files stored in the clear, hashed as-is | **234 verified**, 1 mismatch (`kit`) |
| Files stored encrypted, decrypted first, then hashed | **23 verified**, 0 mismatches |
| Files stored encrypted, not decrypted (not attempted) | 401 unverified |
| `MGO2.SELF` | not verifiable — see below |

**258 payloads verified in total, zero false positives.** A 16-byte HMAC agreeing on 258
distinct inputs is not coincidence.

The 424 encrypted files are the ones sitting on disk at **exactly `size + 24` bytes**, still
inside the path-keyed asset-cipher container documented in `CRYPTO.md`. The digest covers the
plaintext, so those cannot be checked without decrypting. Twenty-three were decrypted with
`dev/tools/solideye/Solideye.exe -dec`, one from each `stage/` subdirectory, keyed by the
directory component of the path (`stage/init_n`, `stage/lobby`, …) exactly as `CRYPTO.md`
describes. All 23 decrypted to **exactly** the manifest's `size` and all 23 digests matched.

Two controls that could have failed and did not:

- `stage/init_n/cache.dci` and `stage/ota_chat/cache.dci` have **different ciphertexts** (different
  directory keys) but the **same manifest digest**. They decrypt to byte-identical plaintext.
  That independently confirms both the decryption and that the digest is a function of plaintext
  only — not of the stored bytes, the path, or the encryption.
- 16 further groups of same-content files (`sdpack/X.ssp` vs `sdpack_e/X.ssp`) share a digest
  despite differing paths, ruling out any path or filename contribution to the input.

### What was ruled out, and how

All negatives below were tested against real files with the positive control above available,
so the method demonstrably can detect a match:

- **Plain MD5** — over the stored bytes of all 660 files, over `disk[:-24]`, over `disk[:size]`,
  and over decrypted plaintext. Zero matches.
- **SHA-1** — the leading hypothesis from the field looking 20 bytes long. It is not 20 bytes
  long; the field is 16, bounded on both sides by fields whose values are independently
  confirmed (the size matches the real file length, and the record array ends exactly at EOF
  with no slack). SHA-1 truncated to 16, from either end, matches nothing.
- **SHA-256 / SHA-512 / SHA-224 / SHA-384 / RIPEMD-160 / SM3 / BLAKE2** truncated to 16 from
  either end, plus byte-reversed and 32-bit-word-byteswapped forms of each.
- **Endian-damaged MD5** — a plausible failure mode on a big-endian build: MD5 with big-endian
  message-word loads, big-endian length encoding, and big-endian digest output, in all eight
  combinations. None matched. (This was the standing hypothesis when the format was last
  looked at; it is now closed.)
- **Prefix/suffix hashing** — MD5 and SHA-1 over every prefix of a 580-byte file, and over the
  first/last 16 B, 64 KiB and 1 MiB of a large one.
- **Name- or size-salted digests** — filename, full path, size and version word prepended and
  appended.
- **`MD5(key64 || MD5(data))`**, the construction the asset cipher uses, with the 64-byte `kit`
  file as the key.
- Simple 16-byte XOR and additive checksums.

## Payload cross-check

| Delta (on-disk minus `size`) | Files | Meaning |
| --- | --- | --- |
| `0` | 235 | stored in the clear |
| `+24` | 424 | still in the asset-cipher container |

The `+24` is **constant** — it does not vary with `size mod 8`. Sizes in that set include
`77`, `2764`, `819200` and `3011009`, whose residues mod 8 are 5, 4, 0 and 1; all are `+24`.

That is worth recording because `CRYPTO.md` describes the container as "PKCS#7-padded to 8 bytes
and a 16-byte digest appended — **24 bytes of overhead**". Real PKCS#7 padding to an 8-byte block
would make the overhead vary between 17 and 24 bytes with the payload length. Across 424 samples
it never varies. So the container's overhead is a **fixed 8 bytes plus the 16-byte digest**, not
variable padding — the "24" in `CRYPTO.md` is right, the "PKCS#7" is not, and the two only agree
by accident on payloads that are already block-aligned. Decrypting returns exactly `size` bytes
in all 23 cases tested, which is the same fact from the other side.

## Tree shape

31 directories, 660 files, maximum depth 3.

```
(root)
├── MGO2.SELF                 flags 0x06, declared but see below
├── bgm/                      152 files
├── sdpack/                   22      sdpack_e/  22      (identical filenames in both)
├── shader/                    1
├── slotdat/                  17
├── speech/                    8      speech_e/   8      (identical filenames in both)
├── stage/                     0 files, 23 subdirectories
│   ├── init_n/ lobby/ n001a/ … n018a/ nt_mgsetup/ nttitle/ ota_chat/
│   └── r_onlinelobby/ r_sna01_n/ r_sneak_n/
├── kit                       64 bytes
├── lippatch.dat              lippatch_e.dat
└── vox_ex1.dat  vox_ex3.dat
```

`stage/` is the only directory that contains directories; nothing nests deeper than
`stage/<name>/<file>`.

## Trailer

There is none. The last entry is `vox_ex3.dat` and its 16-byte digest ends at `0x73CE`, the
final byte of the file. No padding, no index, no footer.

## Open questions

1. **`kit` is the one plaintext file whose digest does not verify.** 64 bytes, delta 0, and the
   only miss out of 235. Its size and high entropy match the 64-byte key blobs used elsewhere in
   the patch system (the `.inf` path installs 64-byte blobs into keystore slots 7 and 8), so the
   likely explanation is that the copy on disk was rewritten locally after the manifest was
   authored, rather than that the digest rule differs for it. Untested either way.
2. **`MGO2.SELF` is declared but absent, so its digest cannot be checked.** The manifest declares
   `version 0x01240000`, `size 19,615,992`, `digest 70f524ddfad388a2283139a64c43301d`. No file of
   that name exists in `p/`. What is there instead are two files the manifest does not declare —
   `MGO2-136-Syringe-ps3.self` and `MGO2-136-Syringe-ps3 (2).self` — both 19,517,872 bytes,
   98,120 short of the declared size (and not the container's +24). They are **not copies of each
   other**: same length, different digests. Neither matches the declared digest. These look like
   community-built replacements rather than the archive's own payload.
   `PATCH_INVESTIGATION.md` §3 treats the missing `MGO2.SELF` as a crash root cause; nothing here
   contradicts that.

   Note this directory is a live RPCS3 install the user is actively working in — the `.self`
   filenames observed changed between two sessions a day apart. Re-check before relying on it.
3. **The `0x06` flags byte** on that same entry. n=1.
4. **The two empty header strings.** No reading proposed.
5. **The version word's low 16 bits.** Always zero in this sample.
6. Whether the client ever *writes* this file. `ADDRESSES.md` notes `"DLT2"`/`"DLTB"` are each
   `memcmp`'d exactly once and never written, so the archive must be seeded externally — which
   means a server-side patch flow would have to produce this file, digests and all. The parser
   here is enough to build one: the digest function is `ptsys_digest()` in
   `dev/tools/parse_dl_manifest.py`.
