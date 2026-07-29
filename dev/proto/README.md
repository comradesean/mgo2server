# Kaitai Struct specs for the lobby protocol

Machine-checkable byte layouts for selected commands, one `.ksy` per packet payload
(the decrypted payload after the 24-byte header / XOR / Blowfish transport layer —
see `dev/docs/CRYPTO.md`). PROTOCOL.md remains the narrative: evidence, history, and
why; these files are the byte-level truth, and the compiler enforces that every byte
belongs to exactly one declared field.

Conventions:

- Every field carries a `doc:` with a confidence tag — **[CONFIRMED]** (capture-proven
  live), **[INFERRED]** (structural or offset-mirror reasoning), **[UNKNOWN]** (position
  exact from the client parser, meaning unestablished; the fingerprint value sent and
  whether it surfaced on screen is recorded).
- `T+0x...` in docs is the client-side struct destination, from the ELF parser traces.
- Unknown regions are named `unknown_*` — an explicit state, not an omission.
- **No `valid:` constraints** (decided 2026-07-23): a constraint freezes an expectation, and
  while fields remain unmapped that converts discovery into parse errors — the first capture
  where an unknown slot finally moves must read as a finding, not corruption. Deviation
  watching belongs in the server as WARNs (store anyway, flag loudly — see PROTOCOL.md's
  0x4390 tripwires), not in the specs as gates. Revisit per field only when it is closed.

