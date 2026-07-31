"""Builds a real, valid BitTorrent .torrent file for the auto-patch P2P path.

Confirmed genuine BitTorrent (ADDRESSES.md Sec 12): the client fetches the .torrent raw over
HTTP, then hands it unmodified to a statically-linked Transmission. Standard BEP3/bencode --
nothing MGO2-specific here except the URL the .torrent is itself fetched from, and the file names
inside it, which must match what build_inf_stub.py already declared as entries.

    URL: %s/%u.%u.%u/%s.%u.%u.%uto%u.%u.%u.torrent
       = <string A base>/<to-version>/<DISC_ID>.<from>to<to>.torrent

This module has no third-party dependencies on purpose: it's imported both by this host-side
builder (writes the .torrent into the docroot) and by dev/runtime/bt_seed.py (the tracker +
seeding peer, run in a bare python:3.12-alpine container), and both need the exact same info
dict / info_hash / piece data -- computed here once, not duplicated.
"""
import hashlib
import pathlib

import build_checkver_stub as checkver

PIECE_LENGTH = 16384  # 16 KiB, a conventional small piece size
TRACKER_PORT = 6969   # standard BEP3 tracker port
PEER_PORT = 6881      # standard BitTorrent peer-wire port


def bencode(value):
    """Minimal bencode encoder -- ints, byte/str strings, lists, dicts (keys sorted, per spec)."""
    if isinstance(value, bool):
        raise TypeError("bencode has no boolean type")
    if isinstance(value, int):
        return f"i{value}e".encode("ascii")
    if isinstance(value, (bytes, bytearray)):
        return str(len(value)).encode("ascii") + b":" + bytes(value)
    if isinstance(value, str):
        return bencode(value.encode("utf-8"))
    if isinstance(value, list):
        return b"l" + b"".join(bencode(v) for v in value) + b"e"
    if isinstance(value, dict):
        def key_bytes(k):
            return k.encode("utf-8") if isinstance(k, str) else bytes(k)
        items = sorted(value.items(), key=lambda kv: key_bytes(kv[0]))
        body = b"".join(bencode(k) + bencode(v) for k, v in items)
        return b"d" + body + b"e"
    raise TypeError(f"not bencodable: {type(value)}")


def build_torrent_info(files):
    """files: list of (name, bytes), in the order they concatenate for piece hashing. Multi-file
    torrent (BEP3's 'files' list) when there's more than one, single-file otherwise."""
    all_bytes = b"".join(data for _, data in files)
    pieces = b"".join(
        hashlib.sha1(all_bytes[i:i + PIECE_LENGTH]).digest()
        for i in range(0, max(len(all_bytes), 1), PIECE_LENGTH)
    ) if all_bytes else hashlib.sha1(b"").digest()

    if len(files) == 1:
        name, data = files[0]
        info = {
            "name": name,
            "piece length": PIECE_LENGTH,
            "pieces": pieces,
            "length": len(data),
        }
    else:
        info = {
            "name": f"{checkver.DISC_ID}.patch",
            "piece length": PIECE_LENGTH,
            "pieces": pieces,
            "files": [{"length": len(data), "path": [name]} for name, data in files],
        }
    info_hash = hashlib.sha1(bencode(info)).digest()
    return info, info_hash, all_bytes


def tracker_url():
    host_no_scheme = checkver.HOST.split("://", 1)[1]
    return f"http://{host_no_scheme}:{TRACKER_PORT}/announce"


def build_torrent_bytes(files):
    info, info_hash, _ = build_torrent_info(files)
    torrent = {"announce": tracker_url(), "info": info}
    return bencode(torrent), info_hash


def torrent_filename():
    from_s = ".".join(str(n) for n in checkver.FROM_VERSION)
    to_s = ".".join(str(n) for n in checkver.TO_VERSION)
    return f"{checkver.DISC_ID}.{from_s}to{to_s}.torrent"


def version_dir():
    return checkver.DOCROOT / ".".join(str(n) for n in checkver.TO_VERSION)


def stub_files():
    """The same two stub payload files build_inf_stub.py already wrote to disk -- read them back
    so the torrent's piece hashes are computed over the exact bytes actually served over HTTP."""
    from_s = ".".join(str(n) for n in checkver.FROM_VERSION)
    to_s = ".".join(str(n) for n in checkver.TO_VERSION)
    names = [
        f"{checkver.DISC_ID}.{from_s}to{to_s}",
        f"{from_s}to{to_s}",
    ]
    vdir = version_dir()
    return [(name, (vdir / name).read_bytes()) for name in names]


def main():
    files = stub_files()
    torrent_bytes, info_hash = build_torrent_bytes(files)

    out_path = version_dir() / torrent_filename()
    out_path.write_bytes(torrent_bytes)
    print(f"wrote {out_path} ({len(torrent_bytes)} bytes)")
    print(f"info_hash: {info_hash.hex()}")
    print(f"tracker: {tracker_url()}")
    print(f"peer port: {PEER_PORT}")


if __name__ == "__main__":
    main()
