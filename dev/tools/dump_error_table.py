#!/usr/bin/env python3
"""Regenerates dev/docs/ERRORS.md from the retail binary and the extracted lobby strings.

Inputs:
  dev/ref/MGO2 (decrypted).elf                     the error table at vaddr 0x106D714
  /mnt/f/ClaudeHole/mgo2_extract/gcx/scenerio_strres  control entries (Solideye + Gcx output)
  dev/analysis/strings/lobby.txt                   id -> text, from the same extraction

  dev/analysis/dialog_paths.json                   result code -> dialogId, from
                                                   dev/tools/trace_dialog_paths.py

Run trace_dialog_paths.py first if the code -> dialogId mapping needs refreshing; this script
only turns dialogIds into sentences. Nothing in ERRORS.md is hand-written — edits made to that
file are destroyed on the next run, so prose belongs in ARM_NOTES below.
"""
import json, struct, pathlib

ELF = "/mnt/f/ClaudeHole/nomad/dev/ref/MGO2 (decrypted).elf"
PATHS = pathlib.Path("/mnt/f/ClaudeHole/nomad/dev/analysis/dialog_paths.json")

# Which dispatcher arm serves which command. Only filled in where a live client or a capture has
# tied the two together; every other arm is named from the operation its own sentences describe,
# which identifies the screen without claiming to know the command id.
ARM_COMMANDS = {
    22: "0x4b01 — create clan",
    23: "0x4b05 — disband clan",
    25: "0x4b51 — set clan emblem",
    29: "0x4b43 — apply to join clan",
}
STRRES = pathlib.Path("/mnt/f/ClaudeHole/mgo2_extract/gcx/scenerio_strres")
CONTROL_BASE, TEXT_BASE = 21368, 21898


def is_japanese(t):
    """Whether a string is the JP variant, i.e. holds CJK or kana."""
    return any('\u3000' <= c <= '\u9fff' or '\uff00' <= c <= '\uffef' for c in t)


def english(slots, texts):
    """The English string id out of one control entry's six language slots.

    Entries come in two shapes and the difference is not structural: some carry a Japanese
    variant first and English second, others start at English. Assuming slot 1 everywhere put
    French in a third of the table. So the slots are read and the JP one, if present, is skipped.
    """
    ids = [TEXT_BASE + o for o in slots]
    if not ids:
        return None
    # A missing id counts as Japanese. The string extraction drops entries with no Latin
    # characters, so a pure-kana line is absent rather than present-and-Japanese, and testing the
    # text alone put the whole JP-first family one slot early — 23808 instead of 23809.
    first = texts.get(ids[0])
    if first is None or is_japanese(first):
        return ids[1] if len(ids) > 1 else ids[0]
    return ids[0]

texts = {}
for line in open("/mnt/f/ClaudeHole/nomad/dev/analysis/strings/lobby.txt", encoding="utf-8", errors="replace"):
    if "\t" in line:
        i, t = line.split("\t", 1)
        if i.isdigit():
            texts[int(i)] = t.rstrip("\n")

def offsets(path):
    d = path.read_bytes(); p = 8; out = []
    while p < len(d) and len(out) < 6:
        b = d[p]
        if b == 0x01: out.append(struct.unpack("<H", d[p+1:p+3])[0]); p += 3
        elif b == 0x02: out.append(d[p+1]); p += 2
        elif b & 0xC0 == 0xC0: out.append(b & 0x3F); p += 1
        else: break
    return out if len(out) == 6 else None

d = open(ELF, "rb").read(); off = 0x106D714 - 0x10000
rows, sec = [], None
for i in range(664):
    dialog, ordinal = struct.unpack(">Ii", d[off+8*i:off+8*i+8])
    if ordinal == -1:
        sec = dialog; continue
    rows.append((sec, dialog, ordinal))

def text_for_dialog(dialog):
    for s, dl, ordinal in rows:
        if dl != dialog or s is None or s >= 32:
            continue
        f = STRRES / f"{CONTROL_BASE + ordinal}.bin"
        o = offsets(f) if f.exists() else None
        if o:
            sid = english(o, texts)
            return sid, texts.get(sid, "")
    return None, ""