To view a capture against a spec, load both into the Kaitai WebIDE
(https://ide.kaitai.io). To compile (generates parsers, validates structure):

    kaitai-struct-compiler -t python --outdir /tmp/out *.ksy

Specs (pilot, 2026-07-23): the `0x4102` personal-stats burst —
`mgo2_cmd_4103.ksy` (character info, 648 B), `mgo2_cmd_4105.ksy` (per-mode grid,
584 B, sent once per period page), `mgo2_cmd_4107.ksy` (personal scores, 588 B,
terminal) — the social family: `mgo2_cmd_4682.ksy` (met-players history record, 25 B),
`mgo2_cmd_4686.ksy` (match-detail record, 93 B), `mgo2_cmd_4221.ksy` (player-details card,
201 B single reply) — and the client→server round-end pair: `mgo2_cmd_4390.ksy` (the host's
per-player stat report, 167 B long form / ~51 B short form; what `round_report` stores) and
`mgo2_cmd_43a2.ksy` (per-player round weapon tallies — one packet per scoring player, fully
decoded). Server→client: `mgo2_cmd_4902.ksy` (game-lobby list entries, **99 B each**, from the
parser at `0xD47E18` — both reference servers write 35 B and lose every lobby after the first).

**Promoted 2026-07-27 — 35 specs**, all mapped field by field and confirmed against a live
client:

- `mgo2_cmd_3103_c2s.ksy` (select character — a one-byte **slot index**, not a character id) and
  `mgo2_cmd_4600_c2s.ksy` (player search — whose second byte means **ignore case**, `1` = ignore,
  the opposite of what it was called).
- **33 of the clan family**: `0x4b00`/`0x4b01` create, `0x4b04`/`0x4b05` disband,
  `0x4b20` profile request, `0x4b30`–`0x4b37` accept/decline/banish, `0x4b40`/`0x4b41` cancel
  join, `0x4b42`/`0x4b43` apply, `0x4b47` record refresh, `0x4b48`/`0x4b4a` emblem fetches,
  `0x4b51` emblem-upload result, `0x4b52` roster request, `0x4b60`–`0x4b63` leadership and emblem
  editor, `0x4b64`–`0x4b67` the two text writes, `0x4b80` foreign clan info, and the whole search
  family `0x4b90`–`0x4b93`.

Still in `blanks/` and why, for the same family: `0x4b21` and `0x4b81` have large unmapped
regions; `0x4b10`, `0x4b46`, `0x4b4c`, `0x4b50`, `0x4b70` and `0x4b73` each keep at least one
genuinely unknown field; and `0x4b11`/`0x4b13`, `0x4b53`/`0x4b55` were held back to keep each
list triple in one place. See `blanks/README.md`.

List-triple start/end packets (`0x4601`/`0x4603`, `0x4681`/`0x4683`, `0x4685`/`0x4687`)
are not specced separately: each is a single u32 **result code**, 0 for success in both
start and end — never a count; the client counts item records itself. Sending a count
there produced the `1032:00000005` error (OBSERVED.md).

---

# One spec per command id — the merged tree (2026-07-29)

**The `blanks/` tier is gone.** It used to hold a draft per command id, with a promotion path into
this directory once a spec was verified. That split has been collapsed: `inbound/` and `outbound/`
now hold **every** id, verified and draft alike, and the id space is enumerated exactly once.

The reason for the merge is that the directory was carrying information the per-field tags already
carry, and carrying it *worse*. A file's location told you someone had decided the whole spec was
"verified", while individual fields inside a promoted spec were still `[UNKNOWN]` and individual
fields inside a draft were capture-proven. **Confidence is per field, so it belongs in the field's
`doc:` tag and nowhere else.**

Counts after the merge: **112 inbound, 204 outbound** — which is exactly `dev/analysis/c2s_ids.txt`
and `s2c_ids.txt`, with `0x0005` counted in both. Every id has exactly one file.

What this changes in practice:

- **Nothing is "promoted" any more.** Improving a spec means improving its field tags in place.
- A spec with no recovered layout still exists and still says so — a missing file is
  indistinguishable from an unsearched id, an explicit blank is not.
- The lesson that prompted this: schemas were twice written fresh at the old root while a draft
  already existed under `blanks/`, because listing one directory did not show the other. A single
  tree makes that impossible.

## Layout

Direction is encoded by the folder, from **the server's** point of view:

| folder | direction | suffix | count | id list |
| --- | --- | --- | --- | --- |
| `inbound/` | client -> server (what we receive and must answer) | `_c2s` | 88 | `dev/analysis/c2s_ids.txt` (112 ids, 21 already verified) |
| `outbound/` | server -> client (what we send and the client parses) | `_s2c` | 173 | `dev/analysis/s2c_ids.txt` (204 ids, 25 already verified) |
| (root) | both directions, identical schema | none | 1 | `0x0005` only |

Direction is carried **twice on purpose** — by the folder and by the `_c2s`/`_s2c` filename
suffix — so that a `grep`/`ls` hit is self-describing even with the path stripped, and a
`sort` groups by direction. `meta.id` matches the full stem including the suffix.

Note inbound/outbound here is the opposite of the ELF's own vocabulary, where the "inbound reply
dispatcher" is the *client's* inbound. The id lists are therefore named `c2s`/`s2c`, which is
unambiguous from either end; only the folders use inbound/outbound.

**The two both-directions ids are handled differently, because they differ differently:**

- **`0x0005`** (ping) is the *same* schema each way — empty, zero bytes, positively established
  on both sides. It is a single unsuffixed file at the root; two copies would differ only in
  prose. Its `doc:` carries both the builder and the parser evidence.
- **`0x49c0`** is two unrelated layouts sharing an id — `{s4 num_ids, u1, u4[num_ids]}` outbound
  from the client vs `{u4 status, u4 pair_count, {u4 key, u4 value}[]}` inbound to it. It is
  split normally, one file per folder.

So a root-level file means "identical in both directions"; that is a claim, not a filing
accident, and it must not be made without checking both sides.

## Rules for these files

- Filename: `mgo2_cmd_<id>.ksy`, id lowercase hex without `0x` (e.g. `mgo2_cmd_43e0.ksy`).
- `meta.id` must match the filename stem; `endian: be`.
- An **empty payload** established positively from the ELF (builder immediately followed by the
  seal, or a parser that opens no reader) is written `seq: []` with the addresses in the `doc:`.
  That is a result, and must not be confused with the `unknown_body`/`size-eos` form, which means
  the layout was *not* recovered. 23 of these exist.
- Layout describes the **decrypted payload after the 24-byte transport header** — no header
  fields, no XOR/Blowfish (see `dev/docs/CRYPTO.md`).
- Direction goes in `meta.title` as `client -> server` or `server -> client`.
- Every field carries a `doc:` with a confidence tag:
  - **[CONFIRMED]** — capture-proven live (only when `PROTOCOL.md`/`OBSERVED.md` says so).
  - **[ELF]** — offset and width read out of the builder/parser disassembly, not yet seen live.
  - **[INFERRED]** — structural or offset-mirror reasoning.
  - **[UNKNOWN]** — position exact, meaning unestablished. Name the field `unknown_<off>`.
- Where the ELF gives no layout at all, the file still exists and says so: a single
  `unknown_body` of `size-eos` plus a `doc:` stating what was searched and came back empty.
  A missing file is indistinguishable from an unsearched id; an explicit blank is not.
- **No `valid:` constraints** — see above for why.
- Record the evidence addresses in the top-level `doc:`: builder call site for client→server,
  parser address for server→client, and the dispatcher that routes it.
- Do not copy field names or layouts from any other server implementation. See `CLAUDE.md`.

## Sources, in order

1. `MGO2.elf` — `dev/ref/MGO2 (decrypted).elf`. The only specification.
2. `dev/docs/PROTOCOL.md` — fill in whatever it already documents, tagged as it tags it.
3. `dev/docs/OBSERVED.md` — live-capture facts, including disproven hypotheses.

Nothing else. In particular no other server's source.
