# dev/tools

Everything here is run by hand. Nothing in this directory is mounted by `compose.yaml` or needed by
the running stack — that is `dev/runtime/`. These are the things you run to *change* what the stack
serves, to read something out of the game binary, or to watch a live session.

Two of them do real work against a console and are documented in full below: **`build_patch_round.py`**
(builds the in-game 1.0 → 1.36 patch) and **`testhk_editor.py`** (points the game at your server).
The rest are catalogued at the end.

Most tools need only Python 3. The patch tools additionally need `pycryptodome`
(`pip install pycryptodome`); `testhk_editor.py` needs the bundled `solideye/Solideye.exe`, which
is a Windows binary.

---

## `build_patch_round.py` — build and serve the in-game patch

Builds a complete, real 1.0 → 1.36 upgrade and stages it in the document root the probes serve, so
the game's **own** patch mechanism installs it. No file is placed on the console by hand.

The format itself is specified in **`dev/docs/PATCH_FORMAT.md`** — read that if you want to know
*what* is being built rather than how to run the builder. `dev/docs/PATCH_HANDOFF.md` is the
working state of the investigation.

### What you need first

1. **The 1.36 patch tree**, at `dev/PATCHES/PATCH 1.36/o/` (this path is the default; override with
   `--tree`). Its layout mirrors the install target, which is the point — what you see is where it
   goes:

   ```
   dev/PATCHES/PATCH 1.36/o/
       MGO2.SELF              the 1.36 executable
       dl/.p                  the DLT2 manifest describing the tree
       dl/.p.original.bak     Konami's pristine manifest, kept for reference
       dl/p/…                 659 data files in 8 subdirectories, ~2 GB
   ```

2. **The server armed.** `MGO2SERVER_CLIENT_VERSION=1.36` in `server.env`. This is the only switch —
   there is no separate patch toggle. Unset (or `1.0`) means the checkver reply is a single `0x00`
   "no update" byte and the builder will refuse to run.

3. **A regenerated checkver reply**, which is what actually offers the update:

   ```
   MGO2SERVER_CLIENT_VERSION=1.36 python3 build_checkver.py
   ```

### Building

The canonical full round — the real executable plus every data file:

```
MGO2SERVER_CLIENT_VERSION=1.36 python3 build_patch_round.py \
    --level 1.12 --blob --include-self --data all --zlib-level 1 \
    --mac 6d676f327365727665725f736c6f7438 --encrypt
```

Roughly 100 seconds; it streams, so memory stays flat regardless of the 2 GB input. It writes two
archives and two `.inf`s into `dev/runtime/www/us/mgo2/patch/1.36.0/` and **verifies each one by
replaying the client's read chain over it**, refusing to write anything that does not decode.

| flag | what it does |
| --- | --- |
| `--blob` | The authentic shape: one downloadable archive per record. `BLUS30109.<from>to<to>` carries the executable (it is disc-specific), `<from>to<to>` carries the data tree (shared across BLUS/BLES/BLJM). Without this you get one download per file, which is not how the real patch works. |
| `--data manifest\|root\|all` | What the generic archive carries besides the manifest. `manifest` is `.p` alone (fast, ~15 KB — good for testing placement); `root` adds the five files directly under `dl/p/`; `all` adds the whole 659-file tree. |
| `--include-self` | Include `MGO2.SELF`. Its source is `--self-file`, defaulting to the tree's own copy. |
| `--mac <hex>` | The key for the envelope's outer HMAC. **This must match what the client's key provider returns** — see the warning below. |
| `--encrypt` | Blowfish-CBC the archive body under the slot-7 key. Required; the client always stacks the decrypt filter. Implies `--container`. |
| `--zlib-level N` | Deflate level, default 6. Use **1** for `--data all`: the tree is mostly already-compressed audio, so 1 costs almost no ratio and several minutes less time. |
| `--level <ver>` | Which version-stamped subset to ship when not using `--blob`. Mostly vestigial for full rounds; it still names the round in the log. |
| `--dry-run` | Build and measure everything, print the plan, write nothing. |
| `--no-place` | Emit `MGO2.SELF` and `.p` as plain names so they land in `dl/p/` with everything else. This is **wrong** and exists only as the A/B control for the placement finding — see below. |
| `--no-compress` | Omit the zlib layer. Also wrong, also only a control. The client's inflate filter fails and the install silently extracts nothing. |

> **The `--mac` key is not universal.** It is whatever the client's crypto slot provider returns for
> slot 8. The value above is the ASCII string `mgo2server_slot8`, which is what *this* project's
> modified `MGO2.SELF` returns — a stock retail executable would demand Konami's real key. If you
> are working with a different client build, this value is yours to discover, not to copy.

### Placement, because it is the non-obvious part

Where a file lands is decided by its **name**, not by any flag. A plain name goes to `dl/p/<name>`;
a name of the form `..N/<rest>` goes N directory levels up from there first. The builder applies
this automatically:

```
MGO2.SELF  ->  ..2/MGO2.SELF  ->  o/MGO2.SELF     (what the loader reads)
.p         ->  ..1/.p         ->  o/dl/.p         (what the archive reader opens)
everything else                ->  o/dl/p/…       (its actual home)
```

