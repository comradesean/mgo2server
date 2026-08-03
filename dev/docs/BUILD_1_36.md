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

**The patch is now LOCALISED — see "What the patch is" below.** It is a PRX loader injected into
the CRT startup at VA `0x10494`, and the plugin it loads is **not installed**, so it is inert on this
machine.

*Superseded reasoning, kept because it shows which argument is the weak one:* the download manifest
declares `MGO2.SELF` at exactly **19,615,992** bytes with HMAC-MD5
**`70f524ddfad388a2283139a64c43301d`** while this file hashes differently. That was the original
evidence, and it is the **weaker** of the two available — all 234 manifest entries verified by
`dev/tools/parse_dl_manifest.py` carry flag byte `0x00`, and `MGO2.SELF` is the **sole entry with
flag `0x06`**, so the one entry whose digest semantics are unvalidated is the one that mismatched.
Cite the instruction stream at `0x10494`, not the hash.

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

## What the patch is: an injected PRX loader in the CRT startup

**1.36 VA `0x10494`–`0x104FC`** — 108 bytes, 27 instructions, sitting in `__start`'s callee between
the last CRT init call and the call to `main`:

```
0x10494  lis   r3,256 ; ori r3,r3,29909   -> 0x010074D5 = "/dev_hdd0/game/BLUS30109/plugin.sprx"
0x104a4  li    r11,480 ; sc                sys_prx_load_module(path, 0, NULL)
0x104ac  ...                               builds an opt struct: size=40, level=1, entry=-1
0x104d0  li    r11,481 ; sc                sys_prx_start_module(id, 0, &opt)
0x104d8  ld    r11,80(r1) ; cmpdi cr7,r11,-1 ; beq   skip if entry is still the sentinel
0x104e8  lwz r0,0(r9) ; mtctr ; lwz r2,4(r9) ; bctrl   call the PRX entry via its OPD
0x1050c  bl    0x10e28                      main
```

**It loads an arbitrary SPRX off the HDD and calls it before `main`.** That is the whole
mechanism — all behaviour change lives in an external plugin, which is exactly why a string scan
found no hostnames and why no branch was flipped.

Verified independently by the main session: `3c600100 606374d5` at file `0x494` is
`lis r3,256; ori r3,r3,29909`, and `0x010074D5` holds `/dev_hdd0/game/BLUS30109/plugin.sprx`.

**Four independent proofs it is hand-applied, not compiler output:**

1. `sc` with `li r11,480` / `li r11,481` occurs **exactly once each in the entire 1.36 image** and
   **never** in the disc build. Every other PRX operation in either build goes through library stubs.
2. **Absolute `lis`/`ori` string addressing**, where both builds address strings TOC-relative — the
   same function uses `lwz r3,-32732(r2)` four instructions earlier. Sweeping both images for
   `lis`+`ori` pairs resolving into printable strings gives 82 hits in 1.36 and 83 in the disc build
   (the control); **all 165 land mid-string on numeric constants except one** — this, landing on the
   NUL-terminated start of the plugin path.
3. **The string was written over compiler-ident padding and clipped its neighbour.** It abuts an
   ident reading `" (GNU) 4.1.1 (SDK240, ...)"`. **717 idents in this build begin `GCC: (GNU)`;
   exactly one is clipped, and it is the one abutting the injected string.**
4. **Stranded original code.** `0x10530` and `0x10538` have **zero inbound branches** and jump back
   into the middle of the injection. They are the overwritten original's cold-path blocks. The
   function's register-restore epilogue, present in the disc build, is gone — space the patcher
   reclaimed to fit 108 bytes under the size-preserving constraint.

### The plugin is NOT installed, so the patch is inert

There is no `plugin.sprx` anywhere under `dev_hdd0/game/BLUS30109/`. The loader tolerates that —
`opt.entry` is pre-seeded to `-1` and checked before the `bctrl` — so the game proceeds to `main`
normally. **The operator is running a plugin-loader build with the plugin absent**, i.e. whatever the
patch was meant to do is not happening.

**The standing caveat, if that ever changes:** a loaded plugin can hook anything at runtime. If
`plugin.sprx` is ever installed, **no live observation from this client is trustworthy as "1.36
behaviour"** — and nothing in the binary would show it.

### Nothing recorded in this file sits in patched code

The patched regions are `.text 0x10494-0x104FC`, rodata `0x10074D5-0x10074F8`, and data
`0x121E458`. Every address recorded here — `0x8EF324`, `0x289218`, `0xAB35B4`, `0xAC22CC`,
`0x990234`, `0xFDD7B0`, entry `0x11E7368` — is outside all three. **The 16-record host table, the
four commerce slots and the 17-entry string-resource block are genuine 1.36.** No re-labelling
needed.

