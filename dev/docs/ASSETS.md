# Opening the disc assets

How to get at MGO2's own data files — the compiled stage scripts, the UI layouts and, most
usefully, the **string resources that hold every UI label**. Established 2026-07-27, when the
Personal Stats slot names were needed and turned out not to be in `MGO2.elf` at all.

This is tier-1 evidence in the same sense the ELF is: it is the shipped game data. It is
*not* a substitute for the ELF when the question is behaviour — the disc says what a label reads,
the binary says what feeds it. Confusing the two is how `training_mode_time_s` happened.

## The crypto

**The key is the path with its last `/` component removed — the directory the file sits in.**
Corrected 2026-07-29 from the opener itself (`0x2EE48` calls `strrchr(path, '/')` and truncates
there); the earlier wording here, "the stage's own path string", happened to be right for stages
and wrong as a general rule.

The rule covers everything the game opens through this path, not just stages:

| File the game opens | Key |
| --- | --- |
| `stage/lobby/cache.dar`, `.qar`, `.vfp`, `.gcx`, `data.cnf` | `stage/lobby` |
| `stage/r_onlinelobby/*` | `stage/r_onlinelobby` |
| `online/ac.sav`, `opt.sav`, `mgof.sav`, `scradj.sav` | `online` |
| `clanemblem/emblem<N>.emb` | `clanemblem` |
| `d/testhk` — the server-address override, see [HOSTS.md](HOSTS.md) | `d` |

No leading `o/` in any of them: the game passes the path relative to its data root, and the VFS
resolves that root per file (some to `/dev_bdvd`, some to `/dev_hdd0` — see HOSTS.md).

**Encryption is opt-in per call site, not a property of the directory.** `helpdisp.sav` sits
alongside the other four saves and is written **unencrypted**; the caller sets bit 31 of the open
mode to request the encrypting stream (`0x280F0` diverts to `0x2EE48` at `0x28154`, and the handle
is tagged `0x08000000` so `0x26ED8`/`0x258E0` dispatch to the decrypting reader and closer).

`o/di` and `o/kit` are **not** key material. That lead was chased and is dead.

The cipher is a position-keyed XOR keystream, so one key decrypts every file in the directory:
`cache.qar` and `cache.vfp` in `lobby/` open with the identical six bytes `ac f1 11 47 85 f7`, and
`cache.dar` differs from them at exactly the positions where the plaintext differs.

Solideye says so itself — `strings Solideye.exe` yields *"Key not set, set key with -k. Usually
this is the path to where the file resides"*. Worth remembering before theorising about key files:
**read the tool's own strings first.**

## Extraction

Both tools are Windows `.exe` and run directly under WSL interop — no wine — but they only accept
**Windows paths**, so every path argument goes through `wslpath -w`.

```bash
S=/tmp/<scratchpad>
D="/mnt/d/.../PS3_GAME/USRDIR"          # the disc dump, NOT dev_hdd0/game/BLUS30109
SE=/mnt/f/ClaudeHole/nomad/dev/tools/solideye
cd $SE

# 1. decrypt — key is the stage's path
cp "$D/o/stage/lobby/cache.dar" $S/disc/lobby/
./Solideye.exe -dec "$(wslpath -w $S/disc/lobby/cache.dar)" \
               -k stage/lobby -o "$(wslpath -w $S/dec/lobby)"
# -> cache.dar.dec, header now "00 00 01 59 album_name.la2..."

# 2. extract — -f is required; the .dec suffix defeats autodetect
./Solideye.exe -e "$(wslpath -w $S/dec/lobby/cache.dar.dec)" -f dar \
               -dict "$(wslpath -w $SE/dictionary.txt)" -o "$(wslpath -w $S/ex/lobby_dar)"
# -> $S/ex/lobby_dar/Dar/*   (345 files for lobby, with real names)
```

**If extraction "succeeds" but produces an empty output folder, the input is still encrypted.**
Solideye exits 0 and creates the type directory either way, which reads exactly like a tool that
does not support the format. It cost a pass to work that out.