A round built with `--no-place` installs all 660 files perfectly and accomplishes nothing, because
the two files whose location matters are both in the wrong directory. That failure looks exactly
like success.

### Deploying and verifying

The probes serve `dev/runtime/www` from a read-only mount, so new files are live immediately — but
the checkver reply is only regenerated by `build_checkver.py`, so re-run that if you changed
versions or hosts.

Always verify before running a client:

```
MGO2SERVER_CLIENT_VERSION=1.36 python3 verify_patch_round.py
```

This fetches over HTTP exactly as the client would, streams each archive back through the crypto
chain, walks the extract list, and hashes every member against its source file. It catches the
things the builder's own check cannot: a stale file in the document root, a truncated write, a
declared size that disagrees with what the server sends, or the probe answering with a fallback
page. Add `--no-content` to skip the per-member hashing (much faster), or `--local` to read the
document root directly rather than over HTTP.

### Before each console run

The install writes a lock file and removes it on success. **A failed install leaves it behind, and
it poisons every subsequent attempt** until deleted.

```
U="…/dev_hdd0/game/BLUS30109/USRDIR"
H="…/dev_hdd1/caches/BLUS30109_BLUS30109"      # note: RPCS3 gives hdd1 a per-title cache root
find "$U/o/dl" "$H/o/dl" -name .l -delete
mkdir -p "$U/o/dl/p/ar" "$H/o/dl/p/ar"
```

For a genuinely clean test also remove the previous run's output (`$U/o/MGO2.SELF`, `$U/o/dl/`) so
that what appears afterwards is unambiguously this run's work.

### Why an up-to-date client is not offered the patch again

The client's own version gate only checks that it is **at least** the record's FROM version — it
never compares against the TO version, so it cannot tell it is already current. `http_probe.py`
therefore parses the packed version out of the checkver POST and answers a bare `0x00` when the
client is at or above what the reply would offer. The decision is logged:

```
checkver body: b'19136512,BLUS30109,1180'
client is 1.36.0, offer is 1.36.0 -- answering 0x00, already up to date
```

The TO version is read back out of the reply itself, so this cannot drift from what
`build_checkver.py` wrote. If the body cannot be parsed it **fails open** — serves the offer
and says so in the log — rather than silently locking a 1.0 client out of patching.

### Reverting to normal play

Blank `MGO2SERVER_CLIENT_VERSION` in `server.env` and re-run `build_checkver.py`. The client
then gets the `0x00` "no update" byte and the version-check screen advances as usual.

---

## `testhk_editor.py` — point the game at your server

MGO2's twelve server hostnames and two ports are **not** in `MGO2.SELF`. They are string resources
in `o/stage/lobby/scenerio.gcx`. But the loader opens **`d/testhk`** first, and if that file yields
a valid 16-byte header it takes the entire address table from the file and never reads the disc
data. So repointing the game needs no patching at all — you write one file, and deleting it
restores stock behaviour exactly.

This is the supported route and is confirmed working. `dev/docs/HOSTS.md` covers the alternatives
and why they are worse.

### Usage

With no arguments it opens a GUI; every field is editable and it shows what each slot feeds.
Headless is usually what you want:

```
python3 testhk_editor.py --no-gui \
    --point-at 192.168.1.200 \
    --http \
    --install "/mnt/d/rpcs3-…/dev_hdd0/game/BLUS30109/USRDIR"
```

| flag | what it does |
| --- | --- |
| `--point-at HOST` | Replace every host/authority in the table with yours. The one flag most runs need. |
| `--http` | Downgrade every `https://` to `http://`. |
| `--install USRDIR` | Encrypt and write `o/d/testhk` under that USRDIR, backing up any existing file. |
| `--plain FILE` | Write the **plaintext** form here instead — useful for inspection, not loadable by the game. |
| `--read FILE` | Start from an existing plaintext table rather than the stock one. |
| `--region US\|EU\|JP` | Which stock table to start from. Default `US`, which is what BLUS30109 selects. |
| `--gate-port` / `--stun-port` | Override the two ports. |
| `--skip-psn` | Set header bit 1. **On 1.36 this skips the PSN / MGO-Shop entitlement check** that otherwise blocks login with dialog `0x5012`. No known effect on the disc build. |
| `--flag-bit0` | Set header bit 0. Effect not established. |

### Things that will waste a live test

- **The file is encrypted.** `d/testhk` is opened through the path-keyed asset opener, which derives
  its key from the directory component of the path (`d`). A plaintext file simply will not load.
  This tool builds the plaintext and then calls `solideye/Solideye.exe` to encrypt it — a Windows
  binary, so on Linux you need WSL or Wine.
- **Ports in the file are big-endian**, which is the *opposite* of how the disc stores them. 15731
  is `3D 73`. The tool handles this; hand-editing is where it bites.
- **Failure is silent but safe.** A missing file, a short header, or any truncated read falls
  through to the disc table, which overwrites every slot. There is no half-loaded state — but also
  no error telling you your file was ignored.