### The login path is NOT patched

1.36's auth-reply parser at `0xD6ED3C` (found via the `xoris r0,r3,32881` / `cmpwi cr7,r0,2566`
signature) normalized-diffs against the disc build with **every difference accounted for by register
allocation**; no instruction added, removed or flipped. Same for `0xD6FCAC` and `0xD708B4`. So the
login failure below is 1.36's own behaviour, not the patcher's.

## KEEP THE REFERENCE IN SYNC — it drifted once already

`dev/ref/MGO2 1.36 (decrypted).elf` is a **copy**. On 2026-08-02 the operator edited the running
`MGO2.self` at 20:15, after the copy was taken at 19:58, and analysis briefly ran against a stale
image. The 27-byte difference was the content-root string in `.data` at VA `0x121E458`:
`/dev_hdd0/game/BLUS30109/USRDIR/o/` in the copy versus `/dev_bdvd/PS3_GAME/USRDIR/o/` in the
running file.

**Re-copy and re-check the md5 before trusting any 1.36 analysis.** Current, 2026-08-02:

```
e2eae0b9858be277e4ff70c55e507c42  dev/ref/MGO2 1.36 (decrypted).elf   (matches the running MGO2.self)
42dba4a017d3c0bcf681e0bbf874c36a  dev/ref/MGO2 (decrypted).elf        (disc build)
```

That edit did **not** break the `d/testhk` override — the gate exchange succeeded at 20:25, ten
minutes after it — so `d/testhk` is not resolved through that content-root string.

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

## Version separation: BUILT 2026-08-02. One toggle, `MGO2SERVER_CLIENT_VERSION`.

```
MGO2SERVER_CLIENT_VERSION=1.0     release-day disc build. THE DEFAULT, what v1 targets.
MGO2SERVER_CLIENT_VERSION=1.36    the patch build.
```

Unset or blank means `1.0`, so a deployment that has never heard of the toggle cannot serve a later
build by accident. Anything else refuses to start, naming both alternatives and echoing the bad
value. Every process logs its resolved version at startup (`Config[... clientVersion=1.36]`), so
which build a container serves is visible rather than inferred.

**`src/main/java/mgo2server/common/ClientVersion.java` is the complete list of what differs.** Every
version-specific value is a column on that enum:

| | `1.0` | `1.36` |
| --- | --- | --- |
| login reply, third field | `1000000` — one integer | ten integers, nine underscores |
| session key resource | `crypto/session.key` | `crypto/session_136.key` |
| session IV | `b0781d5365e3910e` | `35d5c38ed0110ea8` |

**Adding a divergence means adding a column**, which cannot be done without answering *"what does
1.0 do?"*. That is the anti-contamination mechanism, not a convention.

### It replaced two ad-hoc variables, and the hazard was real

`MGO2SERVER_LOGIN_PERKS` and `MGO2SERVER_SESSION_KIT` were `System.getenv` reads on `static final`
fields — frozen at class load, unreachable from a test. `SessionFieldTest` and
`AuthWebControllerTest` pin capture-proven **1.0** vectors while reading those same statics, and
`server.env` set both to their 1.36 values. **Those tests would have failed the moment `server.env`
reached Maven's environment**; they passed only because it is consumed by `compose.yaml` and never
by `mvn`. Nothing enforced the separation.

There was contamination inside the suite too:
`AuthWebControllerTest.underscoreJoinedPerksWouldBeRejected()` asserted the underscore form is
invalid — true for 1.0, and exactly what 1.36 requires.

### The guards

- **Default safety** — an empty environment yields `1.0`.
- **`ClientVersionTest` pins the `1.0` row literal by literal**, so a change made "for 1.36" that
  touches 1.0 fails here rather than becoming a wrong byte on the wire weeks later. It also pins the
  1.36 row, asserts no two versions share a divergent value, and checks both key resources ship.
- **A source scan** fails if any file under `src/main/java` reads either retired variable again. It
  matches `getenv("...")` rather than the bare name — the first version matched the name and
  immediately failed on `SessionField`'s own comment explaining why the variable is gone, which is
  exactly the note a future reader needs.
- **`SessionFieldTest` and `AuthWebControllerTest` now name their version explicitly**, so the pins
  hold regardless of configuration. `SessionFieldTest` gained the 1.36 vector proven today
  (`f5a0880bc3a40336` -> `8dde80bae7eac2753b7c89139395cb21`) and an assertion that the two builds
  derive *different* fields from the same token.