Verified on `lobby`, `r_onlinelobby`, `nttitle`, `ota_chat`, `nt_mgsetup`, `init_n`, for both
`cache.*` and `resident.*`. Filetypes Solideye accepts: `dar`, `qar`, `slot`, `stage`.

## The stage script — where the UI text actually is

```bash
cd $S/gcxrun     # copy gcx.exe + dictionary.txt + commands.txt here first
./gcx.exe -res "$(wslpath -w $S/gcxrun/scenerio.gcx)"    # input = the DECRYPTED gcx
# -> scenerio.gcl           decompiled script
# -> scenerio_strres/N.bin  28693 string-resource entries (lobby)
```

**`gcx.exe` writes into the current working directory.** Do not run it from `dev/tools/gcx/` or it
drops `.gcl` output into the repo.

The Personal Stats labels live in `lobby/scenerio.gcx`, string-resource group
`$strres:17779`/`$strres:17942`, sub-group hash `1ab3b6`, control ordinals 65–151 — 63 stat labels
in order, each with FR/DE/IT/ES and often JP, each with a stable 24-bit resource hash. The hash is
a rotate-5-add over the resource name, computed at `0xD25D0` in the ELF.

## Reading `scenerio_strres/` — the index table, and the trap of counting

**1. Build a flat index first. Never glob-grep the directory.** The lobby dump is 28,693 separate
`<n>.bin` files, and a `grep -l "..." *.bin` over them takes minutes and will time out before it
finishes. One pass to a single TSV makes every later question instant:

```python
import os
with open('/tmp/<scratchpad>/lobby_strres.tsv','w') as out:
    for i in range(28693):
        p = '%d.bin' % i
        if not os.path.exists(p): continue
        d = open(p,'rb').read().replace(b'\x00', b'')
        try: t = d.decode('utf-8')
        except UnicodeDecodeError: t = d.decode('latin-1')
        out.write('%d\t%s\n' % (i, t.replace('\n','\\n').replace('\t',' ')))
```

**2. The file index is NOT the string id — and there IS an index table, so do not count records.**

`scenerio_strres/<n>.bin` is **two things concatenated, thirteen times over**. Each
`[hash] $strres:START $strres:END` line in `scenerio.gcl` (line 2330 onward) gives that group's
**index-record range**; the group's **string pool** is the files between that range's end and the
next group's start.

| group | index files | pool files |
| --- | --- | --- |
| `[40eff4]` | 0-341 | 342-1526 |
| `[7a133b]` | 1527-3389 | 3390-9788 |
| `[2f0293]` | 9789-11033 | 11034-16523 |
| `[642318]` | 16524-16738 | 16739-17778 |
| `[e60831]` | 17779-17942 | 17943-18865 |
| `[d97d38]` | 18866-18926 | 18927-19155 |
| `[1c4a02]` | 19156-19229 | 19230-19567 |
| `[b0e35e]` | 19568-19606 | 19607-19716 |
| `[4f1c53]` | 19717-19743 | 19744-19813 |
| `[d2c5a4]` | 19814-20082 | 20083-21054 |
| `[6acf0d]` | 21055-21115 | 21116-21367 |
| `[03d915]` | 21368-21898 | 21899-24953 |
| `[f0d736]` | 24954-25816 | 25817-28692 |

**`id = index_file_number − group_index_start`.** Index record layout, all little-endian:

```
06 <u24 group_tag>  <tag> <u24 name_hash>  [flag]  <6 varints>  00
tag 0x06 -> no flag byte;  tag 0x0d -> one 0x01 flag byte follows
varint:  b >= 0xC1  -> value = b - 0xC1      (0..62)
         b == 0x02  -> value = next byte     (0..255)
         b == 0x01  -> value = next 2 bytes LE
value 0 = "no string";  otherwise pool_file = (pool_start - 1) + value
```

The six values are **JP, EN, FR, DE, IT, ES**, and deduplication is simply two languages pointing
at the same pool file — which is why *counting* records drifts and *reading* them does not.

**Control for the decoder:** all **5,728** index records across all thirteen groups decode with
exactly six values each, and **zero** values land outside their own group's pool. A wrong
group→pool assignment or a mis-read varint blows up both counts immediately. A working decoder
is at `dev/tools/strres.py` (`resolve(index_file)`, `h24(name)`, `GROUPS`, `POOL`).

