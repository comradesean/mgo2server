# Auto-patch investigation — working notes

Session log for reconstructing the MGO2 auto-patch mechanism (`checkver.html` → `relnote.txt` →
`.inf` → `.torrent`/HTTP-fallback) and evaluating whether a self-hosted test patch is buildable.
The durable findings from this investigation already live in `ADDRESSES.md` §12 and `OBSERVED.md`
("Auto-patch — checkver.html and the update flow"); this file is the working narrative, including
evidence that doesn't belong in those two (fan-tool internals, in-progress stub design) and the
plan for the live test that hasn't happened yet.

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

Phases, in ascending order of risk:
1. `checkver.html` reply + `relnote.txt` — byte-exact known from the ELF, live-tested 2026-07-31,
   works.
2. `.inf` — **offline-verified, live acceptance still unconfirmed.** Three build rounds so far.
   Round 1 implemented a wrong pipeline model ("three Blowfish stages") and was rejected. Round 2
   corrected the pipeline (HMAC-verify → Blowfish-CBC → HMAC-verify, §5) and round-tripped clean,
   but was *also* rejected live — crypto right, plaintext layout wrong (two entry scans at
   different strides, entries start after the inner tag, not at offset 12). Round 3 fixed the
   layout; an opcode-faithful reference implementation (transcribing the actual disassembled
   instructions, not describing them in English) validated every stage against the real rejected
   bytes offline. **But that's a model of the client, not an observation of it** — a live retest
   with the same file still produced the same generic error (see phase 3), so the `.inf` itself is
   the leading remaining suspect again, specifically one of its two HMAC checks (§5), now that the
   alternative explanation below has been ruled out.
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
4. **In flight**: re-checking whether the checkver reply's two key blobs land in the keystore slots
   assumed (`T+7`→slot 7, `T+71`→slot 8) and whether `keystore->get()` returns those 64 bytes
   unmodified — a wrong slot mapping or a keystore-side transform would explain a `.inf` that's
   correct by our own model but still rejected live, and was flagged as unresolved by an earlier
   pass rather than eliminated.
5. Payload delivery — plain HTTP fallback (with `Range:` resume) is the far simpler route than
   standing up a working BitTorrent tracker for the `.torrent` path. Not started.
