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

**Three applied migrations deliberately keep the old paths.** `V20__skills.sql`,
`V21__mail.sql` and `V42__stats_serving.sql` reference `mgo2_cmd_4125.ksy` and
`mgo2_cmd_4390.ksy` at their pre-merge root locations, in comments (written without the directory
prefix here so a link-checker does not flag this paragraph as a broken reference). **Do not fix them.** Flyway
checksums the whole file, comments included, and these are recorded in `schema_version` as applied
— rewriting a comment changes the checksum, `migrate()` fails validation on next startup, and every
game container crash-loops. A stale comment is the cheaper of the two errors. The same trap caught
an edit to `V24` earlier in the same session.

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
- **Every field's `doc:` must say what the field is _for_, in the game's terms** — see below.

## A field is not explained until it is explained in the game's terms

Adopted 2026-08-04, and it is a change to what `[CONFIRMED]` is allowed to mean.

An address chain is evidence, not an explanation. A `doc:` that reads *"parsed at `0xD5A6E8`, stored
at `T+0x1C`, read at `0xD44120` and compared against 3"* has established where the field lives and
proved nothing about why anyone put it on the wire. It is unreviewable by anyone who has not opened
a disassembler, and — worse — it is indistinguishable from a correct-looking misreading. Most of the
wrong findings this project has had to unwind were *precise*; what they lacked was a claim about the
game that would have looked obviously false.

So every field carries both halves:

1. **The evidence chain.** Parse site, store destination, every reader, what each read decides.
   Addresses, as always, tier 1, disc build.
2. **The purpose, in playable terms.** Which screen or moment this touches; what a player sees or
   experiences differently when the value changes; and why the field exists on the wire at all
   instead of being computed client-side. Where a branch reaches a string resource, quote the
   sentence the player reads; where it reaches an error, give the code and cross-check
   `dev/docs/ERRORS.md`.

The second half is what makes the first half falsifiable. "This byte gates whether the JOIN button
on a lobby row is refusable, and refusing prints 5215" is a claim that a capture can kill in one
round. "Compared against 3 at `0xD44120`" is not.

**Where the binary does not support a purpose, say that in those words** — *"no game-level meaning
is readable from this image; what would establish it is X"* — and leave it unexplained. An invented
purpose is far more expensive than an admitted gap, because it reads as settled and stops anyone
looking. Speculation is allowed when it is labelled as speculation in the same sentence.

This applies to negatives too, and it is where the rule earns its keep: *"no reader"* is a fact about
the image, and the useful sentence is what that means for a player — the feature is unreachable in
play, or the value is accepted and discarded, or the screen that would have read it is never built.
The precise-negative vocabulary (`no reader`, `dead code`, `swept`, `inert`, …) records the finding;
the purpose sentence records the consequence.

## Sources, in order

1. `MGO2.elf` — `dev/ref/MGO2 (decrypted).elf`. The only specification.
2. `dev/docs/PROTOCOL.md` — fill in whatever it already documents, tagged as it tags it.
3. `dev/docs/OBSERVED.md` — live-capture facts, including disproven hypotheses.

Nothing else. In particular no other server's source.

## `unread` — a payload the client parses nothing of

**Distinct from a blank, and distinct from `seq: []`.** Three states look similar in a mechanical
count and mean different things:

| form | meaning |
| --- | --- |
| `seq: []` | **positively established empty payload** — the command carries no bytes |
| `seq:` with all `unknown_<off>` fields | the layout was **not recovered**; positions may be known, meanings are not |
| **`unread`** | the payload **exists and has length**, but the client **opens no reader and parses none of it** |

The third is a *result*, not a gap, and until 2026-07-30 the tree had no way to say so. Five specs
assert it in prose while using the all-`unknown_body` form, which reads as the opposite:
`0x2002`, `0x2004`, `0x43F4`, `0x43F5` and `0x4802`. `PACKETS.md` already gives them their own
`unread` legend entry.

Express it by naming the field `unread_body` and saying in its `doc` which parser was traced and
where it returns without reading. A coverage count that treats `unknown_` as "unmapped" then stops
overstating the blanks by five.

Note `0x4112` is the one honest use of an opaque `unknown_body`: exact size (32 bytes), contents
genuinely unknown, because the client memcpys a struct rather than parsing fields.

## Widths are evidence — and evidence can be re-read

The rule is that `type`, `size`, `repeat`, `encoding`, `enum` and `pad-right` are findings, not
opinions, so a mapping batch may rename and document but must not change them. That rule stands. It
exists because speculative width edits are unfalsifiable and this project has shipped wrong bytes
from confident guesses before.