**The `name_hash` is the same rot-5-add 24-bit hash the ELF uses** (`h = ((h<<5 | h>>19) + c) &
0xFFFFFF`, implemented at `0xD25D0`). So a resource name in the binary — `CLAN_SUBJECT`,
`HOST_STANCE_EASY`, `MESSAGE_8` — resolves straight to its record without knowing its id.

**Two different group identifiers, and mixing them wastes a pass.** The `[hash]` in `scenerio.gcl`
names the *set*; the record's own `group_tag` field is what the **ELF** passes as the resolver's
first argument, and they are not equal. `gcl [2f0293]` records carry tag **`0x00F914BF`** — the
constant loaded at `0x8E0C24`, i.e. the lobby and Create Game text — and `gcl [e60831]` records
carry **`0x6B01B5`**, the mailbox text. Match on the tag when you are starting from the binary, on
the gcl hash when starting from the script.

**Superseded, and worth saying why:** an earlier version of this section advised anchoring on a
code-proven id and *walking records outward*, because the packing looked variable and unreadable.
That works, but it is guesswork with a control bolted on, and it drifts — it produced a run of
Common Settings ids that were uniformly wrong by 37 (they were the *help* ids; help sits at
`label + 37`) and an "anchor" that did not exist. **Read the index table instead.** The general
lesson is the project's own: when a structure looks like it has to be inferred, check whether the
format simply carries the answer.

**A group registered by one stage can hold another stage's text.** The Common Settings strings are
in the *lobby* dump even though the screen belongs to a different stage. They looked at first like
they fell outside every range `scenerio.gcl` declares — file 13515 is in none of them — but that
was the index/pool confusion above: 13515 sits in `[2f0293]`'s **pool** (11034-16523), reached from
index file 10337 = id 548. `r_onlinelobby`'s own `scenerio.gcx` is a 101-byte stub, so there is no
second script to extract; look in the lobby set for text you expect elsewhere before concluding it
is missing.

## `.dlz` — SEGS, not supported by Solideye

After decryption a `.dlz` is a concatenation of **SEGS** streams on `0x20000` boundaries.
Big-endian header: `char[4] "segs"`, `u16 flags`, `u16 blockCount`, `u32 uncompressedSize`,
`u32 unknown`, then an 8-byte-per-block table of `u16 compressedSize, u16 uncompressedSize,
u32 offset`. **The offset is 1-based** (`dataStart = offset − 1`); blocks pad to 16 bytes;
`compressedSize == uncompressedSize` means stored, otherwise raw deflate
(`zlib.decompress(blk, -15)`); a size of 0 means `0x10000`.

The payloads are texture and model blobs — **no text**, searched in ASCII, UTF-16LE and UTF-16BE.

## What the disc will and will not tell you

It gives the **complete label vocabulary**: every UI string, ordered, in six languages, with a
stable hash per label.

It does **not** give the label-to-slot binding for the per-mode stats pages. Of the 63 stat labels
only 36 hashes appear in `MGO2.elf` at all, and a search of the whole binary for the DETAIL page's
slot sequence at every stride in u8/u16/u32 found nothing. The binding is in code, TOC-relative —
so naming the remaining slots is ELF work or a live fingerprint session, not disc work.

Two useful tables were found on the ELF side while chasing it: the DETAIL page display list
(36 × u32 resource hashes at `0xE13BDC`, duplicated at `0xE13C6C`) and the title/award threshold
table (39 rows of `{awardId, stringHash, threshold}` at `0xE139C0`, terminated by `0xFFFFFFFF`).
The award table exposes two counters the client tracks with no Personal Stats label at all:
`%d consecutive headshots` and `%d targets captured`.

## Caveat on the mounted paths

`dev_hdd0/game/BLUS30109/USRDIR` is the **HDD install** — its `o/online/` holds five `.sav` files
and nothing else. The disc dump proper is under RPCS3's `games/` directory (see `config/games.yml`
for the path); that is where `o/MGO2.SELF`, `o/stage/` and `o/slotdat/` live.