out = []
w = out.append
w("# Client error codes and their messages\n")
w("""The client turns a server error code into an on-screen message through a table it carries
itself. Nothing about that is guessable — sending a code that is *nearly* right produces a
confidently wrong sentence, which is how we spent a session telling players their clan could not
be found when the emblem was merely on cooldown.

This document is generated from the retail binary. Regenerate with
`dev/tools/dump_error_table.py`.
""")
w("## How a code becomes a sentence\n")
w("""```
server sends result code
  -> per-op error block in the dispatcher     (0xA7DCEC-0xA7E9A8, and near-identical copies)
  -> dialogId                                  chosen by an explicit `cmpwi` chain
  -> 0x885A08(dialogId, code, ctx)             raises the dialog
  -> 0xB8F988                                  linear-scans the table at 0x106D714
  -> {u32 dialogId, i32 ordinal}               664 entries; ordinal -1 marks a section
  -> 0x240708(groupHash, ordinal)              fetches the string
```

Sections below 32 resolve against `MGO_ERROR_RES_LOBBY` (name at `0xE1FD30`), whose strings are
registered in the lobby script `scenerio.gcl` as `-s[1d914] [3d915] $strres:21368 $strres:21898`:
control base **21368**, text base **21898**. A control entry is
`06 <groupHash LE24> 06|0d <itemHash LE24>` followed by six per-language offsets
(`0xC0|n` for n < 64, `01 <u16 LE>`, or `02 <u8>`).

Entries come in two shapes, and the difference is not visible in their structure: some carry a
Japanese variant first, so the order is JP, EN, FR, DE, IT, ES; others begin at English, giving
EN, FR, DE, IT, ES. Reading slot 1 unconditionally puts French in about a third of the table, so
the generator skips slot 0 only when it is Japanese. So

```
stringId(EN) = 21898 + <the English slot> of control file (21368 + ordinal)
```

**Positive control.** Character creation replies `-260`, which the dispatcher maps to dialog 2626,
table index 177, ordinal 148, control file 21516, EN offset 811, string **22709** — *"Desired
character name is already in use."* That is exactly what the client shows, so the chain is proved
rather than assumed.
""")

# Prose that belongs to one arm and cannot be derived from the binary. It lives here rather than
# in ERRORS.md because that file is generated: an earlier version of this analysis was hand-edited
# into the output and was destroyed the next time the generator ran.
ARM_NOTES = {
    29: """**Five of this screen's sentences cannot be reached through a result code.** DialogIds
6454, 6455, 6456, 6458 and 6460 are never loaded into `r3` anywhere in the binary — including
*"A fixed amount of time must pass in order to apply to join a clan."* (6458) and *"You are on the
clan leader's Block List."* (6454). No result code produces them, so a server-side join cooldown or
block-list refusal has to settle for the generic 24101. Carrying the text is not the same as being
able to show it; check this table before designing a refusal around a sentence you found in a
string dump.

This started as "`li r3,6458` occurs nowhere", which only covered the result-code path. The
display path has since been inventoried end to end, and the stronger claim now holds: **no
dialogId in this binary is computed from data.** Every one reaches the display queue through one
of **14 call sites** of `0x7FA780`, and at all of them the id is a compile-time constant — 167
direct `li`, 20 from a two-way `subfic` select, 9 set in the preceding block, and 2 memory loads
whose only writers are themselves `li`. None of those constants is 6454, 6455, 6456, 6458 or 6460.

Where they *do* live: the per-screen message-id constructor `0x756F90` installs them into fields
of a 384-byte object (`152/192/196/200/264`), and nothing reads those fields into a raiser.
`0x7550B0` is an instruction-identical dead twin — called from nowhere and absent from the OPD
table. One mechanism accounts for all five sentences at once, which is what makes this an
explanation rather than a gap.

Unresolved, and stated as such: no reader of that struct's dialogId fields was found at all, so
what the object is *for* is unknown. That is a hole in the description, not in the conclusion,
which rests on the raiser-side inventory being total. What would overturn it: a capture of a real
server making this client print one of those sentences.

This block is also why the tracer exists. Hand-reading missed it for a while because it is only
eight instructions long with one `li` inside it: `bgt cr7,0xA7E924` sends everything above `-1207`
to a continuation 0x4E0 bytes away, `-1217`'s `li` lives in a shared trampoline pool at
`0xA7E7A0`, and `-160` takes two hops through `0xA7E808`, itself shared with the mail block. The
sweep follows all of that without being told to, and independently reproduces the hand reading —
which is the check that the two agree, not just that the tool ran.""",
}

