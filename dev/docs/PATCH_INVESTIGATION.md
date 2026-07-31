# Auto-patch investigation — working notes

Session log for reconstructing the MGO2 auto-patch mechanism (`checkver.html` → `relnote.txt` →
`.inf` → `.torrent`/HTTP-fallback) and evaluating whether a self-hosted test patch is buildable.
The durable findings from this investigation already live in `ADDRESSES.md` §12 and `OBSERVED.md`
("Auto-patch — checkver.html and the update flow"); this file is the working narrative, including
evidence that doesn't belong in those two (fan-tool internals, in-progress stub design) and the
full run log that got the stub working end to end.

**Status: done.** As of 2026-07-31 a real RPCS3 client runs the whole flow — checkver → relnote →
`.inf` → confirmation dialog → HTTP download → completion → release note display — against this
stub. See §0 below for how to run it, or finding 11 (§7) for the live-test log.

## 0. Quickstart — running the stub end to end

Everything is static files served out of `dev/runtime/www/`; no Java web-controller code is
involved in this flow (`http_probe.py` only proxies `/us/mgo2/kid/` and `/us/mgo2/rank/`, and
serves the docroot for everything else). The two builder scripts are the only things that need
running by hand.

1. **Set the target host and version jump** — env vars, not file edits, so switching the version
   under test never means editing code (defaults shown; override only what differs):
   ```
   export MGO2SERVER_PATCH_HOST=http://192.168.1.200      # your server's LAN IP
   export MGO2SERVER_PATCH_FROM=1.0.0
   export MGO2SERVER_PATCH_TO=1.36.0
   export MGO2SERVER_PATCH_DISC_ID=BLUS30109
   ```
   `build_inf_stub.py` and `build_torrent_stub.py` both import `build_checkver_stub.py` for these
   values, so setting them once (`export`, or prefix each command below) keeps every artifact in
   the same version jump — there's no second place a version number can drift out of sync. Real
   jumps seen in the wild (`OBSERVED.md`): `1.10.0`→`1.34.0`, `1.0.0`→`1.36.0`.
2. **Build the checkver reply and release note**:
   ```
   cd dev/tools && python3 build_checkver_stub.py
   ```
   Writes `dev/runtime/www/us/mgo2/patch/checkver.html` and
   `.../patch/<to-version>/relnote.txt`. Also prints `SLOT7_KEY`/`SLOT8_KEY` — the keys
   `build_inf_stub.py` must build the `.inf` against; they're fixed constants, not per-run
   secrets, so nothing needs to be copied by hand.
3. **Build the `.inf` files and stub payloads**:
   ```
   python3 build_inf_stub.py
   ```
   Writes one `.inf` + one placeholder payload file per record (currently two: disc-qualified and
   generic) into the same version directory.
4. **Build the `.torrent` file** (needs steps 2 and 3 done first — it reads the same stub payload
   bytes back off disk to hash them):
   ```
   python3 build_torrent_stub.py
   ```
   Writes the `.torrent` into the same version directory. Prints the `info_hash` — you don't need
   it for anything, `bt_seed.py` (next step) recomputes it the same way and will complain loudly
   if the two ever disagree.
