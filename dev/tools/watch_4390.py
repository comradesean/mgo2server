#!/usr/bin/env python3
"""Live-capture and decode 0x4390 stat reports (or any command) from the gamelobby log.

Follows `docker logs -f` on the gamelobby container, extracts every payload of the chosen
command id, pretty-prints it with the field labels established in dev/proto/mgo2_cmd_4390.ksy,
and archives each hit into a samples folder as:

  - NNN_HHMMSS_chID.bin   (raw payload; NNN continues from the highest number present)
  - log.txt               (appending, human-readable decode of every packet)

Usage:
    dev/tools/watch_4390.py                    # follow live 0x4390 (In and Out 0x4391 acks noted)
    dev/tools/watch_4390.py --replay           # process the container's whole existing log, then exit
    dev/tools/watch_4390.py --cmd 43a2         # watch a different command (hex dump if no decoder)
    dev/tools/watch_4390.py --container NAME   # non-default container

Requires the gamelobby at DEBUG (MGO2SERVER_LOG_LEVEL=DEBUG) so payloads are hex-dumped.
Stop with Ctrl-C. Decoders are labels-as-of 2026-07-24; see the ksy for evidence status.
"""
import argparse
import os
import re
import struct
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_CONTAINER = "mgo2server-gamelobby-1"

# --- 0x4390 field labels (dev/proto/mgo2_cmd_4390.ksy is the authority) -----------------

A_FIELDS = [  # (offset, size, fmt, name) — fmt: B=u8, h=s16, H=u16, I=u32
    (0x00, 4, "I", "chara_id"),
    (0x04, 1, "B", "snake_role_flag"),
    (0x05, 2, "h", "kills"),
    (0x07, 2, "h", "deaths"),
    (0x09, 2, "h", "lockon_kills"),
    (0x0B, 2, "h", "score_delta"),
    (0x0D, 2, "h", "knockouts_dealt"),
    (0x0F, 2, "h", "knockouts_received"),
    (0x11, 2, "h", "headshots_lethal"),
    (0x13, 2, "h", "headshot_deaths"),
    (0x15, 2, "h", "headshots_stun"),
    (0x17, 2, "h", "headshots_stun_received"),
    (0x19, 2, "h", "unknown_0x19"),
    (0x1B, 2, "h", "lockon_deaths"),
    (0x1D, 2, "h", "unknown_0x1d"),
    (0x1F, 2, "h", "round_completed"),
    (0x21, 2, "h", "zero_death_flag"),
    (0x23, 2, "H", "team_slot"),
    (0x25, 2, "H", "seconds"),
    (0x27, 4, "I", "experience_total"),
    (0x2B, 4, "I", "detail_present"),
]

B_NAMES = {
    0: "consecutive_kills", 1: "consecutive_deaths", 2: "consecutive_headshots",
    3: "suicides", 4: "unknown_b04", 5: "friendly_kills", 6: "friendly_stuns",
    7: "salutes", 8: "preset_radio_uses", 9: "text_chat_uses?",
    10: "cqc_given", 11: "cqc_taken", 12: "rolls", 13: "envg_time_s",
    14: "dedicated_host_time_s?", 15: "catapult_uses", 16: "boosts_given",
    17: "falling_deaths", 18: "trap_catches", 19: "scans_hacks", 20: "box_time_s",
    21: "box_uses", 22: "melee_hits_dealt", 23: "melee_hits_taken",
    24: "tdm_consecutive_survivals", 25: "bases_conquered", 26: "sop_destab_uses",
    27: "rescue_goals", 28: "gako_defended", 29: "gako_pickups", 30: "fully_defended",
    34: "capture_goals", 35: "wakes", 36: "combo", 37: "assists",
    39: "kill_1st_place", 40: "base_capture_points", 41: "rescue_b41",
    42: "rescue_carry", 46: "capture_puts", 47: "sne_dogtag_a", 48: "sne_dogtag_b",
    49: "wins_as_snake", 50: "holdups", 51: "snake_kills", 53: "sne_b53",
    54: "deaths_as_snake", 55: "sne_b55", 56: "rounds_as_snake",
}