paths = json.loads(PATHS.read_text()) if PATHS.exists() else None

def describe(dialog):
    """A dialogId as `string | message`, or the silent case."""
    if dialog is None:
        return "—", "_(no dialog raised — the code is stored and the screen does not respond)_"
    sid, txt = text_for_dialog(dialog)
    return str(sid or "—"), (txt.replace("|", "\\|") if txt else f"_(dialog {dialog}, no string)_")

def operation(arm):
    """Name an arm from the operation its own default sentence describes."""
    if arm["index"] in ARM_COMMANDS:
        return f"`{ARM_COMMANDS[arm['index']]}`"
    _, txt = describe(arm["default"])
    tail = txt.split("\\n")[-1].strip()
    for lead in ("Unable to ", "You are ", "This "):
        if tail.startswith(lead):
            return tail.rstrip(".")
    return tail.rstrip(".") or "unattributed"

w("## Codes worth sending\n")
if paths:
    w(f"""Generated by `dev/tools/trace_dialog_paths.py`, which runs each of the dispatcher's
`cmpwi` chains concretely once per candidate result code ({paths['sweep'][0]}..{paths['sweep'][1]})
and records where each one lands. That is a complete description of the chain rather than a
reading of it: an edge is found whether it came from an equality test, a range test or
arithmetic, and each block's **default** path — the answer for every code not named — is reported
rather than left implicit.

These are the client's own codes: send them raw, not masked with `GameError.MASK`.

The arms below are the {len(paths['arms'])} entries of the jump table at `{paths['table']}`,
indexed by an operation ordinal the client stores at `104(r31)`. Four are tied to a command id by
observation; the rest are named from the operation their own sentences describe, which identifies
the screen without claiming to know the command id.
""")
    for arm in paths["arms"]:
        if not arm["resolved"]:
            w(f"\n### Arm {arm['index']} — not analysed  <sub>{arm['entry']}</sub>\n")
            w("This chain is not a pure function of the result code — it calls out and reloads the")
            w("code from memory, so the tracer declined it rather than guessing. "
              f"({arm['unmodeled_reason'][0] if arm['unmodeled_reason'] else 'unmodelled'})\n")
            continue
        w(f"\n### Arm {arm['index']} — {operation(arm)}  <sub>{arm['entry']}</sub>\n")
        w("| code | string | message |")
        w("| --- | --- | --- |")
        for s in arm["spans"]:
            code = f"`{s['lo']}`" if s["lo"] == s["hi"] else f"`{s['lo']}`..`{s['hi']}`"
            sid, msg = describe(s["dialog"])
            w(f"| {code} | {sid} | {msg} |")
        sid, msg = describe(arm["default"])
        w(f"| _(any other)_ | {sid} | {msg} |")
        if arm["unmodeled"]:
            w(f"\n{arm['unmodeled']} codes on this arm were declined rather than guessed at.")
        if arm["index"] in ARM_NOTES:
            w("\n" + ARM_NOTES[arm["index"]])
else:
    w("`dev/analysis/dialog_paths.json` is missing — run `dev/tools/trace_dialog_paths.py`.\n")

