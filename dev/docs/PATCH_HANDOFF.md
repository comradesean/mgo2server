# Auto-patch 1.0 → 1.36: session handoff, updated 2026-08-03

Goal: make the **in-game patch mechanism** install 1.36. Manually placing `MGO2.SELF` on the HDD is
out of bounds — the patch process itself is the deliverable.

Durable findings are merged into `ADDRESSES.md` §12 and `OBSERVED.md`. This file is the working
state: what is proven, what is deployed, and what to do on the next run.

## Where it stands

**The mechanism works end to end.** A real client downloads both archives, verifies them, extracts
all 660 files byte-perfect — creating the eight missing subdirectories itself — and the two files
whose location matters now land where the loader and the archive reader actually read them.

| stage | status |
| --- | --- |
| checkver → relnote → both `.inf`s → both payloads | works |
| payload MAC verification (phase 1) | passes, both files, `r3 = 0` at `0xD66588` |
| phase 2 chain: HMAC → Blowfish → **zlib inflate** → read | works — the zlib layer was the missing one |
| archive prefix compare `0xBBAE70` | passes |
| extraction of 660 members, incl. `mkdir -p` of 8 subdirectories | **confirmed live** |
| placement of `MGO2.SELF` → `o/` and `.p` → `o/dl/` via the `..N/` names | built; last run before it booted 1.0 |

Three things had to be true at once and each failed silently on its own: the payload needs a
**zlib layer** (`ADDRESSES.md` §12, "The payload's own read chain"), scan A must be **non-empty**,
and the two special files need the **`..N/` name escape** (below). The format itself is now
written up independently in **`dev/docs/PATCH_FORMAT.md`**, which is complete enough to rebuild
this from scratch — an implementation written from it alone round-trips and decodes live files.

## The server has to decide when a client is current

The client's version gate only checks it is **at or above** each record's FROM version. Nothing in
it compares against the TO version, so an already-patched client accepts the same offer forever —
observed live as an endless re-patch loop. `http_probe.py` parses the packed version out of the
checkver POST and substitutes a bare `0x00` when the client is already current, reading the TO
version back out of the reply itself so the two cannot drift. It logs the decision:

```
checkver body: b'19136512,BLUS30109,1180'
client is 1.36.0, offer is 1.36.0 -- answering 0x00, already up to date
```

## Solved, and confirmed live — do not re-derive

- **Payload container** = `plaintext || HMAC-MD5(K, plaintext)`. 16 raw bytes appended, no header.
- **`K` = the ASCII string `mgo2server_slot8`** (16 bytes; HMAC zero-pads to its 64-byte block).
  Read from `r22` at `0xBBA6F0`. **This is not Konami's key** — it is our project's name, so this
  HDD's `MGO2.SELF` is modified and its crypto slot provider stubbed. Everything built under it is
  specific to that executable. The ptsys key `0xE26D78` was tried and rejected; don't retry.
- **Scan A is the install list.** `<name> 00 <u32 size BE> <u8 flags>` at plaintext offset 12,
  `hdr[4] = 12 + len(A) + 16`, inner tag over `plaintext[0, hdr[4]-16)`. An empty scan A (the old
  `hdr[4] = 28`) makes `0xBBB0CC` skip the whole install loop **silently**.
- **`dl/p/.l` left behind ⇒ "data is corrupt" on next launch**, sticky until deleted. Reader is
  `0x2FDE0` → `0x2F818`. Distinct from the inert `dl/p/ar/.l`.
- **Devices**: 1 = the per-boot cache partition, 7 = `/dev_hdd0/…/USRDIR/o/`.

## Confirmed live 2026-08-03

- **A 660-member archive installs**, every file byte-perfect against its source.
- **The client creates missing subdirectories itself.** `mkdir -p` is inlined in the open wrapper
  (`0x280F0`), gated on flag bit `0x40`, and every create-mode open in the patch module passes
  flags `0x241`. This corrects the old "the client never calls `mkdir`" claim, which was made by
  grepping for a string in a binary that imports by NID.
- **The `.torrent` is a hash of the payloads**, so it must be rebuilt whenever they change —
  `build_torrent.py`, then restart `probe-bt` and check the two `info_hash` values agree.

