#!/usr/bin/env python3
"""Live-capture and decode 0x4390 stat reports (or any command) from the gamelobby log.

Follows `docker logs -f` on the gamelobby container, extracts every payload of the chosen
command id, pretty-prints it with the field labels established in dev/proto/mgo2_cmd_4390.ksy,
and archives each hit into a samples folder as:

  - NNN_HHMMSS_chID.bin   (raw payload; NNN continues from the highest number present)
  - log.txt               (appending, human-readable decode of every packet)

Only client->server ("In") frames are captured; "Out" frames, including the 0x4391 acks,
are ignored entirely.

Usage:
    dev/tools/watch_4390.py                    # follow live 0x4390
    dev/tools/watch_4390.py --replay           # process the container's whole existing log, then exit
    dev/tools/watch_4390.py --cmd 43a2         # watch a different command (hex dump if no decoder)
    dev/tools/watch_4390.py --container NAME   # one container, or a comma-separated list

By default every game-lobby container is followed at once and each hit is labelled with the lobby
it came from, so a report cannot be missed by watching the wrong one.

Requires the gamelobby at DEBUG (MGO2SERVER_LOG_LEVEL=DEBUG) so payloads are hex-dumped.
Stop with Ctrl-C. Decoders are labels-as-of 2026-07-27; see the ksy for evidence status.
Timestamps in filenames and log.txt are the container's local log clock, not UTC.
A header whose payload cannot be recovered is reported and counted, never dropped quietly.
"""
import argparse
import os
import re
import struct
import queue
import subprocess
import sys
import threading

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Every game lobby, because the stack runs one container per lobby row and a report only appears
# in the lobby it was played in. Watching a single container silently misses everything else --
# a 0x4390 from a training session went unnoticed that way on 2026-07-26.
DEFAULT_CONTAINERS = [
    "mgo2server-gamelobby-1",
    "mgo2server-automatching-1",
    "mgo2server-basictraining-1",
    "mgo2server-combattraining-1",
]

# --- 0x4390 field labels (dev/proto/mgo2_cmd_4390.ksy is the authority) -----------------

A_FIELDS = [  # (offset, size, fmt, name) — fmt: B=u8, h=s16, H=u16, I=u32
    (0x00, 4, "I", "chara_id"),
    (0x04, 1, "B", "flag_0x04"),
    (0x05, 2, "h", "kills"),
    (0x07, 2, "h", "deaths"),
    (0x09, 2, "h", "lockon_kills"),
    (0x0B, 2, "h", "score"),
    (0x0D, 2, "h", "knockouts_dealt"),
    (0x0F, 2, "h", "knockouts_received"),
    (0x11, 2, "h", "headshots_lethal"),
    (0x13, 2, "h", "headshot_deaths"),
    (0x15, 2, "h", "headshots_stun"),
    (0x17, 2, "h", "headshots_stun_received"),
    (0x19, 2, "h", "lockon_stuns_dealt"),
    (0x1B, 2, "h", "lockon_deaths"),
    (0x1D, 2, "h", "lockon_stuns_received"),
    (0x1F, 2, "h", "round_completed"),
    (0x21, 2, "h", "flawless_win"),
    (0x23, 2, "H", "team_win"),
    (0x25, 2, "H", "seconds_in_game"),
    (0x27, 4, "I", "experience_total"),
    (0x2B, 4, "I", "detail_present"),
]

B_NAMES = {
    0: "consecutive_kills", 1: "consecutive_deaths", 2: "consecutive_headshots",
    3: "suicides", 4: "self_stuns", 5: "friendly_kills",
    6: "friendly_stuns", 7: "salutes", 8: "preset_radio_uses",
    9: "text_chat_uses", 10: "cqc_given", 11: "cqc_taken",
    12: "rolls", 13: "envg_time_s", 15: "catapult_uses",
    16: "boosts_given", 17: "falling_deaths", 18: "triggered_trap",
    19: "sop_scans", 20: "box_time_s", 21: "box_uses",
    22: "melee_hits_dealt", 23: "melee_hits_taken", 24: "tdm_consecutive_survivals",
    25: "bases_conquered", 26: "sop_destabilizer_uses", 27: "gako_saved",
    28: "gako_defended", 29: "gako_pickups", 30: "fully_defended_matches",
    31: "rescue_solo_team_wipe", 32: "tsne_spots_made", 33: "tsne_times_spotted",
    34: "capture_goals", 35: "wakes", 36: "combo",
    37: "assists", 38: "headshot_only_penalty_deaths", 39: "kill_1st_place",
    40: "base_capture_time_points", 41: "rescue_carry_marker", 42: "rescue_carry_magnitude",
    43: "tsne_first_pickup", 44: "tsne_carry_time", 45: "tsne_goals",
    46: "capture_put_count", 47: "sne_bodysearches", 48: "sne_dogtags_collected",
    49: "wins_as_snake", 50: "holdup_count", 51: "snake_kills",
    52: "mk2_kills", 53: "times_spotted_snake", 54: "times_spotted_as_snake",
    55: "first_to_spot_snake_per_life", 56: "rounds_as_snake", 57: "mk2_knockouts_dealt",
}

# Slots whose label is still [PREDICTED] in the ksy — printed with a trailing '?' so the
# output never presents a hypothesis as a settled label.
# Empty as of 2026-07-27: b09 text_chat_uses was confirmed live, and b45's
# `training_mode_time_s` was not confirmed but REFUTED — the score table makes it a rule-7
# scoring category, not a duration. Nothing else carries a bare hypothesis as its name.
B_PREDICTED: set[int] = set()


