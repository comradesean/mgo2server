# Blank / skeleton Kaitai specs — one per command id

Every command id in the lobby protocol (Channel A) gets a `.ksy` here, whether or not its
layout is understood. These are **drafts for review**, not verified specs: the point is that
the id space is fully enumerated and each id has a place to record what the ELF says.

Promotion path: when a spec's fields are all mapped and at least the shape is confirmed
against a capture, it graduates to `dev/proto/` (the verified set) and is deleted here.

## Layout

Direction is encoded by the folder, from **the server's** point of view:

| folder | direction | suffix | count | id list |
| --- | --- | --- | --- | --- |
| `inbound/` | client -> server (what we receive and must answer) | `_c2s` | 109 | `dev/analysis/c2s_ids.txt` (112 ids, 2 already verified) |
| `outbound/` | server -> client (what we send and the client parses) | `_s2c` | 195 | `dev/analysis/s2c_ids.txt` (204 ids, 8 already verified) |
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
- **No `valid:` constraints** — see `../README.md` for why.
- Record the evidence addresses in the top-level `doc:`: builder call site for client→server,
  parser address for server→client, and the dispatcher that routes it.
- Do not copy field names or layouts from any other server implementation. See `CLAUDE.md`.

## Sources, in order

1. `MGO2.elf` — `dev/ref/MGO2 (decrypted).elf`. The only specification.
2. `dev/docs/PROTOCOL.md` — fill in whatever it already documents, tagged as it tags it.
3. `dev/docs/OBSERVED.md` — live-capture facts, including disproven hypotheses.

Nothing else. In particular no other server's source.