## Solved 2026-08-03, tier-1 (read from the ELF, not yet seen live)

- **The payload body must be zlib-compressed** (RFC1950, `windowBits = 15`) *under* the Blowfish
  layer. Same shape as the `.inf`'s stage 2b, which cost an earlier round for the same reason.
- **The Blowfish key is confirmed, not guessed.** `0xBBAD3C`/`0xBBAD70` call the keystore's
  `get(slot = 7, dest)` and hand that buffer straight to `0xD66CF0`. `--encrypt`'s `slot7` default
  was right; it is no longer a hypothesis.
- **The phase-2 HMAC filter strips the 16-byte trailer but does not verify it** — `key = NULL`,
  `flag = 1`. The holdback is unconditional; the flag only decides hash-and-compare vs count. So
  Blowfish sees exactly the ciphertext and the PKCS#7 padding is the true end of its stream.
- **`0xBBAF00` is the failure handler**: state 10, error 2, then it deletes `dl/p/ar/` on both
  devices. The staging tree vanishing "as cleanup, every run" *was this failure*, every run.

## Placement: the destination is in the NAME, not the flags

A complete 660-file round installed byte-perfect on 2026-08-03 and the client **still booted 1.0**,
because every member went to `dl/p/` — including `MGO2.SELF`, which the loader reads from `o/`, and
`.p`, which the archive reader opens at `o/dl/.p`. The fix is the `..N/` name grammar at
`0xBB5678` (full write-up in `ADDRESSES.md` §12): a scan-A name of `..<digit>/<rest>` goes that
many directory levels up from `dl/p/`. `build_patch_round.py` now emits `..2/MGO2.SELF` and
`..1/.p` by default; `--no-place` restores the flat names as the A/B control.

Watch for the trap: a name that merely *starts* with a dot is not special. `.p` fails the
`name[1] == '.'` test and falls through to the plain path, which is precisely how it ended up in
the wrong place while looking like it had been handled.

## The archive shape — one download, many files inside

Settled 2026-08-03, and it is what the two scans are *for*. Scan B names what to **download**;
scan A names what to **extract from it**. The real 1.36 patch is the proof: 659 files in the tree,
but the operator's listing has only two payload URLs. So:

```
BLUS30109.<from>to<to>   ->  MGO2.SELF                 (disc-specific: BLUS/BLES/BLJM differ)
<from>to<to>             ->  .p + the whole data tree  (shared across all three discs)
```

and an archive's plaintext is `hdr[4] prefix || member[0] || member[1] || ...`, with the prefix's
scan A listing every member in the same order. The prefix compare at `0xBBAE70` consumes exactly
`hdr[4]` bytes, which leaves the stream positioned on the first member, and each entry then reads
its own declared size off that same open stream — so concatenation order and scan-A order must
agree. `build_patch_round.py` generates both from one `members` list so they cannot drift.

**Two round-trip checks, and they answer different questions.** `build_patch_round.py` calls
`verify_container()` on every archive it builds and refuses to write one that does not decode —
that covers the bytes it just produced. `verify_patch_round.py` starts instead from the URL the
client fetches, streams each archive back through the chain, and hashes every member against its
source file in the tree; that is what catches a stale docroot file, a truncated write, a probe
serving fallback prose, or a declared size that disagrees with what the server actually sends.
Run the second one after any redeploy.

`--data {manifest,root,all}` chooses what the generic archive carries. The builder **streams**
(deflate → Blowfish → HMAC → file, one chunk at a time) because `all` is 2 GB and holding that
whole would want four simultaneous copies; `verify_container` replays the client's chain back off
the written file the same way.

## Deployed right now

The complete patch — the real 1.36 executable plus all 659 data files:

```
MGO2SERVER_CLIENT_VERSION=1.36 python3 dev/tools/build_patch_round.py \
  --level 1.12 --blob --include-self --data all --zlib-level 1 \
  --mac 6d676f327365727665725f736c6f7438 --encrypt
```

