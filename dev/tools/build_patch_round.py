"""Builds ONE round of a real 1.0 -> 1.36 upgrade, from the genuine 1.36 archive.

This is `build_inf_stub.py` with real content instead of 32-byte placeholders. Everything about
the crypto and the .inf layout is unchanged and is imported from there -- what is new here is
*what goes in the entry list* and *what gets served as the payload*.

WHY ROUNDS, AND WHAT IS ACTUALLY BOUNDED. 31 entries per record is a checked bound
(0xBB8AE4/0xBB8BB0), corroborated by the array shape: obj+1072, stride 16, memset of 512 bytes,
count at obj+1584 = 1072 + 16*32. That much is tier-1. The checkver reply's 8-record limit is an
*unchecked* buffer limit, and whether records multiply the entry cap or share that one 512-byte
array is NOT established -- if they share it the real ceiling is 31, not 248. Do not quote 248 as
a fact; it has never been tested against a client, and no .inf with more than one entry ever has.
`--part`/`--parts` exist to split a selection when we find out where the wall really is.

VERSION STAMPS ARE A SELECTOR, NOT A LADDER. Every file in the manifest carries the version it was
last published in (1.01, 1.10, ... 1.36), but the archive is a single SNAPSHOT at 1.36 -- a file
stamped 1.12 is one untouched since 1.12, not a copy of how the archive looked then. The
intermediate states are not reconstructible from what we have, so this script never authors one.
`--level` is purely a convenient way to name a small real subset for testing.

SIZES. The .inf declares the size we actually serve, i.e. the ON-DISK size. For 424 of the 660
files that is the manifest's size + 24, because they are stored in the path-keyed asset-cipher
container (CRYPTO.md; the overhead is a constant 24, not variable PKCS#7 -- see
dev/analysis/dl_manifest_format.md). The manifest's own `size` field is the *plaintext* length and
is a different field with a different job; do not cross the two.

WHAT IS NOT KNOWN, AND WHAT THIS SCRIPT IS FOR. Nothing traced in MGO2.elf moves a file out of
the staging directory `dl/p/ar/`, and nothing writes `dl/.p` (the DLT2 reader opens it read-only,
li r5,0 at 0xD6378C; ptsys's own installer exists but is dead code in the disc build -- both its
DLTB parser and its update path are unreachable, see BUILD_1_36.md / the ptsys passes). So the
apply step is *not* readable from our tier-1 artifact, and this script exists to answer it by
experiment instead: serve a real round, watch where the bytes land. `--include-manifest` adds an
entry named `.p` for exactly that reason -- where a manifest-named entry is written is the single
most informative observation available, and it costs one entry.
"""
import argparse
import hashlib
import hmac
import os
import pathlib
import shutil
import struct
import zlib

import build_checkver as checkver
import build_inf_stub as inf

# dev/analysis/dl_manifest_format.md -- proven on 258 payloads, zero false positives.
# Same 16 bytes as build_inf_stub.ELF_HMAC_KEY; MGO2.elf VA 0xE26D78.
PTSYS_KEY = bytes.fromhex("9357a9dfb8eb8d03b843cd025f2a30ce")

# The reference tree mirrors the INSTALL TARGET, so its root is the game's `o/` directory:
# `o/MGO2.SELF` next to `o/dl/.p` and `o/dl/p/...`. That is the layout a completed patch leaves on
# the HDD, which makes "what should be where" readable straight off the directory rather than from
# a mapping table -- and it is why the `..N/` names in PLACEMENT are what they are.
DEFAULT_TREE = pathlib.Path(__file__).parent.parent / "PATCHES" / "PATCH 1.36" / "o"

MAX_ENTRIES_PER_RECORD = 31   # 0xBB8AE4 / 0xBB8BB0, a checked bound
MAX_RECORDS = 8               # unchecked buffer limit on the checkver reply

# AN ARCHIVE HOLDS MANY FILES, AND THAT IS THE WHOLE POINT OF THE TWO SCANS.
#
# Scan B names what to DOWNLOAD; scan A names what to EXTRACT from it. They are different lists
# with different strides for exactly this reason, and the real 1.36 patch proves the shape: 659
# files in the tree, but the operator's directory listing has only TWO downloadable payloads. So
# one archive carries many members, and the members are laid end to end after the hdr[4] prefix:
#
#     plaintext = hdr[4] prefix (whose scan A lists every member, in order)
#                 || member[0] bytes || member[1] bytes || ...
#
# The installer walks scan A and reads each member's declared size off the same open stream, so
# the concatenation order and the scan-A order have to agree. `Archive.members` below is that
# ordered list -- [(name_once_extracted, source_path)] -- and it is the same list the .inf's scan
# A is generated from, so the two cannot drift.
#
# CONFIRMED LIVE 2026-08-03: a 660-member archive installed against a real client, every file
# byte-perfect, with the client creating the eight missing subdirectories itself along the way.
# What that round got WRONG was placement, not packing -- see PLACEMENT below.