def decode_4390(b: bytes) -> str:
    """Decode one 0x4390 payload. Zero-valued fields are omitted except the few always
    shown, so an absent line means zero, not missing."""
    lines = []
    if len(b) < 0x2F:
        return f"  (truncated frame, {len(b)} bytes, expected >= 47)\n  hex: {b.hex()}"
    for off, size, fmt, name in A_FIELDS:
        (val,) = struct.unpack(">" + fmt, b[off:off + size])
        if val != 0 or name in ("chara_id", "score", "seconds_in_game"):
            lines.append(f"  {name:<26}= {val}")
    (detail,) = struct.unpack(">I", b[0x2B:0x2F])
    if detail and len(b) >= 0x2F + 120:
        slots = struct.unpack(">58h", b[0x2F:0x2F + 116])
        for i, v in enumerate(slots):
            if v != 0:
                name = B_NAMES.get(i, "unknown_b%02d" % i) + ("?" if i in B_PREDICTED else "")
                lines.append(f"  B{i:<2} {name:<22}= {v}")
        (trail,) = struct.unpack(">I", b[0x2F + 116:0x2F + 120])
    elif detail:
        lines.append(f"  !! detail_present={detail} but only {len(b)} bytes — frame truncated")
        return "\n".join(lines)
    else:
        lines.append("  (short form, detail_present=0, no struct B)")
        (trail,) = struct.unpack(">I", b[0x2F:0x33]) if len(b) >= 0x33 else (0,)
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
    ap.add_argument("--container", default=",".join(DEFAULT_CONTAINERS),
                    help="container name, or comma-separated list (default: every game lobby)")
    ap.add_argument("--replay", action="store_true", help="process the whole existing log and exit")
    ap.add_argument("--dir", default=None, help="output folder (default dev/proto/samples/<cmd>)")
    args = ap.parse_args()

    cmd = args.cmd.lower().removeprefix("0x")  # NOT lstrip: it strips a char set, so "04c0" -> "4c0"
    folder = args.dir or os.path.join(REPO_ROOT, "dev", "proto", "samples", cmd)
    os.makedirs(folder, exist_ok=True)
    n = next_index(folder)
    logf = open(os.path.join(folder, "log.txt"), "a")

    containers = [c.strip() for c in args.container.split(",") if c.strip()]
    follow = [] if args.replay else ["-f", "--tail", "0"]
    procs = [(c, subprocess.Popen(["docker", "logs"] + follow + [c],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
             for c in containers]

    head_re = re.compile(
        r"^(?P<date>\d{4}-\d\d-\d\d) (?P<time>\d\d:\d\d:\d\d),\d+ .*DEBUG: "
        r"(?P<dir>In |Out) - command (?P<cmd>[0-9a-f]{4}) - (?P<len>\d+) bytes")
    hex_re = re.compile(r"DEBUG: (?P<hex>[0-9a-f]{2,})\s*$")

    pending = None  # header waiting for its hex line
    pending_source = ""  # which container that header came from
    seen = 0
    dropped = 0  # headers seen but not archived — never let these go by silently
    print(f"Watching {'log history' if args.replay else 'LIVE'} on {', '.join(containers)} "
          f"for 0x{cmd}; archiving to {folder} starting at {n:03d}. Ctrl-C to stop.")

    def lines_from_all():
        """Interleave the containers' streams. One reader thread per container feeds a queue, so a
        silent lobby never blocks a busy one — which a sequential read would do."""
        q = queue.Queue()
        for name, proc in procs:
            def pump(name=name, proc=proc):
                for line in proc.stdout:
                    q.put((name, line))
                q.put((name, None))
            threading.Thread(target=pump, daemon=True).start()
        live = len(procs)
        while live:
            name, line = q.get()
            if line is None:
                live -= 1
                continue
            yield name, line

    try:
        for source, line in lines_from_all():
            h = head_re.match(line)
            if h:
                pending = h if h.group("cmd") == cmd and h.group("dir").strip() == "In" else None
                pending_source = source
                continue
            if pending is None:
                continue
            x = hex_re.search(line)
            if not x:
                print(f"  !! 0x{cmd} header at {pending.group('time')} with no hex line following"
                      f" — packet LOST (is the log at DEBUG?)")
                dropped += 1
                pending = None
                continue
            try:
                b = bytes.fromhex(x.group("hex"))
            except ValueError:
                print(f"  !! 0x{cmd} at {pending.group('time')}: unparsable hex — packet LOST")
                dropped += 1
                pending = None
                continue
            if len(b) != int(pending.group("len")):
                print(f"  !! 0x{cmd} at {pending.group('time')}: header says "
                      f"{pending.group('len')} bytes, hex line has {len(b)} — packet LOST "
                      f"(payload split across lines?)")
                dropped += 1
                pending = None
                continue
            ts = pending.group("time")
            chara = int.from_bytes(b[0:4], "big") if len(b) >= 4 else 0
            fname = f"{n:03d}_{ts.replace(':', '')}_ch{chara}.bin"
            with open(os.path.join(folder, fname), "wb") as f:
                f.write(b)
            body = decode_4390(b) if cmd == "4390" else hex_dump(b)
            block = (f"=== #{n:03d}  {pending.group('date')} {ts}  0x{cmd}  "
                     f"{len(b)} bytes  [{pending_source}]  -> {fname}\n{body}\n")
            print(block)
            logf.write(block)
            logf.flush()
            n += 1
            seen += 1
            pending = None
    except KeyboardInterrupt:
        pass
    finally:
        for _, proc in procs:
            proc.terminate()
        logf.close()
    print(f"{seen} packet(s) captured, {dropped} dropped."
          + ("  <-- DROPPED PACKETS: the capture is incomplete, do not read the set as a"
             " whole exchange." if dropped else ""))


if __name__ == "__main__":
    main()