**Verified:** `mvn verify` is green at 249 unit / 241 integration, and **green again with
`MGO2SERVER_CLIENT_VERSION=1.36` plus both retired variables exported** — an environment that would
have broken the old suite. That run is the contamination check and is worth repeating by hand after
any 1.36 work.

### What this does not cover

The two divergences still unmapped — "can't create a game" and "lobbies look slightly different" on
1.36. The toggle is where their fix goes; it does not fix them. Candidate sites already identified:
`GameDetails.FIXED_SIZE = 372` with its assert, `HostSettingsReply.SIZE = 0x15C`, and
`AutomatchSettingsBlock.RULE_TIMERS` keyed 0..7 only. Also banked from the ELF: 1.36's lobby-list
capacity is **32 -> 100** and its containing struct grew 104 bytes, though the server enforces no cap
today.

## SOLVED: login stops at dialog 0x5012 — a 1.36-only PSN entitlement gate

**The server cannot fix this, because the failing step never reaches the server.**

`FFFFFE03` is **not** a signed −509. It is a **packed pair** built at 1.36 `0xAC350C`:
`code = (status << 8) | phase`. Low byte `0x03` = phase 3; `status << 8 = 0xFFFFFE00` so
**status = −2**. (`-509` appears nowhere in the 1.36 image; the disc build has three
`subfic ...,-509` and 1.36 has zero, which is the control that the sweep works.) Dialog `0x5012` =
20498 is written by exactly one instruction image-wide, 1.36 `0xAC2F50`, and **does not exist in the
disc build at all**.

The state machine at 1.36 `0xAC2DA8` spawns a worker thread named **`psnupdatesvr`**
(`0xEA8B68`) which queries PSN/NP for entitlement to the region's product id —
`UP0101-BLUS30109_00` for BLUS30109. On RPCS3 with no real entitlement the lookup returns **zero
entries** (`0xEA9090` / `0xEA9164`), the worker stores **−2** at `0xEA8C7C`, and the poller raises
the dialog.

The surrounding string block is **entirely absent from the disc build**: `MGOSHOP_TITLE`,
`BUY_KAKUNIN_DOC`, `NO_BUY_DOC`, `JPY`/`USD`/`EUR`, `psnprodlist`, `/ticket.html`, `/rest.html`,
`psnid`, and the three PSN product ids. This is **the MGO Shop**, added post-launch.

### The way out is a switch we already had and did not understand

The worker tests one bit before doing any work:

```
0xEA8BC0  rlwinm r0,r0,0,30,30    extract bit 0x2 of the host-table flag word (0x0187FF9C)
0xEA8BC4  cmpwi  cr7,r0,0
0xEA8BC8  beq    cr7,0xEA8FC0     CLEAR -> do the PSN work
0xEA8BCC  li     r0,0             SET   -> return status 0, skip entirely
```

and that bit is set by **`d/testhk` header byte 0, bit 1**:

```
0x8EF358  ori    r0,r0,2
```

`testhk_editor.py` has carried that bit since it was written, labelled **"effect unknown"**. It is
now `--skip-psn`, and its effect is documented on the `flag_bit1` field. No effect has been
established for it on the disc build.

### The lobby-list hypothesis was WRONG, and the control matters

1.36's `0x2003` parser (`0xF02058`) is instruction-for-identical to the disc build's (`0xD362B0`)
apart from **two immediates**: the list struct offset `1872 -> 1976`, and the entry-count bound
**`31 -> 99`**, i.e. capacity **32 -> 100**. Record layout, field offsets, the 52-byte stride and the
`memset` are byte-identical. Our 322 bytes / 7 entries at 46 bytes each is well inside both. The
gate exchange completes normally and the client's `0x0003` is an ordinary disconnect, not a
rejection.

**Banked for a version toggle:** lobby-list capacity 32 -> 100, containing struct +104 bytes.

## Open

- Whether 1.36 honours the `d/testhk` hostname override at all — the string is present, but presence
  is not a reference. Under investigation 2026-08-02.
- Where 1.36 sources its hostnames. For the disc build `HOSTS.md` establishes they come from disc
  string resources rather than the executable; that must be re-checked here rather than assumed.
- The cause of `0703:00000000` (dialog 1795, *"A network server error has occurred"*) on a 1.36
  client pointed at this server. The **zero** code means nothing answered, as distinct from a server
  answering with an error.