if paths:
    twin = next((t for t in paths["other_tables"] if t["table"] == "0xA7ED30"), None)
    w("\n## What else raises a dialog\n")
    w(f"""The tracer also sweeps the rest of the binary, so the reach of the list above is measured
rather than assumed. There are **{paths['raise_sites']}** call sites of `0x885A08` in the image.
They divide up like this.

**{paths['fixed_code_sites']} report a fixed code.** The instruction before the call is
`li r4,<const>`, so no server result code reaches them. These are the client's own checks —
password length, parental controls, a missing save — and no code we send can produce or suppress
them.

**{len(paths['constant_raises'])} raise the same dialogId whatever the code.** The code is carried
through to the `(nnnn:FFFFFFFF)` suffix the player sees, but it does not select the sentence, so
there is nothing to choose between. Sending a cleverer code to one of these changes the number in
the brackets and nothing else.

**{len(paths['inline_chains'])} are inline chains that do discriminate**, outside any jump table
({', '.join(sorted({c['entry'] for c in paths['inline_chains']}))}). They are in the mail
family and are listed in the JSON rather than here.

**{paths['raise_sites'] - len(paths['raise_sites_covered']) - paths['fixed_code_sites']} are unaccounted for.** They carry a result code but the tracer could not recover a chain for them and
verify it, so nothing is claimed about them either way. That is a known gap, not a clean bill of
health: a sentence absent from this document is not thereby proved unreachable unless the argument
for it is spelled out, as it is for arm 29. `dev/analysis/dialog_paths.json` carries the site
list.
""")
    if twin:
        live = [a for a in twin["arms"] if a["default"] is not None]
        w(f"""### The network-error twin  <sub>{twin['table']}</sub>

A second {len(twin['arms'])}-arm table sits beside the first and is indexed by the same operation
ordinal. Every one of its {len(live)} live arms is fixed: it raises that operation's *"A network
server error has occurred.\\nUnable to X"* dialog and never inspects a result code. Arm 22 gives
create-clan's, arm 29 apply-to-join's, and so on, each matching the `-160` row of the
corresponding arm above.

So the client has two ways to report the same operation failing: one that reads a code we sent,
and one for when nothing came back at all. Only the first is ours to drive.
""")

w("\n## The full table\n")
w("Every entry whose section resolves to `MGO_ERROR_RES_LOBBY`. The dialogId is what the")
w("dispatcher selects; the string is what the player reads.\n")
w("| dialogId | ordinal | string | message |")
w("| --- | --- | --- | --- |")
resolved = unresolved = blank = 0
for s, dialog, ordinal in rows:
    if s is None or s >= 32:
        unresolved += 1
        continue
    f = STRRES / f"{CONTROL_BASE + ordinal}.bin"
    o = offsets(f) if f.exists() else None
    if not o:
        unresolved += 1
        continue
    sid = english(o, texts)
    txt = texts.get(sid, "").replace("|", "\\|")
    resolved += 1
    blank += not txt
    w(f"| {dialog} | {ordinal} | {sid} | {txt} |")

w("\n## Blank messages\n")
w(f"""{blank} rows resolve to a string id that carries no text. Those are real ids, not decode
failures — the extraction has the surrounding ids and simply nothing at that one, which is what an
unused slot in a locale block looks like. Treat a blank as "this dialogId exists but the retail
build shipped no English string for it", and do not send its code expecting a message.
""")

w("\n## Not resolved\n")
w(f"""{unresolved} of {resolved + unresolved} entries belong to sections 32
(`MGO_ERROR_RES_GAME`, name at `0xE1FD18`) and 33 (`MGO_ERROR_RES_GMINFO`, `0xE1FD00`). Those two
groups are not registered in the lobby script, so their control and text bases are unknown and their
ordinals cannot be turned into strings from the lobby extraction alone. They are in-game errors
rather than lobby ones, so the bases are presumably registered in a stage script under
`dev/analysis/strings/` other than `lobby`; finding them is the whole remaining work.
""")
pathlib.Path("/mnt/f/ClaudeHole/nomad/dev/docs/ERRORS.md").write_text("\n".join(out) + "\n", encoding="utf-8")
print("resolved", resolved, "unresolved", unresolved)