**What it does not mean is that a declared width can never be wrong.** On 2026-08-02 a batch found
that eight declarations contradicted the parser, correctly refused to change them, and flagged them
instead. A **third, independent** pass then adjudicated — given both readings, told which was which,
and required to derive each length itself. It confirmed all of them and found two more that the
second pass had missed.

**The procedure that follows: a contested width takes a third reading, and the third reading decides.**
Not the newer pass, not the more confident one. The adjudicator must be able to return "both are
wrong", and must diagnose *what the incorrect reading mistook for the length* — because that
diagnosis is what turns one fix into a closed class.

It did, twice over:

- **`stdu` versus `std`.** The DS-form store with low bits `01` is the **update** form: it rewrites
  its base register. `mr rX,r1` then `stdu r0,120(rX)` leaves `rX = r1+120`, so a loop bound of
  `addi r0,r1,128` is an **end address, not a byte count** — 8 bytes, read as 128. `0x4A27` is the
  control: same 8 bytes, but a plain `std` and an explicit `addi r29,r1,112`, and its declaration was
  always right. Sweeping the parser block `0xD33000`-`0xD5D000` for `stdu rX,disp(rY)` with
  `rY != r1` returns **exactly four** sites, all now corrected. **The class is closed** — no other
  schema can carry it.
- **Straight-line reading through a forward branch.** Honouring `bl` sites but walking through a
  `beq` that skips a read yields the maximum length and misses the gate. Sweeping for a flag test
  followed by a forward branch over a read primitive returns **exactly five** sites; one
  (`0x4982`) was already modelled correctly with `if:`, so the convention existed and these were
  per-schema oversights.

### One `bl` site, N executions — a loop read as a single field

The mirror image of the `stdu` class: that one **over**-counts a loop, this one **under**-counts it.
A parser contains one `bl` to a read primitive, so one field gets declared — but a backward branch
below it makes that single site execute eight times, and eight payload bytes are consumed.

```
0xD5A6E8  addi r29,r1,112          ; cursor
0xD5A6FC  bl 0xd5cb8c   -> r29     ; ONE bl SITE...
0xD5A6F8  addi r29,r29,1
0xD5A704  addi r0,r1,120
0xD5A718  bne cr6,0xd5a6ec         ; ...EIGHT EXECUTIONS
```

**The arbiter is the wire cursor, not the instruction text.** `0xD5CB8C` reloads `[r3+1108]`, adds
one and stores it back on every successful call, so counting calls is counting bytes. Three schemas
(`0x4E21`, `0x4E22`, `0x4E23`) declared 8-byte packets that are 15.

**Swept and closed.** Over `0xD33000`–`0xD5D000`, every backward branch whose body calls a read
primitive: **72 loops**. Discarding the size-driven ones (those calling `0xD5CEB0`) and the shared
sub-parser `0xD4364C`, the fixed-count remainder spans 25 commands — and every one already models
its loop with a `repeat` or a `size:` block. The three above were the only live members, missed
because they were the newest files in the tree.

### A signed type whose only support is the primitive's address

`0xD5CC64` and `0xD5CCD8` are **encoding-identical** — same bound check, same byte-assembly loop,
same return — differing only in two branch displacements by the function offset. Neither is a signed
accessor. **Signedness comes from the caller**: a reload with `lwa`, or comparison against
known-negative constants. Never from which of two byte-identical functions the compiler emitted.

`0x4e10` is its own proof: six adjacent slots on one object, `trailing_word_0` declared `u4` because
it happens to be read by one twin, and `trailing_word_1..5` declared `s4` because they are read by
the other.

**Watch for the laundered form.** The same claim restated in caller-side language — *"the caller
reloads it with `lwa`"* — looks like independent evidence and is not, unless the `lwa` is actually
there. In `0x4e12` it was not: the reload is `lwz` and the parser contains no `lwa` at all. Check
the instruction before accepting the justification.

**Not closed.** `mgo2_cmd_4b75_s2c.ksy`'s `unknown_58` is a known live member awaiting its own
adjudication.

The one class that **cannot** be swept mechanically is a repeat count, because the discriminator is
semantic: `0x4A20`'s "count" was reloaded at the top of every iteration, which is precisely what a
trip count looks like, but it only fed address arithmetic — the real bound was four instructions
away. **The standing check: for every `repeat-expr`, confirm the named field reaches a compare.**
