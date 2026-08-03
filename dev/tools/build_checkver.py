"""Writes dev/runtime/www/us/mgo2/patch/checkver.html -- the reply that offers a patch.

    python3 build_checkver.py                            # 0x00, "no update available"
    MGO2SERVER_CLIENT_VERSION=1.36 python3 build_checkver.py    # offer 1.0.0 -> 1.36.0

RUN IT AFTER ANY CHANGE TO THE VERSION, HOST OR KEYS. It writes two files and nothing else:
`checkver.html` (the reply, despite the extension it is BINARY, and it is POSTed rather than
GETted) and `<to version>/relnote.txt` (the release note the confirmation screen displays).
The probes serve the document root from a read-only mount, so both are live immediately.

WHAT DECIDES WHAT IS SERVED. `MGO2SERVER_CLIENT_VERSION` -- the same, and the only, variable
that selects which client build the whole stack serves. `1.36` offers the upgrade; unset or
`1.0` writes the single byte `0x00`, which is what lets the version-check screen advance and is
the right answer for anyone who just wants to play. There is deliberately no second switch: two
flags that had to agree made the incoherent combination (serving 1.0 while offering the 1.36
upgrade) expressible, which is the per-divergence env var CLAUDE.md forbids.

`MGO2SERVER_PATCH_HOST`, `MGO2SERVER_PATCH_FROM`, `MGO2SERVER_PATCH_TO` and
`MGO2SERVER_PATCH_DISC_ID` override the host, the version range and the disc id.

THIS FILE IS ONLY HALF THE ANSWER. The reply announces records; each announced record must have
a real `.inf` and a real archive on disk beside it, or the client fetches the probe's fallback
page and fails in a way that is invisible server-side. `build_patch_round.py` builds those.
`dev/docs/PATCH_FORMAT.md` specifies every layout here as a standalone format;
`dev/tools/README.md` is the operator's guide.

AN UP-TO-DATE CLIENT MUST NOT BE OFFERED THE PATCH, AND THIS FILE CANNOT DO THAT. The reply is
static, but the client's own version gate only checks it is at or above each record's FROM
version -- nothing in the client compares against the TO version, so an already-patched client
accepts the offer again, forever. `http_probe.py` closes this: it parses the packed version out
of the checkver POST and substitutes a bare `0x00` when the client is already current, reading
the TO version back out of the very reply written here so the two cannot drift.

Byte layout is ADDRESSES.md §12 / OBSERVED.md ("Auto-patch — checkver.html and the update
flow"), pinned from MGO2.elf 2026-07-30/31. Not a guess: every field below is either directly
read by the client (status byte, base URLs, records, terminator, the two key blobs) or
confirmed never read back (the two opaque fields, safe to zero).

    offset 0    1   status: 0x01 = update available
    offset 1    4   opaque u32 (never read back)
    offset 5    ..  string A (patch base), NUL-terminated, <=255 chars
    ..          ..  string B (HTTP-fallback base), NUL-terminated, <=255 chars
    ..          ..  version-range records: "<from>to<to>." NUL-terminated each, <=31 chars,
                     literal "to", and NO trailing "." -- the client's format is "%sinf" with no
                     dot of its own, so the real Konami names are "...1.36.0inf", not "....inf".
                     Corrected 2026-08-03 against the operator's directory listing (Sec 6): the
                     four real filenames are "1.0.0to1.36.0", "1.0.0to1.36.0inf",
                     "BLUS30109.1.0.0to1.36.0", "BLUS30109.1.0.0to1.36.0inf" and
                     "BLUS30109.1.0.0to1.36.0.torrent". The torrent settles it independently: its
                     name is <record>+".torrent", so a trailing dot in the record would have
                     produced "...1.36.0..torrent". Sec 1's "trailing '.' required" was an
                     inference and it contradicted Sec 6's observed URLs all along.
    T           1   terminator: 0x00
    T+1         2   opaque u16 (read, never branched on)
    T+3         4   packed TO version: major<<24 | minor<<16 | revision -- NOT opaque, found
                     2026-07-31. Feeds the confirmation dialog's "Ver. %d.%02d" text (obj+996,
                     0xBB7720; formatter 0xBB5150) AND gates the post-dialog state machine
                     (0x95CD7C compares it against the record's own parsed TO version at
                     obj+992 -- a mismatch, e.g. leaving this zero, advances the screen state by
                     1 instead of 2). Same packing the client's own record parser builds at
                     0xBB766C, so it must equal that, not just be present.
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

Two records are sent, mirroring the real Konami 1.36 patch tree: one disc-qualified
("BLUS30109.<from>to<to>"), one generic ("<from>to<to>"). No trailing dot on either -- see the
record note above. The pairing looks load-bearing rather than decorative: dropping to a single
record was tested live and was reproducibly WORSE, with the client not even reaching relnote.txt.
"""
import os
import pathlib


