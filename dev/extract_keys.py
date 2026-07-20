"""Pulls the crypto constants that genuinely live in the game binary.

    python3 dev/extract_keys.py "/path/to/PS3_GAME/USRDIR/o/MGO2.elf"

The binary is not redistributed with this project -- it is the game, and you are expected to have
your own copy. This script exists so the constants below are reproducible from a disc rather than
taken on trust from a checked-in blob.

What it CANNOT get, and why, so nobody wastes time looking:

  packet.key   The 4168-byte expanded schedule is not in the image, and the raw key it expands
               from is not in the constants region either (checked: none of the nearby .rodata
               constants expand to it). The game builds its schedule at runtime. This key was
               inherited from savemgo Nomad and remains the one artefact with no disc-derived
               provenance.

  session.key  Derivable in principle but not from the disc alone. The transform needs mode 6's
               64-byte context, produced by running the cipher over a blob at 0x10985F0 using the
               master context below -- and that blob is all zeroes on disc, materialised at
               runtime. Recovering it needs a memory dump of a running client.

Offsets are for BLUS30109. vaddr = file offset + 0x10000.
"""
import hashlib
import sys

DELTA = 0x10000

# (vaddr, length, name, what it is)
CONSTANTS = [
    (0xE25AD0, 4, "xor.key",
     "Whole-packet XOR key, applied to every game packet including the header."),
    (0xE25AD8, 16, "hmac.key",
     "HMAC-MD5 key for the packet checksum. Happens to be ASCII."),
    (0xE25AEC, 4168, "blowfish-pi.table",
     "Standard Blowfish pi-init table: 18 P entries then four 256-entry S-boxes. "
     "Not secret -- it is the published constant -- but confirms the cipher is textbook Blowfish."),
    (0xE26DA8, 64, "session-master.ctx",
     "Master context for the check-session transform: 8-byte IV then a 56-byte key. "
     "Decrypts mode 6's key blob into the working context."),
]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    with open(sys.argv[1], "rb") as f:
        image = f.read()

    print(f"{sys.argv[1]}\n{len(image)} bytes\n")

    for vaddr, length, name, description in CONSTANTS:
        offset = vaddr - DELTA
        if offset < 0 or offset + length > len(image):
            print(f"{name}: {vaddr:#x} is outside this image -- wrong binary?")
            continue

        data = image[offset:offset + length]
        digest = hashlib.sha256(data).hexdigest()[:16]

        print(f"{name}  @ {vaddr:#x}  {length} bytes  sha256:{digest}")
        print(f"  {description}")
        if length <= 32:
            print(f"  {data.hex(' ')}")
            printable = "".join(chr(b) if 32 <= b < 127 else "." for b in data)
            print(f"  {printable}")
        else:
            print(f"  {data[:16].hex(' ')} ...")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
