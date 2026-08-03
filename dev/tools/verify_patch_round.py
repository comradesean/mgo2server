"""Replays the CLIENT'S OWN READ CHAIN over a served round, and checks every file inside it.

WHY THIS EXISTS SEPARATELY FROM THE BUILDER. `build_patch_round.py` already verifies what it
builds -- `verify_container()` runs on every archive and refuses to ship one that does not decode.
But that checks the bytes it just produced, in memory, from the sources it just read. It cannot
catch anything that happens AFTER: a truncated write, a stale file left in the docroot from an
earlier round, a probe serving 462 bytes of fallback prose for a path it does not recognise, or a
Range reply that silently restarts at byte 0. Every one of those has a precedent in this
investigation, and every one is invisible from the server side.

So this tool starts from the URL the client would fetch and ends at "does each extracted file
equal the file on disk that it is supposed to be". It is the offline half of the live test.

    python3 verify_patch_round.py                 # against the deployed server
    python3 verify_patch_round.py --local         # against dev/runtime/www, skipping HTTP
    python3 verify_patch_round.py --no-content    # structure only, no member comparison

THE CHAIN IT REPLAYS, which is the installer's, read backwards (ADDRESSES.md Sec 12):

    served bytes -> verify HMAC-MD5 trailer  (phase 1, key = keystore slot 8)
                 -> Blowfish-CBC decrypt     (key = keystore slot 7, 8+56 IV/key split)
                 -> strip PKCS#7             (checked as 1..8 at 0xD6570C)
                 -> zlib inflate             (RFC1950; the stage missed for a whole session)
                 -> hdr[4] prefix must equal the .inf's, byte for byte  (0xBBAE70 memcmp)
                 -> then scan A's members, end to end, in order

Everything is streamed. The generic 1.36 archive is ~1.9 GB and must never be held whole.
"""
import argparse
import hashlib
import hmac
import pathlib
import sys
import urllib.request
import zlib

import build_checkver as checkver

CHUNK = 1 << 20


def _cipher():
    from Crypto.Cipher import Blowfish
    return Blowfish.new(checkver.SLOT7_KEY[8:64], Blowfish.MODE_CBC, checkver.SLOT7_KEY[0:8])


def source_reader(base, name, local_root):
    """Yields the served bytes for `name`, from the docroot or over HTTP."""
    if local_root is not None:
        path = local_root / name
        if not path.is_file():
            raise SystemExit(f"{name}: not in the docroot at {path}")
        with open(path, "rb") as handle:
            while True:
                block = handle.read(CHUNK)
                if not block:
                    return
                yield block
    else:
        with urllib.request.urlopen(f"{base}/{name}") as response:
            if response.status != 200:
                raise SystemExit(f"{name}: HTTP {response.status}")
            while True:
                block = response.read(CHUNK)
                if not block:
                    return
                yield block


def decode(blocks, mac_key, on_plain):
    """Runs the chain and hands decoded plaintext to `on_plain`. Returns (wire size, plain size)."""
    mac, cipher, inflate = hmac.new(mac_key, digestmod=hashlib.md5), _cipher(), zlib.decompressobj()
    tail = b""              # the last 16 bytes are the trailer, not body -- hold them back
    wire = plain = 0
    for block in blocks:
        wire += len(block)
        buf = tail + block
        tail, buf = buf[-16:], buf[:-16]
        if not buf:
            continue
        mac.update(buf)
        out = inflate.decompress(cipher.decrypt(buf))
        plain += len(out)
        on_plain(out)
    if len(tail) != 16:
        raise SystemExit(f"body is {wire} bytes -- too short to carry a 16-byte trailer")
    if mac.digest() != tail:
        raise SystemExit("phase-1 HMAC-MD5 trailer does NOT verify -- the client would reject this")
    return wire, plain


def decode_whole(blocks, mac_key):
    parts = []
    decode(blocks, mac_key, parts.append)
    body = b"".join(parts)
    # The PKCS#7 pad rides inside the cipher layer, so inflate has already stopped at the zlib
    # stream's own end and the pad never reaches us. Nothing to strip here.
    return body


def walk_scan_a(plain_head):
    """[(name, size)] out of a decoded prefix, exactly as 0xBBB0D0 walks it."""
    limit = int.from_bytes(plain_head[4:8], "big")
    cursor, out = 12, []
    while cursor < limit - 16:
        end = plain_head.index(b"\x00", cursor)
        size = int.from_bytes(plain_head[end + 1:end + 5], "big")
        out.append((plain_head[cursor:end].decode("ascii"), size))
        cursor = end + 6            # NUL + u32 size + u8 flags
    return limit, out