5. **Redeploy** — all files are bind-mounted, so a container restart picks them up without a
   rebuild:
   ```
   docker restart mgo2server-probe-http-1 mgo2server-probe-https-1
   docker compose up -d probe-bt   # first time; `docker restart mgo2server-probe-bt-1` after
   ```
   `probe-bt` runs the BitTorrent tracker (port 6969) and seeding peer (port 6881) — see
   `dev/runtime/bt_seed.py`. It uses host networking like the game-lobby services, for the same
   reason (WSL2 mirrored networking's docker-proxy is unreliable for persistent raw TCP).
6. **Point a real client at it** (see `HOSTS.md` for the `d/testhk` override — the supported route
   for repointing the five Konami hostnames) and trigger the version check. Expected flow:
   - `POST /us/mgo2/patch/checkver.html` → `0x01` reply → client fetches `relnote.txt`
   - Client fetches the disc-qualified record's `.inf`, decrypts and parses it
   - "An update has been uploaded" dialog → choose **HTTP Download** — live-confirmed working end
     to end. **Peer-to-Peer parses the `.torrent` and connects correctly but never completes on
     RPCS3** (finding 11, §7 — a real TCP handshake succeeds, but the client never sends its HTTP
     request afterward; RPCS3's own log shows the network ioctl it polls for non-blocking-connect
     completion is unimplemented). `probe-bt`'s tracker/seed are verified correct against both a
     simulated and a real client up to that point, so this may work on real PS3 hardware even
     though it doesn't on this emulator — untested.
   - Triangle/display-details shows the release note text
   - **Hitting X to apply produces the generic error dialog — this is expected.** The payload is
     32 bytes of placeholder text, not a structurally valid patch package, so the install step
     rejecting its content is the correct outcome; building a real installable payload is a
     separate, out-of-scope problem (no real Konami patch content is recoverable — §3, §4).

**Sanity-check the crypto without a client**, useful after any change to either builder script:
```python
import zlib, hmac, hashlib
from Crypto.Cipher import Blowfish
import build_checkver_stub as checkver

data = open("../runtime/www/us/mgo2/patch/1.36.0/BLUS30109.1.0.0to1.36.0.inf", "rb").read()
ciphertext, outer_tag = data[:-16], data[-16:]
assert hmac.new(checkver.SLOT8_KEY, ciphertext, hashlib.md5).digest() == outer_tag
plaintext = Blowfish.new(checkver.SLOT7_KEY[8:64], Blowfish.MODE_CBC,
                          checkver.SLOT7_KEY[0:8]).decrypt(ciphertext)
pad = plaintext[-1]
decompressed = zlib.decompress(plaintext[:-pad])   # raises if the zlib stage is missing/wrong
print("entries+slack:", decompressed[28:])
```

**Two display quirks were found and fixed 2026-07-31** (see finding 11 in §7 for the full trace):
the confirmation dialog showing "Ver. 0.00" instead of a real version number (a checkver field
that wasn't actually opaque), and the release-note text running off the bottom of the display
screen (too long for the update screen's word-wrap/pagination). Live re-test pending.

## 1. The protocol, from the ELF [tier 1]

Full byte-level writeup is in `ADDRESSES.md` §12 / `OBSERVED.md`. Summary:

- `checkver.html` reply byte 0 is a status: `0x00` up to date (what our server has always sent —
  none of this has ever been exercised against a real client), `0x01` update available and the
  rest of the reply is structured (opaque u32, two NUL-terminated base-URL strings, ≤8
  version-range records at 44-byte stride, a terminator, two more opaque fields, then two 64-byte
  blobs that become Blowfish keys for keystore slots 7 and 8).
- **The server supplies both Blowfish keys itself** on this path — nothing needs to be recovered
  from a real client capture, only shaped correctly. This is what makes a self-hosted patch
  tractable at all.
- A record is accepted only if the client's own current version (read at runtime from its mounted
  `.p` archive, not an ELF constant) is ≥ the record's "from" version.
- `"0inf"` is not a distinct extension — it's the client's URL format string `%sinf`, no dot, so
  the record text must supply its own trailing `.` (`...1.34.0` + `inf` = `...1.34.0inf`).
- Fetch order: checkver → `relnote.txt` (fetched, never rendered — no renderer touches it) → one
  `.inf` per accepted record → `.torrent` (genuine, statically-linked Transmission) or, if flag
  bits select it, a plain per-file HTTP fetch from "string B" with `Range:` resume.
- `.inf` is Blowfish-CBC encrypted with slot 8. Decryption is directly observed in the
  disassembly; the **decrypted plaintext's grammar is not** — the reader object carries no
  attributable strings. Provable: a count field and an array of 16-byte entries (name pointer,
  two tested flag bits). Not provable from disassembly alone: the exact header before the count,
  and the full shape of one 16-byte entry. An ELF pass is in flight (see §5) to narrow this
  further before we write bytes.
- The install is real and client-side: `open` the downloaded copy off device 1, `open`+`write` a
  copy onto device 7 at the same relative path, `unlink` the device-1 copy. The full 28-module,
  349-function PRX import table has no `cellGame*` entry anywhere — no PS3 system update package
  is involved.
- No UI beyond a version-number label next to a `"popup"` object on the title screen. No dialog
  raiser, no progress percentage, no display string for `relnote.txt`'s body exist in this module.
  The flow is fully automatic once triggered.

## 2. The user's real 1.36 archive — `.p` (`DLT2`) format [tier 2, real client artifact]

The user has a genuine 1.36-version `dl` archive pulled from a real PS3 hard drive (not the
original packaging — see §3). Its local index file (`dl/.p`, magic `DLT2`) was fully
reverse-engineered against the real 29,647-byte sample:

```
Header (multi-byte fields big-endian):
  0x00  4    magic "DLT2"
  0x04  16   digest of the archive (algorithm unidentified — ruled out MD5, SHA-1[:16])
  0x14  4    archive version, 0x01240000 -> "1.36"
  0x18  4    Unix timestamp, 0x4805E58C -> 2008-04-16 11:39:56 UTC
  0x1C  13   five NUL-terminated strings: "", ".p", "p", "", "patch"
  0x29  ...  entry array begins, no padding

Entry record (variable length):
  name    cstring, NUL-terminated
  parent  u16 BE   (index of parent entry; 0xFFFF = archive root)
  type    u8       (0x01 = directory, record ends here;
                     0x00 = ordinary file; 0x06 = the MGO2.SELF entry)
  -- only present when type != 0x01, 24 more bytes --
  version u32 BE   (0xMMmm0000)
  size    u32 BE
  digest  u8[16]   (same unidentified algorithm as the header digest)
```

Parses the real file exactly to EOF: 691 entries (31 directories, 659 files, 1 `MGO2.SELF`).
Every real on-disk file/directory matches the manifest and vice versa **except `MGO2.SELF`
itself**, which is declared (`version 0x01240000`, `size 19,615,992`, `digest
70f524ddfad388a2283139a64c43301d`) but has no corresponding file anywhere in the archive — this is
the crash root cause, see §3. Root-level entries also show a base/`_e`-suffix split
(`sdpack`/`sdpack_e`, `speech`/`speech_e`, `lippatch.dat`/`lippatch_e.dat`) with **identical
filenames inside both trees** — not a language-dub pair, more likely an alternate
encoding/asset-set. Not confidently decoded.

**Update 2026-07-31: the `DLT2` reader was found.** A later pass, digging into why the auto-patch
install was failing (§7), located the whole patch-archive subsystem at `0xD5EE00`-`0xD64C00`
(self-identifying via a `ptsys:` debug-string family) — it opens `dl/.p` (not `dl/p/.p`), checks
the `DLT2` magic, and gates the archive on a digest check keyed by the same 16-byte constant that
heads the `.inf` stage-3 HMAC key (`0xE20000`) — a real lead on the digest algorithm, though the
algorithm itself is still unconfirmed. Confirmed, and important for anyone hoping to hand-author an
archive: **nothing in `MGO2.elf` can create `dl/.p`** — the magic is `memcmp`'d, never written — so
this reader really is read-only, and the writer really does live elsewhere (presumably `EBOOT.BIN`,
still unverified, no decrypted copy available).

## 3. The crash, and why `MGO2.SELF` matters

The user's real `dl` archive, dropped into a disc-original (`BLUS30109`) RPCS3 install, crashed on
load. Root cause traced through `RPCS3.log`: the archive declares `MGO2.SELF` (v1.36,
19,615,992 bytes) but no such file exists anywhere in it — the archive alone cannot supply the
executable it depends on. The disc's own `MGO2.SELF` is v1.00. Running v1.00 code against v1.36
data hits an unbounded, no-bounds-check table lookup (id × 32-byte stride) that produces exactly
the logged fault address. This is the standalone-vs-integrated-build divergence hazard CLAUDE.md
already warns about in the abstract, playing out literally.

The user's caveats, preserved because they bound how far this evidence generalizes: the archive
"was pulled from a PS3 harddrive, it's not the original form," and "it may be from the standalone
version of the client" (they played cross-version with someone on the integrated build, so it's
plausibly compatible in principle, but that isn't confirmed).

## 4. The four `ANANSI999` fpkg files — extracted, and what's actually in them [tier 4, fan tool]

The user separately had four PS3 PKG files (`MGO2-v24.pkg`, `MGO2-v30.pkg`, `MGO2 Patch
1.36.pkg`, `MGO2 Disc Data.pkg`), all sharing content ID `UP0101-ANANSI999...` — a homebrew/fan
repackaging, not an official Konami content ID. Extracted with `pkg2zip` (Vita/PSM only, does not
support PS3-format PKGs — abandoned) then **PyKG**
(`github.com/AphelionWasTaken/PyKG`, MIT), which does support PS3 NPDRM PKGs and worked cleanly
with its built-in retail key (no need for the all-zero fpkg-key fallback — output was clean, not
garbage).

All four extract to one merged tree (822 files total, since they share a content ID) under
`USRDIR/`:

- `EBOOT.BIN` — the real PS3 entry point for this pseudo-title.
- `executables/` — `MGO2-100-Syringe.self` (7,525,584 bytes), `MGO2-136-Syringe-ps3.self`
  (19,517,872 bytes), and matching `.sprx` files. **Neither matches the `.p` manifest's declared
  `MGO2.SELF` size (19,615,992 bytes)** — confirmed via exhaustive search of the full extracted
  tree (no file of that exact size, no file named `MGO2.SELF`, anywhere). "Syringe" is scene
  terminology for a runtime patcher/loader, not a drop-in executable replacement — this fpkg does
  not ship, and was never going to ship, a literal `MGO2.SELF`. It solves "run patched content" a
  different way (its own `EBOOT.BIN` → Syringe loader → in-memory patching) than the disc/dl-archive
  scheme the retail client expects.
- `syringe/di-eu`, `syringe/di-na`, `syringe/di-jp` — three 64-byte files, byte-identical except
  one field at offset `0x2A`: `0x00`=JP, `0x01`=NA/US, `0x02`=EU. **This is a region selector
  belonging to the fan repackaging tool**, not to Konami's client — it answers how the "Syringe"
  loader picks a region variant to inject, not how the retail game reads its own region (that's
  still the disc-string-resource mechanism `HOSTS.md` documents). Worth keeping separate from
  tier-1 findings.
- `resources/DiscFiles.txt` and the `o/` tree — largely mirror the real disc's file layout,
  consistent with this being a legitimate personal PS3-HDD dump repackaged for portability, not
  fabricated content.

Net conclusion: these four PKGs do not supply a working `MGO2.SELF`, and can't resolve the crash
in §3 by themselves.

## 5. The ELF pass — landed, findings folded into `ADDRESSES.md` §12 / `OBSERVED.md`

Pinned the checkver reply's exact top-level layout and closed the `.inf` pipeline end to end. The
one correction that matters most for §7 below: **the `.inf` isn't single-Blowfish, it's three
stages**, and the third is keyed by a **64-byte blob resident in the ELF itself at `0xE20000`**
(`93 57 a9 df b8 eb 8d 03 b8 43 cd 02 5f 2a 30 ce` + zero padding) — not one of the reply's two
server-supplied keys. So "the server supplies both keys, nothing needs cracking" (§1) is true of
the reply's own slot-7/slot-8 keys, but a self-hosted `.inf` also has to survive this third, fixed
stage correctly.

The good news: the plaintext grammar downstream is now fully known. A 12-byte header (one field is
the region length; two fields unread elsewhere; no magic checked) precedes an entry list:
`<name> 00 <u32 size, big-endian>`, repeated, name inline (not a string-table pointer), next entry
at `NUL+5`. **A hand-authored entry needs only a name and a size** — there's no flags field on the
wire; the flag bits the client tests (device selection, skip, resume) are runtime-only. ≤31
entries per record is a checked bound (unlike the ≤8-record cap on the reply itself, which is an
unchecked buffer limit).

Two remaining unknowns, both flagged rather than guessed at: (a) whether stage 3 transforms the
buffer in place or is itself a discarded verification pass, and (b) a second entry-shaped scan
pass (`0xBB89B0`-`0xBB8AC0`) that runs *before* the recording loop, advances by `NUL+6` instead of
`NUL+5`, and tests a bit on the byte after the NUL — purpose not established. (b) is the one thing
that could make a correctly-shaped `.inf` still misbehave.

Also corrected: a failed version-gate or a failed literal-`to` check while parsing a record is
**fatal** (error state 10), not merely "the record is rejected" as earlier phrasing implied; only a
`strtoul` failure is non-fatal.

## 5a. Phase 1, live-tested [tier 2, real client — 2026-07-31]

`checkver.html` (status `0x01`, two records, two chosen keys) and `relnote.txt` were written by
`dev/tools/build_checkver_stub.py` and served for real. Two harness bugs surfaced and were fixed
before the client actually saw the intended bytes:

- `http_probe.py`'s `do_POST` never checked the docroot for a static file — only `do_GET` did — so
  a POSTed `.html` path (which is how the client actually fetches `checkver.html`) always fell
  through to the old hardcoded `0x00` stub regardless of what was on disk. Fixed by having
  `do_POST` try `from_docroot()` first, same as `do_GET`.
- The placeholder `policy.txt` wrapped at up to 70 chars/line; the real terms screen's display
  width is narrower (~58-60 chars), so lines were visibly chopped. Rewrapped to 58.

With both fixed, the client: parsed the `0x01` reply correctly, fetched `relnote.txt` without
incident, then requested `.inf` at a URL that matched the ELF-predicted
`<record-text>+"inf"` construction byte-for-byte (`BLUS30109.1.0.0to1.36.0.inf`). No `.inf` existed
yet, so it got the harness's generic fallback text, failed to parse it as ciphertext, and raised a
clean error dialog (`-160`/`21917`, "A network server error has occurred.") rather than hanging —
the expected outcome for this stage, and the first real-client confirmation that the reply's
top-level layout and the record→URL construction are both correct. Findings folded into
`OBSERVED.md`.

The same live test also prompted a re-check of the "`relnote.txt` is never rendered" claim (user
correction — see below), which turned out to be right: the claim was scoped only to `uupdate.cc`,
and the body really is rendered by the owning screen, in a scrollable 5-line pane, along with a
real download-progress percentage and a third dialog raiser (`0x8BE974`) the original pass missed.
All three corrections are in `ADDRESSES.md`/`OBSERVED.md` now.

Not yet written: `.inf` and payload files.

## 6. Real historical server evidence, from the user's own screenshot [tier 2]

The user has screenshots of Konami's actual `mgo2web.konami.com` patch directory for the 1.36
release, corroborating and sharpening the ELF-only picture:

- Confirmed URLs: `.../patch/1.36.0/relnote.txt`,
  `.../patch/1.36.0/BLUS30109.1.0.0to1.36.0inf`, `.../patch/1.36.0/1.0.0to1.36.0inf`,
  `.../patch/1.36.0/BLUS30109.1.0.0to1.36.0.torrent`.
- **Both the disc-qualified (`BLUS30109.1.0.0to1.36.0`) and generic (`1.0.0to1.36.0`) record
  pairs exist server-side as real files**, each with its own small `...inf` (1-2KB) and a larger
  same-named-minus-suffix payload file. This confirms — rather than just being "consistent with,"
  as `OBSERVED.md` currently hedges — that a real checkver reply for this upgrade carried **two**
  version-range records, and the client fetches an independent `.inf`+payload pair per accepted
  record, not two routes to the same content.
- The disc-qualified payload is reported as "significantly smaller" than the generic one. Not
  explained by anything read from the ELF; not asserting a cause.
- Matches the ELF picture cleanly: the small `.inf` is the Blowfish-encrypted manifest (count +
  16-byte entries); the larger unnamed-extension file is the actual payload, most likely fetched
  via the plain-HTTP-fallback path (`%s/%u.%u.%u/%s` from "string B"). If that large file's name
  really is exactly the record text with no extension, the simplest reading is that the `.inf` in
  each case declares **one entry** whose name equals the record text itself — i.e. one bundled
  blob rather than a per-file manifest. That would make a stub trivial: one entry, one file we
  fully control the contents of.

## 7. Stub-test design, as currently planned

Goal: exercise the real network flow end-to-end (server sends a real `0x01` reply, client really
fetches `relnote.txt` → `.inf` → payload, and installs it) using placeholder payload bytes, not
reconstructed Konami patch content — since the latter isn't available (see §3, §4).

Target versions, per the user's real-URL evidence: from `1.0.0` to `1.36.0`, mirroring both
records (disc-qualified `BLUS30109.1.0.0to1.36.0.` and generic `1.0.0to1.36.0.`), matching
`http://mgo2web.konami.com/us/mgo2/patch/1.36.0/...` but pointed at a local IP.

Mechanically simple to deploy: `checkver.html`, `relnote.txt`, and every patch file the client
would fetch are served as plain static files out of `dev/runtime/www/us/mgo2/patch/...` — no Java
web-controller code involved (confirmed via `compose.yaml` and `dev/runtime/http_probe.py`, which
proxies only `/us/mgo2/kid/` and `/us/mgo2/rank/`, and serves everything else straight from the
docroot). The risky part is entirely in the *bytes*, not the deployment.

Phases, in ascending order of risk — **all now live-confirmed working, 2026-07-31** (see finding
11 below for the full end-to-end result):
1. `checkver.html` reply + `relnote.txt` — byte-exact known from the ELF, live-tested 2026-07-31,
   works.
2. `.inf` — **live acceptance confirmed 2026-07-31.** Four build rounds. Round 1 implemented a
   wrong pipeline model ("three Blowfish stages") and was rejected. Round 2 corrected the pipeline
   (HMAC-verify → Blowfish-CBC → HMAC-verify, §5) and round-tripped clean, but was *also* rejected
   live — crypto right, plaintext layout wrong (two entry scans at different strides, entries start
   after the inner tag, not at offset 12). Round 3 fixed the layout and validated offline via an
   opcode-faithful reference implementation, but a live retest *still* failed with the same generic
   error — the actual missing piece turned out to be a whole undiscovered pipeline stage (zlib
   inflate between the CBC decrypt and the inner HMAC, finding 7), not a bug in anything already
   built. Round 4 added it; a real client now accepts the `.inf`, shows the confirmation dialog,
   and completes the download.
3. **A dead end, kept for the record: the client never creates a directory, anywhere — true, but
   not the live blocker.** The install loop opens `dl/p/ar/<name>` on device 7 with
   `O_CREAT|O_WRONLY`, which creates the file but not missing parent directories, and the test
   install had no `dl` folder at all. `mkdir -p USRDIR/dl/p/ar/t/0/` was applied and retested —
   **same error, still zero network activity after the `.inf`.** Tracing the actual post-`.inf`
   control flow explained why: that install loop lives inside the **state-3 downloader**, reached
   only after a player answers a confirmation dialog the client raises *itself* (no server signal
   needed) once the `.inf` is accepted. So "no request after the `.inf`" is what a **successful**
   `.inf` looks like — silence isn't evidence of a blocked write, it's evidence the `.inf` was
   never accepted in the first place. A real rejection happens upstream of that tail, at the
   checkver status byte, one of the two HMAC checks, or the record parser (least likely — a
   correctly-built `.inf` URL was observed live, which requires the parser to have succeeded).
   Also resolved in the same pass and worth keeping: the `dl` "mount" isn't a VFS mount (no mount
   table exists anywhere), `dl/p/.l`'s `ENOENT` at boot is a dead read with no consequence, and the
   real archive path is `dl/.p`.
4. **The keystore-decrypt fix (found 2026-07-31): confirmed correct, twice.** `get()`
   unconditionally Blowfish-CBC-decrypts whatever `set()` stored, under a master key resident in
   the ELF at `0xE26DA8`; `build_checkver_stub.py` now sends the two key blobs pre-encrypted under
   that key so the client's effective key equals `SLOT7_KEY`/`SLOT8_KEY`. This was re-derived
   independently via an *executed* opcode-faithful trace (master key bytes re-dumped from the ELF,
   IV/key split re-confirmed at `0xD645C8`, CBC direction re-confirmed at `0xD64690`) and separately
   confirmed **live**: a debugger breakpoint mid-`.inf`-verification showed the literal ASCII string
   `"mgo2server_slot7"` sitting in registers — i.e. the client really does end up holding our chosen
   plaintext key, not decrypted garbage. This fix is settled; do not re-litigate it without new
   evidence.
5. **The two-record structure is load-bearing, not incidental — tested live 2026-07-31.** Tried
   dropping the checkver reply to a single record (disc-qualified only) on the theory that the
   client was dying while building the *second* record's `.inf` request. Result: reproducibly
   *worse* — the client didn't even reach `relnote.txt`, which it always fetches when both records
   are present. Reverted to two records. Whatever the real bug is, sending only one record is not
   the fix.
6. **A record-loop control-flow correction, live-traced 2026-07-31: `uupdate.cc`'s four
   generic-error exits each abort the whole function, not just the current record.** The earlier
   theory that record 0 succeeds and record 1's *request-building* fails was wrong — the loop can
   only advance to the next record via its footer (`0xBB8BCC`), so "record 1's `.inf` was never
   fetched" means record 0's own iteration hit one of the four exits (`0xBB7E2C`, `0xBB7F4C`,
   `0xBB8730`->`0xBB8904`/`0xBB8910`, `0xBB88B8`), not a problem specific to the second record.
   `0xBB7E2C` was mis-identified as an HTTP-object-construction check; it's actually
   `sendRequest`'s (`0xBB2B70`) own internal "HTTP status wasn't 200" case — ruled out by both a
   direct `curl`+`HEAD` check of the probe (clean `200`, byte-identical body) and, later, live
   register captures (`r0=200`, `CR7 EQ=1`) at the exact comparison instruction (`0xBB2D14`),
   confirmed multiple times across different requests (`policy.txt`, `checkver.html`, the `.inf`
   itself).
