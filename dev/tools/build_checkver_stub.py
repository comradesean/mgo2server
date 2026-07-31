"""Builds a self-hosted checkver.html "update available" reply and its relnote.txt.

Byte layout is ADDRESSES.md §12 / OBSERVED.md ("Auto-patch — checkver.html and the update
flow"), pinned from MGO2.elf 2026-07-30. Not a guess: every field below is either directly
read by the client (status byte, base URLs, records, terminator, the two key blobs) or
confirmed never read back (the two opaque fields, safe to zero).

    offset 0    1   status: 0x01 = update available
    offset 1    4   opaque u32 (never read back)
    offset 5    ..  string A (patch base), NUL-terminated, <=255 chars
    ..          ..  string B (HTTP-fallback base), NUL-terminated, <=255 chars
    ..          ..  version-range records: "<from>to<to>." NUL-terminated each, <=31 chars,
                     literal "to", trailing "." required (client's %sinf has no dot of its own)
    T           1   terminator: 0x00
    T+1         2   opaque u16 (read, never branched on)
    T+3         4   opaque u32 (read, never branched on)
    T+7         64  Blowfish key -> keystore slot 7 (payload files)
    T+71        64  Blowfish key -> keystore slot 8 (.inf stage 1/2)

The two key blobs are chosen here, not recovered -- the server supplies both. They're fixed
(not random) so a later .inf-building step can reuse the exact same slot-7/slot-8 keys.
Stage 3 of .inf decryption uses a *third* key that is NOT server-supplied -- it's resident in
the ELF at 0xE20000 -- so it plays no part in this reply and isn't handled here.

Two records are sent, mirroring the real Konami 1.36 patch tree the user has screenshots of:
one disc-qualified ("BLUS30109.<from>to<to>."), one generic ("<from>to<to>.").
"""
import pathlib

HOST = "http://192.168.1.200"
PATCH_BASE = f"{HOST}/us/mgo2/patch"
FROM_VERSION = (1, 0, 0)
TO_VERSION = (1, 36, 0)
DISC_ID = "BLUS30109"

# Fixed, chosen-by-us key material -- 16 significant bytes + zero padding to 64, matching the
# shape observed for the one ELF-resident key we *do* have bytes for (0xE20000). Whether the
# client only consumes the first N<=56 bytes as the actual Blowfish key is not confirmed, but
# since we also hold the private end of this cipher, whatever interpretation the client uses,
# using the identical 64-byte blob on both ends keeps them in sync.
SLOT7_KEY = bytes.fromhex("6d676f327365727665725f736c6f7437") + b"\x00" * 48  # "mgo2server_slot7"
SLOT8_KEY = bytes.fromhex("6d676f327365727665725f736c6f7438") + b"\x00" * 48  # "mgo2server_slot8"
assert len(SLOT7_KEY) == 64 and len(SLOT8_KEY) == 64

WWW = pathlib.Path(__file__).parent.parent / "runtime" / "www"
DOCROOT = WWW / "us" / "mgo2" / "patch"


def version_text(v):
    return ".".join(str(n) for n in v)


def record(text):
    encoded = text.encode("ascii")
    assert len(encoded) <= 31, f"record {text!r} exceeds the 31-char name field ({len(encoded)})"
    return encoded + b"\x00"


def build_reply():
    from_s, to_s = version_text(FROM_VERSION), version_text(TO_VERSION)
    records = [
        record(f"{DISC_ID}.{from_s}to{to_s}."),
        record(f"{from_s}to{to_s}."),
    ]

    body = bytearray()
    body += b"\x01"                       # status: update available
    body += (0).to_bytes(4, "big")        # opaque u32, unread
    body += PATCH_BASE.encode("ascii") + b"\x00"   # string A
    body += PATCH_BASE.encode("ascii") + b"\x00"   # string B (fallback == same tree for now)
    for r in records:
        body += r
    body += b"\x00"                       # terminator T
    body += (0).to_bytes(2, "big")        # opaque u16, unread
    body += (0).to_bytes(4, "big")        # opaque u32, unread
    body += SLOT7_KEY
    body += SLOT8_KEY
    return bytes(body)


def build_relnote():
    # Never rendered by the client (fetched, not displayed) -- content is unconstrained.
    return (
        f"mgo2server self-hosted test patch\n"
        f"{version_text(FROM_VERSION)} -> {version_text(TO_VERSION)}\n"
        f"Stub content for exercising the auto-patch protocol; not real Konami patch data.\n"
    ).encode("ascii")


def main():
    reply = build_reply()
    checkver_path = DOCROOT / "checkver.html"
    checkver_path.write_bytes(reply)
    print(f"wrote {checkver_path} ({len(reply)} bytes)")

    version_dir = DOCROOT / version_text(TO_VERSION)
    version_dir.mkdir(parents=True, exist_ok=True)
    relnote_path = version_dir / "relnote.txt"
    relnote_path.write_bytes(build_relnote())
    print(f"wrote {relnote_path}")

    print(f"slot 7 key: {SLOT7_KEY.hex()}")
    print(f"slot 8 key: {SLOT8_KEY.hex()}")


if __name__ == "__main__":
    main()
