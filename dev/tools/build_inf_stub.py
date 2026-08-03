"""Builds the .inf files a hand-authored checkver.html reply promises.

Pipeline is HMAC-MD5 verify -> Blowfish-CBC decrypt -> zlib inflate -> HMAC-MD5 verify, pinned
from MGO2.elf 2026-07-31 (ADDRESSES.md Sec 12, "The .inf pipeline"; OBSERVED.md's matching
correction). Not a guess -- every step below mirrors a disassembled function:

    outer tag   = HMAC-MD5(slot 8 key, ciphertext)                  0xD652E0 @ 0xBB7E7C
    ciphertext  = Blowfish-CBC-encrypt(slot7[8:64], IV=slot7[0:8],   0xD66CF0 @ 0xBB8618
                      PKCS7-pad(zlib.compress(inner)))
    inner       = header(12) + HMAC-MD5(ELF key, header) + entries + 16 slack  0xD652E0 @ 0xBB8848

    THE MISSING STAGE (found 2026-07-31, cost a third rejected .inf): what decrypts off the
    Blowfish-CBC layer is fed straight into a zlib inflate stream (ctor 0x28887C ->
    inflateInit2_ with windowBits=15, i.e. a standard RFC1950 zlib wrapper -- inflate() itself
    is zlib 1.2.3 at 0xD2DB04, identifiable by its own copyright string in the ELF). Every
    layout rule below (header, the two entry scans, the trailing slack) describes the
    DECOMPRESSED buffer, not the CBC plaintext directly -- confirmed at 0xBB87B0 (header is read
    from the post-inflate buffer) and 0xBB8AEC (scan B's bound is the decompressed length minus
    16). A plaintext that skips this stage still passes both HMACs and has valid PKCS7 padding,
    which is why this was mistaken for a padding bug for a full investigation round: the pad
    check (0xD6844C) never even runs on a bad inflate, since the failure the client reports
    comes out of inflate() itself ("incorrect header check" / "unknown compression method"),
    reusing the same generic error-state-10 path as a real pad failure. Decompressed output is
    capped at 256 KB (0xBB86C4).

    header: u32 unknown(0) | u32 L | u32 unknown(0)
      -- hdr[0] and hdr[8] are copied to r1+116/r1+124 at 0xBB87DC and never read again anywhere
         in the function; only hdr[4] (r1+120) is consumed. Zero is safe.
      -- L is BOTH the stage-3 HMAC stream length (0xBB881C) and the bound of the *first* entry
         scan (0xBB89B8). Set L = 28 so that first scan is empty; see below.

    THE LAYOUT TRAP (found 2026-07-31, cost two rejected .inf files):
    The plaintext holds TWO entry scans, not one, and the one that actually records entries
    starts AFTER the inner HMAC tag, not at offset 12.

      0xBB89B0-0xBB8AC0  scan A: cursor starts at base+12, bound base+L-16, stride NUL+6
                         (<name> 00 <u32 size BE> <u8 flags>), flags bit 0x20 gates a
                         stat of "dl/p/<name>" for resume accounting. Feeds obj+1012, a
                         display counter only -- nothing gates on it.
      0xBB8AF0           cursor += 16          <- steps over the inner HMAC tag
      0xBB8B00-0xBB8BC8  scan B: bound base+total_plaintext-16, stride NUL+5
                         (<name> 00 <u32 size BE>).  THIS is the scan that fills the entry
                         array at obj+1072 and drives the download/install.

    With L = 28, scan A exits on its first bound test with the cursor untouched at base+12, so
    scan B starts at base+28 -- immediately after a 16-byte tag placed at [12, 28). The two
    scans cannot be the same list: their strides differ by one byte, so a list parsed correctly
    by A desyncs under B and vice versa.

    The 16 trailing bytes are required, not decorative: scan B's bound is
    total_plaintext - 16, so without them the final entry falls outside the bound and is
    dropped. Contents are never read.

    entries: repeated  <name> 00 <u32 size, big-endian>   (name/size only -- no flags in scan B)

File on disk = ciphertext || outer tag  (outer tag is NOT encrypted, appended raw, 16 bytes)

PKCS7 here means: last plaintext byte is the pad count, 1..8 -- a 0 is rejected client-side, so a
plaintext that's already a multiple of 8 still needs a full padding block.

Keys: slot 7 and slot 8 come from build_checkver.py (the same reply that announces this
.inf must carry the keys used to build it). The third key, for the header/entries HMAC, is
resident in the ELF at 0xE20000 and is not ours to choose.
"""
import hashlib
import hmac
import pathlib
import zlib

from Crypto.Cipher import Blowfish

import build_checkver as checkver

# 0xE20000, MGO2.elf -- 16 significant bytes; HMAC uses the key block as-is, so no padding needed.
ELF_HMAC_KEY = bytes.fromhex("9357a9dfb8eb8d03b843cd025f2a30ce")

DOCROOT = checkver.DOCROOT


def pkcs7_pad(data):
    pad_len = 8 - (len(data) % 8)  # 1..8, never 0
    return data + bytes([pad_len]) * pad_len


def build_entries(entries):
    body = bytearray()
    for name, size in entries:
        encoded = name.encode("ascii")
        body += encoded + b"\x00" + size.to_bytes(4, "big")
    return bytes(body)


# Scan B's bound is (decrypted length - 16), so the entry list needs this much dead space after
# it or the last entry is never reached.  0xBB8AEC-0xBB8AF8, 0xBB8BB8-0xBB8BC8.
TRAILING_SLACK = b"\x00" * 16