7. **SOLVED, 2026-07-31: the `.inf` pipeline is missing a zlib-inflate stage, and this was the
   entire bug.** A live breakpoint trace reached the real failure point for the first time:
   `0xBB7D88` (build record-0 request) → `0xBB2D14` (status 200, passes) → `0xBB7E2C` (sendRequest
   succeeded) → `0xBB7F4C` (passes) → `0xBB8730`, where `r3 = -1` and `CR7 LT=1` take the branch
   into the generic error dialog. Two wrong turns on the way to the real cause, both corrected by
   live evidence rather than more disassembly-reading:
   - First assumed `0xBB8730` was the CBC-decrypt/PKCS7-pad check failing. A hand-dump of the
     actual 64-byte key from RPCS3's Memory Viewer (`r1+384` at the breakpoint) proved the key in
     memory is byte-identical to `SLOT7_KEY` — ruling that out — and a from-scratch offline
     re-decrypt of the real `.inf` produced valid `08`×8 PKCS7 padding, matching.
   - Then a static trace claimed the pad-check instruction was `0xD6845C` and that it should be
     firing. **Live-tested directly: a breakpoint at `0xD6845C` never hit, at all.** That's what
     broke the case open — the function at `0x2884F8` (previously assumed to be a "buffered
     reader") is actually a **zlib inflate stream filter** (ctor `0x28887C` calls
     `inflateInit2_` with `windowBits=15`, a standard RFC1950 wrapper; `inflate()` itself is
     recognizable zlib 1.2.3 at `0xD2DB04`, with its own copyright string in the ELF at
     `0xE23959`). The `-1` at `0xBB8730` is `inflate()` reporting "incorrect header check" /
     "unknown compression method" on our uncompressed plaintext — reusing the exact same
     generic error-state-10 path a real pad failure would, which is why it read identically to a
     crypto bug for a full investigation round.
   - Confirmed offline: `zlib.decompress()` on the real Blowfish-CBC-decrypted `.inf` plaintext
     raises `Error -3: unknown compression method` — the identical failure, reproduced without
     RPCS3 at all.
   **Fix, applied and verified end-to-end**: `build_inf_stub.py` now `zlib.compress()`s the
   `header + inner_tag + entries + slack` block before PKCS7-padding and Blowfish-CBC-encrypting
   it. Every existing layout rule (header, the two entry scans, the 16-byte trailing slack)
   describes the *decompressed* buffer, confirmed at `0xBB87B0` (header read post-inflate) and
   `0xBB8AEC` (scan B's bound is decompressed-length-minus-16); decompressed output is capped at
   256 KB (`0xBB86C4`). Regenerated `.inf` files round-trip cleanly through outer HMAC → CBC
   decrypt → PKCS7 unpad → zlib inflate → inner HMAC → entry parse, checked directly in Python.
   Deployed; live re-test pending.
8. **A separate, unimplemented endpoint found in passing: `GET /VT006-U1/info/`.** Documented in
   `HOSTS.md` as disc-string slot 11 (`http://info.service.konamionline.com/VT006-U1/info/`, the
   "info service" host, region-specific suffix `-U1`/`-E1`/`-J1`) but its expected reply shape was
   never determined; `http_probe.py` currently answers it with the generic TERMS fallback stub,
   which is almost certainly wrong. Seen once, mid-session, on a different host/thread than the
   `uupdate.cc` record loop — likely a periodic check-in unrelated to the patch flow rather than
   part of it. Not yet fixed; flagged for follow-up.
9. **`http_probe.py` gained `do_HEAD` support, 2026-07-31.** `BaseHTTPRequestHandler` answers any
   verb without a `do_*` method with a bare `501 Unsupported method`, and — critically — that path
   never calls this harness's own `_log()`, since logging only happens inside the `do_GET`/`do_POST`
   methods written here. A `HEAD` request would therefore fail *and* leave zero trace in the log.
   Added `do_HEAD` (same body-lookup as `do_GET`, headers only, logged) as a precaution; no live
   evidence yet that the client actually issues `HEAD` requests in this flow, so treat this as a
   defensive fix, not a confirmed root cause.
10. **Debugging methodology, worth keeping**: the patch flow runs across at least two named PPU
    threads — `uupdate.cc` (coordinates the record loop and `.inf` handling) and `udldata`
    (performs at least the `policy.txt`/terms fetch, and possibly generic downloads) — both calling
    into the same shared `sendRequest` (`0xBB2B70`). Breakpoints must be set on the correct thread
    in RPCS3's Debugger window; setting them on `MGS4 MAIN` never fires. The PPU decoder must be
    set to **Interpreter (static)** for breakpoints to work reliably — but the interpreter's speed
    hit was severe enough in one test to stall the *unrelated* `policy.txt`/terms-of-service screen
    on a loading spinner, a new symptom that had nothing to do with the actual bug and disappeared
    once the CPU decoder was switched back for a plain (non-debugger) repro. Do not diagnose from a
    single register snapshot without following it up against an independent, from-scratch
    re-verification (as in finding 7) — this session had a false-positive "crypto is broken" read
    from live registers that a direct offline recheck immediately disproved.
11. **The full flow works end to end, live-confirmed 2026-07-31: checkver → relnote → `.inf` →
    confirmation dialog → HTTP Download → completion → release note display.** After the zlib fix
    (finding 7), a real client showed the confirmation dialog for the first time, offered a choice
    of Peer-to-Peer (recommended) or HTTP Download, and HTTP Download completed immediately against
    our 32-byte stub payload — no BitTorrent tracker needed, confirming the plain-HTTP-fallback
    path (`%s/%u.%u.%u/%s` from checkver's second base-URL string) is what the client actually
    uses when P2P isn't chosen. Two small cosmetic follow-ups, both **fixed 2026-07-31**:
    - The confirmation dialog read **"An update (Ver. 0.00) has been uploaded"** instead of a real
      version number. Traced to `checkver.html`'s `T+3` field, previously assumed opaque — it's a
      packed TO version (`major<<24 | minor<<16 | revision`, same packing the client's own record
      parser builds at `0xBB766C`), read by the dialog's `"Ver. %d.%02d"` formatter (`0xBB5150`)
      *and* by a post-dialog state-machine check (`0x95CD7C`) that diverts the screen-state
      advance from `+2` to `+1` on a mismatch against the record's own parsed TO version — not
      purely cosmetic, though the flow completed anyway with it zeroed. `build_checkver_stub.py`
      now sends the real packed `TO_VERSION`; see `ADDRESSES.md` §12 for the full trace.
    - `relnote.txt`'s content, rendered via the "display update details" triangle prompt, ran off
      the bottom of the screen. The update screen word-wraps and paginates the body (`ADDRESSES.md`
      §12: up to 62 lines, 5 shown at a time with scroll arrows) — the original single
      82-character sentence apparently didn't render cleanly within that. `build_relnote()` now
      returns a handful of short, independently-safe lines instead of relying on the client's
      exact wrap width.
    **Both fixes live-confirmed 2026-07-31**: dialog now shows the real version, release note
    fits without scrolling off screen.

    **Peer-to-Peer, tested out of curiosity, 2026-07-31: crashed the client immediately** with no
    tracker implemented — unlike HTTP Download's clean rejection at the apply step, the client's
    torrent code path isn't defensive against "no tracker reachable." That gap motivated actually
    building the tracker + seeding peer (below) rather than leaving it as a known limitation.

    **A real BitTorrent tracker and seeding peer now exist, 2026-07-31**, in `dev/tools/
    build_torrent_stub.py` (bencode encoder, `.torrent` builder, shared info-dict/info_hash/
    piece-data computation) and `dev/runtime/bt_seed.py` (a BEP3 HTTP tracker on port 6969 and a
    genuine peer-wire protocol seed on port 6881 — handshake, bitfield, choke/unchoke, piece
    serving — both compose services, `probe-bt`). Not a stub reply: since the client links real
    Transmission, this had to speak the actual protocol. Verified against a hand-written
    simulated client before any live test: tracker announce returns a correct compact peer
    record, and a full handshake→bitfield→interested→unchoke→request→piece exchange returns the
    exact concatenated bytes of both stub payload files. `.torrent` is served over HTTP
    byte-identical to what `build_torrent_stub.py` wrote. Live re-test with a real client
    pending — see the quickstart in §0 for how to run it.

    **Live-tested 2026-07-31: the tracker/seed implementation is correct; the remaining blocker
    looks like an RPCS3 network-emulation gap, not a server bug.** The client:
    - Fetches the `.torrent` and parses it correctly — confirmed by RPCS3's own log deriving the
      *exact* `info_hash` we compute (`d16a72667fbe0d1679348c85498b45d66a1b4a4f`) to build a
      resume-file path (`sys_fs_open(".../resume.d16a72667fbe0d1679348c85498b45d66a1b4a4f-dl")`).
    - Genuinely calls `sys_net_bnet_connect` to `192.168.1.200:6969` (RPCS3's own log: `[Native]
      Attempting to connect on 192.168.1.200:6969`).
    - **The TCP handshake actually completes** — confirmed independently of our own code via
      `ss -tn` on the host, which showed a real `ESTABLISHED 192.168.1.200:6969 <-> 192.168.1.100:*`
      connection, and via accept-level logging added to `bt_seed.py`'s tracker (mirroring the fix
      to `http_probe.py`'s HEAD-request blind spot: log every accepted connection, not just ones
      that parse as valid requests) — `accepted connection from 192.168.1.100:*` fires reliably,
      repeatedly, across multiple separate connection attempts and a full client restart.
    - **But no HTTP request ever follows.** Every real qBittorrent connection on this same host
      (unrelated local traffic, useful as a control) shows `accepted connection` immediately
      followed by `GET /announce?...`. Every connection from the real client shows only the
      accept — the socket sits open, `ss` reporting zero bytes queued in either direction, until
      it's eventually abandoned.
    - RPCS3's log shows why, most likely: after each `connect()` returns `EINPROGRESS` (correct,
      expected for a non-blocking connect), the game polls `sys_net_infoctl(cmd=8, ...)` in a
      tight ~20ms loop — and every single one of those calls is logged by RPCS3 itself as
      `sys_net TODO`, i.e. **unimplemented**. If `cmd=8` is (as the polling pattern strongly
      suggests) how the guest checks whether an in-progress non-blocking connect has completed,
      the game can never learn that its connection actually succeeded, even though it has —
      explaining a real, fully-open, doing-nothing TCP socket precisely.
    - Also opens **two sockets in immediate succession** (0.3ms apart) to the same destination
      before ever polling for completion — consistent with giving up on believing the first
      connect finished and trying again, rather than a deliberate parallel-connect strategy.
    **Conclusion**: this project's tracker + seeding peer are provably correct — verified against
    both a hand-written simulated client (full handshake -> bitfield -> piece exchange) and now a
    real client reaching the TCP-established stage with the exact right `info_hash` and address.
    The remaining gap is outside this project: RPCS3's own `sys_net` emulation doesn't appear to
    implement whatever `sys_net_infoctl(cmd=8)` is for, so the game never recovers from a
    non-blocking connect. Not something fixable from `dev/runtime/bt_seed.py` or any other
    server-side change. Worth reporting upstream to RPCS3 if real P2P testing matters later; out
    of scope for this project to fix directly.

    The original goal of this investigation — exercising the real auto-patch protocol end to end
    against a real client with placeholder payload bytes — is met.

    **The natural stopping point**: hitting X to apply/continue after the download and release-note
    screen produces the generic error dialog again — expected, and not a protocol bug. The stub
    payload is 32 bytes of placeholder text, not a structurally valid patch package, so the
    install/apply step rejecting its *content* is the correct outcome. Building a real installable
    payload would require reverse-engineering the patch-package format itself, which is a separate
    problem from the network protocol this investigation set out to validate, and was explicitly
    out of scope from the start (§3/§4 — no real Konami patch content is recoverable, and this was
    never going to be a stub with genuinely installable content).
