# Server addresses: where the client gets them, and how to change them

Everything about how `BLUS30109` discovers the five Konami hostnames, the gate port and the STUN
port — and the three ways to point them at our own server. **The addresses are not in `MGO2.SELF`
and never were.** That belief cost most of a session; the note below on what was searched exists so
nobody repeats it.

**The recommendation, as of 2026-07-29: use `d/testhk`.** It is a drop-in file the game itself
looks for, it needs no modified game data, and deleting it restores stock behaviour exactly. The
other two routes are documented as fallbacks and are **not yet retired** — see
[Before retiring the fallbacks](#before-retiring-the-fallbacks).

---

## The three routes, ranked

| Route | Touches | Reversible | Status |
| --- | --- | --- | --- |
| **`d/testhk` override** | one new file on the HDD install | delete the file | **confirmed live 2026-07-29** |
| `scenerio.gcx` patch | rewrites shipped disc data | restore from backup | proven feasible, never run in game |
| RPCS3 IP swap list | emulator config only | edit the setting | works; emulator-specific, not a client change |

The IP swap list is not a client change at all — it rewrites the resolver inside RPCS3, so it
cannot help a real PS3 and it says nothing about what the game does. The other two change what the
game itself asks for.

---

## 1. Where the addresses live

`o/stage/lobby/scenerio.gcx`, **string-resource entries 28654–28691**: three 12-slot regional
blocks, each followed by a 13th field.

| Block | Entries | Gate host | Gate port | Region byte |
| --- | --- | --- | --- | --- |
| US | 28654–28666 | `mgo2gateus.konamionline.com` | 15731 | 1 |
| EU | 28667–28679 | `mgo2gateeu.konamionline.com` | 25731 | 2 *(inferred)* |
| JP | 28680–28692 | `mgo2gatejp.konamionline.com` | 5731 | 0 / default |

STUN is 3478 in all three. The US block in full:

| Slot | Entry | Content |
| --- | --- | --- |
| 0 | 28654 | `mgo2gateus.konamionline.com` + port 15731 |
| 1 | 28655 | `mgo2stunna.konamionline.com` + port 3478 |
| 2 | 28656 | `https://mgo2web.konami.com/us/mgo2/` |
| 3 | 28657 | `https://mgo2auth.konami.com/us/mgo2/kid/gidauth5.html` |
| 4 | 28658 | `http://mgo2stunna.konamionline.com/sttn/` |
| 5 | 28659 | `https://id.konami.net/` |
| 6 | 28660 | `https://mgo2web.konami.com/community/` |
| 7 | 28661 | `http://mgo2web.konami.com/us/mgo2/red/man.html` |
| 8 | 28662 | `https://mgo2web.konami.com/reward/` |
| 9 | 28663 | `http://mgo2web.konami.com/us/mgo2/red/mptshop.html` |
| 10 | 28664 | `http://mgo2web.konami.com/us/mgo2/red/official.html` |
| 11 | 28665 | `http://info.service.konamionline.com/VT006-U1/info/` |
| — | 28666 | `c1 00`, an integer 0 OR'd into the flag word. **Not a delimiter** |

EU and JP are the same twelve slots with `/eu/` + `VT006-E1` and `/jp/` + `VT006-J1`.
`id.konami.net/`, `/community/` and `/reward/` are identical across all three.

**Record encoding** (verified against all 28693 records): `07 <strlen+1> <ascii…> 00` for a string,
`01 <lo> <hi>` for a **little-endian** u16, trailing `00` ends the record.

**These are the source of the gate port.** `OBSERVED.md` records 15731 from RPCS3 logs; it is
readable here as disc data, and the "disc or region specific" guess is now settled — it is a
per-region field, EU 25731, JP 5731.

### Why every earlier search missed them

The strings are **not byte-visible even after stage decryption**. A raw search of the decrypted
`scenerio.gcx` for `mgo2gateus` returns −1. The string-resource blob is XOR-obfuscated with a
non-periodic keystream; only `gcx.exe -res` unpacks it.

Searched and clean, so nobody repeats it: `MGO2.SELF`, `MGO2.elf`, `EBOOT.BIN`, `EBOOT.elf`, and a
`grep -rla "konami.com"` over the **entire** `BLUS30109` folder — zero files. In the decrypted ELF,
`mgo2web.konami.com` was additionally searched under constant XOR (all 255 keys), constant ADD/SUB,
XOR-with-running-index (all 256 bases), any repeating XOR key of period 1–8 (via the `c[i]^c[i+L]`
signature, which finds a key without knowing it), UTF-16 LE/BE, and reversed. All negative. The
only `konami` substring in the binary is a leftover `t4136106.konami` at file `0x1024FF0`.

The HDD install holds none of it either — see [What is not on the HDD](#what-is-not-on-the-hdd).

---

## 2. The consumer

The table is not read by C++ looking up ids. It is pulled in by a **stage-script command**, which
is why the constants appear nowhere in the text section — they exist only as little-endian literals
in the GCX byte stream.

`lobby/scenerio.gcl`, `proc17`, switches on `$var:varbuf[4]` and calls
`command [cea915] -addrs $strres:28654` (US) / `28667` (EU) / `28680` (JP, the default arm).

| Address | What |
| --- | --- |
| `0x1031568` | GCX native registry entry `{hash 0x00CEA915, opd 0x1018CA8}` |
| `0x7F9310` | the `addrs` native itself |
| `0x7F9380` | `0x439EB9`, the hash of the `addrs` option; zero return skips the body |
| `0x7F93A4` | `0xDB178` reads the base strres id as a little-endian s16 from the script stream |
| `0x7F9440` | `r29 <= 1` — the test that makes only slots 0 and 1 take a port |
| `0x7F9460` | selects `id + 12` and ORs its integer into the flag word |
| `0x28AA90` / `0x28AB00` | `GetHostString(i)` / `SetHostString(i, s)` → `B + i*256` |
| `0x28AAD8` / `0x28AAB0` | `GetPort(i)` / `SetPort(i, v)` → `*(u16*)(B + 3072 + i*2)` |
| `0x00FC2F20` | holds `B` = `0x016188C8` (link-time constant) |
| `0x016188C8` | host slot `i` at `+ i*0x100`, 12 slots × 256 bytes |
| `0x016194C8` | port slot `i` at `+ i*2`; only 0 and 1 are ever written |
| `0x016194CC` | the flag word |

**Twelve slots is proved, not counted.** 12 × 256 = 3072 is exactly where the port array starts.

Where the values end up:

| Slot | Consumer |
| --- | --- |
| 0 gate | network context `+0xEE` (host) / `+0x16E` (port), built at `0x8849E8`; connect at `0x9462C0` (`lhz r5,366(r3)`), second reader `0xA7941C` |
| 1 STUN | context `+0x12E` / `+0x170`; also `0x8F0B88`, `0x8F0C60`, `0x8F0F10`, `0x8F1004` |
| 2 web base | context `+0xAE`; version check at `0xBB6938`, `0xBB6A70`, `0xBB6F78` (`uupdate.cc` cluster, TOC base `0xFFA350`) |
| 3 auth URL | `0xBB1BB4`, `strncpy` into `r27+12`, 128 bytes (`uaccount.cc` cluster, TOC base `0xFFA2B0`) |

`0xBB1BAC` also reads `di+44` — the disc serial word `9a 8d 7f 96` — and submits it with the login.

### Region select: `o/di` byte 42

| Address | What |
| --- | --- |
| `0x7F4A78` | the `varbuf[4]` native (hash `0x009BA0AC`, OPD `0x1018958`); body is `lbz r3,42(r9)` |
| `0x01698E04` | the 64-byte struct loaded verbatim from `o/di` |
| `0x2FB28` | the `di` loader — `open("di")`, read 64 bytes |
| `0x2FBD8` | the fallback when `di` is missing: writes defaults and **byte 42 = 0** → JP |

`o/di` is 64 bytes; **byte 42 = `0x01` on BLUS30109 → the US block** (verified directly). Byte 43 is
`0x02`. The same byte gates `varbuf[6]` in `init_n` and `nttitle`.

*Inferred, not checkable from this disc:* EU discs carry `di[42] == 2`.

---

## 3. The `d/testhk` override — the recommended route

`0x7F9310` opens `d/testhk` **before** touching the stage data. If the file yields a 16-byte
header, the whole table comes from it and the disc block is never read. It is retried on every
invocation.

**Path (verified from the game's own `sys_fs_open`):**

```
/dev_hdd0/game/BLUS30109/USRDIR/o/d/testhk
```

**The HDD install, not the disc.** RPCS3 logs `sys_fs_open(path="…/dev_hdd0/…/o/d/testhk")` →
`CELL_ENOENT`. The VFS serves different files from different roots — `bgm/`, `speech_e/`,
`sdpack_e/` from HDD, `stage/*.dlz` and the big `.dat` archives from `/dev_bdvd` — so this had to
be measured. `o/di` exists only on the disc side and is the cleanest discriminator between the two
trees.

### Format

```
16 bytes   header. Only byte 0 matters, and only its low two bits:
             bit 0 -> OR 1 into the flag word 0x016194CC
             bit 1 -> OR 2 into the same word
           Bits 2-7 and bytes 1-15 are read and never referenced.
then 12x   <string bytes> 0x00      NUL-terminated, read one byte at a time
           <2 bytes>                BIG-endian port; used for slots 0 and 1 only,
                                    read and discarded for 2-11, but MANDATORY
```

Minimum file 16 + 12×3 = **52 bytes**. Nothing after the twelfth record is read.

**There is no validation.** The only test in the header path is that the read returned exactly 16
bytes (`cmpdi cr7,r3,16` at `0x7F9368`). No magic, version, count, length or checksum. A header of
sixteen zeros is valid and sets neither bit.

**The port endianness is the opposite of the disc.** The loader does `lhz` on the raw file bytes
(`0x7F95C0`), so the file is big-endian — 15731 is `3D 73`, where the disc holds `73 3D`. The
strres path decodes little-endian at `0xDF9A8`. A byte-swapped port is the likeliest way to waste a
live test.

**String cap is 255 characters.** The loop exits at index 255 *without* terminating the buffer
(`0x7F9504`, `cmpwi cr6,r31,255`), and the copy that follows is an unbounded `strcpy` at `0xDCC680`
into a 256-byte slot. Over the cap is an overrun, not a truncation.

**Failure is safe.** Open failure, a short header, or any truncated read closes the handle and falls
through to the strres path, which overwrites all twelve slots and both ports. No crash, no half
state. If the file is fully consumed, the strres path is **skipped entirely**.

### It is encrypted

`d/testhk` is opened with the flag that routes it to the path-keyed asset opener, so a plaintext
file will not load.

| Address | What |
| --- | --- |
| `0x7F9330` | passes `"d/testhk"` with `r4 = 0x0000000180000000` (mode/flags packed) |
| `0x280F0` | at `0x28154`, bit 31 of the flags diverts to the encrypted opener |
| `0x2EE48` | the path-keyed opener: truncates the path at its **last** `/` for the key |
| `0x26ED8` / `0x258E0` | read / close, dispatching on the `0x08000000` handle tag |

**The key is the directory component** — `d` for `d/testhk`, `stage/lobby` for the lobby assets,
`online` for the HDD saves. That single rule covers every case.

> **Correction to `ASSETS.md`.** It states the key is "the stage's path". The general rule is the
> path truncated at the **last** `/`. The two readings agree on single-directory paths and diverge
> only on `stage/lobby/…`, where last-`/` gives the field-proven `stage/lobby`.

Build it with **`dev/tools/testhk_editor.py`** (stdlib Python, tkinter GUI, CLI fallback):

```bash
python3 dev/tools/testhk_editor.py --point-at 192.168.1.200 --http \
        --install "/path/to/rpcs3/dev_hdd0/game/BLUS30109/USRDIR"
```

It refuses to write to the disc tree, encrypts via Solideye, and re-decrypts to verify before
installing. Delete `o/d/testhk` to revert.

### Confirmed live, 2026-07-29

A 455-byte override (HTTPS retained) installed and loaded; the client then failed TLS. A 450-byte
rebuild with `--http` — five `https://` slots, one byte shorter each — **worked**. That confirms in
one stroke: the path, the key `d`, the 16-byte header, the record layout, the mandatory trailing
bytes, the big-endian ports, and that the override really does suppress the disc table.

---

## 4. Patching `scenerio.gcx` — the fallback

Proven feasible end to end, **never run in the game**. Use only if `testhk` turns out to be
unavailable on a target build.

- `Solideye -dec` → `-enc` with key `stage/lobby` is **bit-exact**, header included
  (md5 `532af9a1596a5f9a6a0517a62bbf3803` for the stock file).
- Decrypted layout: `0x68` section header (`0x4805E206` at `+0x10` is a **format magic, not a
  checksum** — the same value appears in `nttitle`); `0x7c` offset table, 28693 × u32 LE, **plaintext**,
  low 24 bits = record offset, top byte a flag; `0x1C0D0` blob start, `0x12AFB0` bytes,
  XOR-obfuscated.
- **The obfuscation is XOR-linear**, so it never has to be understood: to change plaintext P→P′,
  XOR the file byte by `P^P′`.
- Equal-length edits touch only the string bytes. Length changes also need table entries after the
  edited record rewritten, preserving each flag byte. No count, length or checksum needs updating.
- Convenient layout accident: the server table is the **last 1585 bytes of the blob**, so a length
  change shifts nothing else.

Entry 28656 sits at decrypted offset `0x146A93` (table slot `0x1C03C`), 39 bytes:
`07 24 "https://mgo2web.konami.com/us/mgo2/" 00 00`.

The table exists **only** in `lobby/scenerio.gcx`. `init_n`, `nttitle` and `ota_chat` carry
support/marketing URLs only.

---

## 5. RPCS3 IP swap list — the emulator fallback

`config/custom_configs/config_BLUS30109.yml`, key `IP swap list`, format
`host=ip&&host=ip`. Editable with **`dev/tools/ipswap_editor.py`**. Close RPCS3 first — it rewrites
its config on exit.

Covers only the five hostnames the client resolves. Note the table above has a sixth,
`id.konami.net`, which the swap list does not include; it has not been observed being dialled.

---

## What is not on the HDD

Nothing on the HDD side stores a server address. Every client-written file is decrypted and
accounted for: five `.sav` files, ten `.emb` clan emblems, an empty `photo_mgo/`. No hostname, IP
or port in plaintext or ciphertext, and the installer's 1.2 GB `stage01.dat` does **not** embed the
disc's lobby stage (sampled 48-byte runs from `cache.dar`/`.qar`/`.vfp` are absent).

**Consequence: there is no HDD-side cache to repoint or poison.** The client resolves the gate every
session, so the disc block — or `testhk` — is the single source.

Two findings worth carrying elsewhere: `ac.sav` is a **persisted copy of record-store record 25**,
which answers `CLIENT_STORE.md`'s open question about whether any of the store survives to disk
(record 25 does; the other 25 do not). And `helpdisp.sav` is written **unencrypted** — encryption is
opt-in per call site, not a property of the directory.

---

## Before retiring the fallbacks

**Open: does `d/testhk` exist in 1.36?** Everything above is read from release-day `BLUS30109`.
The override is a developer facility, and developer facilities are exactly the kind of thing a
later build strips. Until a 1.36 binary has been checked, the other two routes stay.

What to check, in order:

1. Does the `addrs` native still open `d/testhk` before the strres path — i.e. does the equivalent
   of `0x7F9310` still contain the open call?
2. Is the format the same? Twelve slots, 16-byte header, big-endian ports, mandatory trailing
   bytes.
3. Is the file still keyed on `d`, and still on the HDD install rather than the disc?
4. Is the strres block still 28654-based, and is the region still `di` byte 42?

If 1 fails, the gcx route becomes the primary and section 4 is the recipe.

## Other open questions

- **The flag word `0x016194CC`.** Bit 1 is read at `0xBB1538`, `0xBB2260` (`uaccount.cc`) and
  `0xBB92AC`, `0xBBC9A8` (`uupdate.cc`); what it gates is unknown. **Bit 0 has no reader** — a
  negative worth keeping, since the six flag-word loads that were resolved all test bit 1.
  Neither is the HTTPS switch: the scheme is part of the stored URL string.
- **TLS from the host's native RPCS3.** `.121`/`.122` complete handshakes; `.100` sends
  `certificate_unknown` and closes. `CA30.cer` md5-matches the repo CA, is PEM like the stock
  certs, the leaf verifies against it with SANs covering all the hostnames, and no `vfs.yml`
  redirects `dev_flash`. Unresolved. The discriminator not yet run: connect from a VM against the
  same probe.
- **Solideye's cipher vs the game's** is confirmed only by the `stage/lobby` case working in the
  field. The key derivation shape read from the ELF (64-byte blob XOR a 16-byte digest of the
  directory, repeating) matches Solideye's own construction, but they have not been compared byte
  for byte.

---

## Reproducing the extraction

```bash
S=<scratch>
D="…/PS3_GAME/USRDIR"
SE=dev/tools/solideye; GX=dev/tools/gcx
cd $SE
./Solideye.exe -dec "$(wslpath -w "$D/o/stage/lobby/scenerio.gcx")" \
               -k stage/lobby -o "$(wslpath -w $S/dec)"
# -> scenerio.gcx.dec, 1374068 bytes (input 1374092; a 24-byte container is stripped)
mkdir -p $S/gcx; cp $GX/gcx.exe $GX/dictionary.txt $GX/commands.txt $S/gcx/
cp $S/dec/scenerio.gcx.dec $S/gcx/scenerio.gcx
cd $S/gcx && ./gcx.exe -res "$(wslpath -w $S/gcx/scenerio.gcx)"
# -> scenerio_strres/28654.bin … 28691.bin
```

Both tools are Windows `.exe` run under WSL interop, they accept **Windows paths only**, and
`gcx.exe` writes into the current working directory. `gcx.exe` has **no repack option** — which is
why section 4 edits the decrypted blob in place rather than rebuilding it.

See [ASSETS.md](ASSETS.md) for the wider asset-extraction method.