def encrypt_container(plaintext, keyspec):
    """Blowfish-CBC the archive body, same construction the .inf uses.

    CONFIRMED tier-1 on 2026-08-03, upgrading this from the guess it was written as. Phase 2's
    per-group body fetches the key itself: 0xBBAD3C calls the keystore singleton (0xD64498) and
    0xBBAD70 invokes vtable +4, `get(slot=7, dest)`, into a stack buffer, and that same buffer is
    r5 to the Blowfish-CBC stream constructor at 0xBBADE0 (0xD66CF0). So the key really is
    keystore slot 7 -- the .inf's own stage-2 material, `get()`-decrypted -- and the 8+56 IV/key
    split is the one 0xD66CF0 already documents. `slot7` is now the evidenced default, not a
    hypothesis.
    """
    from Crypto.Cipher import Blowfish
    blob = checkver.SLOT7_KEY if keyspec == "slot7" else bytes.fromhex(keyspec)
    if len(blob) != 64:
        raise SystemExit(f"--encrypt wants a 64-byte key blob, got {len(blob)}")
    pad = 8 - (len(plaintext) % 8)
    padded = plaintext + bytes([pad]) * pad
    return Blowfish.new(blob[8:64], Blowfish.MODE_CBC, blob[0:8]).encrypt(padded)


# WHERE A MEMBER LANDS IS DECIDED BY ITS NAME, not by its flags byte.
#
# 0xBB5510 builds the output path, and its FIRST instruction tests the name's first byte against
# '.' (0xBB552C). The escape it guards, at 0xBB5678, is:
#
#     ".." <digit N> "/" <rest>          N checked <= 3 at 0xBB56B0
#
# On a match it builds `<device root> + "dl/p/"` and then walks backwards erasing characters until
# it has eaten N slashes, then strcat's <rest>. So N is "go up N directory levels from dl/p/".
# Anything not matching that exact four-byte shape -- including a name that merely starts with a
# dot, like ".p" (name[1] is 'p', not '.') -- falls through to the plain `"dl/p/" + name`.
#
# That is why the first full round installed correctly and still booted 1.0: every member went to
# dl/p/, including the two that must not. Measured against the observed base of USRDIR/o/dl/p/:
#
#     "..2/MGO2.SELF"  ->  o/MGO2.SELF   (the executable the loader actually picks up)
#     "..1/.p"         ->  o/dl/.p       (where the archive reader opens it, ADDRESSES.md Sec 12)
#
# The data tree keeps plain names, because dl/p/ IS its home.
PLACEMENT = {"MGO2.SELF": "..2/MGO2.SELF", ".p": "..1/.p"}


def placed(name, args):
    return PLACEMENT.get(name, name) if not args.no_place else name


def destination(name):
    """Where a scan-A name actually lands, for the build log."""
    if len(name) > 4 and name[:2] == ".." and name[2].isdigit() and name[3] == "/":
        return "/".join(["o", "dl", "p"][:3 - int(name[2])] + [name[4:]])
    return f"o/dl/p/{name}"


def scan_a_of(members):
    """The scan-A rows for an archive's members: [(name once extracted, size, flags)]."""
    return [(inner, path.stat().st_size, inf.DEFAULT_SCAN_A_FLAGS) for inner, path in members]


class CountingSink:
    """Swallows the container so --dry-run reports real sizes without touching the docroot."""

    def write(self, data):
        return len(data)