def _version_tuple(env_var, default):
    raw = os.environ.get(env_var, default)
    parts = tuple(int(p) for p in raw.split("."))
    assert len(parts) == 3, f"{env_var}={raw!r} must be major.minor.revision"
    return parts


# TIED TO THE SERVED BUILD, not to a switch of its own. Offering a 1.0 -> 1.36 upgrade is only
# coherent when the server is actually serving 1.36, so the patch reply is gated on
# MGO2SERVER_CLIENT_VERSION -- the same variable, and the only variable, that decides which build
# this server serves (CLAUDE.md, "There are two tier-1 binaries"). Unset means 1.0, so the safe
# default falls out for free: anything other than 1.36 writes the client's own single 0x00 "no
# update" byte, which is what this server sent before the auto-patch investigation began
# (ADDRESSES.md Sec 12, OBSERVED.md) and is the only reply that lets ordinary play proceed.
#
# This replaces the former MGO2SERVER_PATCH_ENABLED, which was a per-divergence env var of exactly
# the kind CLAUDE.md forbids -- two switches that had to agree, with a wrong combination
# (serving 1.0 while offering the 1.36 upgrade) silently expressible. Now it cannot be said.
CLIENT_VERSION = os.environ.get("MGO2SERVER_CLIENT_VERSION", "").strip() or "1.0"
if CLIENT_VERSION not in ("1.0", "1.36"):
    raise SystemExit(f"MGO2SERVER_CLIENT_VERSION={CLIENT_VERSION!r} -- only '1.0' or '1.36' are valid")
PATCH_ENABLED = CLIENT_VERSION == "1.36"

