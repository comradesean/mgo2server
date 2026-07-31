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