def build_container(sink, members, args):
    """The served payload, whole: deflate -> Blowfish-CBC -> append HMAC-MD5.

    THE ORDER IS THE READ CHAIN RUN BACKWARDS, and every link of that chain is read out of the
    installer's per-group body (0xBBACCC-0xBBAE3C), so this is tier-1 rather than inference:

        file  ->  0xD652E0 HMAC filter  ->  0xD66CF0 Blowfish-CBC  ->  zlib inflate  ->  read

    The last link is the one this project missed for a full session, and it is invisible from
    outside. The stack object built at r1+1816 (vptr 0xFB1D80) is a zlib inflate stream: its
    vtable +0 (0x288778) is `open`, which forwards down to the file, and its +8 (0x2884F8) is
    `read`, which drives zlib's own `inflate()` at 0xD2DB04. Any inflate error returns **-1**
    (0x288764) -- and at 0xBBAEEC a read of <= 0 simply falls out of the compare loop with no
    error state set, so an uncompressed payload downloads, MACs, and then silently installs
    nothing. Identical in shape to the `.inf`'s own stage 2b, which cost an earlier round.

    The HMAC filter in THIS chain strips but does not verify: 0xBBADC0 passes key=NULL (which the
    ctor turns into 64 zero bytes at 0xD65528) and flag=1. The 16-byte holdback is unconditional
    -- the lookahead buffer at this+300 is maintained at 0xD661C8-0xD66218, ahead of any test of
    the flag -- and the flag byte at +321 only selects, at 0xD66354/0xD66378, whether those bytes
    are fed to MD5 and compared or merely counted. Phase 1 already verified the trailer, so phase
    2 strips it and moves on. The useful consequence: Blowfish sees exactly the ciphertext, so the
    PKCS#7 padding really is the last thing in its stream and the pad check at EOF is clean.

    IT IS WRITTEN AS A STREAM, not assembled in memory, because the real generic archive is the
    2 GB data tree. Holding that whole and then deflating, encrypting and verifying it would want
    four simultaneous copies; this keeps the peak at one CHUNK regardless of archive size. The
    plaintext's MD5 is accumulated on the way past so the verify pass can confirm the round-trip
    without ever materialising it either.
    """
    prefix = inf.build_prefix(scan_a_of(members))
    plain_md5, mac = hashlib.md5(), hmac.new(bytes.fromhex(args.mac), digestmod=hashlib.md5)
    cipher = carry = None
    if args.encrypt:
        from Crypto.Cipher import Blowfish
        blob = checkver.SLOT7_KEY if args.encrypt == "slot7" else bytes.fromhex(args.encrypt)
        if len(blob) != 64:
            raise SystemExit(f"--encrypt wants a 64-byte key blob, got {len(blob)}")
        cipher, carry = Blowfish.new(blob[8:64], Blowfish.MODE_CBC, blob[0:8]), b""
    deflate = None if args.no_compress else zlib.compressobj(args.zlib_level)
    written = 0

    def emit(data, final=False):
        """One hop down the chain: deflate output -> Blowfish -> HMAC -> the file."""
        nonlocal carry, written
        if cipher is None:
            if data:
                mac.update(data); sink.write(data); written += len(data)
            return
        buf = carry + data
        if final:
            # PKCS#7 on the CBC layer, checked as 1..8 at 0xD6570C -- 0 is rejected, so an
            # already-aligned stream still needs a full block of 08.
            pad = 8 - (len(buf) % 8)
            buf += bytes([pad]) * pad
            carry = b""
        else:
            cut = len(buf) - (len(buf) % 8)
            buf, carry = buf[:cut], buf[cut:]
        if buf:
            block = cipher.encrypt(buf)
            mac.update(block); sink.write(block); written += len(block)

    def feed(data, final=False):
        plain_md5.update(data)
        emit(deflate.compress(data) if deflate is not None else data)
        if final:
            emit(deflate.flush() if deflate is not None else b"", final=True)

    feed(prefix)
    for _, path in members:
        with open(path, "rb") as handle:
            while True:
                chunk = handle.read(1 << 20)
                if not chunk:
                    break
                feed(chunk)
    feed(b"", final=True)
    # Phase 1 MACs the file exactly as served, so the MAC covers everything before it.
    tag = mac.digest()
    sink.write(tag)
    return written + 16, plain_md5.digest(), len(prefix)


def verify_container(name, path, expected_md5, expected_prefix, args):
    """Replay the client's own read chain over the file we just wrote; refuse to ship if it differs.

    This closes the exact gap that made an earlier round unfalsifiable: every stage of that chain
    fails SILENTLY on the client, so an offline replay is the only place a layering mistake
    announces itself. Streamed for the same reason the build is -- the 2 GB archive is never held
    whole -- so what it compares is the plaintext's MD5 and its leading hdr[4] bytes, the two
    things that decide the 0xBBAE70 memcmp and the extraction.
    """
    size = path.stat().st_size
    mac = hmac.new(bytes.fromhex(args.mac), digestmod=hashlib.md5)
    inflate = None if args.no_compress else zlib.decompressobj()
    plain_md5, head, remaining = hashlib.md5(), bytearray(), size - 16
    cipher = None
    if args.encrypt:
        from Crypto.Cipher import Blowfish
        blob = checkver.SLOT7_KEY if args.encrypt == "slot7" else bytes.fromhex(args.encrypt)
        cipher = Blowfish.new(blob[8:64], Blowfish.MODE_CBC, blob[0:8])
    with open(path, "rb") as handle:
        while remaining:
            block = handle.read(min(1 << 20, remaining))
            if not block:
                raise SystemExit(f"{name}: file ended {remaining} bytes early")
            remaining -= len(block)
            mac.update(block)
            plain = cipher.decrypt(block) if cipher is not None else block
            if cipher is not None and not remaining:
                pad = plain[-1]
                if not 1 <= pad <= 8 or plain[-pad:] != bytes([pad]) * pad:
                    raise SystemExit(f"{name}: PKCS#7 padding is not what 0xD6570C accepts")
                plain = plain[:-pad]
            out = inflate.decompress(plain) if inflate is not None else plain
            plain_md5.update(out)
            if len(head) < len(expected_prefix):
                head += out[:len(expected_prefix) - len(head)]
        if mac.digest() != handle.read(16):
            raise SystemExit(f"{name}: phase-1 MAC does not verify against its own body")
    if bytes(head) != expected_prefix:
        raise SystemExit(f"{name}: the archive's leading hdr[4] bytes are not the .inf's -- "
                         f"0xBBAE70 would reject this")
    if plain_md5.digest() != expected_md5:
        raise SystemExit(f"{name}: the read chain does not reproduce the plaintext")