- The disc build reads **12** records, 1.36 reads **16**. A table built for one is not the other.

---

## Everything else

### Patch tooling

**`build_checkver.py`** writes `dev/runtime/www/us/mgo2/patch/checkver.html` — the reply that
offers the patch — plus the release note beside it. It is the switch that turns the whole thing on:

```
python3 build_checkver.py                                 # 0x00 "no update", normal play
MGO2SERVER_CLIENT_VERSION=1.36 python3 build_checkver.py  # offer 1.0.0 -> 1.36.0
```

**Run it after any change to the version, host or keys.** Despite the `.html` extension the file
is binary, and the client POSTs to it rather than GETting it. The probes mount the document root
read-only, so the new reply is live immediately.

The reply carries the base URLs, the version-range records, and the two key blobs the client files
into slots 7 and 8 — **encrypted**, because the client's key fetch is a decrypt, not a copy.
`MGO2SERVER_PATCH_HOST`, `..._FROM`, `..._TO` and `..._DISC_ID` override the host, range and disc
id.

Announcing a record commits you to serving a real `.inf` and archive beside it: a record with no
files on disk makes the client fetch the probe's fallback page, which fails invisibly from the
server side. `build_patch_round.py` builds those.

**`build_torrent.py`** writes the `.torrent` for the P2P path into the docroot beside the payloads:

```
MGO2SERVER_CLIENT_VERSION=1.36 python3 build_torrent.py
```

**Re-run it after every `build_patch_round.py`.** The torrent is a hash of the payload bytes —
116,282 SHA-1 piece digests over the current ~1.9 GB round — so a stale one describes files that no
longer exist, and nothing warns you: the client fetches a perfectly valid torrent, fails every
piece, and it looks like a network fault. It prints an `info_hash`, which is how you check that the
two halves agree:

```
build_torrent.py    -> info_hash: ec9a1f0c8c63cd261da70f23aafb3ca47b5b1ffc
probe-bt at startup -> seeding info_hash ec9a1f0c…, 1905156512 bytes across 116282 piece(s)
```

Different hashes mean the served torrent and the seeder describe different bytes. `probe-bt`
recomputes from the payload files at startup, so restart it after rebuilding.

The P2P path has never completed a transfer: the client fetches and parses the torrent correctly
and connects to the peer, then stalls, and HTTP is what actually delivers a round. It is kept
working because that stall is an open question, not because anything depends on it.

| tool | what |
| --- | --- |
| `build_inf_stub.py` | The `.inf` layout and crypto envelope, importable and runnable standalone. `build_patch_round.py` builds on it. |
| `verify_patch_round.py` | Replays the client's read chain over what the **server is actually serving**, and hashes every extracted member against its source. |
| `build_torrent.py` | Writes the `.torrent` for the P2P path — **re-run after every `build_patch_round.py`**, see below. |
| `parse_dl_manifest.py` | Parses the `DLT2` manifest at `o/dl/.p` — names, sizes, versions, digests. |

### Reading the game binary

| tool | what |
| --- | --- |
| `extract_keys.py` | Pulls the crypto constants out of your own copy of `MGO2.elf`, with offsets. |
| `dump_error_table.py` | Regenerates `dev/docs/ERRORS.md` — all 556 codes and the sentence each produces. |
| `trace_dialog_paths.py` | Traces every `result code → dialogId` path in the binary. |
| `analyze_mgo2.py` | PPC64 BE instruction decoding and data-flow tracing, read-only. |

### Decoding live traffic

| tool | what |
| --- | --- |
| `decode_settings.py` | Decodes a `0x4310` host-settings blob into its known fields. |
| `decode_stats.py` | Decodes a `0x4390` end-of-round stat report into labelled slots. |
| `watch_4390.py` | Live-captures and decodes stat reports (or any command) out of the lobby log. |
| `watch_command.sh` | Watches the lobby DEBUG log for a command id and captures its payload as it arrives. |
| `capture_logs.sh` | Appends every game-lobby container's log to a file that survives container recreation. `docker compose up -d --build` discards container logs, and two live sessions were lost that way. |

### Environment and checks

| tool | what |
| --- | --- |
| `ipswap_editor.py` | Editor for RPCS3's IP swap list — the host → IP redirect map. An alternative to `testhk`, and a worse one. |
| `stun_selftest.py` | Asserts the STUN reply format against a running responder. A regression there produces no error, just a hung game. |
| `upnp_probe.py` | Answers the client's own UPnP discovery. |
| `field_scoreboard.py` | Derives the field-mapping coverage numbers from `dev/proto/` directly. Run it rather than quoting a number from memory. |
| `seed.sql` | Inserts the lobby rows, a test account and a news item. Required — an empty `lobby` table is a silent dead end. |
| `dnsmasq.conf` | A logging DNS server. **DNS is not needed to play** — this is for discovering which hostnames a different disc or region asks for. |
| `gcx/`, `solideye/` | Third-party binaries for the disc's own asset containers. `Solideye.exe` is what encrypts `d/testhk`. |
| `retired/` | Superseded implementations, kept because they document a working approach. |