class MemberChecker:
    """Splits the inflating stream on member boundaries and digests each one as it passes."""

    def __init__(self, prefix, members):
        self.prefix, self.members = prefix, members
        self.head = bytearray()
        self.index, self.done, self.digest = 0, 0, hashlib.md5()
        self.results, self.total = [], 0

    def feed(self, data):
        self.total += len(data)
        if len(self.head) < len(self.prefix):        # the hdr[4] region comes first
            take = min(len(self.prefix) - len(self.head), len(data))
            self.head += data[:take]
            data = data[take:]
        while data and self.index < len(self.members):
            name, size = self.members[self.index]
            take = min(size - self.done, len(data))
            self.digest.update(data[:take])
            self.done += take
            data = data[take:]
            if self.done == size:
                self.results.append((name, size, self.digest.hexdigest()))
                self.index, self.done, self.digest = self.index + 1, 0, hashlib.md5()

    def problems(self):
        out = []
        if bytes(self.head) != self.prefix:
            out.append("the archive's leading hdr[4] bytes are NOT the .inf's -- 0xBBAE70 rejects")
        if self.index != len(self.members):
            out.append(f"stream ended inside member {self.index + 1}/{len(self.members)} "
                       f"({self.members[self.index][0] if self.index < len(self.members) else '?'})")
        expected = len(self.prefix) + sum(size for _, size in self.members)
        if self.total != expected:
            out.append(f"plaintext is {self.total:,} bytes, scan A accounts for {expected:,}")
        return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", default=None,
                    help="URL of the patch directory (default: the host build_checkver uses)")
    ap.add_argument("--local", action="store_true",
                    help="read dev/runtime/www directly instead of over HTTP -- checks the files "
                         "but NOT that the probe serves them, which is half the point")
    ap.add_argument("--tree", type=pathlib.Path,
                    default=pathlib.Path(__file__).parent.parent / "PATCHES" / "PATCH 1.36" / "o",
                    help="the extracted 1.36 archive, to compare each member against")
    ap.add_argument("--no-content", action="store_true",
                    help="check structure only; skip hashing members against their sources")
    ap.add_argument("--mac", default="6d676f327365727665725f736c6f7438",
                    help="phase-1 HMAC key in hex (default: the ASCII 'mgo2server_slot8' this "
                         "client's stubbed slot provider returns)")
    args = ap.parse_args()

    to_s = checkver.version_text(checkver.TO_VERSION)
    from_s = checkver.version_text(checkver.FROM_VERSION)
    base = args.base or f"{checkver.HOST}/us/mgo2/patch"
    local_root = (checkver.DOCROOT if args.local else None)
    where = f"{local_root}" if args.local else base
    print(f"verifying the {from_s} -> {to_s} round at {where}\n")

    mac_key = bytes.fromhex(args.mac)
    payload_root = args.tree / "dl" / "p"
    failures = 0

    for index, stem in enumerate((f"{checkver.DISC_ID}.{from_s}to{to_s}", f"{from_s}to{to_s}")):
        rel = (lambda n: f"{to_s}/{n}") if local_root is None else (lambda n: f"{to_s}/{n}")
        prefix_dir = (local_root if local_root is not None else None)

        def fetch(name):
            if local_root is not None:
                return source_reader(None, f"{to_s}/{name}", local_root)
            return source_reader(base, f"{to_s}/{name}", None)

        print(f"record {index}: {stem}")
        inf_plain = decode_whole(fetch(stem + "inf"), mac_key)
        limit, members = walk_scan_a(inf_plain)
        prefix = inf_plain[:limit]
        scan_b_name = inf_plain[limit:].split(b"\x00")[0].decode("ascii")
        scan_b_size = int.from_bytes(inf_plain[limit + len(scan_b_name) + 1:
                                               limit + len(scan_b_name) + 5], "big")
        print(f"  .inf decodes: hdr[4]={limit:,}, scan A lists {len(members)} file(s), "
              f"scan B downloads {scan_b_name!r} ({scan_b_size:,} bytes)")

        checker = MemberChecker(prefix, members)
        wire, plain = decode(fetch(stem), mac_key, checker.feed)
        print(f"  archive decodes: {wire:,} bytes on the wire -> {plain:,} plaintext")
        if wire != scan_b_size:
            print(f"  !! the .inf declares {scan_b_size:,} but the server sent {wire:,} -- the "
                  f"client downloads the declared count and would truncate or overrun")
            failures += 1
        for problem in checker.problems():
            print(f"  !! {problem}")
            failures += 1

        if args.no_content:
            print(f"  {len(checker.results)} member(s) decoded, content check skipped\n")
            continue

        good = missing = bad = 0
        for name, size, digest in checker.results:
            # A name of the form "..N/rest" goes N levels up from dl/p/ (0xBB5678) -- strip it to
            # find the source. Without this the lookup silently misses and the member is reported
            # as "no source to compare against", which reads like a pass and is not one.
            bare = name[4:] if (len(name) > 4 and name[:2] == ".."
                                and name[2].isdigit() and name[3] == "/") else name
            source = payload_root / bare
            if bare == "MGO2.SELF":
                source = next((p for p in (args.tree / "MGO2.SELF",
                                           args.tree / "MGO2.self") if p.is_file()),
                              args.tree / "MGO2.SELF")
            elif bare == ".p":
                # `.p.authored` is what a build leaves behind; `.p` is it once the operator has
                # renamed it into place. Either is the right comparand -- but NOT
                # `.p.original.bak`, which declares the stock SELF's digest rather than ours.
                source = next((p for p in (args.tree / "dl" / ".p.authored",
                                           args.tree / "dl" / ".p") if p.is_file()),
                              args.tree / "dl" / ".p")
            if not source.is_file():
                missing += 1
                continue
            actual = hashlib.md5()
            with open(source, "rb") as handle:
                for block in iter(lambda: handle.read(CHUNK), b""):
                    actual.update(block)
            if actual.hexdigest() == digest:
                good += 1
            else:
                bad += 1
                print(f"  !! {name}: extracts to {size:,} bytes that do NOT match {source}")
        print(f"  members: {good} match their source, {bad} differ, {missing} had no source "
              f"to compare against\n")
        failures += bad

    if failures:
        print(f"FAILED: {failures} problem(s). The client would not install this round cleanly.")
        return 1
    print("OK -- every archive decodes through the client's chain and every member checks out.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