def ptsys_digest(payload):
    return hmac.new(PTSYS_KEY, payload, hashlib.md5).digest()


# --------------------------------------------------------------------------- manifest parsing

class Entry:
    __slots__ = ("name", "parent", "flags", "version", "size", "digest", "index")

    def __init__(self, index, name, parent, flags, version=None, size=None, digest=None):
        self.index, self.name, self.parent, self.flags = index, name, parent, flags
        self.version, self.size, self.digest = version, size, digest

    @property
    def is_dir(self):
        return bool(self.flags & 0x01)


def parse_manifest(path):
    return parse_manifest_bytes(pathlib.Path(path).read_bytes(), str(path))


def parse_manifest_bytes(data, path="<bytes>"):
    """Layout per dev/analysis/dl_manifest_format.md. Big-endian throughout."""
    if data[:4] != b"DLT2":
        raise SystemExit(f"{path}: not a DLT2 manifest")
    header = data[:0x29]
    offset, entries = 0x29, []
    while offset < len(data):
        end = data.index(b"\x00", offset)
        name = data[offset:end].decode("ascii")
        offset = end + 1
        parent, flags = struct.unpack_from(">HB", data, offset)
        offset += 3
        if flags & 0x01:
            entries.append(Entry(len(entries), name, parent, flags))
            continue
        version, size = struct.unpack_from(">II", data, offset)
        digest = data[offset + 8:offset + 24]
        offset += 24
        entries.append(Entry(len(entries), name, parent, flags, version, size, digest))
    return header, entries


def entry_path(entries, entry):
    if entry.parent == 0xFFFF:
        return entry.name
    return entry_path(entries, entries[entry.parent]) + "/" + entry.name


def version_word(text):
    """'1.36' -> 0x01240000. The minor byte is plain binary printed as %d, NOT BCD."""
    major, minor = (int(part) for part in text.split("."))
    return (major << 24) | (minor << 16)


def version_text(word):
    return f"{word >> 24}.{(word >> 16) & 0xFF:02d}"


# --------------------------------------------------------------------------- manifest authoring

def build_manifest(header, entries, selfe_digest=None, selfe_size=None):
    """Re-emit the FULL 1.36 manifest, substituting only the MGO2.SELF entry.

    This is deliberately not parameterised by version. The archive is one snapshot, so the only
    honest manifest to author is the 1.36 state it actually describes; anything else would declare
    1.36-era digests under an older version word. Every entry is carried over byte for byte --
    including each file's own version stamp and its digest, which are already correct for exactly
    these payload bytes.

    The one substitution is MGO2.SELF, which the archive declares (size 19,615,992, digest
    70f524dd...) but does not contain. We ship the patched .self, the only 1.36 executable that
    exists here (BUILD_1_36.md), so we declare its real digest. That is sound because the manifest
    digest is a checksum under a key resident in the ELF (0xE26D78), not a signature -- authoring
    the manifest means authoring what it claims.

    The header digest covers [0x14 .. EOF] and is recomputed. Header fields other than the digest
    are preserved, so the version word stays 0x01240000 and the five NUL-terminated strings
    (whose blanks mean "default to the previous field" -- see the ptsys parser at 0xD63BF0) are
    passed through untouched.
    """
    body = bytearray()
    for entry in entries:
        body += entry.name.encode("ascii") + b"\x00"
        body += struct.pack(">HB", entry.parent, entry.flags)
        if entry.is_dir:
            continue
        digest, size = entry.digest, entry.size
        if entry.name == "MGO2.SELF" and selfe_digest is not None:
            digest, size = selfe_digest, selfe_size
        body += struct.pack(">II", entry.version, size) + digest

    tail = header[0x14:0x29] + bytes(body)
    return b"DLT2" + ptsys_digest(tail) + tail


# --------------------------------------------------------------------------- round assembly