# Overridable so the same stub can exercise any version jump without editing this file --
# MGO2SERVER_CLIENT_VERSION=1.36 MGO2SERVER_PATCH_FROM=1.10.0 python3 build_checkver.py
# then the same env vars for the other builders (they import this module, so they always see the
# same jump; there is no separate place version numbers can drift out of sync). Real jumps seen in
# the wild (OBSERVED.md): 1.10.0->1.34.0, 1.0.0->1.36.0. TO defaults to the served build rather
# than to a literal, so it cannot disagree with MGO2SERVER_CLIENT_VERSION. These are meaningless
# when the served build is 1.0 -- the 0x00 reply carries no version.
HOST = os.environ.get("MGO2SERVER_PATCH_HOST", "http://192.168.1.200")
PATCH_BASE = f"{HOST}/us/mgo2/patch"
FROM_VERSION = _version_tuple("MGO2SERVER_PATCH_FROM", "1.0.0")
TO_VERSION = _version_tuple("MGO2SERVER_PATCH_TO", f"{CLIENT_VERSION}.0")
DISC_ID = os.environ.get("MGO2SERVER_PATCH_DISC_ID", "BLUS30109")

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
    from Crypto.Cipher import Blowfish  # imported lazily: only build_reply() needs it, and
    # importing this module just for its HOST/DOCROOT/version constants (build_inf_stub.py,
    # build_torrent.py, bt_seed.py) shouldn't require pycryptodome to be installed.
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
    if not PATCH_ENABLED:
        # [ELF, ADDRESSES.md Sec 12] status byte 0x00 alone: uupdate.cc reads one byte, sees no
        # update, and the version-check screen advances immediately. This is the whole reply --
        # no opaque fields, no records, nothing else is read on this path.
        return b"\x00"

    from_s, to_s = version_text(FROM_VERSION), version_text(TO_VERSION)
    # Two records: disc-qualified, then generic -- matches the real Konami 1.36 patch tree.
    # Tried dropping to one record 2026-07-31 on the theory that uupdate.cc's per-record loop
    # (0xBB8BCC footer, tail at 0xBB7FA4) was dying while building the SECOND record's .inf
    # request (0xBB7D88), landing on a generic-error exit -- leading suspect 0xBB7E2C, an
    # HTTP-object construction check -- before the confirmation dialog. The one-record reply
    # made things WORSE and reproducibly so: the client didn't even reach relnote.txt, which
    # it always fetched with two records present. So the paired structure looks load-bearing,
    # not incidental. Back to two records; the real fix has to be in what differs about
    # BUILDING the second record's request, not in removing it.
    records = [
        record(f"{DISC_ID}.{from_s}to{to_s}"),
        record(f"{from_s}to{to_s}"),
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
    to_major, to_minor, to_revision = TO_VERSION
    packed_to_version = (to_major << 24) | (to_minor << 16) | to_revision
    body += packed_to_version.to_bytes(4, "big")  # T+3: packed TO version, see docstring
    body += encrypt_for_keystore(SLOT7_KEY)
    body += encrypt_for_keystore(SLOT8_KEY)
    return bytes(body)


# Konami's genuine 1.36 release note, recovered from the Wayback capture of
# mgo2web.konami.com/us/mgo2/patch/1.36.0/relnote.txt (2011-02-13) and kept at
# dev/PATCHES/PATCH 1.36/relnote.txt. Tier 2 -- a real server artifact, not our reconstruction --
# so it is preferred over the stub below whenever it is present.
REAL_RELNOTE = pathlib.Path(__file__).parent.parent / "PATCHES" / "PATCH 1.36" / "relnote.txt"


def build_relnote():
    if REAL_RELNOTE.exists():
        return REAL_RELNOTE.read_bytes()

    # IS rendered (ADDRESSES.md Sec 12: the update screen's sub-state 6/7 word-wraps the body
    # into up to 62 lines and shows 5 at a time with scroll arrows). Live-tested 2026-07-31: the
    # single long sentence this used to be ran off the bottom of the display before the user
    # could see the end. Kept to a handful of short, independently-safe lines so it fits on one
    # page regardless of the client's exact wrap width -- no line here needs the client's
    # word-wrap to render cleanly.
    return (
        f"mgo2server test patch\n"
        f"{version_text(FROM_VERSION)} -> {version_text(TO_VERSION)}\n"
        f"Stub data only.\n"
        f"Not real Konami content.\n"
    ).encode("ascii")


def main():
    reply = build_reply()
    checkver_path = DOCROOT / "checkver.html"
    checkver_path.write_bytes(reply)

    if not PATCH_ENABLED:
        print(f"wrote {checkver_path} ({len(reply)} bytes) -- PATCH DISABLED, no-update reply. "
            "Set MGO2SERVER_CLIENT_VERSION=1.36 to serve the 1.36 build and offer the upgrade.")
        return

    print(f"wrote {checkver_path} ({len(reply)} bytes) -- PATCH ENABLED, offering "
        f"{version_text(FROM_VERSION)} -> {version_text(TO_VERSION)}. This is research-only "
        "payload, not real Konami content; do not leave this the deployed default.")

    version_dir = DOCROOT / version_text(TO_VERSION)
    version_dir.mkdir(parents=True, exist_ok=True)
    relnote_path = version_dir / "relnote.txt"
    relnote_path.write_bytes(build_relnote())
    print(f"wrote {relnote_path}")

    print(f"slot 7 key: {SLOT7_KEY.hex()}")
    print(f"slot 8 key: {SLOT8_KEY.hex()}")


if __name__ == "__main__":
    main()
