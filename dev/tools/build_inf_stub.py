"""Builds the .inf files a hand-authored checkver.html reply promises.

Pipeline is HMAC-MD5 verify -> Blowfish-CBC decrypt -> HMAC-MD5 verify, pinned from MGO2.elf
2026-07-31 (ADDRESSES.md Sec 12, "The .inf pipeline"; OBSERVED.md's matching correction). Not a
guess -- every step below mirrors a disassembled function:

    outer tag   = HMAC-MD5(slot 8 key, ciphertext)                  0xD652E0 @ 0xBB7E7C
    ciphertext  = Blowfish-CBC-encrypt(slot7[8:64], IV=slot7[0:8],   0xD66CF0 @ 0xBB8618
                      PKCS7-pad(inner))
    inner       = header(12) + entries + HMAC-MD5(ELF key, header+entries)   0xD652E0 @ 0xBB8848

    header: u32 unknown(0) | u32 total-inner-length | u32 unknown(0)
    entries: repeated  <name> 00 <u32 size, big-endian>   (name/size only -- no flags on the wire)

File on disk = ciphertext || outer tag  (outer tag is NOT encrypted, appended raw, 16 bytes)

PKCS7 here means: last plaintext byte is the pad count, 1..8 -- a 0 is rejected client-side, so a
plaintext that's already a multiple of 8 still needs a full padding block.

Keys: slot 7 and slot 8 come from build_checkver_stub.py (the same reply that announces this
.inf must carry the keys used to build it). The third key, for the header/entries HMAC, is
resident in the ELF at 0xE20000 and is not ours to choose.
"""
import hashlib
import hmac
import pathlib

from Crypto.Cipher import Blowfish

import build_checkver_stub as checkver

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


def build_inf(entries):
    body = build_entries(entries)
    inner_len = 12 + len(body) + 16  # header + entries + inner (stage-3) HMAC tag
    header = (0).to_bytes(4, "big") + inner_len.to_bytes(4, "big") + (0).to_bytes(4, "big")
    inner = header + body
    inner_tag = hmac.new(ELF_HMAC_KEY, inner, hashlib.md5).digest()
    plaintext = pkcs7_pad(inner + inner_tag)

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
        f"{checkver.DISC_ID}.{from_s}to{to_s}": f"{checkver.DISC_ID}.{from_s}to{to_s}.inf",
        f"{from_s}to{to_s}": f"{from_s}to{to_s}.inf",
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