def link_or_copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        target.unlink()
    try:
        os.link(source, target)          # same filesystem: no second copy of 2 GB
    except OSError:
        shutil.copy2(source, target)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tree", type=pathlib.Path, default=DEFAULT_TREE,
                    help="the extracted 1.36 archive (holds dl/.p, dl/p/, MGO2.self)")
    ap.add_argument("--level", required=True,
                    help="the rung to ship, e.g. 1.12 -- every file stamped with that version")
    ap.add_argument("--part", type=int, default=None,
                    help="1-based part number, for rungs above the 248-file ceiling")
    ap.add_argument("--parts", type=int, default=1)
    ap.add_argument("--include-manifest", action="store_true",
                    help="add an entry named '.p' carrying the authored manifest (see module doc)")
    ap.add_argument("--include-self", action="store_true",
                    help="add MGO2.SELF, served from the tree root")
    ap.add_argument("--self-file", type=pathlib.Path, default=None,
                    help="serve this file as the executable payload instead of the tree's "
                         "MGO2.self -- e.g. the disc's genuine SCE\\0-signed MGO2.SELF, to test "
                         "whether the client's post-download reader rejects an unsigned raw ELF")
    ap.add_argument("--blob", action="store_true",
                    help="authentic shape: ONE downloadable archive per record, named after the "
                         "record itself -- BLUS30109.<from>to<to> carries MGO2.SELF, <from>to<to> "
                         "carries the data tree. What --data puts inside the second one.")
    ap.add_argument("--data", choices=("manifest", "root", "all"), default="manifest",
                    help="what the generic archive carries, on top of the manifest .p. "
                         "'manifest' (default) is .p alone -- the proven single-member round. "
                         "'root' adds the five files sitting directly under dl/p/, which needs no "
                         "directories to exist. 'all' adds the whole 659-file tree, which needs "
                         "eight subdirectories the client CANNOT create (it calls mkdir nowhere).")
    ap.add_argument("--mac", nargs="?", const=PTSYS_KEY.hex(), default=None, metavar="KEYHEX",
                    help="append the 16-byte HMAC-MD5 trailer the installer verifies (see MAC_KEY). "
                         "Optional argument is the key in hex; the default is the ptsys key, on "
                         "the hypothesis that slot 8 returns it zero-padded to HMAC's 64-byte block")
    ap.add_argument("--encrypt", nargs="?", const="slot7", default=None, metavar="KEYHEX",
                    help="Blowfish-CBC encrypt the container before appending the MAC, which "
                         "phase 2's decrypt filter (0xBBADE0) requires. Optional "
                         "argument is a 64-byte key blob in hex (first 8 = IV, next 56 = key), "
                         "matching the .inf's slot-7 layout; the default reuses the slot-7 key. "
                         "Implies --container.")
    ap.add_argument("--no-compress", action="store_true",
                    help="serve the container body UNCOMPRESSED. The client always stacks a zlib "
                         "inflate filter (vtable 0xFB1D80, read 0x2884F8 -> inflate 0xD2DB04) on "
                         "top of the Blowfish one, so this cannot work -- inflate returns -1 on "
                         "the first read and the installer silently extracts nothing. Kept only "
                         "as the A/B control for that finding; do not ship a round with it.")
    ap.add_argument("--container", action="store_true",
                    help="wrap each payload as `hdr[4] prefix || content` so the archive's first "
                         "hdr[4] bytes match the .inf's, which 0xBBAE70 memcmps. Implies --mac.")
    ap.add_argument("--no-place", action="store_true",
                    help="emit MGO2.SELF and .p as plain names, so they land in dl/p/ like "
                         "everything else. That is where the first full round put them, and it "
                         "is why the client still booted 1.0 -- the loader reads o/MGO2.SELF and "
                         "the archive reader opens o/dl/.p. Kept as the A/B control for the "
                         "'..N/' name grammar at 0xBB5678.")
    ap.add_argument("--zlib-level", type=int, default=6,
                    help="deflate level (default 6). The 2 GB tree is mostly already-compressed "
                         "audio and packs, so 1 costs almost no ratio and a lot less time.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not checkver.PATCH_ENABLED:
        raise SystemExit(f"MGO2SERVER_CLIENT_VERSION={checkver.CLIENT_VERSION} -- refusing to build a\n"
                         "live round while serving 1.0. The patch is tied to the served build:\n"
                         "set MGO2SERVER_CLIENT_VERSION=1.36. While serving 1.0 the checkver reply\n"
                         "must stay the client's own 0x00 'no update' byte.")

    # `dl/.p` is the base. The operator keeps Konami's pristine copy alongside it as
    # `.p.original.bak`, and the two are NOT interchangeable as artifacts: the original declares
    # the stock 1.36 SELF (ptsys digest 70f524dd...), while the SELF this project installs is a
    # modified build (c3883975...). What makes the choice safe is that re-authoring from either
    # produces BYTE-IDENTICAL output -- verified 2026-08-03 -- because MGO2.SELF's digest and size
    # are exactly the fields build_manifest() substitutes, and nothing else differs between them.
    manifest_path = args.tree / "dl" / ".p"
    payload_root = args.tree / "dl" / "p"
    header, entries = parse_manifest(manifest_path)
    print(f"manifest base: {manifest_path.name}")

    level_word = version_word(args.level)
    rung = [e for e in entries if not e.is_dir and e.version == level_word
            and e.name != "MGO2.SELF"]
    rung.sort(key=lambda e: entry_path(entries, e))

    if args.part is not None:
        chunk = (len(rung) + args.parts - 1) // args.parts
        rung = rung[(args.part - 1) * chunk: args.part * chunk]

    # The tree names it MGO2.SELF (as installed); older copies used MGO2.self.
    self_source = args.self_file or next(
        (p for p in (args.tree / "MGO2.SELF", args.tree / "MGO2.self") if p.is_file()),
        args.tree / "MGO2.SELF")
    self_digest = self_size = None
    if args.include_self:
        self_bytes = self_source.read_bytes()
        self_digest, self_size = ptsys_digest(self_bytes), len(self_bytes)

    authored = build_manifest(header, entries, self_digest, self_size)

    # ---- the entry list, with the sizes we will actually serve
    served = []
    for entry in rung:
        relative = entry_path(entries, entry)
        source = payload_root / relative
        if not source.exists():
            print(f"  SKIP (absent on disk): {relative}")
            continue
        served.append((relative, [(relative, source)], source.stat().st_size))
    if args.include_self:
        served.append(("MGO2.SELF", [("MGO2.SELF", self_source)],
                       self_source.stat().st_size))

    manifest_target = None
    if args.include_manifest:
        manifest_target = args.tree / "dl" / f".p.round-{args.level}"
        manifest_target.write_bytes(authored)
        served.append((".p", [(".p", manifest_target)], len(authored)))

    if len(served) > MAX_ENTRIES_PER_RECORD * MAX_RECORDS:
        raise SystemExit(f"{len(served)} entries exceeds the {MAX_ENTRIES_PER_RECORD * MAX_RECORDS} "
                         f"ceiling ({MAX_ENTRIES_PER_RECORD}/record x {MAX_RECORDS} records) -- "
                         f"use --part/--parts")

    # --blob: replicate what Konami actually shipped, rather than what the format permits.
    #
    # The payload URL is "%s/%u.%u.%u/%s" with the final %s taken from the .inf ENTRY NAME, so the
    # observed payload files being named exactly the record text ("BLUS30109.1.0.0to1.36.0",
    # "1.0.0to1.36.0" -- the operator's directory listing) forces one conclusion: each real .inf
    # declared exactly ONE entry, whose name was the record text. Not an inference from a
    # filename; the format string leaves no other way to produce those names.
    #
    # The observed size split then reads cleanly. The disc-qualified payload is ~17 MB and the
    # generic one is much larger, which fits the executable being disc-specific (BLUS30109 /
    # BLES00246 / BLJM67001 are three separately signed SELFs -- that product-id triple is in
    # 1.36's own string block) while the data tree is shared. This also explains Sec 6's
    # "significantly smaller" disc-qualified payload, recorded there as unexplained.
    #
    # So: record 0 carries the executable, record 1 carries the manifest. The real generic blob
    # was presumably a container holding the data tree, whose format we do not have -- using the
    # authored .p in its place still exercises the naming and the install path, which is what is
    # actually under test here.
    if args.blob:
        from_s_, to_s_ = (checkver.version_text(checkver.FROM_VERSION),
                          checkver.version_text(checkver.TO_VERSION))
        if manifest_target is None:
            manifest_target = args.tree / "dl" / ".p.authored"
            manifest_target.write_bytes(authored)

        # The generic archive's members: the manifest first, then whatever slice of the data tree
        # --data asks for. `.p` leads because the real install has it, and because it is the one
        # member whose landing place we already know is wrong (it goes to dl/p/.p, while the
        # archive reader opens dl/.p) -- keeping it in every round keeps that visible.
        data_members = [(placed(".p", args), manifest_target)]
        if args.data != "manifest":
            pool = sorted(p for p in payload_root.rglob("*") if p.is_file())
            if args.data == "root":
                pool = [p for p in pool if p.parent == payload_root]
            data_members += [(str(p.relative_to(payload_root)).replace(os.sep, "/"), p)
                             for p in pool]

        served = [(f"{checkver.DISC_ID}.{from_s_}to{to_s_}",
                   [(placed("MGO2.SELF", args), self_source)], self_source.stat().st_size),
                  (f"{from_s_}to{to_s_}", data_members,
                   sum(p.stat().st_size for _, p in data_members))]

    # THE INSTALLER VERIFIES AN HMAC-MD5 TRAILER, AND THAT IS WHY EVERY ROUND SO FAR WAS DELETED.
    #
    # Read from the disc build 2026-08-03. The install phase re-opens the staged payload read-only
    # (0xBB5028 builds "dl/p/ar/<name>", 0x280F0 opens it O_RDONLY) and streams it through a
    # verifier constructed at 0xD652E0 with vptr 0xFBBDA0:
    #
    #   open  0xD65B08 -- builds the HMAC ipad/opad blocks (xori 0x36 / 0x5C at 0xD65FE4), then
    #                     prefetches exactly 16 bytes and FAILS unless it gets them (0xD66088)
    #   read  0xD660F0 -- a 16-byte delay line: it emits the bytes it held, refills, and hashes
    #                     only what it emitted. So the final 16 bytes are never hashed and never
    #                     delivered -- they ARE the expected MAC.
    #   check 0xD66580 -- memcmp(computed, trailer, 16); on mismatch 0xD6659C sets flag bit 3 and
    #                     read returns -1, the installer's 0xBBA7A4 takes the failure branch, and
    #                     0xBBACB4 sets state 10. It returns BEFORE the phase that would create
    #                     dl/p/ar/t/0/, which is why that directory was never written.
    #
    # So the payload format is `plaintext || HMAC-MD5(K64, plaintext)`. There is no header, no
    # magic number and no length field -- the only structural requirement is a length of >= 16.
    # A signed SELF is not expected: no 53 43 45 00 compare exists anywhere in the reader, which
    # is what finally killed the "the .self is unsigned" theory.
    #
    # THE KEY IS `mgo2server_slot8`, CONFIRMED LIVE 2026-08-03, AND IT IS NOT KONAMI'S.
    #
    # K64 is fetched at runtime by singleton->vtable[1](8, buf) at 0xBBA6EC into a 64-byte stack
    # buffer at r1+8168; the singleton lives at 0x1698DA8, past the end of the file image, so it
    # cannot be read statically. A breakpoint at 0xBBA6F0 showed r22 -> the ASCII string
    # "mgo2server_slot8" (16 bytes; HMAC zero-pads it to its 64-byte block, so a 16-byte key is
    # exactly equivalent). Signing with it, a breakpoint at 0xD66588 then showed memcmp returning
    # r3 = 0 for BOTH served files -- computed HMAC at r1+112 identical to the trailer at r26+300,
    # 93df54af... for the executable and 7e90c973... for the manifest. Verification passes.
    #
    # THE HAZARD, AND IT IS THE IMPORTANT PART: that string is this project's own name. A 2008
    # retail binary cannot contain it, so the MGO2.SELF this client runs is NOT stock -- its
    # crypto slot provider is stubbed. Everything built under this key is therefore specific to
    # that modified executable. A stock client would demand Konami's real slot-8 key, which we do
    # not have and cannot recover from the disc build. Do not describe this as "the MGO2 patch
    # format key" anywhere; it is the key THIS client happens to ask for.
    #
    # The ptsys manifest key (0xE26D78) was tried first, on the theory that slot 8 might return it
    # zero-padded. It does not -- that round was rejected. Recorded so it is not retried.
    if args.encrypt:
        args.container = True
    if args.container and not args.mac:
        args.mac = PTSYS_KEY.hex()   # placeholder; --mac should be given explicitly
    # Containers are built and WRITTEN here, before the .inf, because a declared size can no
    # longer be computed ahead of time: deflate's output length is not a function of its input
    # length, and the archive is streamed rather than assembled. Scan B's size is what the client
    # downloads, so it has to be the real length of the bytes we serve -- write it, measure it,
    # then declare that. Scan A's size is untouched by any of this: it is the EXTRACTED length,
    # i.e. each member's own size, which is what the installer pulls out of the inflated stream.
    version_dir = checkver.DOCROOT / checkver.version_text(checkver.TO_VERSION)
    if args.mac:
        key = bytes.fromhex(args.mac)
        if args.container:
            if not args.dry_run:
                version_dir.mkdir(parents=True, exist_ok=True)
            sized = []
            for name, members, _ in served:
                target = version_dir / name
                if args.dry_run:
                    size, digest, prefix_len = build_container(CountingSink(), members, args)
                else:
                    with open(target, "wb") as handle:
                        size, digest, prefix_len = build_container(handle, members, args)
                    verify_container(name, target, digest,
                                     inf.build_prefix(scan_a_of(members)), args)
                    print(f"  built and verified {name} ({size:,} bytes)")
                sized.append((name, members, size))
            served = sized
        else:
            served = [(name, members, size + 16) for name, members, size in served]
        print(f"MAC: appending HMAC-MD5 under a {len(key)}-byte key"
              + (", declared sizes are the built container's actual length"
                 if args.container else ", declared sizes +16"))

    # EVERY RECORD THE REPLY ANNOUNCES MUST GET A REAL .inf. build_checkver.py always sends
    # two -- disc-qualified and generic, mirroring the real Konami tree -- and that two-record
    # shape is load-bearing: dropping to one was tested live and was reproducibly *worse*, the
    # client not even reaching relnote.txt (PATCH_INVESTIGATION.md Sec 7, finding 5). A record
    # with no .inf on disk is not a no-op either: http_probe.py answers any unknown path with its
    # generic fallback text and a 200, so the client receives 462 bytes of prose where ciphertext
    # should be. That is exactly the Sec 5a failure, and it is invisible from the server side.
    # So entries are spread across the announced records rather than packed into the first.
    announced = max(2, (len(served) + MAX_ENTRIES_PER_RECORD - 1) // MAX_ENTRIES_PER_RECORD)
    if announced > MAX_RECORDS:
        raise SystemExit(f"{len(served)} entries needs {announced} records, over the {MAX_RECORDS} "
                         f"the reply can announce -- use --part/--parts")
    records = [served[i::announced] for i in range(announced)]

    total = sum(size for _, _, size in served)
    inside = sum(len(members) for _, members, _ in served)
    print(f"round {args.level}: {len(served)} archive(s) carrying {inside} file(s), "
          f"{total / 1e6:.1f} MB on the wire, {len(records)} record(s) of "
          f"<= {MAX_ENTRIES_PER_RECORD}")
    # Round-trip: the authored manifest must re-parse and its header digest must verify, or we
    # are shipping something the client's own DLT2 reader (0xD63668, digest check 0xD640C4)
    # would discard with "ptsys:digest errror".
    if authored[:4] != b"DLT2" or ptsys_digest(authored[0x14:]) != authored[4:0x14]:
        raise SystemExit("authored manifest fails its own header digest -- refusing to ship")
    _, reparsed = parse_manifest_bytes(authored)
    if len(reparsed) != len(entries):
        raise SystemExit(f"authored manifest re-parses to {len(reparsed)} entries, "
                         f"expected {len(entries)}")
    declared = sum(1 for e in reparsed if not e.is_dir)
    print(f"authored manifest: {len(authored)} bytes, {declared} files declared, "
          f"header digest verifies, re-parses to {len(reparsed)} entries")
    for name, members, size in served:
        print(f"    {name:40} {size:>13,} on the wire, {len(members):>3} file(s) inside")
        for inner, path in members[:6]:
            print(f"        -> {destination(inner):<48} {path.stat().st_size:>12,}")
        if len(members) > 6:
            print(f"        -> ... and {len(members) - 6} more")

    if args.dry_run:
        return

    version_dir.mkdir(parents=True, exist_ok=True)

    from_s = checkver.version_text(checkver.FROM_VERSION)
    to_s = checkver.version_text(checkver.TO_VERSION)

    for index, record_entries in enumerate(records):
        # Record text mirrors the real Konami listing (PATCH_INVESTIGATION.md Sec 6); the client
        # appends a bare "inf" to it, so the trailing dot has to be in the text itself.
        # Must match build_checkver.record() exactly -- these are the strings the reply
        # announces, and the client builds both the .inf URL (<record>+"inf") and the payload URL
        # from them. No trailing dot: corrected 2026-08-03 against the real directory listing.
        stem = f"{checkver.DISC_ID}.{from_s}to{to_s}" if index == 0 else f"{from_s}to{to_s}"
        if index > 1:
            stem = f"{stem}.r{index}"

        # Scan A names the files to extract from THIS record's archive; scan B names the archive
        # itself. The disc-qualified record carries the executable, the generic one the data tree.
        # Scan A is the flattened member list, generated from the same `members` the container's
        # own prefix was built from, so the 0xBBAE70 memcmp cannot fail on a drift between them.
        scan_a = [row for _, members, _ in record_entries for row in scan_a_of(members)]
        inf_bytes = inf.build_inf([(name, size) for name, _, size in record_entries], scan_a)
        inf_path = version_dir / f"{stem}inf"   # no dot: the client format is "%sinf"
        inf_path.write_bytes(inf_bytes)
        print(f"wrote {inf_path} ({len(inf_bytes)} bytes, {len(record_entries)} archive(s), "
              f"{len(scan_a)} file(s) inside)")

        for name, members, _ in record_entries:
            target = version_dir / name
            if args.container:
                pass          # already streamed to disk and verified, above
            elif args.mac:
                # Written rather than linked: the served bytes are no longer the source bytes.
                plaintext = b"".join(path.read_bytes() for _, path in members)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(plaintext
                                   + hmac.new(bytes.fromhex(args.mac), plaintext, hashlib.md5).digest())
            else:
                link_or_copy(members[0][1], target)
    print(f"payloads staged under {version_dir}")


if __name__ == "__main__":
    main()
