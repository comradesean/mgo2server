"""Builds a self-hosted checkver.html "update available" reply and its relnote.txt.

Byte layout is ADDRESSES.md §12 / OBSERVED.md ("Auto-patch — checkver.html and the update
flow"), pinned from MGO2.elf 2026-07-30/31. Not a guess: every field below is either directly
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
    T+7         64  Blowfish-CBC(SLOT7_KEY) -> keystore slot 7 (payload files / .inf stage 2)
    T+71        64  Blowfish-CBC(SLOT8_KEY) -> keystore slot 8 (.inf stage 1 HMAC)

**The two blobs on the wire are ciphertext, not the effective keys.** Found 2026-07-31: the
keystore's get() Blowfish-CBC-decrypts whatever set() stored, under a master key resident in
the ELF at 0xE26DA8 (IV = first 8 bytes, 56-byte Blowfish key = the rest). So SLOT7_KEY/
SLOT8_KEY below are the keys the client actually ends up using (and what build_inf_stub.py
encrypts the .inf against) -- what goes into the reply is those bytes re-encrypted under the
master key, via encrypt_for_keystore(). Sending SLOT7_KEY/SLOT8_KEY raw (the first version of
this script) made the client's effective key be Decrypt(SLOT_KEY) -- deterministic garbage --
and the .inf was rejected every time despite being byte-correct by every other measure.

Stage 3 of .inf decryption uses a separate, different key that is NOT server-supplied and NOT
routed through the keystore -- it's resident in the ELF at 0xE20000 -- so it plays no part in
this reply and isn't handled here.

Two records are sent, mirroring the real Konami 1.36 patch tree the user has screenshots of:
one disc-qualified ("BLUS30109.<from>to<to>."), one generic ("<from>to<to>.").
"""
import pathlib

from Crypto.Cipher import Blowfish

HOST = "http://192.168.1.200"
PATCH_BASE = f"{HOST}/us/mgo2/patch"
FROM_VERSION = (1, 0, 0)
TO_VERSION = (1, 36, 0)
DISC_ID = "BLUS30109"

# The keystore's master key, 0xE26DA8 in MGO2.elf -- IV (first 8 bytes) + 56-byte Blowfish key.
# get() CBC-decrypts every slot's stored bytes under this, unconditionally, so this is what
# actually protects the wire blobs below -- not a free choice, read straight from the binary.
_MASTER_KEYBLOB = bytes.fromhex(
    "74f66dc28598f5d1"
    "72ac2dcace5544d665f11d05bea20568e76c529deb35890ec332ff24"
    "fe5d9c3fb34189cf47055b26f9e4cc639a46b5465404df41e65b8e4e"
)
assert len(_MASTER_KEYBLOB) == 64
_MASTER_IV, _MASTER_KEY = _MASTER_KEYBLOB[:8], _MASTER_KEYBLOB[8:]


def encrypt_for_keystore(plaintext_key):
    """CBC-encrypts a 64-byte key blob the way it must arrive for keystore get() to decrypt it
    back to `plaintext_key`. C[i] = E(P[i] XOR C[i-1]), C[-1] = IV -- the exact inverse of the
    client's get()-side CBC decrypt (0xD645C8)."""
    assert len(plaintext_key) == 64
    cipher = Blowfish.new(_MASTER_KEY, Blowfish.MODE_CBC, _MASTER_IV)
    return cipher.encrypt(plaintext_key)


# Fixed, chosen-by-us key material -- these are the EFFECTIVE keys the client ends up using
# after keystore get() decrypts them, and what build_inf_stub.py builds the .inf against. 16
# significant bytes + zero padding to 64, matching the shape of the one ELF-resident key we
# don't get to choose (0xE20000, the .inf stage-3 HMAC key).
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
    body += encrypt_for_keystore(SLOT7_KEY)
    body += encrypt_for_keystore(SLOT8_KEY)
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
