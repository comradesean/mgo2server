#!/usr/bin/env python3
"""Regenerates dev/docs/ERRORS.md from the retail binary and the extracted lobby strings.

Inputs:
  dev/ref/MGO2 (decrypted).elf                     the error table at vaddr 0x106D714
  /mnt/f/ClaudeHole/mgo2_extract/gcx/scenerio_strres  control entries (Solideye + Gcx output)
  dev/analysis/strings/lobby.txt                   id -> text, from the same extraction

The CODES list is hand-maintained: those pairs come from reading the dispatcher's cmpwi
chains in the disassembly, not from any table, so a new one has to be traced before it can
be added here.
"""
import struct, pathlib

ELF = "/mnt/f/ClaudeHole/nomad/dev/ref/MGO2 (decrypted).elf"
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

# codes recovered from the dispatcher error blocks (disassembly, not the table)
CODES = [
 ("0x4b01", "create clan", "0xA7E680", [
   (-1206, 6412), (-1200, 6408), (-1230, 6415), (-1231, 6411),
   (-1233, 6410), (-262, 6410), (-160, 6414), (-24, 6409)]),
 ("0x4b05", "disband clan", "0xA7E74C", [(-1205, 6517), (-1207, None), (-1203, None)]),
 ("0x4b51", "set clan emblem", "0xA7E410", [
   (-1216, 6524), (-1215, 6420), (-1218, 6529), (-1207, 6404), (-160, 6528)]),
 ("0x4b43", "apply to join clan", "0xA7E43C", [(-1217, None), (-1201, None), (-1207, None), (-160, None)]),
 ("0x4801", "send mail (per recipient)", "0x8EFD40", [
   (-830, 6176), (-810, None), (-801, None), (-802, None), (-831, None), (-832, None), (-1230, None)]),
 ("0x3103", "delete character", "0x94F60C", [(-268, 2659), (-1212, 2658), (-241, 2660), (-260, 2626)]),
]

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

w("## Codes worth sending\n")
w("Recovered from the dispatcher's `cmpwi` chains. These are the client's own codes: send them")
w("raw, not masked with `GameError.MASK`.\n")
for cmd, what, addr, pairs in CODES:
    w(f"\n### `{cmd}` — {what}  <sub>{addr}</sub>\n")
    w("| code | string | message |")
    w("| --- | --- | --- |")
    for code, dialog in pairs:
        sid, txt = text_for_dialog(dialog) if dialog else (None, "")
        msg = txt.replace("|", "\\|") if txt else "_(dialogId not recovered)_"
        w(f"| `{code}` | {sid or '—'} | {msg} |")

w("\n## The full table\n")
w("Every entry whose section resolves to `MGO_ERROR_RES_LOBBY`. The dialogId is what the")
w("dispatcher selects; the string is what the player reads.\n")
w("| dialogId | ordinal | string | message |")
w("| --- | --- | --- | --- |")
resolved = unresolved = 0
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
    w(f"| {dialog} | {ordinal} | {sid} | {txt} |")

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
