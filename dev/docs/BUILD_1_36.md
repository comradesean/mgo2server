# The 1.36 build — quarantined findings

**Everything in this file describes `dev/ref/MGO2 1.36 (decrypted).elf`, 19,615,992 bytes.**
Nothing in it applies to the release-day disc build, and nothing from the rest of `dev/docs/`
applies here. See `CLAUDE.md`, "There are two tier-1 binaries".

This file exists so that 1.36 work cannot leak into the disc-build documentation by accident. A
disc address used against 1.36 lands in unrelated code and reads as a plausible finding — which is
worse than an obviously wrong one, because nothing about it looks wrong.

## ⚠ THE SUBJECT BINARY IS MODIFIED — read before trusting anything below

**`dev/ref/MGO2 1.36 (decrypted).elf` is not stock 1.36. It was deliberately patched**, per the
operator, *"with the express intent to bypass connections. They may have hardcoded something."*

Proof, not supposition: the game's own download manifest declares `MGO2.SELF` at exactly
**19,615,992** bytes with HMAC-MD5 **`70f524ddfad388a2283139a64c43301d`**. This file is exactly that
size and hashes to **`e46930f921b8dd8509d92d6416604e74`**. Right size, different content — an
in-place byte patch that preserved length.

**So every finding in this file carries an unresolved question: is it 1.36, or is it the patch?**
Findings in code the patcher did not touch are genuine 1.36; findings inside patched code describe
somebody's modification and would be wrong to record as protocol. Until the patch is localised, read
every claim here as *"observed in this binary"* rather than *"true of 1.36"*.

**There is no stock 1.36 to diff against** — it is not on disk, and the only file of that size is
this one. So the patch has to be found by analysis rather than comparison. Under investigation
2026-08-02.

What has been ruled out already, with a control: a string scan finds **no** hardcoded private-server
endpoint — no `savemgo`, `nomad`, `localhost`, or non-stock hostname — and the IPv4 literals are
near-identical between the two builds (`4.1.2.7` is a compiler artifact, `239.255.255.250` is SSDP
multicast, `172.16.0.0`/`172.31.255.255` are private-range constants). `SYRINGE` is **stock**: it is
the in-game item, sitting among `BANDANA`, `STEALTH`, `S. PLUG` in both builds. So if the patch
redirects anything, it is **code, not strings** — a flipped branch or a NOP, which a string scan
cannot see.

**Confidence note on what is already recorded below.** The host-table finding (12 → 16 records) is
the least likely of these to be patched: it is corroborated by three independent structural facts —
the loop bound, the port-array offset moving 3072 → 4096, and four new indices having live call
sites — and a patcher bypassing connections has no reason to *widen* a table. The login-path
findings are the most exposed, because "bypass connections" points directly at them.

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

## SOLVED: `0703:00000000` — the host table went from 12 records to 16

**The 1.36 host-address loader reads sixteen records where the disc build reads twelve.** Verified
three ways:

```
disc  0x7F955C:  cmpwi cr7,r27,11    ->  12 records
1.36  0x8EF324:  cmpwi cr7,r27,15    ->  16 records
```

plus 1.36's port accessors sit at **4096** (16 × 256) where the disc build uses 3072 (12 × 256)
(`sth r4,4096(r3)` at 1.36 `0x289218`), and all four new indices have live call sites.

**Why the failure was silent, which is the expensive part.** A 12-record file is consumed through
record 11; the loader then tries record 12, the one-byte read returns 0 at EOF, and it **falls
through to the string-resource table with no diagnostic**. The client dials the real
`mgo2gateus.konamionline.com`, nothing answers, and reports `0703:00000000` — code **zero**, because
nothing rejected it. The fallback is working as designed; it simply is not what an operator wants.

**Fix applied 2026-08-02:** `dev/tools/testhk_editor.py` now writes **16** records. Minimum file is
`16 + 16*3 = 64` bytes, up from 52. **A 16-record file is correct for both builds** — the disc build
reads the first twelve and never looks further — so this is a compatibility fix, not a version
change, and it needs no toggle.

### What the four new slots are

Slots 12-15 are the **PS Store commerce and PSN-update subsystem**, added post-launch. Consumers
(1.36 addresses): 12 returned raw by a getter at `0xAB35B4`; 13 a base URL with `/query.html`
appended, ~10 call sites; 14 formatted `%s?prod=%d` at `0xAC22CC`, whose own stock default in the
binary is `http://127.0.0.1/`; 15 `strncpy(...,511)` then the shared HTTP entry at `0x990234`. The
same string block holds the PSN product ids `UP0101-BLUS30109_00`, `EP0101-BLES00246_00`,
`JP0101-BLJM67001_00`.

**`point_at` leaves 12-15 on loopback by default.** We do not serve those endpoints, and slot 13 is
fetched from about ten call sites — answering it wrongly breaks a session that would otherwise work.
Pass `include_commerce=True` to aim them at the server deliberately, which is a worthwhile
*experiment*: the requests then land in the probe logs and can be mapped.

### Hostnames still come from string resources

Confirmed for 1.36, with a control: `mgo2gate`, `stunna`, `konamionline` and `https://` all return
zero hits in the image, while the same search does find `http://127.0.0.1/`, `.com` ×58 and the PSN
product ids. So `testhk` remains the right mechanism.

One consequence for the fallback route: 1.36's regional string-resource block is **17 entries, not
13** (the loop writes slots 0..15, then reads `base + 16` for the flag word; the disc build reads
`base + 12`). Release-day `scenerio.gcx` would be misread by a 1.36 client, so `HOSTS.md` section 4
does not apply here unless re-derived against the 1.36 patch's own `scenerio.gcx`.

## Requirement: version separation must be explicit, and it is not built yet

**Operator instruction, 2026-08-02: do not roll 1.36 behaviour into the v1 server.** When 1.36
support is added it must be behind **a clear toggle in the env configuration** (`server.env`,
alongside the existing `MGO2SERVER_*` settings), so the running version is a deliberate, visible
choice rather than something inferred.

Nothing in the server has been changed for 1.36 to date. The only 1.36-driven change so far is to
`dev/tools/testhk_editor.py`, which is a client-side install tool, not the server, and whose output
is valid for both builds.

## Open

- Whether 1.36 honours the `d/testhk` hostname override at all — the string is present, but presence
  is not a reference. Under investigation 2026-08-02.
- Where 1.36 sources its hostnames. For the disc build `HOSTS.md` establishes they come from disc
  string resources rather than the executable; that must be re-checked here rather than assumed.
- The cause of `0703:00000000` (dialog 1795, *"A network server error has occurred"*) on a 1.36
  client pointed at this server. The **zero** code means nothing answered, as distinct from a server
  answering with an error.