| archive | on the wire | carries |
| --- | ---: | --- |
| `BLUS30109.1.0.0to1.36.0` | 9,158,184 | `MGO2.SELF` → `o/MGO2.SELF` |
| `1.0.0to1.36.0` | 1,895,998,328 | `.p` → `o/dl/.p`, plus 659 files → `o/dl/p/…` |

Layout per archive:

```
BlowfishCBC( zlib.compress( header(12) || scanA || innerTag(16) || every member, in order ),
             PKCS#7 to 8 )  ||  HMAC-MD5(K, ciphertext)
```

Build takes ~100 s at `--zlib-level 1`; the tree is mostly already-compressed audio, so level 6
buys almost nothing and costs several minutes. Both tools stream, so peak memory is one chunk.

`server.env` has `MGO2SERVER_CLIENT_VERSION=1.36` — **armed**. The game servers were deliberately
not recreated and are still serving the 1.0 divergences they started with; see the note in
`server.env` for why that is right for a patch test and wrong once a client is actually on 1.36.

`http_probe.py` had to change for this to work at all: it read whole files into memory (fatal at
1.9 GB) and logged the `Range:` header while ignoring it, answering 200 with the full body — which
would have corrupted any resumed download in a way that only surfaces as a failed MAC. It now
streams and answers 206. The probes also **mount** the docroot instead of copying it at startup,
so static changes no longer need a restart and 1.9 GB is not duplicated into two writable layers.

## To run the next test

1. Arm the server: set `MGO2SERVER_CLIENT_VERSION=1.36` in `server.env`, re-run
   `build_checkver.py`, restart `probe-http`/`probe-https` (they snapshot `dev/runtime/www`
   at startup, so a static-file change alone is not picked up).
2. Clear the poison file and recreate staging:

```
U="/mnt/d/rpcs3-v0.0.41-19598-357b7d44_win64_msvc/dev_hdd0/game/BLUS30109/USRDIR"
H="/mnt/d/rpcs3-v0.0.41-19598-357b7d44_win64_msvc/dev_hdd1/caches/BLUS30109_BLUS30109"
find "$U/o/dl" "$H/o/dl" -name ".l" -delete
mkdir -p "$U/o/dl/p/ar" "$H/o/dl/p/ar"
```

**Note the corrected device-1 path.** The earlier handoff said `dev_hdd1/o/`, which does not
exist under this emulator — RPCS3 gives hdd1 a per-title cache root, and the real directory is
`dev_hdd1/caches/BLUS30109_BLUS30109/o/`. The old cleanup line was silently a no-op.

3. Breakpoints, in priority order:
   - `0xBBAE70` — the prefix compare. **If this fires, the diagnosis was right.**
   - `0x28875C` — reads `r3` = `inflate()`'s return, the one-run discriminator if it fails again:
     `-3` (`Z_DATA_ERROR`) means the bytes are not zlib; `-5` (`Z_BUF_ERROR`) means the source
     delivered nothing, which is a staging problem, not a format one.
   - `0xBBAF00` — the failure handler. Reaching it means the compare loop ended without a match.

## Method note, earned the hard way

Five static analyses of `0xBBA458` produced **five** wrong claims, each costing a round trip:
`0xBBA8C8`'s role, the reachability of `0xBBACB4` and `0xBBB190`, the device for the `dl/p/ar/t/`
call, and "scan A is display-only" — that last one *correct about the function it was read from*
and wrong about the one that mattered. Two of my own live readings were also wrong: I credited the
installer for `dl/p/` opens the **parser** makes, and I proposed a device-7 staging experiment that
silently tripped the "already complete, skip download" path at `0xBB8210` and invalidated its own
result.

When a static claim and the client disagree, the client is right. A claim true of one caller is not
true of another. And check whether a diagnostic perturbs the thing it measures.

**One more, from the zlib finding.** The inflate filter was missed by every earlier pass because
it is constructed **inline** — a vptr and a source pointer written to the stack, with no `bl` to a
constructor. Scanning a function for `bl`s to known crypto/stream constructors will not find it.
Two independent traces (one live-reading session, one background agent) converged on it only after
both were forced to enumerate *every* branch out of a 94-instruction window rather than looking
for the calls they expected.