def decode_4390(b: bytes) -> str:
    lines = []
    if len(b) < 0x2F:
        return f"  (short frame, {len(b)} bytes)\n  hex: {b.hex()}"
    for off, size, fmt, name in A_FIELDS:
        (val,) = struct.unpack(">" + fmt, b[off:off + size])
        if val != 0 or name in ("chara_id", "score_delta", "seconds"):
            lines.append(f"  {name:<26}= {val}")
    if len(b) >= 0x2F + 116:
        slots = struct.unpack(">58h", b[0x2F:0x2F + 116])
        for i, v in enumerate(slots):
            if v != 0:
                lines.append(f"  B{i:<2} {B_NAMES.get(i, 'unknown_b%02d' % i):<22}= {v}")
        (trail,) = struct.unpack(">I", b[0x2F + 116:0x2F + 120])
        if trail:
            lines.append(f"  TRAILING WORD NONZERO      = {trail:#x}  <-- never seen before, investigate")
    return "\n".join(lines)


def hex_dump(b: bytes) -> str:
    out = []
    for i in range(0, len(b), 16):
        chunk = b[i:i + 16]
        out.append(f"  {i:04x}  {' '.join(f'{c:02x}' for c in chunk)}")
    return "\n".join(out)


def next_index(folder: str) -> int:
    hi = 0
    for f in os.listdir(folder):
        m = re.match(r"(\d+)_", f)
        if m:
            hi = max(hi, int(m.group(1)))
    return hi + 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cmd", default="4390", help="command id hex to capture (default 4390)")
    ap.add_argument("--container", default=DEFAULT_CONTAINER)
    ap.add_argument("--replay", action="store_true", help="process the whole existing log and exit")
    ap.add_argument("--dir", default=None, help="output folder (default dev/proto/samples/<cmd>)")
    args = ap.parse_args()

    cmd = args.cmd.lower().lstrip("0x")
    folder = args.dir or os.path.join(REPO_ROOT, "dev", "proto", "samples", cmd)
    os.makedirs(folder, exist_ok=True)
    n = next_index(folder)
    logf = open(os.path.join(folder, "log.txt"), "a")

    docker = ["docker", "logs"] + ([] if args.replay else ["-f", "--tail", "0"]) + [args.container]
    proc = subprocess.Popen(docker, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    head_re = re.compile(
        r"^(?P<date>\d{4}-\d\d-\d\d) (?P<time>\d\d:\d\d:\d\d),\d+ .*DEBUG: "
        r"(?P<dir>In |Out) - command (?P<cmd>[0-9a-f]{4}) - (?P<len>\d+) bytes")
    hex_re = re.compile(r"DEBUG: (?P<hex>[0-9a-f]{2,})\s*$")

    pending = None  # header waiting for its hex line
    seen = 0
    print(f"Watching {'log history' if args.replay else 'LIVE'} on {args.container} "
          f"for 0x{cmd}; archiving to {folder} starting at {n:03d}. Ctrl-C to stop.")
    try:
        for line in proc.stdout:
            h = head_re.match(line)
            if h:
                pending = h if h.group("cmd") == cmd and h.group("dir").strip() == "In" else None
                continue
            if pending is None:
                continue
            x = hex_re.search(line)
            if not x:
                pending = None
                continue
            b = bytes.fromhex(x.group("hex"))
            if len(b) != int(pending.group("len")):
                pending = None
                continue
            ts = pending.group("time")
            chara = int.from_bytes(b[0:4], "big") if len(b) >= 4 else 0
            fname = f"{n:03d}_{ts.replace(':', '')}_ch{chara}.bin"
            with open(os.path.join(folder, fname), "wb") as f:
                f.write(b)
            body = decode_4390(b) if cmd == "4390" else hex_dump(b)
            block = (f"=== #{n:03d}  {pending.group('date')} {ts}Z  0x{cmd}  "
                     f"{len(b)} bytes  -> {fname}\n{body}\n")
            print(block)
            logf.write(block)
            logf.flush()
            n += 1
            seen += 1
            pending = None
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        logf.close()
    print(f"{seen} packet(s) captured.")


if __name__ == "__main__":
    main()
