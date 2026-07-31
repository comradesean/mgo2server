#!/usr/bin/env python3
"""Decode a 0x4310 host-settings blob (the decrypted 352-byte push) into its known fields.

Offsets are the ones GameService.applyHostSettings reads, all live-confirmed 2026-07-22 (the
Common Settings map, weapon restrictions, and level-limit base were each pinned by single-variable
hosting captures — see dev/docs/OBSERVED.md). The client stores this per (character, lobby
subtype); the blob_audit trigger (blob_audit.sql) archives every push so consecutive hosts do not
overwrite the evidence.

Usage:
    # dump the decrypted blob from the audit table as hex, then decode:
    docker exec mgo2server-postgres-1 psql -U mgo2server -d mgo2server -t -A \\
        -c "select encode(blob,'hex') from blob_audit order by id desc limit 1" \\
      | python3 decode_settings.py -
    python3 decode_settings.py <hex>
"""
import struct
import sys

RULES = {0: "Deathmatch", 1: "Team Deathmatch", 2: "Rescue", 3: "Capture",
         4: "Sneaking", 5: "Base"}  # rule 1 & 2 confirmed live; rest inferred from screen order

# commonA @0x142, commonB @0x143 — capture-proven bit maps (mirror GameListEntry packers).
COMMON_A = {0: "idle-kick enable", 2: "always-set", 3: "friendly fire", 4: "ghosts",
            5: "auto-aim", 7: "uniques"}
COMMON_B = {0: "teams switch", 1: "auto assign", 2: "silent mode", 3: "enemy nametags",
            4: "level limit enable", 6: "voice chat", 7: "team-kill enable"}


def bits(val, table):
    return [name for bit, name in sorted(table.items()) if val & (1 << bit)] or ["(none)"]


def show(b: bytes):
    def u8(o): return b[o]
    def u16(o): return struct.unpack(">H", b[o:o + 2])[0]
    def u32(o): return struct.unpack(">I", b[o:o + 4])[0]
    def s(o, n): return b[o:o + n].split(b"\0", 1)[0].decode("latin1", "replace")

    print(f"len {len(b)} (0x{len(b):x})")
    print(f"  name @0x00      = {s(0x00, 16)!r}")
    print(f"  comment @0x10   = {s(0x10, 128)!r}")
    print(f"  password @0x90  = enabled {u8(0x90)}  {s(0x91, 16)!r}")
    print(f"  dedicated @0xA1 = {u8(0xA1)}")
    print(f"  rotation @0xA3  (rule,map,flags)x15:")
    for i in range(15):
        o = 0xA3 + i * 3
        rule, mp, fl = b[o], b[o + 1], b[o + 2]
        if rule == 0 and mp == 0:
            break
        print(f"      [{i}] rule={rule} ({RULES.get(rule, '?')}) map={mp} flags={fl}")
    print(f"  weapon restr @0xD5 = {b[0xD5:0xE5].hex()}  (bit0 of byte0 = enabled)")
    print(f"  max players @0xE5  = {u8(0xE5)}")
    print(f"  briefing @0xE6     = {u32(0xE6)}")
    print(f"  stance @0xF6       = {u8(0xF6)}")
    print(f"  lvl-limit tol@0xF7 = {u8(0xF7)}   base @0xF8 (u32) = {u32(0xF8)}")
    print(f"  17 timers @0xFC    = {[u32(0xFC + 4 * i) for i in range(17)]}")
    print(f"  uniques @0x140     = red {u8(0x140)} blue {u8(0x141)}")
    print(f"  commonA @0x142 = 0x{u8(0x142):02x}  {bits(u8(0x142), COMMON_A)}")
    print(f"  commonB @0x143 = 0x{u8(0x143):02x}  {bits(u8(0x143), COMMON_B)}")
    print(f"  idle-kick @0x146 = {u8(0x146)}   team-kill @0x148 = {u8(0x148)}")
    print(f"  host-options @0x155 = 0x{u8(0x155):02x}  (bit1 = non-stat)")


def main():
    args = sys.argv[1:]
    if args == ["-"]:
        args = [sys.stdin.read().strip()]
    if not args:
        print(__doc__)
        return
    for hx in args:
        show(bytes.fromhex(hx.strip().replace(" ", "")))
        print()


if __name__ == "__main__":
    main()