# SCAN A IS THE INSTALL LIST, AND LEAVING IT EMPTY IS WHY NOTHING EVER INSTALLED.
#
# The .inf carries TWO tables and they do different jobs:
#   scan B  (this file's `entries`, at plaintext offset hdr[4])  -- what to DOWNLOAD.
#   scan A  (at plaintext offset 12, up to hdr[4]-16)            -- what to WRITE OUT of the
#                                                                   downloaded archive.
# ADDRESSES.md calls scan A "display-only". That is true of the .inf parser at 0xBB89B0 and false
# of the installer: 0xBBB0BC-0xBBB0CC computes cursor = blob+12, bound = blob + hdr[4] - 16, and
# `ble -> 0xBBBA20` skips the ENTIRE per-record install loop when bound <= cursor. With the old
# HEADER_LEN = 28 the two are equal, so the branch was taken unconditionally for every group and
# dl/p/ar/t/0/ was never written. Confirmed live: the payload verifies (both HMACs pass, r3 = 0 at
# 0xD66588), no error state is ever set, and phase 2 simply does not run.
#
# Entry layout is scan B's plus a one-byte flags field:  <name> 00 <u32 size BE> <u8 flags>
# Flags bits, from the finalize/extract paths:
#   0x0F  ordering-pass index; the 16-pass loop at 0xBBB76C handles only records whose low nibble
#         equals the pass number
#   0x10  output stream selector (0xBBB2D8)
#   0x20  destination: CLEAR = install straight to dl/p/<name> (0xBBB5D0 -> 0xBB5618); SET = write
#         to dl/p/ar/t/0/<name> and enable the 16-pass finalize (0xBBB164/0xBBB18C)
# Default 0x00: direct install, no finalize pass -- the shortest path to bytes landing on disk.
#
# NOT YET CONFIRMED, and the reason this is a step rather than a fix: the payload archive's
# decrypted plaintext must BEGIN with these same hdr[4] bytes (header + scan A + tag), because
# 0xBBAE44-0xBBAEFC reads hdr[4] bytes from the archive and memcmps them against the .inf's. And
# phase 2 stacks a Blowfish-CBC decrypt filter (0xBBADE0) that phase 1 does not, so the archive
# may need encrypting too. Neither is settled; see the note in build_patch_round.py.
DEFAULT_SCAN_A_FLAGS = 0x00


def build_scan_a(records):
    """records: [(name, size, flags)] -- the files to extract from the archive, in order."""
    table = bytearray()
    for name, size, flags in records:
        table += name.encode("ascii") + b"\x00" + size.to_bytes(4, "big") + bytes([flags])
    return bytes(table)


def build_prefix(scan_a=()):
    """The hdr[4] bytes: header || scan A || inner tag.

    The payload archive's plaintext must START with exactly these bytes -- 0xBBAE44 reads hdr[4]
    of them from the archive and 0xBBAE70 memcmps them against the .inf's copy, so the two are
    generated here once rather than assembled twice.
    """
    table = build_scan_a(scan_a)
    header_len = 12 + len(table) + 16
    header = (0).to_bytes(4, "big") + header_len.to_bytes(4, "big") + (0).to_bytes(4, "big")
    # Stage 3 verifies plaintext[0 .. hdr[4]-16) against the tag at [hdr[4]-16, hdr[4]).
    return header + table + hmac.new(ELF_HMAC_KEY, header + table, hashlib.md5).digest()


def build_inf(entries, scan_a=()):
    body = build_entries(entries)
    inner = build_prefix(scan_a) + body + TRAILING_SLACK
    plaintext = pkcs7_pad(zlib.compress(inner))

    cipher = Blowfish.new(checkver.SLOT7_KEY[8:64], Blowfish.MODE_CBC, checkver.SLOT7_KEY[0:8])
    ciphertext = cipher.encrypt(plaintext)

    outer_tag = hmac.new(checkver.SLOT8_KEY, ciphertext, hashlib.md5).digest()
    return ciphertext + outer_tag


def stub_payload(name, size):
    """A placeholder payload of exactly `size` bytes -- not real patch data."""
    label = f"stub payload for {name}\n".encode("ascii")
    if len(label) >= size:
        return label[:size]
    return label + bytes(size - len(label))


def main():
    version_dir = DOCROOT / ".".join(str(n) for n in checkver.TO_VERSION)
    from_s = ".".join(str(n) for n in checkver.FROM_VERSION)
    to_s = ".".join(str(n) for n in checkver.TO_VERSION)

    # One entry per .inf, name matching the real Konami directory listing's pattern (a payload
    # file named after the record text itself, no extension) -- see PATCH_INVESTIGATION.md Sec 6.
    records = {
        f"{checkver.DISC_ID}.{from_s}to{to_s}": f"{checkver.DISC_ID}.{from_s}to{to_s}inf",
        f"{from_s}to{to_s}": f"{from_s}to{to_s}inf",
    }

    for payload_name, inf_filename in records.items():
        payload_size = 32
        entries = [(payload_name, payload_size)]

        inf_bytes = build_inf(entries)
        inf_path = version_dir / inf_filename
        inf_path.write_bytes(inf_bytes)
        print(f"wrote {inf_path} ({len(inf_bytes)} bytes, {len(entries)} entr{'y' if len(entries)==1 else 'ies'})")

        payload_path = version_dir / payload_name
        payload_path.write_bytes(stub_payload(payload_name, payload_size))
        print(f"wrote {payload_path} ({payload_size} bytes, stub content)")


if __name__ == "__main__":
    main()
