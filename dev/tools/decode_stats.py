#!/usr/bin/env python3
"""Decode a 0x4390 end-of-round stat report into labelled slots.

The report is a fixed-layout superset (mode-INDEPENDENT); modes differ only in which slots the
results screen shows and how it weights them into the score. Confirmed by a two-round TDM match
and a Rescue Mission round (2026-07-22) — see dev/docs/OBSERVED.md, "The 0x4390 scoreboard".

Usage:
    # paste the hex the freebattle1 logs at DEBUG right after "In  - command 4390":
    python3 decode_stats.py 000000010000050002...           # one payload
    python3 decode_stats.py <hex1> <hex2>                   # several, side by side
    # or pipe hex lines in:
    docker logs mgo2server-freebattle1-1 | grep -A1 'command 4390' | ... | python3 decode_stats.py -

Correlate the printed A/B slots against the results screen: report each player's per-category
counts (Kill/Death/Headshot/Stun/Assist/... plus mode objectives like Goal/Team Win/Target
Defence) and match distinct values to slots. All-equal values (everyone got 1) cannot be told
apart — push for a match with distinct counts to finish the unlabelled slots.
"""
import struct
import sys

# Confirmed labels (struct A, signed s16 at 0x05 + 2*i). See OBSERVED.md.
A_LABELS = {
    0: "kills",
    1: "deaths",
    3: "score (signed; mode-weighted total)",
    4: "stun/knockout",
    6: "headshots dealt",
    7: "headshot-deaths (=enemy headshots; medium-high)",
    13: "rounds (1/report)",
    14: "objective: Team Win OR Target Defence (unsplit)",
}
# Unlabelled A slots seen nonzero: A2, A5, and mode objectives (Goal, Assist, ...). B block
# (0x2f, 58x s16) is a separate itemised breakdown, positions known / meanings not.


def decode(payload: bytes) -> dict:
    if len(payload) < 0x2b:
        raise ValueError(f"payload too short: {len(payload)} bytes (need >= 0x2b)")
    a = [struct.unpack(">h", payload[5 + 2 * i:7 + 2 * i])[0] for i in range(15)]
    has_b = len(payload) >= 0xa7
    b = [struct.unpack(">h", payload[0x2f + 2 * i:0x31 + 2 * i])[0] for i in range(58)] if has_b else []
    return {
        "id": struct.unpack(">I", payload[0:4])[0],
        "flag@0x04": payload[4],
        "A": a,
        "time@0x23": struct.unpack(">I", payload[0x23:0x27])[0],
        "exp@0x27": struct.unpack(">I", payload[0x27:0x2b])[0],
        "extraflag@0x2b": struct.unpack(">I", payload[0x2b:0x2f])[0] if len(payload) >= 0x2f else None,
        "B": b,
        "len": len(payload),
    }


def show(payload: bytes):
    d = decode(payload)
    print(f"=== character id {d['id']}  ({d['len']} bytes)  flag@0x04={d['flag@0x04']}  "
          f"exp={d['exp@0x27']}  time@0x23={d['time@0x23']} ===")
    for i, v in enumerate(d["A"]):
        if v or i in A_LABELS:
            off = 0x05 + 2 * i
            print(f"  A{i:<2} 0x{off:02x} = {v:6}   {A_LABELS.get(i, '?')}")
    nz = [(i, v) for i, v in enumerate(d["B"]) if v]
    if nz:
        print("  B nonzero (0x2f detail block, unmapped):",
              ", ".join(f"B{i}=0x{0x2f + 2 * i:02x}:{v}" for i, v in nz))
    print()


def main():
    args = sys.argv[1:]
    if args == ["-"]:
        args = [line.strip() for line in sys.stdin if line.strip()]
    if not args:
        print(__doc__)
        return
    for hx in args:
        hx = hx.strip().replace(" ", "")
        try:
            show(bytes.fromhex(hx))
        except ValueError as e:
            print(f"skip ({e}): {hx[:32]}...")


if __name__ == "__main__":
    main()
