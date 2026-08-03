# The 1.36 build — quarantined findings

**Everything in this file describes `dev/ref/MGO2 1.36 (decrypted).elf`, 19,615,992 bytes.**
Nothing in it applies to the release-day disc build, and nothing from the rest of `dev/docs/`
applies here. See `CLAUDE.md`, "There are two tier-1 binaries".

This file exists so that 1.36 work cannot leak into the disc-build documentation by accident. A
disc address used against 1.36 lands in unrelated code and reads as a plausible finding — which is
worse than an obviously wrong one, because nothing about it looks wrong.

## Why we have it

Opened 2026-08-02. The operator installed 1.36 and it failed to reach the server; investigating that
turned up the fact that it is a **different build**, not a patched copy.

The strategic reason to care is bigger than that one bug. A large block of this project's mapping is
tier-1 only and carries the note *"cannot reach tier 2, because no available client build exercises
this"*:

- the `0x49xx` team / tournament family,
- the `0x4Axx` tournament and survival event subsystem,
- the `0x4Exx` Survival Match List.

**1.36 is that missing build.** It is the version where the post-launch content is live, so it is
the only route by which those mappings ever become live-confirmable. Mapping is not version-scoped
even though *serving* is — see `CLAUDE.md`, "Map now, build later".

## Established facts

| | |
| --- | --- |
| file | `dev/ref/MGO2 1.36 (decrypted).elf` (gitignored, like the disc build) |
| size | 19,615,992 bytes — 2.2 MB larger than the disc build's 17,373,376 |
| format | **raw decrypted ELF**, magic `\x7fELF`. Not a SELF; the copy on the HDD install is named `MGO2.self` but is not `SCE\0`-wrapped |
| arch | PPC64 big-endian, OS/ABI `0x66`. `objdump` refuses it — use `powerpc64-linux-gnu-objdump -D -b elf64-powerpc` |
| entry | `0x11E7368` |
| text LOAD | file `0x0`–`0x117E348` ↔ VA `0x10000`–`0x118E348` |
| data LOAD | file `0x1180000` ↔ VA `0x1190000` |
| **VA ↔ offset** | **`file offset = VA − 0x10000`**, for *both* LOAD segments — the same convention as the disc build |

**It is not the stock 1.36 either.** The download manifest declares `MGO2.SELF` at exactly
19,615,992 bytes with HMAC-MD5 `70f524dd…`; this file is that size but hashes to `e46930f9…`. Right
size, different content — the signature of in-place byte patching. See `dev/analysis/dl_manifest.txt`
and `dev/tools/parse_dl_manifest.py` for the manifest and the key.

## Address correspondences measured so far

Do not extrapolate from these. They are recorded to show how far apart the builds are, not to
support a mapping between them.

| item | disc build | 1.36 |
| --- | --- | --- |
| `d/testhk` string | VA `0xE0B588` (file `0xDFB588`) | VA `0xFDD7B0` (file `0xFCD7B0`) |

The two binaries differ from **byte 29 onward**; roughly 16 million bytes differ.

## What transfers and what does not

**Transfers:** the VA↔offset convention, PPC64 and OPD handling, the disassembly method, and — as
far as anything has been checked — the protocol shapes themselves. A disc-build finding is a good
*lead about where to look*.

**Does not transfer:** every address. `ADDRESSES.md`, every `.ksy`, `PROTOCOL.md`, `OBSERVED.md`
are all disc-build documents.

**Watch the cached disassembly.** The scratchpad's `mgo2.dis` is the **disc** build. Any 1.36
listing must say so in its filename.

## Open

- Whether 1.36 honours the `d/testhk` hostname override at all — the string is present, but presence
  is not a reference. Under investigation 2026-08-02.
- Where 1.36 sources its hostnames. For the disc build `HOSTS.md` establishes they come from disc
  string resources rather than the executable; that must be re-checked here rather than assumed.
- The cause of `0703:00000000` (dialog 1795, *"A network server error has occurred"*) on a 1.36
  client pointed at this server. The **zero** code means nothing answered, as distinct from a server
  answering with an error.
