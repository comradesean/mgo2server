#!/usr/bin/env python3
"""Parser for MGO2's download/patch manifest, ``USRDIR/o/dl/.p`` (magic ``DLT2``).

The manifest is what the game's patch subsystem -- it calls itself **ptsys** in its own log
strings -- reads to decide which files under ``USRDIR/o/dl/p/`` are missing or stale. It is a
flat, ordered array of records that encodes a directory tree by **parent index**, not by depth
bytes or terminators.

Everything below was read out of the bytes of the file itself and cross-checked against the
1,000-odd real files sitting in the sibling ``p/`` directory; see
``dev/analysis/dl_manifest_format.md`` for the evidence behind each field.

Usage::

    python3 dev/tools/parse_dl_manifest.py [path/to/.p] [-o out.txt]

With no arguments it reads the RPCS3 install path below and writes the dump to stdout.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import hmac
import os
import struct
import sys

DEFAULT_PATH = (
    "/mnt/d/rpcs3-v0.0.41-19598-357b7d44_win64_msvc/dev_hdd0/game/BLUS30109"
    "/USRDIR/o/dl/.p"
)

MAGIC = b"DLT2"

#: The digest key, 16 bytes at VA ``0xE26D78`` in ``MGO2.elf``. ``ADDRESSES.md`` records it as
#: "the 16-byte key used by the DLT2 archive's own digest check (``0xD640C4``-``0xD6410C``,
#: ``memcmp`` on mismatch -> ``ptsys:digest errror``)". The same 16 bytes head the ``.inf``
#: stage-3 HMAC key block at ``0xE20000``.
DIGEST_KEY = bytes.fromhex("9357a9dfb8eb8d03b843cd025f2a30ce")


def ptsys_digest(payload: bytes) -> bytes:
    """The manifest's digest function: HMAC-MD5 under :data:`DIGEST_KEY`.

    Verified byte-for-byte against 257 real entries plus the header -- see
    ``dev/analysis/dl_manifest_format.md``.
    """
    return hmac.new(DIGEST_KEY, payload, hashlib.md5).digest()

#: Offset of the first entry record. The header is fixed up to 0x1C and then carries a run of
#: NUL-terminated strings; 0x29 is where the string run ends on the one manifest we have.
HEADER_FIXED_END = 0x1C

FLAG_DIRECTORY = 0x01

# Fixed part of a leaf record, after the name and the 3-byte (parent, flags) prefix:
#   u32 BE version, u32 BE size, 16-byte digest
LEAF_TAIL = 4 + 4 + 16


class Entry:
    __slots__ = ("index", "offset", "name", "parent", "flags", "version", "size", "digest", "path")

    def __init__(self, index, offset, name, parent, flags):
        self.index = index
        self.offset = offset
        self.name = name
        self.parent = parent
        self.flags = flags
        self.version = None
        self.size = None
        self.digest = None
        self.path = name

    @property
    def is_dir(self) -> bool:
        return bool(self.flags & FLAG_DIRECTORY)


def _cstr(buf: bytes, pos: int):
    end = buf.index(b"\0", pos)
    return buf[pos:end].decode("ascii", "replace"), end + 1


def format_version(v: int) -> str:
    """Render the u32 version word.

    Observed values are all ``0x01XX0000``. Reading the second byte as a decimal number gives
    exactly the published MGO2 version ladder -- 0x0A -> 1.10, 0x14 -> 1.20, 0x1E -> 1.30,
    0x24 -> 1.36 -- and every observed value lands on a legal minor. That reading is inference,
    so the raw word is always printed alongside it.
    """
    major = (v >> 24) & 0xFF
    minor = (v >> 16) & 0xFF
    low = v & 0xFFFF
    s = f"{major}.{minor:02d}"
    if low:
        s += f"+{low:#06x}"
    return s


class Manifest:
    def __init__(self, data: bytes):
        if data[:4] != MAGIC:
            raise ValueError(f"not a DLT2 manifest: magic is {data[:4]!r}")
        self.data = data
        self.digest = data[0x04:0x14]
        self.version = struct.unpack_from(">I", data, 0x14)[0]
        self.timestamp = struct.unpack_from(">I", data, 0x18)[0]

        # Header string run. On the single manifest available this is:
        #   "" , ".p", "p", "", "patch"
        # The ptsys log strings name four per-entry fields -- flag, localpath, remotepath,
        # dispname -- so these are most likely the manifest's own equivalents. Which string is
        # which is NOT established; they are reported positionally.
        self.header_strings = []
        pos = HEADER_FIXED_END
        while len(self.header_strings) < 5:
            s, pos = _cstr(data, pos)
            self.header_strings.append(s)
        self.entries_offset = pos

        self.entries: list[Entry] = []
        self._parse_entries(pos)
        self._resolve_paths()

    @property
    def digest_ok(self) -> bool:
        """Recompute the header digest. It covers ``[0x14 .. EOF]`` -- version word onward."""
        return hmac.compare_digest(ptsys_digest(self.data[0x14:]), self.digest)

    def _parse_entries(self, pos: int):
        data = self.data
        n = len(data)
        while pos < n:
            offset = pos
            name, pos = _cstr(data, pos)
            parent, flags = struct.unpack_from(">HB", data, pos)
            pos += 3
            e = Entry(len(self.entries), offset, name, parent, flags)
            if not e.is_dir:
                if pos + LEAF_TAIL > n:
                    raise ValueError(f"truncated leaf record at {offset:#x} ({name})")
                e.version, e.size = struct.unpack_from(">II", data, pos)
                e.digest = data[pos + 8: pos + LEAF_TAIL]
                pos += LEAF_TAIL
            self.entries.append(e)
        self.end_offset = pos

    def _resolve_paths(self):
        for e in self.entries:
            if e.parent == 0xFFFF:
                e.path = e.name
            else:
                if e.parent >= e.index:
                    raise ValueError(f"forward parent index {e.parent} at entry {e.index}")
                p = self.entries[e.parent]
                if not p.is_dir:
                    raise ValueError(f"entry {e.index} parented to non-directory {p.name}")
                e.path = f"{p.path}/{e.name}"

    @property
    def dirs(self):
        return [e for e in self.entries if e.is_dir]

    @property
    def files(self):
        return [e for e in self.entries if not e.is_dir]

    def children(self, index):
        return [e for e in self.entries if e.parent == index]


def render(m: Manifest, path: str, payload_root: str | None = None) -> str:
    out = []
    w = out.append
    size = len(m.data)

    w("MGO2 download manifest (DLT2)")
    w("=" * 78)
    w(f"source        : {path}")
    w(f"file size     : {size} bytes ({size:#x})")
    w("")
    w("Byte order is BIG-endian throughout. The `14 00 00 00` run that looks like a")
    w("little-endian 20 is not a length prefix at all: it straddles two big-endian fields,")
    w("the low half of the version word and the high half of the size word. See")
    w("dev/analysis/dl_manifest_format.md.")
    w("")
    w("The digests are HMAC-MD5 (16 bytes, not 20) under the key")
    w(f"  {DIGEST_KEY.hex()}   (MGO2.elf VA 0xE26D78)")
    w("An entry's digest covers the file's PLAINTEXT bytes -- the decrypted form, whose length")
    w("is the size field. The header's digest covers the manifest from 0x14 to EOF.")
    w("")

    w("HEADER")
    w("-" * 78)
    w(f"  0x0000  4   magic          {m.data[:4].decode('ascii')!r}")
    w(f"  0x0004  16  digest         {m.digest.hex()}")
    w(f"                             HMAC-MD5 over [0x14 .. EOF]: "
      f"{'VERIFIED' if m.digest_ok else 'MISMATCH'}")
    w(f"  0x0014  4   version        {m.version:#010x}  -> {format_version(m.version)}")
    ts = _dt.datetime.fromtimestamp(m.timestamp, _dt.timezone.utc)
    w(f"  0x0018  4   timestamp      {m.timestamp:#010x}  -> {ts:%Y-%m-%d %H:%M:%S} UTC (if unix time)")
    pos = HEADER_FIXED_END
    for i, s in enumerate(m.header_strings):
        w(f"  {pos:#06x}  {len(s)+1:<3} string[{i}]      {s!r}")
        pos += len(s) + 1
    w(f"  {m.entries_offset:#06x}      first entry record")
    w("")

    w("SUMMARY")
    w("-" * 78)
    w(f"  entries          : {len(m.entries)}")
    w(f"  directories      : {len(m.dirs)}")
    w(f"  files            : {len(m.files)}")
    total = sum(e.size for e in m.files)
    w(f"  total file bytes : {total} ({total / 1024 / 1024:.1f} MiB)")
    vers = {}
    for e in m.files:
        vers[e.version] = vers.get(e.version, 0) + 1
    w("  version words seen (file count):")
    for v in sorted(vers):
        w(f"      {v:#010x}  {format_version(v):>6}   {vers[v]:4d}")
    flags = {}
    for e in m.entries:
        flags[e.flags] = flags.get(e.flags, 0) + 1
    w("  flag bytes seen (entry count):")
    for f in sorted(flags):
        note = "directory" if f & FLAG_DIRECTORY else "file"
        w(f"      {f:#04x}  {flags[f]:4d}   {note}")
    w("")

    w("FOLDER STRUCTURE")
    w("-" * 78)
    w("  (directories only; parent index in brackets)")

    def walk(idx, depth):
        for c in m.children(idx):
            if not c.is_dir:
                continue
            nfile = sum(1 for x in m.entries if x.parent == c.index and not x.is_dir)
            ndir = sum(1 for x in m.entries if x.parent == c.index and x.is_dir)
            w(f"  {'    ' * depth}{c.name}/   [{c.index}]  {nfile} files"
              + (f", {ndir} dirs" if ndir else ""))
            walk(c.index, depth + 1)

    walk(0xFFFF, 0)
    w("")

    w("ENTRIES")
    w("-" * 78)
    w("  off      idx  par   flg  version     size        digest")
    for e in m.entries:
        if e.is_dir:
            w(f"  {e.offset:#07x}  {e.index:3d}  {e.parent:5d}  {e.flags:#04x}  "
              f"{'<dir>':<11} {'':<11} {'':<32}  {e.path}/")
        else:
            w(f"  {e.offset:#07x}  {e.index:3d}  {e.parent:5d}  {e.flags:#04x}  "
              f"{e.version:#010x}  {e.size:<11d} {e.digest.hex()}  {e.path}")
    w("")

    if payload_root and os.path.isdir(payload_root):
        w("PAYLOAD CROSS-CHECK")
        w("-" * 78)
        w(f"  against {payload_root}")
        w("  delta = on-disk size minus manifest size.")
        w("  A delta of +24 means the stored copy is still in the path-keyed asset-cipher")
        w("  container (CRYPTO.md), whose overhead is a constant 24 bytes. Those files cannot")
        w("  be digest-checked without decrypting them first, because the digest covers the")
        w("  plaintext.")
        w("")
        deltas = {}
        missing = []
        digest_ok = []
        digest_bad = []
        for e in m.files:
            fp = os.path.join(payload_root, e.path)
            if not os.path.exists(fp):
                missing.append(e.path)
                continue
            d = os.path.getsize(fp) - e.size
            deltas.setdefault(d, []).append(e.path)
            if d == 0:
                with open(fp, "rb") as f:
                    body = f.read()
                (digest_ok if ptsys_digest(body) == e.digest else digest_bad).append(e.path)
        for d in sorted(deltas):
            w(f"  delta {d:+8d} : {len(deltas[d]):4d} files")
        w("")
        w(f"  digest verified (delta 0, hashed as-is) : {len(digest_ok)}")
        w(f"  digest MISMATCH                         : {len(digest_bad)}")
        for p in digest_bad:
            w(f"      {p}")
        if missing:
            w(f"  missing on disk : {len(missing)}")
            for p in missing[:20]:
                w(f"      {p}")
        w("")

    w("TRAILER")
    w("-" * 78)
    if m.end_offset == size:
        w(f"  None. The last entry's digest ends at {size:#x}, which is EOF exactly.")
    else:
        w(f"  {size - m.end_offset} unparsed bytes at {m.end_offset:#x}:")
        w(f"      {m.data[m.end_offset:].hex()}")
    w("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("path", nargs="?", default=DEFAULT_PATH)
    ap.add_argument("-o", "--output", help="write the dump here instead of stdout")
    ap.add_argument("--payload", help="directory holding the downloaded files "
                                      "(default: sibling 'p' of the manifest)")
    args = ap.parse_args(argv)

    with open(args.path, "rb") as f:
        data = f.read()
    m = Manifest(data)

    payload = args.payload
    if payload is None:
        payload = os.path.join(os.path.dirname(os.path.abspath(args.path)), "p")

    text = render(m, args.path, payload)
    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
        print(f"wrote {args.output} ({len(text)} bytes)", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
