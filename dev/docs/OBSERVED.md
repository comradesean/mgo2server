# Observed client behaviour

Everything here came from a real client — MGS4, disc `BLUS30109`, running on RPCS3 v0.0.41 — not
from documentation or from other preservation projects. That distinction matters: every value
inferred from the MGO1 and Portable Ops emulators turned out to be wrong for MGO2, including the
policy path, the gate hostname, the gate port and the version-check response byte.

Sources of truth used, in order of usefulness:

1. **The decrypted game binary** (`PS3_GAME/USRDIR/o/MGO2.elf`) — the only actual specification.
   Everything else is somebody's reading of it. See "Error 090B:00000001" for how to navigate it.
2. **RPCS3's own log** (`log/RPCS3.log`) — `DnsHook: DNS query for …` gives real hostnames, and
   `Attempting to connect on <ip>:<port>` gives real ports.
3. **The HTTP/TLS probe** (`dev/runtime/http_probe.py`) — exact paths, methods and bodies.
4. **[MiguelRipoll23/mgo2-server](https://github.com/MiguelRipoll23/mgo2-server)** — an independent
   MGO2 server covering the web API that Nomad does not. Nomad is only the game server.

Companion documents:

- **`dev/docs/PROTOCOL.md`** — the TCP command protocol, command by command and byte by byte: framing,
  the XOR and checksum, which payloads are encrypted, and every command this server handles.
- **`dev/docs/STUN.md`** — the UDP port check ("Adjusting port settings") in full. Separate because it
  is UDP, runs on its own thread in the client, and shares nothing with the lobby servers.
- **`dev/docs/CRYPTO.md`** — every cipher, key and hash, and where each is applied.
- **`dev/docs/SETUP.md`** — everything outside this repository that has to be true before an unmodified
  client can play: emulator settings, the certificate, and the host address the port check needs.

This file is the record of what was *observed and verified*, including the things that turned out
to be wrong. The other two describe what the code does today.

## The clan roster's leader badge — the leader's ID, delivered by another packet (2026-07-27)

**CONFIRMED FIXED.** The Clan Leader badge renders on Check Roster once `T+0x18` of the clan-info
packets carries the leader's **character id**. We had been sending the founding date there in
`0x4b81` and zeros in `0x4b21`, so the client knew a clan had a leader *named* Sean but never
which character that was, and no roster row could match.

That also **confirms `T+0x18` is the leader's character id**, empirically and not by inference. The
previous claim that it was the founding date came from an experiment that swapped it with `T+0x58`
and saw the member count render epoch seconds — which proved `T+0x58` and said nothing about
`T+0x18`. Second invalid elimination found in this packet family in one day.

### The empty-category fallback writes back, observed (2026-07-30)

Predicted as a hazard when the fallback was found; now seen happening.

A character was stripped to zero gear, reconnected (drawing the forced rows in upper body and feet),
and later given the starter set. Its stored appearance had been `head 33, upper 13, feet 62`.
Afterwards it read **`upper 11, feet 57`** — precisely the two category **base ids** the fallback
force-equips, and neither of which the character had been wearing.

So `stb r23,20416(r11)` at `0x927544` does not merely affect the screen: the value reaches
`chara_appearance`. **Narrowing a live character's gear can silently rewrite their outfit.**

Two things this does *not* establish, and they matter before anyone does a bulk gear change:

- **When** the write-back is persisted — on screen entry, on an outfit commit, or on any save. The
  character in question had several reconnects and screen visits in between.
- Whether an item the character still owns is preserved. `upper 13` (T-shirt) was in the starter set
  and was replaced anyway, which is not what a pure "fix the illegal ones" rule would do — but there
  was also live testing in that window, so operator action cannot be excluded.

Recorded as an observation with its ambiguity intact rather than a mechanism.

### Both gear gates confirmed live, and the empty-category fallback with them (2026-07-30)

Test: strip one character's `chara_gear` to a single row — item 33 (Beret), `colours = 1` — and
reconnect. `0x4124` went from 651 bytes to 41.

**Observed, and all four predictions held:**

| | expected | seen |
| --- | --- | --- |
| HEAD | None + Beret only | ✔ |
| Beret colours | Black alone, not ten | ✔ |
| chest / waist / accessories / hands | None only (hardcoded exempt ids) | ✔ |
| **upper body / feet** | **empty — no None entry and nothing owned** | **✘ — see below** |

So **item ownership (`0x927350`, record `+8`) and colour availability (`0x925538`/`0x92772C`,
record `+12`) are both real, server-controlled, and working.** That closes the loop on the claim
withdrawn earlier the same day, which had said gear was ungated.

#### The empty-category fallback, live

The two categories with no "None" entry did not come up empty. They showed **Tactical Jacket** and
**Tactical Boots & Knee Guards (Type A)**, each with **no colour swatches**.

That is the fallback at `0x92751C`-`0x927568` doing exactly what the trace said: when the built
list is zero-length (`lwz r0,6604(r9); cmpwi 0` at `0x927510`) the client **force-equips the
category's base id** (`stb r23,20416(r11)` at `0x927544`) and appends one row labelled ordinal 0.

Base ids are **11** (upper body) and **57** (feet) — precisely the two items that appeared. The
swatches are empty because the forced item has no `chara_gear` row, so no colour mask reaches
record `+12`.

**Consequence worth knowing before stripping gear on a live character:** the fallback *writes* the
equipped byte. A character left in this state and then committing an outfit would persist
`upper = 11` and `feet = 57`, replacing whatever they were actually wearing — here a T-shirt and
Tactical Boots. The strip is reversible; the outfit commit that follows it may not be.

#### Two category names upgraded from ordering-derived to observed

The names above were flagged as *"ordering-derived, counts verified, NOT hash-resolved"* for upper
body, hands, feet, chest and waist, because the flat string dump's group boundaries are unreliable.

The fallback renders **ordinal 0 of the category**, and the client displayed "Tactical Jacket" for
upper body and "Tactical Boots & Knee Guards (Type A)" for feet — matching `gear_item.name` for ids
11 and 57. **Those two categories' index-0 alignment is now observed rather than inferred**, which
is the specific thing that could not be certified from the dump. Hands, chest and waist remain
ordering-derived; the same trick would settle each of them, since all three have a None at ordinal 0
that the fallback would render.

### Gear item names: what is anchored and what is only ordering (2026-07-30)

All 67 reachable gear ids are named in `gear_item.name` (V69). **The confidence is not uniform**,
and two agents disagreed about it — the honest position is the more cautious one.

**Anchored, safe:**

- **Head** — the ELF special-cases ids **35 and 38** at `0x926D6C`/`0x926D74` off the head byte
  `+0x80`. Those are ordinals 7 and 10, landing on **Bush Hat** and **Fleece Cap** — the only two
  soft crushable hats, exactly what you would special-case for wear under a full-head accessory.
  Two independent anchors in an 11-slot list.
- **Accessories** — three colour-set signatures across non-adjacent ids, each landing on a
  semantically coherent group: 104/108 share a set (the two headsets), 105/109/111 share another
  (three soft head coverings), 103/106/107 share the lens set. Corroborated further by ordinals
  25-29 being used by exactly one item (Shemagh Scarf: brown/gray/blue/yellow/rose) and 30-31 by
  exactly the three lens items (Orange, Clear).
- **Item 33 = Beret** — head ordinal 5, and the only head item besides Fleece Cap carrying the
  10-solid mask rather than 21-colour camo. A beret and a fleece cap are precisely the two hats you
  would not print camo on.

**Ordering-derived, counts verified, NOT hash-resolved: upper body, hands, feet, chest, waist.**
One agent reported these as resolved by group hash and ordinal; the other showed why that cannot be
certified from the flat string dump, and it is right. `dev/analysis/strings/lobby.txt` concatenates
separate resource groups, and its boundaries are demonstrably unreliable — there are visible "None"
blocks before head (15992) and chest (16074) but **none** before waist (16147), hands (16213) or
accessories (16280), though all three take a None at ordinal 0.

Every count matches its `li r25,N` immediate and every colour signature is consistent, but that is
corroboration, not resolution. Treat those five categories' names as high-confidence labels rather
than proven ones, and re-derive them properly if one ever matters.

**Id 22 is deliberately NULL** — its disc header points the English ordinal at a Japanese string
reading "trousers (provisional name)", with a stray `Aucun` alongside. A defect in the disc data,
not a gap in ours.

### The colour mask is a per-item slot index

Worth stating separately because it rules out a design that would look natural. The catalogue record
is `{item_id, colour_slot, colour_name_ordinal}`, and `chara_gear.colours` indexes **`colour_slot`**
— so **bit 0 is Auscam Desert on item 29, Black on item 33, and Orange on item 103**.

A single global colour bitmask is therefore impossible, and the name ordinal reaches 35, which the
trailer's `bit <= 31` bound could not express anyway. `chara_gear` already stores one mask per item
row, which is the correct shape and needs no change.

Item 105 is the clearest example: slots 0-7 (`0x000000FF`) but name ordinals
`{15,16,17,19,20,21,23,24}` — it skips two. Reading its mask against a global colour list would name
the wrong colours.

Also noted: colour name ordinals **32-35 are unnamed on the disc but in use** by the three lens
items (103, 106, 107), so the eyewear ships more lens variants than the disc names. Those swatches
are skipped at runtime.

### The greyed "To" row — PARTLY resolved, and the grey-out itself is NOT explained (2026-07-29)

Reported: in Mail -> Create New Mail -> To, a row was greyed out until the player had friends;
after visiting the Friend List it went bright and **never greyed again**, across client restarts
and with the To: field cleared. Selecting the bright row did nothing.

**Open: why "View/Edit Address Book" was dim.** The operator reports directly that *that* row was
greyed, and operator testimony outranks an inference. An earlier version of this entry claimed the
greyed row must have been Friend List; that was **over-claimed and is withdrawn**. What is actually
established is below; what is not is at the end.

**Friend List's dim rule is real, and does match part of the report.** [ELF] the row painter
`0x8E4970` dims it when
`byte 20190 == 0`, and that byte is not a latch — it is **recomputed as the friend count** every
time the screen is built (`0x8EAB0C`-`0x8EAB48`, 32 iterations over the roster block from
`0xD3A094(session+364)`, counting entries whose `+32` is nonzero; both it and 20189 are stored 0
when the roster pointer is null). Zero friends dims it; the `0x4580` fetch returning two makes it
bright; the roster is refetched at every login, so it never returns to zero. Clearing the To: field
cannot affect it — that touches only `recipientCount` at `screen+0x180000+13736`.

**"View/Edit Address Book" was never dim, and doing nothing is correct.** `text22` is JP
宛先リスト確認／編集 — *view/edit the RECIPIENT list*; the English name is a mistranslation and
there is no persistent address book. Its handler `0x8EDF78` requires `recipientCount > 0`
(`0x8EDF88 ble`) and otherwise plays deny SE 91 (`0x8EEE84`) and returns. **Bright is not the same
as usable.** Add a recipient and it opens.

The full dim table, from `0x8E4970`:

| row | dims when |
| --- | --- |
| Add Recipient | `recipientCount > 7` (`0x8E49AC`) |
| Friend List | `byte 20190 == 0`, i.e. **no friends** (`0x8E4A3C`) |
| Clan Roster | `byte 20189 == 0` or bit 2 set (`0x8E4AB4`/`0x8E4AC4`) |
| GM | bit 2 set (`0x8E4AE8`) |
| View/Edit Address Book | **bit 18 set**, i.e. the letter is addressed to the GM (`0x8E4B30`) |

**Bit 18 is the GM flag**, confirmed live: selecting To -> GM greys the address-book row, because a
GM letter has no recipient list to edit. Set by the GM item (`0x8EF098`); cleared by all four other
To-menu items and by the send; **not** cleared by leaving the screen.

**Two traces read that bit as 17 before the arithmetic was checked.** `rldicl. rX,r0,46,63` tests
bit `64-46 = 18`. Bit 17 is real but unrelated — the message-body editor modal (`0x8EE940`) — which
is exactly why the wrong label kept half-fitting and survived two investigations. Check the rotate
before naming a bit.

#### What is NOT established, and is the open question

The address-book row dims **iff bit 18 is set**, and bit 18 has **two** setters, not one:

- `0x8EF098` — the GM menu item. Requires the player to pick GM. Cannot explain a grey-out seen
  before GM was ever selected.
- **`0x8E6ECC`** — a **screen-entry arm** inside `0x8E63E4`, gated on **bit 3**, which also loads
  `text16` and zeroes the eight recipient slots and `recipientCount`. Described by the trace as the
  "this compose is already addressed to the GM" entry path. **What sets bit 3 was never traced.**

So a dim row on first entry is fully consistent with `0x8E6ECC` firing, and nothing rules it out.

The initial state of bit 18 is **inference, not evidence**: the trace could not locate the screen
object's constructor (reached via the screen-manager singleton at `*(0xFEFA80-32768)` = `0x166EA28`
field 0; `0x8EF270`'s OPD `0x101B8E0` has one reference, TOC slot `0xFE7C70`, whose loader was not
resolved). What *was* read is narrower: no instruction stores a literal into this screen's `+372`,
and the only wholesale mask (`0x8E4F8C`-`0x8E4FB8`, `and r9,r9,0xFFFF0FF7`) does not touch bit 18.
"Clear at construction" does not follow from that if the object is reused or if bit 3 is set on
entry.

**Next step:** trace bit 3's writers and whether `0x8E63E4` runs on ordinary screen entry. Until
then the grey-out is unexplained, and the Friend-List reading is a hypothesis competing with an
unexcluded mechanism — not the answer.

### Host rating: one vote per GAME is operator policy (2026-07-29)

Confirmed live once the gate went in: rejoining the same game offers no prompt, and a new game by
the same host offers one again. Both behaviours are intended.

Nothing in the client constrains this — the binary has no notion of who you have rated before, and
its own latches are cleared whenever the picker is re-armed. So the limit is entirely ours, carried
in the `0x4321` gate byte, and it has to agree with `host_review_once_per_game` or the client is
offered a prompt whose vote we then discard.

| option | verdict |
| --- | --- |
| **per game** | **chosen.** A rating is about a hosting session, so a regular opponent stays rateable and a host's average keeps moving |
| per host, ever | rejected — freezes each host's average after one vote, so the ranking board is decided by whoever votes first and stops meaning anything within days |
| per host per window (e.g. 24h) | not implemented; the right fix *if* farming becomes real, layered on top of per-game rather than replacing it |

Known exposure: a host can create a fresh game repeatedly to harvest votes from the same player.
Accepted for now — it costs a teardown and re-create each time, and no ranking here has ever been
contested. The full reasoning lives at the gate in `GameListGameController`.

### Host rating: we switched it off on every join, in one hardcoded byte (fixed 2026-07-29)

Only one host rating has ever been recorded on this server, and no `0x43c4` appears in any log.
Three readings were eliminated by live testing first — it was not the successor taking the host
role (the game never migrated), not a two-player dead end (the one success WAS two players), and
not a requirement that the game end rather than be quit (a completed four-round stage produced
nothing). A capture even showed the joiner receiving `0x4313` wire `0x0a7` = **1**, the gate open,
and still no prompt.

**The cause [ELF].** `0x4321`, the join reply, carries a byte at wire `0x28` that we sent as a
hardcoded zero, justified in the comment as *"echo writes 0"*. The parser at `0xD441DC` reads it
and `0xD441FC` stores it to `detailsBase + 964` — **the same slot `0x4313` wire `0x0a7` writes**,
and the slot the star picker is gated on. The join reply lands *after* any pre-join `0x4313`, so
it overwrote the open gate with zero on every single join.

The gate is read further downstream than expected, which is why the `0x4313` byte looked
sufficient:

- the end-of-game screen **snapshots** `details+964` when it is *constructed*, into `screen+344`
  (six identical sites, e.g. `0x9D7F34`, `0x9DF0B4`, `0xA0C5D8`)
- `0x9DCA34` skips opening the star picker when that snapshot is zero — no picker, no `0x43c4`
- the slot itself is only re-read at `0xA31DB0`, *after* the player has already chosen a rating

So `0x4313` wire `0x0a7` is necessary but never sufficient. Both packets must carry the flag.

**It also explains the single success.** That one needed a `0x4313` to arrive *after* the join and
*before* the results screen was built — a details refresh from inside the game.

**The operator's hypothesis was that we were sending an "already voted" flag.** That specific
mechanism is a **negative**: the three latches (`flags` bits `0x1`/`0x10`/`0x20` and the zeroing of
`state+200` at `0xA31DC0`) are all client-local, and `host_score` (details+956) and `host_votes`
(details+960) have no reader anywhere in the send path. But the instinct — that something we send
suppresses the prompt — was exactly right, and it is what got this looked at properly.

**Seventh inherited constant.** Same shape as the other six: transcribed faithfully from a
reference server, wrong for this client, invisible because nothing tested it.

### Dialog 2944 cannot be raised at all

*"Game rules and map have not been set. / Please set game rules and map."* is a carried-but-dead
table entry at `0x106D714`. There is no `li r,2944` into any argument register anywhere in the
image (the six `li r0,2944` hits are AltiVec stack offsets), and no `addi`/`ori`/`subfic` form
produces it either. Neither a server result code nor a client-side check can show it.

So the empty-rotation refusal keeps the generic code — there is no better one to find. Its
neighbour **2945** is equally unraisable, as are **2826** ("You do not own the map this host is
using") and **2833** ("This Combat Training session is not currently accepting applicants"). They
belong with the five clan sentences `ERRORS.md` already lists as unreachable.

### Skill progression: `0x43a4` is how the client reports it, and we were dropping it (2026-07-29)

Skills level by **use**. The server cannot observe use, so the client has to report — and it does,
in `0x43a4`, which we did not handle at all. Every character's skill levels were therefore frozen
at whatever they were granted at creation, and the apparent split (Sean level 3 on everything,
rawr and poop level 1) was purely an artefact of creation date: characters predating V20 got the
24,576 backfill, later ones get `MINIMUM_VISIBLE_EXPERIENCE` = 8,192.

**The chain, end to end [ELF].** `0x4125`/`0x4129` → `profile+11444` → the player-announce builder
at `0x8841A8` copies it to `announce+50` → the receivers at `0x2764E0` and `0x278230` `SET` it into
record-store key 392 (live) **and** key 648 (baseline), so the delta starts at zero on join → in
match, `0x6FCA40` (`addi r6,r6,1`) increments the live value once per use, snapping to
`(level << 13) + 8192` on level-up at `0x6FCAD4` → at teardown `0x27D028` emits a record for every
skill whose live value differs from its baseline, then rebaselines.

**The reported value is ABSOLUTE, not a delta.** `0x27D12C` writes the delta and `0x27D140`
immediately overwrites it with `live[id]`. Storing deltas would compound every round.

**The host reports for everyone.** It sweeps all 24 player slots (`0x7083C8`/`0x708800` →
`SubmitReport(slot, 1)` at `0x27DF38`), so attribution is the character id at wire `+0x00`, not the
connection — unlike `0x4390`, whose attribution is connection-implicit.

Wire, total `8 + 3*count`:

| offset | size | field |
| --- | --- | --- |
| `+0x00` | 4 | character id (blob key 332) |
| `+0x04` | 4 | record count, capped at 127 by the sender (`0xD419BC`) |
| `+0x08` | 3 × count | `{u8 skill_id, u16 experience}` — no flag byte, unlike `0x4125` |

It opens **wait slot 53** (`0xD41A78`), so an unanswered report is a latent `FFFFFF60`.

**Why nothing persisted, precisely.** In-match accrual writes record-store key 392;
`profile+11444` — what `0x4125`/`0x4129` fill and what the announce builder serialises for the
*next* match — is written by nothing else in the image. So `profile+11444` is entirely
server-authoritative: experience accrued in a round lived only in the blob and was discarded at
teardown. It also means our `0x4129` must not answer `0x4128` with pre-round values after a report
has arrived, or the player watches their skills regress.

Not yet observed on the wire: no `0x43a4` appears in any capture or log to date, so the layout is
tier-1 (read from the binary) and the round trip is still untested live.

### Creating a game with no rule or stage selected hangs the client (fixed 2026-07-29)

Reported live: pressing Create Game without picking any rule or stage is not refused, and the
client goes straight to an infinite load. There is no round to start, so nothing ever completes.

**The client is supposed to catch this.** `ERRORS.md` dialog 2944 is *"Game rules and map have not
been set. / Please set game rules and map."*, sitting immediately beside 2945, the Create Game
screen's own network warning. So the sentence exists and belongs to that screen; the check simply
does not fire on this build. Which result code reaches dialog 2944 is **[UNKNOWN]** — that mapping
is not in `ERRORS.md`, so the server refusal below uses the generic code rather than an invented
one.

**It has been reaching us all along.** Decoding the rotation out of all 214 stored `0x4310`
payloads (`dev/proto/samples/4310/captures.psv`):

| rotation entries with a map set | captures |
| --- | --- |
| 0 | **2** |
| 1 | 206 |
| 2 | 4 |
| 3 | 1 |
| 6 | 1 |

Both empty ones are character 3, on 2026-07-28. We accepted them and created the games.

**The test is the map, not the rule.** Rule 0 is Deathmatch and is a real choice; map 0 is no stage.
Across those 214 captures the maps actually used are 1, 2, 3, 4, 7 and 12, and a zero map never
appears beside a real entry — which also matches the rotation's own `rule == 0 && map == 0`
terminator convention. Testing the rule instead would refuse every Deathmatch on the server.

Refused at `0x4311`, before the blob is persisted, so an empty rotation cannot become the next
session's Create Game pre-fill either. `0x4311` is the right place for the same reason the hosting
ban is there: it discriminates result codes, where `0x4317` renders everything generic.

Note this also corrects a scope claim made in passing: the shipped stage set is **not** only
`{2, 3, 4, 7, 12}`. That is automatching's pool (`map_bit 4252`); map 1 appears in real host
settings.

### The wrong turn, which is the part worth keeping

An ELF investigation concluded the badge **could not exist in this build**, and it was wrong. Its
two supporting facts were both true and remain true:

- The roster row's state byte reaches the renderer, but the display filter is
  `addi -1; clrlwi; cmplwi 1; bgt` — 1 and 2 take the same branch, and no `cmpwi ...,2` exists on
  the row path. **The badge is not selected by the state byte.**
- Of the 68 wire bytes in a row, only `+0` (id), `+4` (name[16]) and `+21` (state) are read by
  anything. The other 47 are parsed and ignored by all six consumer sites. **Filling them changes
  nothing.**

Both correct. The conclusion drawn from them was not, because the question was "can this client
draw a leader badge" and the evidence only covered **one packet**. The selector lives in a
different one. The report even named its own gap — the 8-entry `{flag, id, name[16]}` table at
`global+0x1835AC` whose network-side seeding it could not find, flagged as "a gap in my analysis,
not a proven negative". That gap was exactly where the answer was, and the verdict was stated over
it rather than around it.

The rule this cost us: **an elimination is only as wide as the code you actually read.** "No field
in this packet selects it" is a sound finding; "this build cannot draw it" is a different claim
needing the whole client. The narrow one was true and useful; the broad one sent us to accept a
version-mismatch theory that was false.

### Still true and still useful

- **The emblem-painter icon is client-local.** `0x4b21`'s `T+0x6FC` parses as `{editor id, editor
  name[16]}` (`0xD58B34`, then a 16-byte read at `T+0x700` — so the old note calling `T+0x700` a
  512-byte blob is wrong about that field), and nothing reads either. Assigning the painter in game
  moves the icon because the screen writes its own table from user input.
- **The roster caps at 64 rows**, and a 65th aborts the entire parse with `-71` — the same
  lose-the-whole-list failure as `0x4b12`'s 101st record. We do not cap it.
- Sending the real 0/1/2 membership state still matters: a state-0 applicant row is dropped by the
  display filter, so the vocabulary is load-bearing even though the badge does not use it.

### The emblem half is CONFOUNDED — do not cite it

[2026-07-27] The badge and the emblem were fixed in one commit and reported as one cause. The
badge holds up. **The emblem does not, and the confound is a client-side cache.**

Round 2 of the probe sent the id in `0x4b81` only. The badge disappeared, as expected. **The
in-game emblem still rendered** — which under the one-cause story it should not have.

The likely explanation is the role-swap experiment itself. While leadership sat with poop, Sean was
an ordinary member and his emblem rendered correctly. The client caches clan emblems by clan id (a
30-entry texture cache, plus the 768-byte buffer at `profile+6873`) and neither is cleared by a
relog, because the process survives it. So clan 2's emblem was warmed into every client during the
window when the bug was not biting, and every emblem observation since may be reading that cache
rather than anything the server sent.

If that is right, the leader id fixed the badge and did nothing for the emblem — the emblem was
masked, not repaired, and is still broken on a cold client.

**The test that settles it:** fully restart the client process (not a relog — the caches live in the
process), with the leader id absent from both packets, and look at a leader's emblem in a game
session. Until that is run, treat "one field, two symptoms" as unproven for the emblem.

The lesson is not about the cache. It is that an experiment which *changes the game state* — here,
who leads the clan — can leave a residue that survives into every later observation. The role swap
was a good experiment and it silently poisoned the well for everything measured afterwards.

### Which packet supplies it: `0x4b21`, for the badge

[CONFIRMED 2026-07-27] Separated with a probe (`MGO2SERVER_LEADER_ID_PROBE`) rather than left as a
reasoned guess, because both packets had been changed in one commit. With the id sent **only in
`0x4b21`** and `0x4b81` zeroed, the Clan Leader badge still renders on the Member List. So the
clan-affiliation view is the source, and `0x4b81`'s copy is not what the roster reads.

Round 2 settled it for the badge in both directions: with the id in `0x4b81` only, the badge
disappeared. So `0x4b21` is **necessary**, not merely sufficient — a distinction round 1 alone could
not have made, and one an earlier draft of this section blurred.

## A clan leader's emblem in game — real, unexplained, did not recur (2026-07-27, UNRESOLVED)

**The symptom was real.** Three clients, one match. Sean and poop in clan 2 with an emblem on
display. poop's emblem rendered on every screen and Sean's on none, including Sean's own. The
server was verified on the wire to be sending both identical clan data in `0x4122` — same clan id,
same `emblem_flag=03`. Transferring leadership moved the symptom with the role.

**Nothing we changed explains it, and it has not come back.** The leader-id field that fixed the
Check Roster badge was the leading candidate and is now ruled out: with the id sent in **neither**
`0x4b21` nor `0x4b81`, and clients fully restarted, the emblem still renders for the leader. The
probe was run three ways — `4b21`, `4b81`, `none` — and the emblem was present in all three.

So this is filed as a **first-connection hiccup**: a transient in that session, not a server
behaviour. It should not be cited as fixed, because nothing fixed it.

What was genuinely established while chasing it is worth keeping, since all of it is independent of
the symptom:

- **The membership state never reaches peers.** The join-announcement packer `0x88407C` uses it
  only as a guard on the clan id, with the `state - 1 <= 1` idiom that accepts 1 and 2 alike. All
  15 readers of `profile+6837` were enumerated; the one asymmetric test (`0x8E1D48`, `cmpwi r3,2`)
  is leader-*enabling*.
- **The privilege word is not a gate here either.** `0xAB0048` masks bit `0x100` only when the state
  switch already selected leader, and at privilege `0` both branches proceed. It does explain the
  old `0xFFFF` experiment — a nonzero privilege makes the widget bail early — and confirms `0x100`
  is the leader bit.
- **`0x4b49` failures are destructive.** The handler at `0xD57064` writes 2 to `profile+6872` on
  `-1214` and 0 on `{-21, -1207, -1215, -1202}`; only success leaves it alone. A single failed
  emblem download demotes the flag below the exact `== 3` the render path needs. Every `0x4b49` we
  served in the observed window carried result 0, so this was not the cause here — but it is a real
  trap for any future refusal.

### Why the role swap was misleading

It moved the symptom, which looked like proof that leader-ness was the variable. Two ELF passes
were then framed around "is it a state test or a privilege bit", both came back correct and
negative, and the framing was never revisited. Meanwhile the swap had also warmed clan 2's emblem
into every client's cache during the window when Sean was an ordinary member — caches that a relog
does not clear, because the process survives it.

So the experiment both misdirected the search and contaminated every later measurement. That is
worse than a wrong hypothesis, because nothing about the subsequent observations looks wrong.
**An experiment that changes game state leaves residue; plan the control before running it, not
after the result looks confusing.**

## Online News, and padding that was not inert (2026-07-27)

The first time anyone watched this client render news, it showed **10 pages from 2 rows**, real
items on 1 and 8, the rest blank and dated 12-31-1969. The cause was our own 886-byte NUL padding:
the `0x200a` parser loops inside a packet until the payload is drained, so the padding was parsed
as further records at 138 bytes each. Full mechanism in `PROTOCOL.md` under `0x2008`.

Three things worth keeping from how this went:

- **The prediction was exact before the fix.** Bodies of 19 and 134 characters give 7 and 6
  entries, 13 capped at 10, second real item at position 8. Being able to predict the *wrong*
  behaviour to the page is what made the diagnosis safe to act on without a second experiment.
- **A two-row test settled it in one round.** One row was ambiguous between "phantoms scale per
  item", "fixed table size" and "a count field we send as zero". Adding a second row with a
  deliberately different body length discriminated all three at once, because the phantom run
  length is a function of body length.
- **The falsified claim was a non-sequitur, not a wrong observation.** `PROTOCOL.md` said the body
  terminates at its first NUL — correct — and concluded the padding was therefore harmless. The
  conclusion does not follow from the premise, and it carried the note "no client has been
  observed rendering a news item" the whole time. An untested inference sitting next to an
  admission that it was untested still read as settled.

Confirmed fixed: 2 pages, both real.


## The clan emblem on the connect path (2026-07-27)

Setting `0x4122`'s emblem flag (wire `0xf0` -> `profile+6872`) to 3 makes the client fetch the
emblem during connect. The risk was that `0x4b48` is recorded as blocking character select, so a
slow or wrong reply would stall the lobby. It does not:

    21:30:54.943  In  - command 4b48 - 4 bytes    00000002
    21:30:54.946  Out - command 4b49 - 772 bytes  00000000 454d4244 8000...
    21:30:55.044  In  - command 4900              <- 98ms later, lobby continues

Three things worth recording:

- **The emblem block starts with the ASCII magic `EMBD`** (`45 4D 42 44`), immediately after the
  four-byte result word. Useful for telling a real emblem from a zero-filled one at a glance in a
  hex dump, which is exactly how this was verified.
- **Zeros are not a stall.** An earlier connect at 21:14:58 served 772 zero bytes, because the
  clan was mode 4 and `emblemOf` correctly declined to serve it. The client accepted that and
  carried on identically. So a clan with no emblem costs nothing on this path.
- The flag is what drives it. With the flag at 0, the client never sends `0x4b48` at all — the
  emblem is silently absent rather than empty.


## How this file gets things wrong

Two failure modes have each cost real time here, and both are cheap to avoid.

**Another implementation is not a specification.** mgo2-server and the Nomad upstreams both work —
for their own targets. Neither was validated against `BLUS30109`, and the MGS4-integrated build
differs. That divergence has now been paid for six times: the policy path, the gate hostname, the gate port, the version-check byte, the login perks field, and the two appearance bytes character creation discarded. The perks field is the instructive one,
because it was copied *correctly* — `Array(10).fill("1000000").join("_")` is genuinely what
mgo2-server sends. Faithful transcription of a source that does not apply is still wrong, and it
looks exactly like diligence.

**An elimination is only valid if you can say what you would have seen had it been the cause.**
"The perks field" sat on the eliminated list below for a long time. The experiments that put it
there varied the perk *values* while holding the separators fixed — and the binary discards that
value entirely, so they varied an axis that provably could not matter. Ten attempts, ten identical
failures, read as "not this" when they meant "this dimension is inert." Worse, the observable that
would have settled it was already being printed: `http_probe.py` has logged
`-> proxied, <n> bytes` since the login endpoint was first written. A reply of 108 bytes where 34
were expected was on screen and never compared against anything, because "well-formed" was being
judged against our own assumed format — which came from the same source as the bug.

So: before crossing something off, name the observation that would have confirmed it, and check
that the experiment actually produced that observation. And when the reasoning is about bytes,
look at the bytes rather than at the schema you believe they follow.

## Hostnames

> **Superseded in part by [HOSTS.md](HOSTS.md).** The table below is what the client was *seen*
> resolving — still valid as observation. Since 2026-07-29 the same values are readable as **disc
> data**: string resources 28654–28691 in `o/stage/lobby/scenerio.gcx`, three regional blocks, with
> the gate and STUN ports stored beside their hosts. That is a tier up from a DNS log, it adds the
> six other URLs the client holds that never get resolved, and it is what makes the addresses
> changeable. Go there first.

| Host | Purpose |
| --- | --- |
| `mgo2web.konami.com` | Static documents and the version check |
| `mgo2auth.konami.com` | Login |
| `mgo2gateus.konamionline.com` | Gate server (`us` = region) |
| `mgo2stunna.konamionline.com` | STUN, for NAT traversal (`na` = region) |
| `info.service.konamionline.com` | Resolved, purpose not yet observed |

Redirection is done with RPCS3's **IP swap list**, not DNS: its DnsHook resolves inside the
emulator, so pointing the DNS setting at a local server does nothing.

```
mgo2web.konami.com=<ip>&&info.service.konamionline.com=<ip>&&mgo2gateus.konamionline.com=<ip>&&mgo2stunna.konamionline.com=<ip>&&mgo2auth.konami.com=<ip>
```

## Ports

| Port | Protocol | Notes |
| --- | --- | --- |
| 80 | HTTP | Static documents |
| 443 | HTTPS | Version check and login |
| 3478 | UDP | STUN. Required — see below. |
| 15731 | TCP | **Gate.** Not 5730 (Nomad's default) or 5731 (the MGO1 emulator's). |

For comparison, `mgo2-server` documents gate 5731, account 5732, game 5733+. This client dials
15731 for the gate, so that value is disc or region specific; the ports for the other lobbies come
from the lobby list and can be anything.

> **"Disc or region specific" is now settled: it is region specific, and the disc says so.**
> The gate port is stored next to its hostname in the address table — US 15731, EU 25731, JP 5731,
> with STUN 3478 in all three. `o/di` byte 42 picks the block, and it is `0x01` (US) on
> `BLUS30109`. So 15731 is no longer only a value read off an RPCS3 log; see [HOSTS.md](HOSTS.md).
> The lobby ports are unaffected — those still come from the lobby list.

## STUN

**The port check is documented in full in `dev/docs/STUN.md`** — the exchange that works, the reply
format, the Docker and secondary-address requirements, the eliminated hypotheses and the remaining
unknowns. Only the headline facts are kept here.

Matches are peer-to-peer, so the client discovers its public address before it will enter a lobby.
With no STUN server reachable it retries UPnP against the router and then fails — which presents
as a lobby error, not a NAT one, and is easy to misread.

The client does not send a plain binding request. It sends `len=12` (basic) and `len=24`
(CHANGE-REQUEST) probes from its own port 5730, and classifies its NAT from which address answers.

**Never echo the client's `0xf000` vendor attribute back.** It drives the client's decoder into an
infinite branch and hangs the game on "Adjusting port settings" with no error and no timeout. This
was confirmed in both directions. `stun_probe.py` defaults to not sending it.

**None of the three reference servers implement a STUN responder**, so none can be copied for the
reply shape:

- **GHzGangster/Nomad** and the savemgo forks: no STUN code at all. Every `stun` match in the
  source is the in-game *stun grenade* weapon-restriction flag.
- **MiguelRipoll23/mgo2-server**: the README architecture table lists "STUN server — 3478/udp", but
  there is no STUN source file in the repo and its compose file has a single service. The entry is
  aspirational; the code punts.
- **boiln/echo**: does not hand-roll it either — it runs stock **coturn** in `stun-only` mode, and
  its `stun.conf` requires two `listening-ip` addresses.

So coturn-on-two-addresses is the only reference-blessed shape, and our responder behaves like
coturn — notably, it sends no vendor attribute.
## UPnP, and "Adjusting port settings"

MGO2 does not ask the console to forward ports. It carries its own IGD client — the binary holds
`mrdUPnP / Ver[0.0.1.00]` beside `uupnp.cc`, along with `M-SEARCH`, `ssdp:discover`,
`239.255.255.250`, `WANIPConnection`, `GetExternalIPAddress`, `AddPortMapping` and
`DeletePortMapping`. The screen reading "Adjusting port settings" is that sequence.

Observed: one discovery burst from a single source port, asking for four targets in this order.

```
urn:schemas-upnp-org:service:WANIPConnection:1
urn:schemas-upnp-org:service:WANPPPConnection:1
urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
urn:schemas-upnp-org:service:InternetGatewayDevice:1
```

**All four are `service:` types, including the last.** UPnP defines `InternetGatewayDevice` as a
*device* type, and every conformant gateway advertises it that way. This client asks for it as a
service. A responder that matches only the spec-correct URN answers none of the four, and the
client waits indefinitely rather than timing out — which is what the first version of
`dev/tools/upnp_probe.py` did, and it cost a test cycle. Echo back whatever target was asked for.

### Where it stops now, and what is ruled out

With the login fixed, the client reaches this phase and stalls in it. One clean RPCS3 session:

```
0:02:13.31  [mgonet_connect_timeo]  connect 192.168.1.100:15731   gate, lobby list, clean 0003
0:02:13.65  [uaccount.cc]           connect 192.168.1.100:443     login, 36-byte reply
0:02:19-24  [mrdUPnP]               connect 192.168.1.1:49152  x8  the real router
0:02:25.10  [mrdUPnP]               bind    192.168.1.100:5730
            ...nothing further. recvfrom is called in a loop; nothing is sent.
```

Established, each checked rather than assumed:

- **UPnP succeeds.** The router ends up holding `UDP 5730 -> 192.168.1.100:5730` described as
  `988358F30A3C`, which is the client's own machine id — the binary has
  `mrdUPnP_Create_Machine_Uniq_Id` and `%02X%02X%02X%02X%02X%02X` next to `KONAMI`. Enumerating
  the router's mappings read-only shows it. The eight connects are that exchange succeeding, not
  a retry loop.
- **The client uses the real router, not a local responder.** It never fetches our description,
  even when ours answers all four searches first.
- **STUN is answered.** Two binding requests per run, from an ephemeral port and then from 5730,
  each with the `0xf000` vendor attribute. ~~The client never sends CHANGE-REQUEST~~ — **this was wrong; see the capture below.** It does
  send one (change-ip and change-port together) as RFC 3489 Test II. The original claim was made
  while the responder still echoed the `0xf000` vendor attribute, which hung the client before it
  got that far. Left struck rather than deleted because the false conclusion is instructive. It is not
  doing full RFC 3489 classification here.
- **The gate is not implicated.** Its exchange completes and the lobby list decodes field for
  field against SaveMGO's own `Hub.getLobbyList` layout — 46 bytes an entry, correct types,
  ports and ids. The account lobby is never contacted at all.
- **`EADDRINUSE` on `192.168.1.100:1900` is a red herring.** Windows' own SSDP Discovery service
  (`svchost`) binds port 1900 by default, so every RPCS3 user on Windows gets this, SaveMGO's
  included. The client falls back to an ephemeral port and discovery works regardless.
- **Unsolicited UDP to port 5730 does not move it.** Sent from WSL and from Windows, as a bare
  datagram, a Binding Request and a Binding Response. The WSL-to-Windows path is not the problem:
  a Windows listener receives WSL-sent datagrams, tested directly.
- **RPCS3's own UPnP setting is irrelevant.** The client asks 21 `cellNetCtlGetInfo` codes and
  NAT type is not among them; there is no value that setting changes for the game.

So the phase completes its visible work and the client still waits.

### What the screen is actually waiting on

The binary says this is not a NAT screen at all. The post-login state machine at `0x9468B8` has
seven states, dispatched on a halfword at `+0x68` of its context through a jump table at
`0x94690C`. **State 2 is where it sits.** It polls `0xD38120`, a thin wrapper on `0xD35E44`, and:

```
result == 0                       -> advance to state 3
result == -102 (-0x66) or -64     -> stay in state 2, poll again
anything else                     -> error 090B with the result as the detail
```

`-102` and `-64` are this library's "still in progress" codes, which is why the screen neither
advances nor errors. It polls forever.

The library is the game's own `mgonet`, and its debug strings name the call:

```
0xE25A50  mgonet_connect_timeo
0xE25A68  **** wait ***
0xE25A78  **** poll off ***
0xE25A90  mgo_connect_server_by_index() index=%d, type=%d
```

`mgo_connect_server_by_index` is `0xD34B50` — the callee of the poll. It bounds-checks an index
against a count at `+0x754` of its context, over an array at `+0x750` with a stride of `0x34`,
which is the parsed lobby list.

**So the client is not stuck adjusting ports. It is stuck trying to connect to a server from the
lobby list, and that connect never gets going** — which is exactly consistent with the account
lobby never being contacted and no TCP connect appearing in the log after the gate.

`mgo_connect_server_by_index` calls the connect-with-timeout poller at `0xD34A38` (from
`0xD34C0C`) and returns its result unchanged. That poller is a **singleton** over a global context:

```
state = [g+0x1c]
  0 -> sys_ppu_thread_create("mgonet_connect_timeo", entry 0xD35530); state = 1; return -102
  1 -> [g+0x20] == 0 ? "**** wait ***" : return -64
                     : "**** poll off ***"; result = [g+0x14]; state = 0; return result
  else -> return -64
```

and the worker at `0xD35530` does the blocking connect, stores the result at `+0x14`, aborts its
net operations, **sets the completion flag `[g+0x20] = 1`, and only then exits**. The flag is set
before the exit, so an aborted exit does not strand it.

**This means the client is not sitting in state 2.** A poll there with `state == 0` would create a
`mgonet_connect_timeo` thread, and the log shows exactly one for the whole session — the one that
connected to the gate and completed normally. No second worker is ever created, and no TCP connect
is attempted after the gate. Whatever drives the screen is one of the other six states.

So the call chain above is understood but is *not* where it hangs.

### Read out of the client's own memory

RPCS3's Memory Viewer settles things that disassembly alone cannot. The singleton objects for
these machines live in a run of pointer slots; each is `*(slot)`, and a slot reading zero means
that machine is not running.

| slot | machine | observed |
| --- | --- | --- |
| `0x166E7F0` | 34-state top-level flow (`0x88CD2C`) | **NULL** |
| `0x166F04C` | login machine (`0x9455BC`) | **NULL** |
| `0x166F050` | job worker (`0x9461D8`) | **NULL** |
| `0x166F054` | connect machine (`0x9468B8`) | **NULL** |
| `0x166F058` | waiting machine (`0x946F00`) | `0x54CE89D0` — **live** |

The live one is in **state 0** (`*(u16*)(0x54CE89D0+0x68) == 0`), which polls mgonet channel 2 and
returns without advancing while the result is `-102` or `-64`. Unlike every other state examined,
**it has no timeout** — no tick counter, no ceiling. That is why the screen waits forever instead
of erroring, and why cancelling removes the button without ending anything.

Its mgonet context is `[obj+0x60] = 0x501033D0`, and reading it confirms two things:

- **The per-type connection table is empty.** `FF FF FF FF` appears at `0x501033D0`, `+0x44` and
  `+0x88` — exactly the `type * 0x44` stride `mgo_connect_server_by_index` computes. All three
  slots are `-1`. No socket is open to any lobby.
- **The lobby list arrived intact.** At `+0x75C`, in `0x34`-byte strides, entries read
  `type=1 "Account" 192.168.1.100 :15732 id=2` and `type=2 "Game" … :15733 id=3` — every field of
  what the gate sent, parsed and stored. (Two entries because this was captured during the
  gate-removal test.) **The gate encoding is confirmed correct from the client side**, not merely
  from our own logs.

RPCS3's log agrees and is reproducible run to run: one `mgonet_connect_timeo` thread per session,
connecting only to the gate on 15731, then UPnP, then `bind 192.168.1.100:5730`, then no further
network activity at all. The account lobby is never dialled.

### The lobby-list handshake is verified inside the client

The mgonet packet parser is `0xD361A4`, dispatching on the command word. Reading all three arms
settles what our gate must do, and confirms it does it:

```
0x2002  lwzu r31, 0x750(r28)     ; marker at ctx+0x750
        cmpwi r31, 0 ; bne -> bail   must be 0 to start
        stw  r31, 4(r28)             count  := 0
        stw  r0,  0(r28)             marker := -1      "list in progress"

0x2003  addi r28, r28, 0x750     ; entries parsed at 0x34 bytes each,
        ...                        type at +0xC, name at +0x10

0x2004  lwzu r0, 0x750(r31)      ; marker
        cmpwi r0, 0 ; beq -> bail    requires 0x2002 to have run
        li   r4, 0xa ; li r5, 2
        bl   0xd32e08                fire event 0x0A on channel 2 — "list complete"
        stw  r0, 0(r31)              marker := 0
```

The observed context shows the marker back at `0`, which is what a **completed** `0x2004` leaves,
and the entries populated. So the client ran the whole sequence: start accepted, entries stored,
completion event fired. **Our `0x2002`/`0x2003`/`0x2004` are correct and fully consumed** — proven
from the client's own memory and its own code, not from our logs or from a reference server.

Two independent reviews of the reference implementations agree there is nothing more the gate
does. `mgo2-server` replies with exactly those three packets and never pushes anything unsolicited;
SaveMGO's Nomad is identical, sends nothing on connect, writes no session or flag, and holds no
state that gates the onward connect. Both were re-read specifically to look for a missing step and
found none.

One real divergence did come out of that review and has been fixed: **the list must be ordered by
id, not by name.** Nomad iterates `NLobbies.get().values()`, a map keyed by lobby id, so the
canonical seeding makes list index and lobby type coincide — index 0 = type 0 Gate, 1 = Account,
2 = Game. Ordering by name put Account at index 0 and the Gate at index 2. The client keys
connections by type in a three-slot table at stride `0x44` while its debug string reads
`mgo_connect_server_by_index() index=%d, type=%d`, carrying both. Whether the client requires the
identity is not proven; the change restores parity with the server it was developed against.

Also corrected: `mgo2-server`'s README and `AGENTS.md` advertise a STUN server on 3478/udp and its
`deno.json` imports `npm:stun`, but **there is no STUN code in that repository** — `grep -rni stun
src/` returns nothing. This file previously cited that README as evidence STUN is a required
component. STUN is still needed (the client demonstrably sends binding requests, and SaveMGO ran
one on a separate host), but the citation rested on documentation its own code does not implement.

The multicast does reach WSL from RPCS3 on Windows, so a responder there can serve it:

```
python3 dev/tools/upnp_probe.py --respond --ip 192.168.1.100
```

Mappings are logged, not created. Nothing in the harness touches a real router.

## The account lobby, read from the binary

The client's account-lobby code sits beside the mgonet packet parser. Its reply dispatcher is
`0xD37024`, and the request senders are one function each: `0x3003` at `0xD38180` (a second
sender exists at `0xD39F18`), `0x3040` at `0xD37B00`, `0x3048` at `0xD37BF0`, `0x3101` at
`0xD37DE4`, `0x3103` at `0xD37A0C`, `0x3105` at `0xD37918`, `0x3107` at `0xD37CC0`. Each sender
marks a request-status id "in progress" and the matching reply arm marks it complete:
`0x3004`→5, `0x3041`→0xD, `0x3049`→0xE, `0x3102`→0xF, `0x3104`→0x10, `0x3106`→0x11,
`0x3108`→0x12.

Verified request layouts: `0x3003` is a u32 id (ctx+0x150) followed by exactly 16 bytes
(ctx+0x154) — the session field. `0x3103` and `0x3105` carry one u8 index, bounds-checked ≤ 7
client-side before sending. `0x3101` is 16 name bytes then the appearance bytes. `0x3040` is one
u8 slot; `0x3107` is 16 bytes of name.

Verified reply grammars: `0x3004`, `0x3102`, `0x3104`, `0x3106`, `0x3108` are parsed as a single
s32 result — anything after it is ignored. `0x3041` is s32 result, then (if 0) a u32 and 16
bytes. `0x3049` is a **fixed grid parsed identically regardless of character count**:

```
s32 result; u8 slots; u8 count; u8 selectedSlot; u8 name[16];   23-byte header
8 entries x 52 bytes: u8 slot; u32 charaId; u8 name[16];
                      u8 appearance[9]; u32; u8 appearance[14]; u32
u8 tail[32]                                                     total 0x1D7 = 471
```

After parsing, the client scans the eight entries for one whose first byte equals
`selectedSlot`. The reference servers' seemingly different entry layout (a leading u32 index
instead of a u8 slot) lands on this grid exactly: three bytes of each index complete the
previous entry's final u32 and the low byte becomes the slot.

Two things follow, one of them a bug that has been fixed:

- **Our character-list trailer was 32 bytes; the canonical one is 35.** Both Nomad upstreams
  and mgo2-server pad the body to 0x1B4 and append the same 35-byte block, making 471 total.
  Ours sent 468. This is not a parse error — the read primitives bound-check only the 0x400
  receive buffer, and begin/end read (`0xD5C844`/`0xD5C858`) never compare consumed bytes
  against the payload length — but the client would have read its last three tail bytes from
  stale buffer contents. Fixed to the canonical 35 bytes.
- **The client can send `0x3040` and `0x3107`, and no reference implementation answers them.**
  Nomad v1, v2, mgo2-server and ours all lack handlers (v1 answers inbound `0x3042` with an
  empty `0x3041`, which is a different exchange). Expected replies if they ever arrive:
  `0x3041` = s32, u32, 16 bytes; `0x3108` = s32. An unanswered request would strand its status
  id the way the current port-settings screen is stranded, so if a future hang coincides with
  one of these being sent, this is where to look. Since SaveMGO ran without them, the normal
  disc flow presumably never sends them.

Everything else in our account lobby matches the binary: the session field length, the
one-s32 result replies, entry stride and appearance order, the `0x3102` success payload
(result + new character id — the client ignores the id), and the 8-entry ceiling.

**Not established: how the client derives the 16 session bytes from the login token.** Nomad v1
(and mgo2-server, which copies it) decode the field as XOR with `35 D5 C3 8E D0 11 0E A8` then
a Blowfish encrypt with the auth key; Nomad v2 instead Blowfish-decrypts all 16 bytes with a
different key (`Ptsys.KEY_6`, itself stored encrypted) and truncates to 8 chars. The two are
mutually exclusive, so at most one matches this disc. The XOR mask appears nowhere in the
binary in any byte order, and both keys are shipped in derived forms (v1 as a full precomputed
schedule, v2 encrypted), so a byte search cannot arbitrate; the client-side filler of
ctx+0x154 was not located (the two callers of the accessor at `0xD36C5C` only format the bytes
as hex for web URLs). We use the v1 scheme, which is what SaveMGO ran in production against
this build. The first real `0x3003` will settle it: a wrong decode produces a clean
INVALID_SESSION reply and a client-side error, not a hang.

## The port check is a game-lobby connect plus check-session — traced end to end

The waiting machine at `0x946F00` — the one machine live during the stall — has twelve states
(jump table at `0x946F5C`, dispatched on the halfword at `+0x68`). Reading them settles what
"Adjusting port settings" actually does after UPnP and STUN:

- **State 0** requires at least one type-2 (Game) entry in the lobby list (`0xD35F1C(ctx,2) > 0`,
  else error `0x908`), reads a halfword from config id `0xFE` — the **ordinal of the game lobby
  to use** — and polls `0xD35E44(ctx, 2, ordinal, 2)`, which resolves the ordinal to a list
  index and calls `mgo_connect_server_by_index(index, 2)`. `-102`/`-64` poll again with **no
  timeout**; `0` advances; anything else raises `0x91E`.
- **State 1** sends **`0x3003` check-session over the game-lobby connection**: u32 stored
  character id, 16 session bytes, and a trailing flag byte (from `+0x294` of the object behind
  `0x883F20`) — request-status id 6. The stored character id lives behind the accessor
  `0xD3A094` and is zero until a character has been selected, so **the port check claims
  character id 0**.
- **State 2** waits for the `0x3004` result with a real timeout (a tick counter that raises
  `0x923`). Result `0` advances to state 3; `-0xF0` → `0x924`, `-0x192` → `0xA50`,
  `-0x193`/`-0x194` → `0x933`, `-0xF2` and everything else → `0x925`. These are the same
  "official" codes Nomad v2 defines (`CHAR_CANTBEUSED = -0x192` and friends), so the server's
  reply payload chooses the client's error screen directly.

Three consequences:

- **The next server the client contacts after the gate is the game lobby, not the account
  lobby.** Every earlier statement here reasoning from "the account lobby is never dialled"
  stands factually, but the expectation behind it was wrong — during this phase the client was
  never going to dial the account lobby.
- **RETRACTED — do not implement this.** The premise below was false and the changes built on it were reverted; the game lobby rejects a check-session with no character selected. Kept only because the reasoning is instructive. See "reconciled against the disassembly" later in this file.

~~The game lobby must accept a check-session with character id 0 and no character selected.~~
  SaveMGO passed this by a collision of defaults — the client zero-initialises its stored id and
  v1's MySQL `current_character` column defaulted to 0, so `0 == 0`. Our port modelled "no
  selection" as null and rejected, which would have failed the port check with `0x925` the
  moment the connect ever succeeded. Fixed: with no character selected, a claimed id of 0 and a
  valid session now check in.
- **The stall mechanism is narrowed to one shape.** The connect poller singleton (its pointer is
  the word at `0xFFE5F0`) has exactly two states — its only writers are the poller itself
  (`0xD34A38`) and the ctx initialiser (`0xD355B4`) — and state 0 always creates a
  `mgonet_connect_timeo` thread. Endless `-64` with no new thread in the log therefore means
  **state 1 with the completion flag at `+0x20` never set**: a worker that was created but never
  ran to completion, or a creation that failed outright — the `sys_ppu_thread_create` result is
  **ignored** at `0xD34ADC`. To confirm from a hung session, read `g = [0xFFE5F0]` in the Memory
  Viewer, then `[g+0x1C]` (expect 1), `[g+0x20]` (expect 0), `[g+0xC]` (the port — expect 15733,
  proving the target is the game lobby), `[g+8]` (pointer to the host string), `[g+0x14]` (the
  stored result). And grep the RPCS3 log for the second `mgonet_connect_timeo` creation — its
  absence or an error there is the whole story.

This reframes the emulator hypothesis precisely: whatever the MGO2PC build fixes, it is
something the connect worker (entry `0xD35530`) needs between thread creation and setting its
completion flag.

The phase continues past check-session: **state 3 sends `0x4100`** (empty payload,
request-status id `0x15`) — the character-connect burst our game lobby already answers with ten
packets — and **state 4** waits for it (timeout error `0x1037:FFFFFF60`), then fills in a large
parameter object and advances to states 5+, which is where the actual UDP verification must
live. So the server-side obligations for the whole port check are: accept the TCP connect,
answer `0x3003` with result 0, and answer `0x4100` — all of which this server now does, with
the burst layouts still unverified against the client's parsers.

## The port check decoded from a live packet capture

A Wireshark capture of a **working** MGO2PC session (`savemgo.pcapng`) settles the port check on
the wire, and Wireshark itself labels it **CLASSIC-STUN (RFC 3489)** — no magic cookie, exactly
as the binary predicted. The client binds UDP 5730 and runs two-address NAT classification
against two STUN server IPs. Read the bytes, not the schema:

The client sends a Binding Request to the primary STUN server, carrying one Konami `0xf000`
vendor attribute, and gets back a Binding Response with **four** attributes:

```
REQ  ->  0001 000c <16B txid> f000 0008 0573000000000002
RESP <-  0101 0030 <txid>
         0001 0008 0001 1662 2fcd2aa0   MAPPED-ADDRESS   port 0x1662=5730  ip 47.205.42.160
         0004 0008 0001 0d96 0fcc42cf   SOURCE-ADDRESS   port 3478  ip 15.204.66.207 (self)
         0005 0008 0001 0d97 0fcc14bb   CHANGED-ADDRESS  port 3479  ip 15.204.20.187 (other srv)
         8020 0008 0001 fd37 c498fd81   XOR-MAPPED-ADDRESS (obfuscated, non-RFC-5389 key)
```

The client then contacts the second server (learned from CHANGED-ADDRESS), which returns the
**same** MAPPED-ADDRESS `47.205.42.160:5730`. It also sends a CHANGE-REQUEST leg
(`0003 0004 00000006` = change IP **and** port) — so it *does* send CHANGE-REQUEST, correcting the
earlier note here that it never does.

What makes it PASS, stated as the responder must satisfy it:

1. **Two server addresses**, each answering on the STUN port. DNS gave only the primary
   (`stun.mgo2pc.com` → 15.204.66.207); the second (15.204.20.187) is handed to the client in the
   first response's CHANGED-ADDRESS. So our responder supplies the second address itself.
2. **MAPPED-ADDRESS port must equal the client's source port (5730)** — port-preserving.
3. **Both servers must report the identical mapped ip:port.** That consistency across two
   distinct server addresses is what the client reads as full-cone (NAT type `0x10`) and passes;
   a differing/absent mapping reads as symmetric (0/1/2) and fails `0692:00000003`.

`dev/tools/retired/stun_probe.py` already emits MAPPED + SOURCE + CHANGED with `peer` as the mapped address
(port-preserving) and, given a second address, answers change-IP from it — i.e. it is the right
shape. The capture removes the last doubt about the format (four attributes are accepted; the
old "decoder rejects >2 attributes" comment was wrong and is fixed). The remaining risk is
operational: it must run host-networked (Docker's UDP proxy rewrites the source port, which would
break the port-preserving mapping) and with the real second address configured. The XOR-MAPPED `0x8020`
attribute is **required** — a three-attribute reply is rejected, which is how its necessity was
established. Its obfuscation was later reproduced: it is keyed on the request's transaction id,
not a magic cookie. See `dev/docs/STUN.md`.

## The post-login machines, mapped to the flow (reconciled against the disassembly)

A working MGO2PC session reaches character select, joins a match, and quits, giving the
ground-truth order: **gate (5731) → UDP port check (STUN, 5730) → account lobby (5732, character
select) → game lobby (5733, join)**. The state machines map onto it as follows, each cited to the
binary:

| machine (obj slot) | step | connects | 0x3003 sender | onward |
| --- | --- | --- | --- | --- |
| `0x9461D8` (0x166F050) | fetch lobby list | — | — | sends `0x2005` |
| `0x95244C` | UDP port check | — (STUN, binds 5730) | — | raises `0692:xxxx` |
| `0x9468B8` (0x166F054) | **account lobby / char select** | **type 1** via `0xD38120` | **`0xD38180`** (account id from ctx+0x150, req-status 5) | UI requests `0x3048` char list |
| `0x946F00` (0x166F058) | **game join** (user-initiated) | **type 2** via `0xD384A4` | **`0xD39F18`** (character id from *(ctx+0x57d8), + flag byte, req-status 6) | `0x4100` loadout burst via `0xD3A9F4` |

Connection slots are keyed by type at stride `0x44`, valid types 0/1/2 only (`0xD358CC`); type 0
= gate (established by the gate handshake, not this path), 1 = account, 2 = game. The two connect
wrappers hard-code the type: `0xD38120` → type 1, `0xD384A4` → type 2. `0x946F00`'s ordinal comes
from config key `0xFE`, which the game-lobby-list UI (`0x935344`) writes from the entry the user
picks — proving `0x946F00` is a **user-initiated game join**, not an automatic post-port step.

**This corrects a claim made earlier in this work:** that `0x946F00` (seen live in one memory
read) was the "Adjusting port settings" step dialing a game lobby with character id 0. It is the
game-join machine, always entered after character select with a real character. Server changes
built on that false premise — accepting a game-lobby check-session with id 0, and a
characterless `0x4100` burst — have been reverted. The `0x3049` trailer (35 bytes / 0x1d7) and
`0x4101` grid (0x142) fixes are independent of this and stand.

## The port check is beaten — the game reaches the menu (stock RPCS3 + our server)

The long-standing "the client binds 5730 but never sends STUN" was a **logging artifact**, and
it is now disproven end to end. With `sys_net` at Trace level and a STUN responder running, the
BLUS30109 client on **stock RPCS3** plainly does: `bind 192.168.1.100:5730` →
`sendto(len=32) → 192.168.1.100:3478` (a STUN Binding Request carrying the Konami `0xf000`
vendor attribute). Default RPCS3 batches the sendto into a `⁂ sys_net_bnet_sendto [n]` summary
and, with no responder answering, nothing confirmed it — which is why every prior session
concluded it was never sent.

The first responder reply was **rejected** because it was three attributes where the real server
sends four. The missing one is **XOR-MAPPED-ADDRESS**, and two things about it were non-standard:
its type is **`0x8020`** (not the RFC-5389 `0x0020`), and it is XORed against the **request
transaction id**, not the magic cookie (`port ^ txid[0:2]`, `ip ^ txid[0:4]`). Decoded from the
capture and validated: for txid `eb55d721…`, client `47.205.42.160:5730`, it reproduces the
captured `port=fd37 ip=c498fd81` exactly. `dev/tools/retired/stun_probe.py` now sends this by default.

With the four-attribute reply, the game accepts the response, runs the port check to a verdict,
and **reaches the online menu.** The verdict is `0692:00000003` ("NAT looks symmetric"), a soft
dialog that lets the user proceed — it is not a hang. It is symmetric only because the client ran
just the first NAT test — **historical: this was with the vendor attribute still echoed. With that
removed the client runs Test II and the check passes, so a 0692 verdict today is a regression, not
the expected outcome.** (three basic Binding Requests to the primary, no CHANGE-REQUEST, never
queried the second address), so full-cone can't be confirmed; that matters for P2P match hosting,
not for reaching the lobby. Making it a clean pass (`0x10`) would require driving the client
through the two-address / change-request legs — a later concern.

So: **stock RPCS3 + our server now clears gate → login → lobby list → port check → menu.** The
next server-side surface is the account lobby (`15732`) reached from the menu.

## Error 0692:00000003 — the UDP port check, a second machine after the connect

There are **two** post-login "adjusting port" machines in the binary, and they are easy to
conflate:

1. The connect machine at `0x946F00` (module base `0xFF1018`) — a game-lobby TCP connect plus
   check-session plus `0x4100`. This is where our BLUS30109 client on stock RPCS3 hangs
   forever, and it is documented above.
2. A **UDP port-check machine** at `0x95244C` (module base `0xFF1210`, six states, jump table
   `0x9524A4`, state in the halfword at `+0x66`). State 1 binds a UDP socket and starts a
   probe; state 3 polls it via `0x8F0DA8` and classifies the result: `0`/`1` pass (0 rings the
   success chime `0x1CF`, 1 advances), while **`3`, `4`, and anything else raise error `0692`
   with that classification as the detail** (`0x952758` → `li r4,3`; `0x952764` → `li r4,4`;
   `0x952788` → `li r4,0`), through the confirm-dialog path `0x885A08`.

So `0692:00000003` is not a DNS or connect failure — a connect failure aborts state 1 before any
probe runs. It is the UDP probe completing and the server-side or NAT verdict coming back as
classification 3. The probe reaches a server, that server (or the round trip) judges the client's
UDP port unusable, and the client reports it.

This was seen on the **MGO2PC custom build**, which is a different game build on a patched RPCS3
and is not the target. Its RPCS3 log shows it resolving `stun.mgo2pc.com` and connecting to
`15.204.239.231:5731` — MGO2PC's own live gate.

**The cause was a local UDP 5730 collision, confirmed by experiment.** `netstat` showed exactly
one holder of `192.168.1.100:5730` on Windows (a stale RPCS3 instance from BLUS30109 testing,
not the MGO2PC client); closing that process let the MGO2PC client progress past the port check.
So `0692:0003` here was the live client being unable to own 5730 because a second RPCS3 instance
held it — two emulator instances on one host contend for the same UDP port. This **corrects an
earlier version of this entry** which read the failure as a NAT/firewall verdict on the user's
network because the build reached a real remote STUN host. That was an over-read of the log: the
port-close experiment refutes it. The operational rule is simply **one RPCS3 instance at a time,
with 5730 verified free before launch** (`netstat -ano | findstr :5730`).

**That question is now closed, and the answer was no.** Our own BLUS30109 client's
"Adjusting port settings" hang had an unrelated cause: the responder was echoing the client's
`0xf000` vendor attribute back, which drives the client's decoder into an infinite branch. With
the echo removed the client completes classification and passes. The two failures share a screen
and nothing else. See `dev/docs/STUN.md`.

## What stock RPCS3 does and does not do for the port check (read from RPCS3 master)

Reading RPCS3's own source (`github.com/RPCS3/rpcs3`, master) settles what the emulator
contributes:

- **RPCS3 has no STUN client at all.** No STUN code anywhere in the tree; `cellNetCtlGetNatInfo`
  is faked (`cellNetCtl.cpp`), hardcoding NAT type 2 / STUN OK. So MGO2's port check is entirely
  the game's own mrdUPnP STUN — the emulator neither performs nor assists it.
- **No emulator UDP socket contends with the game's ports.** The only fixed internal UDP port is
  the RPCN P2P socket 3658 (bind-rewritten to 3659); nothing binds 3478 or 5730. So a collision
  with the game's STUN is impossible at the emulator level.
- **The UDP send path is a faithful passthrough.** `lv2_socket_native::sendto` calls host
  `::sendto` directly; the only drop is a *public* destination while Internet is Disconnected
  (`is_ip_public_address` returns false for 192.168/x, so LAN-local sends are never blocked or
  rewritten). Bind of `192.168.1.100:5730` maps 1:1 to a host bind and succeeds.

So stock RPCS3 is fully capable of carrying the game's STUN with Internet set to Connected. **The
"bind 5730 then never sendto" is therefore game-side, not the socket layer** — the game aborts
before it sends, it is not the emulator dropping the datagram.

One real stock limitation the source shows, kept as a weak candidate: `sys_net_infoctl` implements
only cmd=9 (returns the DNS nameserver); **cmd=5 and cmd=53 fall through to `default` and return
`CELL_OK` with the output struct left zeroed** (`sys_net.cpp`). If some component read a local
interface/address out of those and rejected zeros, it could abort. It is weak because the log
shows cmd=5/9/53 issued on the `mgonet_connect_timeo` and `uaccount.cc` threads — the gate and
login, which both *succeed* — not on the `mrdUPnP` thread that runs the port check.

**Crucially, the fork does not fix any of this in public source.** The public `cipherxof/rpcs3:mgs4`
adds only graphics/audio/perf commits over upstream and touches no net file; the historical MGO2
net patch (a 2020 WSAPoll change) is long upstreamed. So stock and the SaveMGO build share
identical net code — any difference lives in the unpublished `savemgo-rebase7` branch, the
different game binary (`NPMG00020` standalone MGO vs `BLUS30109` MGS4-disc MGO2), or config.

## MGO2 requires a PSN/NP sign-in to go online; the SaveMGO build fakes it

Observed on stock RPCS3: with RPCN disabled, MGO2 refuses to go online with **"Unable to connect
to network (0519:8002AA0C)"**. So the game gates its online mode on a PSN/NP sign-in, which stock
RPCS3 supplies only through RPCN. The SaveMGO custom build reaches online **with RPCN off**
(`rpcn.yml` has empty NPID/password, config `PSN status: Disconnected`), so it must fake the NP
sign-in — a genuine emulator behaviour, and one absent from the public fork, i.e. carried in the
private branch. This is the clearest thing the custom emulator demonstrably *does*. It is about
getting online (passing the sign-in gate), which is upstream of the port check; it does not by
itself explain the port-check stall on an RPCN-enabled stock client.

## Error 090B:00000001 — traced in the game binary

This is no longer guesswork. The decrypted MGO2 module names the exact instruction that raises it.

Reference material for all addresses below: `MGO2.elf` under `PS3_GAME/USRDIR/o/`, an ELF64 PPC64
big-endian image. Virtual address = file offset + `0x10000` for both PT_LOAD segments. The TOC
pointer `r2` is `0x10353A8`, taken from the `.opd` function-descriptor table at `0xFFEC90`
(every descriptor is `{entry, toc}` and every one carries that same TOC). That table also gives
23,779 function boundaries, which is what makes the disassembly navigable.

### Only one site can produce it

The error is formatted `(%04X:%08X)` from a pair `(code, detail)`. Exactly three instructions in
the whole image load `0x090B` as the code:

| site | detail argument | renders as |
| --- | --- | --- |
| `0x945A3C` | `li r4, 1` | `090B:00000001` |
| `0x946A34` | `extsw r4, r3` — a negative network return code | `090B:FFFFFF..` |
| `0x946B98` | `li r4, -0xF0` | `090B:FFFFFF10` |

The observed detail is `00000001`, so the failure is `0x945A3C` and nothing else. The other two
sites belong to a different state machine (`0x9468B8`) and cannot render a detail of 1.

### What that site is

`0x945A3C` sits in the state machine at `0x9455BC`, whose state 3 polls `0x944444`. That poll
reads a status field and returns 0 for done, -1 for failed, 1 for still working. On failure it
calls a virtual accessor for the reason code and maps it:

| reason | error code |
| --- | --- |
| 1 | **090B** |
| 2 | 070B |
| 3 | 0911 |
| 4 | 0846 |
| 5 | 0912 |
| 6 | 0847 |
| 7 | not an error — the state machine advances |
| 8 | code 0 |
| other | 0910 |

The object it polls is the singleton built at `0xBB1C40`, and its worker is `0xBB0FB8`. That
function is **`uaccount.cc`** — the HTTPS login. It is the code that assembles
`name`, `passwd`, `product`, `lang`, `tz`, `disk`, `ps3`, `stime`, `seed`, `np` and `flag`, all
loaded from one pointer table at `0xFF22B8`, alongside the literal `uaccount.cc` and an embedded
`-----BEGIN CERTIFICATE-----`.

**So 090B:00000001 is a login error, not a lobby error.** The adjacency of `MGO_ERROR_RES_LOBBY`
to the `(%04X:%08X)` format string is a coincidence of the string blob — those three
`MGO_ERROR_RES_*` names are never referenced from any code that computes `0x090B`.

### The three ways to trigger it

Reason 1 is set at `0xBB1618`, reachable from exactly three places:

1. **The POST itself fails.** `0xBB1584`: if the request call returns negative, every error except
   `0x80710A06` falls straight through to reason 1. This is what the RPCS3 log shows —
   `connect` → `EINPROGRESS` → `shutdown` → error dialog, with no TLS handshake.
   `0x80710A06` is not an exemption; see the certificate branch below.
2. **The response body does not parse.** The parser at `0xBB16B0` requires, with no slack:
   `strtol(base 10)` `,` `strtol` `,` `strtol` `,` `<token>`. A missing comma, or a `strtol` that
   consumes zero characters, jumps to reason 1. The token is then passed to cellHttpUtil import #3
   (NID `0x8E6C5BB9`, called as `(out, outSize, in, &required)`) with a null output to measure it,
   and `required` must equal `0x11` — i.e. **the fourth field must be exactly 16 characters**,
   which confirms the 16-hex session half we already return.
3. **The first field is 10, 11 or 12.** The jump table at `0xBB1994` maps the leading integer of
   the response: 0 is success; 2, 5, 6, 7, 8 give distinct errors; 1, 3, 4, 9 and anything above
   12 give reason 3 (`0911`); and 10, 11, 12 give reason 1.

Our reply is `0,<account id>,<perks>,<16 hex>`, which satisfies (2) and (3). That leaves (1) —
the transport — as the cause, which agrees with the RPCS3 log and with the fact that no
server-side change has ever moved the outcome.

### The certificate branch, and a decisive experiment it enables

`0x80710A06` is `CELL_HTTPS_ERROR_HANDSHAKE`, per RPCS3's `cellHttp.h`. It is the one error the
login task does not immediately report, because it is the one error where the client can say
something more specific. At `0xBB19C8` it re-reads the saved SSL verify mask and classifies:

```
verifyErr & 0x1800 == 0            -> reason 1  (090B:00000001)
verifyErr & ~0x1800 != 0           -> reason 1  (090B:00000001)
otherwise                          -> reason 2  (070B:00000002)
```

`0x1800` is exactly `CELL_HTTPS_VERIFY_ERROR_EXPIRED (0x0800)` plus
`CELL_HTTPS_VERIFY_ERROR_NOT_YET_VALID (0x1000)`. So the special case is not tolerance — it is a
**clock-and-validity-window diagnosis**. A certificate that fails *only* because of its dates gets
its own error, 070B. Every other certificate failure — unknown CA, bad chain, common-name
mismatch, not verifiable — lands back on 090B:00000001, indistinguishable from the socket never
opening.

The mask is saved at `+0x24` of the request object by the `cellHttpsSslCallback` at `0xBB3310`,
whose signature matches RPCS3's `s32(u32 verifyErr, void** sslCerts, s32 certNum, const char*
hostname, const void* id, void* userArg)` register for register. That callback also honours two
switches: a per-request bit that pre-clears the two date bits, and a global word at `0x16194CC`
whose bit 0 makes it discard every verify error and accept the certificate outright. Bit 1 of the
same word is what decides whether `np=<psn name>` is appended to the login request.

### That prediction was tested against the real client, and it held

Serving `dev/runtime/tls/cert-expired.pem` — the same CA, key and common name as the working chain,
re-signed over 2020–2021 so that expiry is its only defect — produced exactly the predicted
outcome:

```
TLS handshake ok from ... (TLSv1.2, AES256-SHA256)
  POST http://mgo2web.konami.com/us/mgo2//patch/checkver.html
TLS handshake ok from ... (TLSv1.2, AES256-SHA256)
  POST http://mgo2web.konami.com/us/mgo2//patch/checkver.html
TLS handshake FAILED from ...: [SSL: SSLV3_ALERT_CERTIFICATE_EXPIRED]
```

and on screen:

> Security Certificate has either expired or has not been enabled. (Your PS3tm system clock may
> not be set correctly.) Continue processing? **(070B:00000002)**

The dialog names both bits of the `0x1800` mask — "expired or has not been enabled" is
`CELL_HTTPS_VERIFY_ERROR_EXPIRED` and `..._NOT_YET_VALID` — and the code is `070B:00000002`,
the reason-2 pairing read out of the binary. The static analysis is confirmed by observation.

Four things follow, all of them new:

1. **The login connection reaches the TLS handshake and evaluates our certificate.** It is not
   dying in the socket layer. The earlier `connect` → `EINPROGRESS` → `shutdown` teardown is not
   what happens on every attempt.
2. **Our CA chain verifies.** The client's only complaint was the date. An untrusted CA produces
   `unknown_ca` and 090B instead — that is what a stock `curl` sends when it has not been given
   `ca-cert.pem`. So installing the CA at `CA30.cer` genuinely works, and the normal
   `cert.pem` is exonerated as a cause of 090B.
3. **The version check and the login verify certificates differently.** The same expired chain was
   accepted twice for `checkver.html` and rejected for the login. That is the per-request bit at
   `+0x28` of the request object, tested at `0xBB359C`, which pre-clears the two date bits before
   the callback decides: `uupdate.cc` sets it, `uaccount.cc` does not.
4. **070B is a prompt, not a dead end** — "Continue processing?". It is raised through
   `0x8858F0`, which takes *two* callbacks and a flag byte of `0x12`, where 090B goes through
   `0x885A08` with one callback and `0x10`. A confirm dialog and an error dialog respectively.

With the transport and the certificate both cleared, the remaining triggers for 090B are the
response grammar and the leading status field — the parts we thought were already satisfied.

### Root cause: the perks field

Answering "Continue" to the 070B prompt let the login proceed over the expired connection, and
the probe caught the request we had never previously been able to see:

```
POST http://mgo2auth.konami.com/us/mgo2/kid/gidauth5.html
     body fields: name,passwd,product,lang,tz,disk,ps3,stime,seed,np
     -> proxied, 108 bytes, text/plain;charset=UTF-8
```

108 bytes is far too long for `0,<id>,<perks>,<16 hex>`. We were sending:

```
0,122345677,1000000_1000000_1000000_1000000_1000000_1000000_1000000_1000000_1000000_1000000,84486ef2cca76f51
```

Against the parser at `0xBB16B0`:

| step | outcome |
| --- | --- |
| `strtol` → `0` | ok, the success status |
| next byte `,` | ok |
| `strtol` → `122345677` | ok |
| next byte `,` | ok |
| `strtol` → `1000000`, stops at `_` | ok, digits were consumed |
| next byte must be `,`, but is `_` | **fails** — `0xBB172C`/`0xBB1730` branch to reason 1 |

So the third field must be a **single decimal integer immediately followed by a comma**. Its value
is then thrown away: `strtol`'s result at `0xBB1710` is never stored anywhere, so only the syntax
matters. `1000000` works; the ten-element underscore-joined list mgo2-server sends does not.

That reference targets the standalone MGO2, and this is the MGS4-integrated build — the same
divergence that already cost us the gate port and the policy path.

**This corrects an earlier entry in this file.** "The perks field" was listed below as eliminated.
It was not: the attempts varied the perk *values* while keeping the underscores, so every one of
them died at the same byte and looked like the same failure.

### The old folklore, for the record

Konami's own support answer, preserved on GameFAQs, attributes 090B
to inbound **UDP** being blocked, and the thread identifies the port as **5730**. That matches what
the client does here: every STUN request originates from port 5730, so the game binds it and
expects to receive on it.

The mechanism is easy to misread. NAT discovery asks the server to reply from a *different* port,
and a stateful firewall treats a reply from a port the game never contacted as unsolicited inbound
traffic and drops it. The client then concludes its UDP port is closed. Nothing in the server logs
indicates a problem, because the server did send the reply.

On Windows, allow it inbound:

```
netsh advfirewall firewall add rule name="MGO2 UDP 5730" dir=in action=allow protocol=UDP localport=5730
```

Opening that port did not resolve it here, so the UDP explanation is at best incomplete.

A second explanation appears in period forum threads: that 090B:00000001 also means the client's
**region** does not match the service — a NA disc against EU servers, or similar. This client is
consistently NA: disc `BLUS30109`, it resolves `mgo2gateus`, and it fetches `/us/mgo2/...`
documents. Both explanations are now superseded: the binary shows the code is raised by the login
task alone, and neither UDP reachability nor region is consulted on any path that reaches it.

Two candidates that the binary also rules out as causes of *this* code:

- the `checkver` reply — it is parsed by a different module (`uupdate.cc`) that cannot raise 090B
- `product=2592964502` in the login request, which is sent but never echoed or validated

## Where it currently stops, and why the server may not be the cause

The client reaches the login screen, fetches the policy, passes the version check, receives the
lobby list correctly, and then reports 090B:00000001.

RPCS3's log shows the login connection being abandoned rather than refused:

```
connect(s=54) -> 192.168.1.100:443
EINPROGRESS
cellNetCtlDelHandler          19ms later
shutdown(s=54, how=2)
close(s=54)
                              error dialog
```

No TLS handshake, no HTTP request — the server is never asked. It is intermittent: some attempts
do complete the POST and receive a well-formed reply, and still fail.

Immediately before that teardown the game makes calls the emulator does not implement:

```
196 x  sys_net TODO: sys_net_infoctl(cmd=9)
 32 x  sys_net TODO: sys_net_infoctl(cmd=53)
 19 x  cellNetCtl TODO: cellNetCtlAddHandler
  4 x  cellNetCtl: Unsupported request: INFO_HTTP_PROXY_SERVER, INFO_SSID, ...
```

`TODO` is RPCS3's marker for an unimplemented call. The game queries its network configuration
and receives nothing. This was once promoted here to the leading explanation for the stall.

**It is refuted.** A working MGO2PC session on the custom RPCS3 build was compared against the
stock build's hung session, and the custom build leaves the *same* calls unimplemented:
`sys_net_infoctl(cmd=9)` TODO ×298 (stock ×210), `cmd=53` TODO ×65 (stock ×44), `cmd=5` TODO ×6
(both), `cellNetCtlAddHandler/DelHandler` TODO (both). The build that reaches a lobby has the
identical unimplemented calls as the build that hangs, so those TODOs are not the blocker. The
custom RPCS3 differs from stock in some *other* way, or the difference is server-side; it is not
these network-config calls.

The binary trace above raises this from a candidate to the leading explanation. 090B:00000001 is
raised by the login task, and the only one of its three triggers our reply does not already
satisfy is a failed HTTPS POST — which is exactly what the teardown above is.

What has been eliminated as the cause, each tested against a real client: the lobby list contents,
ordering and encoding; lobby ports; the account id in the login reply; the reply's content type;
sequence-number enforcement; STUN behaviour including two-address NAT discovery; inbound UDP on
5730; and the WSL network boundary.

The perks field was on this list and should not have been — see "Root cause: the perks field"
above. Every attempt varied its value but kept the underscore separators, so all of them failed
identically and the field looked ruled out.

## HTTP endpoints

Plain HTTP on port 80:

```
GET http://mgo2web.konami.com/us/mgo2/policy/policy.txt      terms of service
GET http://mgo2web.konami.com/us/mgo2/help/0_0.txt           online manual
```

`us` is the region, and `0_0` is indexed, so sibling files almost certainly exist.

TLS on port 443:

```
POST https://mgo2web.konami.com/us/mgo2//patch/checkver.html
     p=<flags>,<title id>,<nonce>          e.g. p=16777216,BLUS30109,394436512
     -> a single 0x00 byte, meaning up to date. NOT the ASCII "0" (0x30).

POST https://mgo2auth.konami.com/us/mgo2/kid/gidauth5.html
     name=<game id>&passwd=<md5>&product=…&lang=…&tz=…&disk=…&ps3=…&stime=…
     &seed=<48 hex>&np=<psn name>
     -> 0,<account id>,<perks>,<16 hex session>    success
     -> 1,0,0,0000000000000000                     failure
```

The double slash in `/us/mgo2//patch/` is the client's, not a typo.

### Auto-patch — `checkver.html` and the update flow [ELF, 2026-07-30]

**Static analysis only — never exercised against a real client.** Our server has always answered
`checkver.html` with a single `0x00` byte (`dev/runtime/www/us/mgo2/patch/checkver.html` is
literally that one byte, served statically), so nothing below has been observed live. Addresses in
`ADDRESSES.md` §12.

**Byte 0 of the reply is a status, not a fixed sentinel.** `0x00` = up to date (what we send).
`0x01` = update available, and the rest of the reply is a structured payload: an opaque u32
(never read back — safe to zero), two NUL-terminated base-URL strings ("string A" for the patch
tree, "string B" for the HTTP-fallback tree, 255 usable characters each), a list of version-range
records, a `0x00` terminator, two more opaque fields (read but never branched on in this module),
then **two 64-byte blobs that become Blowfish keys** — keystore slot 7 for payload files, slot 8
for `.inf`. Any byte-0 value other than `0x00`/`0x01` is an immediate error. **The server supplies
both of these keys itself** — there is no baked-in secret to recover for them — but see below,
because a *third* key used later in the `.inf` pipeline is not one of these two.

**A version-range record is a variable-length wire string; the 44-byte/≤8 figures describe the
client's in-memory array, not the reply.** Text form `<from>to<to>.` (**trailing dot required**,
packed `major<<24 | minor<<16 | revision`, revision unbounded). Stream advance between records is
`strlen()`-based. The ≤8-record cap is an unchecked buffer limit, not a validated bound — a 9th
record overwrites the record count itself. A `strtoul` parse failure skips a record (silently, the
count and truncated name still advance); a failed literal-`to` check or a failed version gate is
**fatal (error state 10)** — corrected from an earlier, looser "rejected" framing.

A record is accepted only if the client's own current version is ≥ the record's "from" version.
That current version is **not** an ELF constant: it is read at runtime from the client's mounted
`.p` archive (`0xBB68A0`/`0xBB6EC0`, `mount-registry → vtable+24 → ".p"`). A stock disc with no
archive reports `1.0.0` (`0x01000000`), matching the `p=16777216,...` seen in the checkver request
body.

**This is what "`0inf`" is.** It isn't a distinct extension — it's the client's URL format string,
literally `%sinf` with no dot (`0xBB7D48`), so the record text has to end in its own `.` for the
concatenation to read `...1.34.0inf`. The historical URL set the user has —
`BLUS30109.1.10.0to1.34.0inf`, `1.10.0to1.34.0inf`, and a `.torrent` matching the traced format
`%s.%u.%u.%uto%u.%u.%u.torrent` (string A base + `"BLUS30109"` + from/to versions) byte for byte —
is consistent with a checkver reply carrying two version-range records for the same upgrade, one
disc-qualified and one generic.

**Fetch order:** checkver → `relnote.txt` → one `.inf` per accepted record → `.torrent`, or, if flag
bits at obj+1036 select it, a plain per-file HTTP fetch from string B with `Range:` resume instead
of BitTorrent.

**`relnote.txt` is rendered — corrects an earlier claim that it was fetched and never displayed.**
That claim was scoped only to `uupdate.cc`'s own code, which is true as far as it goes (the module
fetches the body into the update object at offset +2506, 64 KiB cap, and touches it no further),
but the body is exported through the object's virtual `getStatus` (offset +36 of a 44-byte status
struct) to the owning screen, which polls it every frame and, in flow state 1, word-wraps the body
into up to 62 lines and renders 5 at a time through a scrollable UI pane (widgets `0x521FD0`-
`0x521FD4`, sub-state machine `0x95CBCC` sub-states 6/7). Static analysis only — flow state 1 has
never been reached against a real client, since our server has always sent `checkver.html` status
`0x00`. Two more corrections fell out of the same pass: update-vtable slot +0 (`0xBB4BF8`) is a real
download-progress percentage (`bytes-done*100/bytes-total`), and while neither of the two dialog
raisers used elsewhere in the client (`0x8858F0`, `0x885A08`) appears anywhere in this screen's
code, a **third** raiser (`0x8BE974`, 74 call sites binary-wide) does, called with a version string
from the same `0xBB5150` formatter — so "no dialog raiser" was true only of those two specific
functions, not of the screen in general.

**Live-tested, 2026-07-31 — the first real-client confirmation of any of this.** A hand-authored
`checkver.html` reply (status `0x01`, two version records, two chosen Blowfish keys) was served to
a real client. It parsed correctly and proceeded exactly as predicted: fetched `relnote.txt`
without incident, then requested `.inf` at a URL byte-for-byte matching the predicted
`<record-text>+"inf"` construction (`BLUS30109.1.0.0to1.36.0.inf`, from a record text of
`BLUS30109.1.0.0to1.36.0.`). No `.inf` existed yet, so the client received the harness's generic
fallback body, failed to parse it as ciphertext, and raised a clean, generic error dialog
("A network server error has occurred.", code `-160`/`21917`, `ERRORS.md`) rather than hanging or
crashing. This is the first field evidence that the reply's top-level layout and the record→URL
construction are both correct.

**Corrected 2026-07-31: `.inf`'s three stages are HMAC-MD5 verify → Blowfish-CBC decrypt →
HMAC-MD5 verify, not three cipher layers.** `0xD652E0`, previously assumed to be a second Blowfish
decryptor, is the constructor of an HMAC-MD5 verifying stream filter; the real Blowfish-CBC stream
(`0xD66CF0`) is stage 2, sitting between two integrity checks rather than surrounded by more
decryption:

- Stage 1 (`0xBB7E7C`) HMAC-MD5-verifies the whole downloaded file against keystore slot 8's full
  64 bytes (used as an HMAC key block — not split, not a cipher key).
- Stage 2 (`0xBB8618`) Blowfish-CBC-decrypts the file minus its last 16 bytes — those 16 bytes are
  stage 1's tag, not padding or an IV. Keystore slot 7's 64 bytes split **8 (IV) + 56 (key)**,
  through the standard Blowfish schedule (pi table confirmed at `0xE25AEC`) — a stock CBC library
  given the raw key/IV reproduces this with no pre-expanded schedule needed.
- Stage 3 (`0xBB8848`) HMAC-MD5-verifies stage 2's plaintext against a **64-byte blob resident in
  the ELF at `0xE20000`** (`93 57 a9 df b8 eb 8d 03 b8 43 cd 02 5f 2a 30 ce` + zero padding). **This
  key is still not server-supplied** — real constraint on hand-authoring an `.inf`. **Settled: this
  is verification only** — the drain target is stack scratch assigned once, not the 256 KB
  plaintext buffer, so stage 2's output is final and stage 3 neither transforms nor aliases it.

Padding on the CBC layer is **PKCS#7**, last byte checked as `1..8` (`0` rejected, so block-aligned
plaintext still needs a full pad block). Either HMAC failing is **fatal** (error state 10), the
same path as a bad checkver record — not silent. Both keys are exactly the MD5 block size (64
bytes), so a stock `hmac` implementation uses them verbatim.

This also resolves an open question in `CRYPTO.md`'s Blowfish section: the session-field's
"non-standard chaining" (`C[i] = decrypt(P[i]) XOR P[i-1]`) is not a second mode — `0xD645C8`, the
routine it's built on, is the identical textbook-CBC-decrypt primitive `.inf`'s stage 2 uses, just
run with plaintext/ciphertext roles swapped.

**Corrected 2026-07-31, after two hand-built `.inf` files decrypted and verified cleanly but still
produced zero entries.** The plaintext holds **two entry scans, not one**, and the one that
actually records entries starts *after* the inner HMAC tag, not at header offset 12 as the prior
pass assumed. Scan A (`0xBB89B0`-`0xBB8AC0`, the "second grammar-shaped pass" below, now resolved —
not a pre-pass over the same list) reads `<name> 00 <u32 size, BE> <u8 flags>` at stride `NUL+6`,
starting at offset 12, bounded by `hdr[4]-16`; it's display-only (feeds a KB counter that's copied
onward but never branched on). At `hdr[4]` the cursor jumps 16 bytes — over the inner HMAC tag —
into scan B (`0xBB8B00`-`0xBB8BC8`), which reads `<name> 00 <u32 size, BE>` at stride `NUL+5`,
bounded by `total_plaintext-16`, into the array that actually drives the install (**≤31 entries,
checked**, `obj+1072`). Name is inline in the plaintext, not a string-table pointer. A hand-authored
`.inf` therefore wants scan A left empty (`hdr[4] = 28`: 12-byte header + 16-byte inner tag, so
scan A's bound equals its start) and needs ≥16 bytes of trailing slack after the last scan-B entry,
or that entry falls outside `total_plaintext-16` and is silently dropped. Whether a real Konami
`.inf` populates scan A too (entries listed twice, once with flags, once without) is unverified —
we don't.

The **install loop is now confirmed closed**: `0xBB8E6C` reads the destination filename straight
from entry offset +0 (the name pointer out of the `.inf` plaintext), gated on the runtime flags
word equalling `0x12`. With the two-scan layout above resolved, the full chain from "`.inf` bytes on
the wire" to "file written to `dl/p/ar/<name>`" has no remaining unknowns.

**`.torrent` is genuine BitTorrent**, not a naming convention — the client statically links
Transmission (bencode parser, tracker announce/scrape query string, peer-ID fingerprint table, the
works, `~0xD83000`-`0xDDF000`). The downloaded `.torrent` is handed to `tr_torrentInitData` raw,
unencrypted; only the payload files inside a torrent go through the slot-7 cipher. The HTTP
fallback avoids all of this and is the far easier route to self-host.

**The payload really is installed client-side, with a real install step — not a passive overlay.**
The full PRX import table (28 modules, 349 functions, read from `sys_proc_prx_param` at
`0xFADEA0`) has no `cellGame`, `cellGameExec` or `cellGameUpdate` entry anywhere — there is no PS3
system-update package involved. Downloaded files land under `dl/p/ar/` on one device (device 1),
and the install loop at `0xBB8E6C`-`0xBB903C` does a straight `read`/`write` copy of each file onto
a **different** device (device 7) at the same relative path, then `unlink`s the device-1 copy. That
copy-then-delete is a real install, distinct from the download cache.

**Device 7 has no archive involvement at all, and the client never creates a directory,
anywhere.** Devices 1/2/3/6/7 all resolve through the same handler straight to `cellFsOpen`; only
device 2 has a populated root (`/dev_bdvd/PS3_GAME/USRDIR/o/`), and nothing in `MGO2.elf` ever
writes to the device-root table — it's load-time/external data, not client-managed, so "what device
7 is" was the wrong question: it's just `USRDIR` (an empty-string root). The install loop is
`sprintf path → open(dev 1, RD) → open(dev 7, O_CREAT|O_WRONLY) → read/write → close ×2 → unlink`,
and `O_CREAT` creates the file, not missing parent directories — the client never calls `mkdir`
anywhere in the binary.

**This is true but turned out not to be the live blocker — corrected 2026-07-31, one round later.**
The install loop above is inside the **state-3 downloader**, a function only reached after a
player answers a confirmation dialog. A hand-authored `checkver.html` + `.inf` (the `.inf`
independently confirmed byte-correct offline, via an opcode-faithful reference implementation) was
rejected live with no request past the `.inf` fetch; that silence was first read as evidence the
missing `dl` folder blocked the install write, so `USRDIR/dl/p/ar/t/0/` was created and the test
re-run — **same generic error, still no further network activity.** Tracing the actual post-`.inf`
control flow explained why: the record-loop tail (`0xBB7FA4`) that runs once entries are scanned
doesn't touch the install loop or make any `.torrent`/HTTP decision at all — after a harmless,
ruled-out free-space check (`cellHddGameCheck`, needs 1 KB against RPCS3's ~40 GB stub), it sets
`state = 1` and returns. State 1 is "waiting for the player to confirm the download" — the client's
own per-frame screen pump notices the state change and raises a confirmation dialog itself
(`0x8BE974`), with **no further request to the server needed to trigger it**. The download worker
thread polls that decision every 200ms and only reaches state 3 (and the install loop) once
answered. **So "no network request after the `.inf`" is what a *successfully-accepted* `.inf`
looks like, not evidence of a blocked install** — a real rejection produces the generic error
dialog *before* this tail, at the checkver status byte, one of the two HMAC checks, or the record
parser. The `dl/p/ar/` directory fix was accurate but never actually exercised.

**The `dl` "mount" is not a VFS mount, and `dl/p/.l` is a red herring.** `0x2FD50` constructs a
patch-archive *service object* with `"dl"` as a plain path prefix, not a mount name — there's no
mount table. The archive it actually opens is **`dl/.p`** (not `dl/p/.p`), matching the user's real
1.36 artifact exactly. `dl/p/.l` (opened once, `FSStart` thread) is dead: its only effect feeds two
getters with zero call sites anywhere in the binary. **Nothing in `MGO2.elf` can create `dl/.p`** —
its `DLT2` magic is compared, never written — so a from-scratch archive has to be seeded
externally, confirming `PATCH_INVESTIGATION.md` §2's inference that the writer lives in `EBOOT.BIN`
rather than here. New lead on that section's unidentified digest algorithm, though: the archive's
own digest check (`0xD640C4`) is keyed by the **same 16 bytes** that head the `.inf` stage-3 HMAC
key at `0xE20000` — the two checks likely share a primitive.

**There is real update UI — this section previously understated it.** `uupdate.cc` itself carries
no display strings (`0xE20040`-`0xE201F8` is wire-format templates, paths and thread/method names
only) and never calls `0x8858F0`/`0x885A08`, which is true and was the origin of the original "no
UI" claim — but the *owning screen* (ctor `0xBB6EC0` → `0x95E670`/`0x95F160`) is a real update
screen: it polls the updater's status every frame (`0x9610BC`), reads a genuine download-progress
percentage (`0xBB4BF8`), renders `relnote.txt`'s body in a scrollable pane (see above), and raises
dialogs through a third raiser, `0x8BE974`, that the earlier pass didn't check for. So "fully
automatic, no confirmation" no longer stands as written — it wasn't re-checked for this session,
and the presence of a dialog raiser this screen actually calls, plus a real progress readout, mean
this needs a fresh look before it's asserted either way.

### Rankings — an HTTP feature, not a command [ELF, 2026-07-27]

**The Rankings menu never touches the TCP protocol.** It POSTs to two endpoints, relative to the
same base URL as the documents above (the client `strcat`s the path onto the network config's URL
slot 2 at `0x911224`, so the base must end in `/`):

```
POST http://mgo2web.konami.com/us/mgo2/rank/mgogetrank.html       player boards
POST http://mgo2web.konami.com/us/mgo2/rank/mgogetrank_clan.html  clan boards
     term=..&rule=..&skey=..&from=..&records=..&pid=..   (cid on the clan endpoint)
```

It is a POST, not a GET — the transport picks its method from `flags & 1` at `0xBB4254` and the
ranking caller passes 3. All six parameters are always present, always in that order, each
rendered `"%u"`. `rule` is masked to 4 bits and `skey` to 3. `from` is a row offset, advanced by
50. `records` is **1** when the client wants its own standing (with its own id in `pid`/`cid`) or
**100** for a page (with the id 0); it sends nothing else.

The reply is a binary blob, **little-endian** — note that this is the opposite order from every
lobby packet, and the reader at `0xBC3CE8` is where that is visible. It is `12 + 28 * N` bytes:

```
u32 N          records that follow
u32 total      entries on the whole board (drives the scroll limit and min(total,10) rows drawn)
u32            read at 0x912BE0 and discarded
N * { u32 rank, u32 id, char[16] name, u32 value }
```

The whole body is XOR-scrambled — see `CRYPTO.md`, "The ranking scramble".

Only two things make the client reject a reply: an HTTP status other than 200 (`0xBB2D14`), and
`N` greater than the `records` it asked for (`0x912AF4`). There is no magic prefix, no checksum
and no length check — and the reader does not bound itself by the body length, so a reply that is
short for its own `N` is parsed off stale buffer exactly as an under-length lobby packet is.

Two hazards found while implementing:

- The 16 name bytes go into a stack buffer the client never clears (`0x912D30`) and are then
  passed to `strlen` (`0xAF7140`). A name filling all sixteen bytes has no terminator. We emit at
  most fifteen characters; the lobby protocol's 16-byte name fields are safe only because *there*
  the client appends its own NUL.
- `skey` selects which board. The value set is ELF-exact — `{0,2,3,4,5}` on the player endpoint and
  `{2,3,6}` on the clan endpoint, from the menu tables at `0x914140` and `0x9153A0` — but what each
  one *means* is inferred, not proven. The firmest is that `skey` 4 and 5 are the only rows drawn
  as `x.yy` with a ten-segment gauge (`0x910740`, multiplier 1/256), i.e. 8.8 fixed-point star
  ratings, which is what Host Score and Instructor Score are. See `RankingService` for the rest and
  for how confident each mapping is.

This also settles a standing question in the negative: **the `0x4Axx` block is not rankings.** Its
records embed the 204-byte game-settings sub-record, so it belongs to games. `COMMANDS.md` still
lists it as an unidentified subsystem, which it remains.

Note the nonce in the version check changes every launch, and the `seed` in the login request is
48 hex characters (24 bytes) whose role is not yet understood.

## TLS

The PS3 validates the server certificate against its own store at
`dev_flash/data/cert/CA*.cer`, and drops the connection before sending a request if the chain does
not verify — which looks exactly like the server never being contacted. A self-signed certificate
is not enough.

For RPCS3 this is solvable without patching the client: generate a CA, sign the server certificate
with it, and write the CA over one of the `CAxx.cer` files. The client was observed reading
`CA29`–`CA31`, and installing at `CA30.cer` works. The PS3's TLS stack is from 2008, so the server
must also allow TLS 1.0 and legacy ciphers.

## Session tokens

A token is 32 hex characters and the first **16** are returned to the client. The server no
longer stores a prefix of it: it stores the 32-hex-character value the client will derive, so
`account.session` is `varchar(32)`. The ruled-out models below are historical — the transform
was solved, see `dev/docs/CRYPTO.md`. That the client receives 16 characters is confirmed: it matches `mgo2-server`'s login byte for byte
(`sessionToken.slice(0,8)` stored, `slice(0,16)` returned).

**The transform that recovers it is NOT understood, and `SessionIds.decode` is wrong.** This was
long described as "the client encrypts the stored half into the `0x3003` packet", recovered by
XOR-with-mask then an auth-Blowfish *encrypt*. Captured live from the retail client (BLUS30109),
that model does not hold:

```
login reply : 0,122345677,1000000,1888e089ebe181fd     (stored8 = 1888e089)
0x3003 field: a5a0dd9199494cf00e06ae9dc4655563
decode()    : 589889e531a57dfc      <- matches neither ASCII "1888e089" (3138383865303839)
                                       nor hex-decode of the token (1888e089...)
```

Ruled out empirically against the real auth key table — **do not re-test these**:

- plaintext = ASCII of the stored 8 chars, or hex-decode of the returned 16 chars
- one-block and two-block (full 16-byte) variants of both
- Blowfish *encrypt* and *decrypt* directions, with and without the XOR mask

None reproduce the observed field. The decisive tell is the `SPECIAL` sentinel in `SessionIds`:
it is hard-coded to map one captured 16-byte field to the token `"cafebabe"`, and running that
same field through `decode` yields `eb018b74d2f66650` (encrypt) or `037fd0a3a234266b` (decrypt) —
neither is `"cafebabe"` (`6361666562616265`). The sentinel exists *because* the transform was never
actually inverted; it is a hard-coded patch over a wrong model, not a compatibility shim.

What *is* verified: our XOR mask (`35 d5 c3 8e d0 11 0e a8`) and auth key table (0x1048 bytes =
P-array + four S-boxes) are byte-identical to `mgo2-server`'s `XOR_SESSION_ID_BYTES` and
`BLOWFISH_KEY_AUTH`, and its `encryptAuthPayload` is `blowfishEncrypt` — the same direction we use.
So keys and algorithm match a working server; only the derivation is wrong. Since our decode equals
`mgo2-server`'s, the same field would miss there too, which suggests `mgo2-server` targets a
different client build (consistent with its underscore-joined perks, which this client rejects).

**This is solved.** The transform was traced in the binary (below), implemented as
`nomad.common.crypto.SessionField`, and confirmed against a live client:

```
Account 122345677 checked in to ACCOUNT lobby.
```

The client reaches the account lobby and the character screen. `SessionIds` and its hard-coded
`cafebabe` sentinel are gone; nothing is inverted any more. Login stores
`SessionField.stored(token)` and check-session matches the presented sixteen bytes directly.

### What the client actually does, traced in MGO2.elf

The transform runs at **login**, not at check-session. The login-reply parser stores the token as
its **16 ASCII characters** (confirmed: it round-trips through a `cellHttpUtil` unescape that
reports 17 bytes required = 16 chars + NUL, i.e. identity — base64 would need 12 or 24), then at
`0xBB1800` makes a virtual call and copies the 16-byte result to parse-object `+0x154`, which the
`0x3003` builder ships verbatim.

The call is `f(r3=obj, r4=out, r5=in, r6=0x10, r7=6)` on a singleton whose pointer lives in the
static global `0xFFE6DC` (= `0x1698DA8`, `.bss`; the accessor `0xD64498` is a plain getter, no lazy
init). `0x1698DA8` appears nowhere else in the image and no code forms it inline — every user goes
through that getter.

The vtable is at **`0xfbbd00`**, recovered by finding OPD descriptors (identified by their TOC field
`0x10353A8`) for the service's code region and then the array of pointers to them:

| slot | function | role |
|---|---|---|
| `+0x0` | `0xd64860` | register key for a mode |
| `+0x4` | `0xd64798` | mode → key schedule |
| `+0x8` | `0xd645c8` | the block cipher itself |
| `+0xC` | `0xd644b0` | the wrapper invoked at login (mode 6) |

`0xd644b0` calls `+0x4(obj, mode, 0)`, which must return `0x40` or it logs and spins on `b .`; then
`+0x4(obj, mode, ctxbuf)` to build a context; then `+0x8(obj, out, in, len, ctx)` to transform.
`0xd645c8` rejects `len & 7`, so it is an **8-byte block cipher**. `0xd64798` is:

```
if (unsigned)(mode-1) > 9  -> error        ; modes 1..10
row = obj + mode*8 ; keyptr = *(row+4) ; keylen = *(row+8)
if keylen > 0 && outbuf:  +0x8(obj, outbuf, keyptr, keylen, *(obj+4))
```

So a **master context at `*(obj+4)`** decrypts a **64-byte per-mode key blob** into the context that
then encrypts our 16 bytes. Mode 6's blob is registered at `0x2fa8c` — `bl` the getter, then
`+0x0(obj, mode=6, keyptr, 0x40)` where `keyptr = *(*(TOC-0x7f68) - 0x7ff8)` = **`0x10985f0`**.

**Dead end for static analysis:** the 64 bytes at `0x10985f0` are **all zero in the image**, its
address appears only in the pointer slot at `0xfbc6bc`, and no code constructs it inline. The key is
materialized at runtime. Recovering it needs either the runtime derivation chased further, or a
memory dump of `0x10985f0` (and `obj` at `0x1698DA8`) from a running client — the cipher body at
`0xd645c8` can still be read statically.

## Protocol, confirmed working

A real client completed a lobby list exchange against this server:

```
In  - command 2005 - 0 bytes      client asks for the lobby list
Out - command 2002 - 4 bytes      start
Out - command 2003 - 138 bytes    three lobby entries
Out - command 2004 - 4 bytes      end
In  - command 0003 - 0 bytes      client continues
```

That single exchange validates the whole transport: the packet XOR, the HMAC-MD5 checksum,
sequence numbering, framing, and the lobby list encoding — none of which had been tested against
anything but this project's own test client.

## Command 0x3107 — check character name

Sent by the client on the account lobby around the character-registration screen. It is a
name-availability pre-check: savemgo's Nomad names it in a commented-out case,
`Accounts.checkCharacterName(ctx, in)` (`AccountLobby.java`), and shipped without it.

**It is fatal, and we handle it.** The note that it "is not fatal" was written from a partial
observation: the game does reach **Register New Character** with the command unanswered, because
the stall happens at the *next* step. On entering a name the client waits about forty seconds for
a `0x3108`, never sends `0x3101`, and fails with `0A41:FFFFFF60`. savemgo ships it commented out;
that is not evidence it is optional for this client. See `dev/docs/PROTOCOL.md`.

## The client reaches the MGO2 main menu

A real client (BLUS30109, stock RPCS3) now completes the whole path against this server: port
check, login, check-session, character creation, character select, the game-lobby connect burst,
and the wardrobe update — arriving at the main menu with **Lobby Select, Online News, Mail, Clan,
Personal Data, Rankings**. No command goes unanswered on the way.

### `FFFFFF60` means "you did not reply"

The single most useful debugging fact found so far. When a command goes unanswered this client does
not error immediately: it stalls for tens of seconds and then fails with `FFFFFF60`, prefixed by
whatever screen was open.

| Prefix | Screen | Command that was missing |
| --- | --- | --- |
| `0A41` | Register character | `0x3107` check character name |
| `092E` | Connecting to lobby | `0x4700` connection info, `0x4820` mail |
| `0A21` | Character select | `0x4900` game lobby info |
| `1031` | Update character info | `0x4130` update personal info |

So a `FFFFFF60` is never a malformed reply — it is a missing one. Read
`No handler for command …` out of the lobby log and implement that command.

### Character creation was dropping two of the player's choices

`readAppearance` skipped a byte after `upper` and another after `chestColor`, on an inherited
comment claiming the original server discarded them. That was wrong, and it cost the player their
choices silently.

The wardrobe update `0x4130` carries the same fields in the same order and names them: the byte
after `upper` is `lower`, and the byte after `chestColor` is `handsColor`. Confirmed against a live
client — a character created with `lower = 0` had a real `lower` the moment `0x4130` was
implemented and the player changed clothes. Both fields are now read at creation.

This is the sixth time an inherited assertion about "what the original server did" has been wrong.


## A real client hosts a game

The full path now works against an unmodified client (`BLUS30109`, stock RPCS3): port check, login,
check-session, character creation and selection, the connect burst, the main menu, Lobby Select,
entering a game lobby, the Create Game screens, and into the game as host.

Both crypto directions are confirmed by real traffic rather than by inherited test vectors.
`0x4305` is the only payload encrypted outbound, and the Create Game screen opening proves it;
`0x4310` arrives encrypted inbound and decrypted to 348 bytes of settings.

### What is not proven

- **Nobody has joined.** `0x4320` (join game) is unimplemented, as is most of the in-match host
  protocol (`0x4340`–`0x4346`, `0x43a0`–`0x43d0`). Whether a match plays is untested.
- **Peer-to-peer is unproven.** `0x4700` records the host's endpoint but nothing serves it to a
  peer, and NAT classification has only ever run on a LAN with no NAT in the path.
- **Host settings are discarded**, so a created game uses defaults whatever the player chose.

### Two self-inflicted faults worth remembering

Both came from fixing something else and not checking the result.

`seed.sql` was made idempotent by deleting and reinserting the lobby rows without specifying ids,
so the identity column advanced on every run. The rows looked right; their ids had drifted to 10,
11 and 12. Since compose passes `MGO2SERVER_LOBBY_ID` to each server, lobby 3 must be the game
lobby, and creating a game failed on a foreign key against an id that no longer existed. **Ids that
something outside the database depends on are not an implementation detail.**

Before that, the same file had been re-run with an `ON CONFLICT DO NOTHING` guard that had no
unique constraint to conflict against, silently doubling the lobby list. The client addresses a
lobby by its index in the list it was sent, so that corrupts Lobby Select specifically.


## Where the Common Settings toggles live — settled by capture

*2026-07-22, live client, single-variable hosting experiment.* Two games were hosted by the same
character minutes apart, identical except the second enabled **only Friendly Fire** (plus known
timer/count changes that land in already-confirmed offsets). The decrypted `0x4310` blobs were
archived by a database trigger and diffed byte for byte. Every declared change appeared exactly
where Nomad's `Hosts.checkSettings` reads it — TDM time/rounds/tickets in the 17×u32 timer table
at `0xFC`, max characters at `0xE5`, briefing at `0xE6` — and the friendly-fire flip moved
**exactly one other bit: byte `0x142`, bit 3**, Nomad's `commonA.friendlyFire`.

So, settled:

- **The Common Settings toggles are in the `0x4310` blob**, at `0x142` (commonA) / `0x143`
  (commonB), with Nomad's bit map — which is bit-for-bit the map our `0x4302` game-list entry has
  always used. The earlier conclusion from three ELF passes that the blob does not carry them
  (and that they ride in `0x4110`'s header) was **wrong**; `0x4110` was never even observed this
  session, including with a created game and a joined second player.
- **Level-limit base is a u32 at `0xF8`** (0 in both captures, level limit disabled), not a u16
  at `0x142`. The previous read had been storing `commonA<<8 | commonB` — 9216 for the baseline —
  as the base of every hosted game. Seventh entry for the "inherited/claimed offsets that were
  wrong" ledger, and the first one where the wrong claim cited the ELF rather than a reference.
- **The populated `0x4305` reply is parsed by the client at the transcribed offsets.** The second
  Create Game screen opened pre-filled with the first game's settings (confirmed visually), and —
  the clincher — the two constants our reply injects per Nomad (`0x02`, `0x20`) came back in the
  second `0x4310` push at exactly the request offsets that map to their reply positions
  (`0xEA` ← reply `0x0ED`, `0x144` ← reply `0x147`). The client read our reply, stored those
  fields, and round-tripped them. They are evidently real (unknown-meaning) fields, not padding.
- `0x4398` ping reports decoded live: `{u32 host ping, then u32 chara id + u32 ping pairs}` —
  a captured 12-byte payload read `host=100, {chara 2, ping 100}` and landed correctly on the
  game row and roster.
- `0x4440` carries a 1-byte payload observed as `01`, sent by host and joiner around team-select
  time — consistent with Nomad's "Set Team" comment, still unproven.

### The first full match, end to end

*Same session, 2026-07-22.* Create → second client joins → match starts → finishes → **host
passed to the joiner** → original host quits. Zero `No handler` lines. `0x43a0` arrived as
`{u32 own chara id, u32 target chara id}` and the succession worked completely: game re-keyed,
old host dropped from the roster, new host's client took over the `0x4398` heartbeat and
re-registered its peers. Both players were served the populated `0x4129` results card without
complaint.

The negative result matters as much: **`0x43ca`, `0x4390`, `0x43a2`, `0x4392` and `0x4110` were
never sent** at any point in that complete match. Whatever triggers the round-lifecycle and
stat-submission commands, it is not simply "a match being played" — they are conditional
(mode/stat-game/path dependent), and their layouts remain live-unverified. Do not assume a stat
report per round when reasoning about experience.

## The Common Settings map, confirmed setting by setting

*2026-07-22, single-variable hosting sweep: one setting flipped per hosted game, every decrypted
`0x4310` blob archived by the `blob_audit` trigger and diffed against its predecessor. Each row
below moved exactly its own bits and nothing else.* Nomad's decode went **thirteen for thirteen**
on everything this build's UI can express.

| setting (UI name) | location | evidence |
| --- | --- | --- |
| Friendly Fire | `0x142` bit 3 | single-bit diff |
| Ghost Pranks | `0x142` bit 4 | single-bit diff |
| Idle Kick + minutes | `0x142` bit 0, count `0x146` | both moved (3 min) |
| Teams Switch Positions | `0x143` bit 0 | single-bit diff |
| Auto Assign Teams | `0x143` bit 1 | single-bit diff |
| Silent Mode | `0x143` bit 2 | single-bit diff |
| Enemy Nametag Display | `0x143` bit 3 | single-bit diff |
| Level Limit + base + ± | `0x143` bit 4, base u32 `0xF8`, tolerance `0xF7` | all three moved (22, ±0/±5/±10) |
| Voice Chat | `0x143` bit 6 | single-bit diff |
| Team Kill Kick + count | `0x143` bit 7, count `0x148` | both moved (5) |
| Dedicated Host Settings | `0xA1` byte | single-byte diff; client also bumps max characters +1 |
| Weapon Restrictions enable | `0xD5` bit 0 | single-bit diff ("All Unlock") |
| Weapon ban bits | `0xD5`–`0xE4` per Nomad's table | tab-level: Primary/Secondary/Support "All Lock" each set only Nomad-named bits |

Collateral facts from the sweep:

- **Disable snaps sliders to defaults**: turning a numeric setting off resets its count on the
  next push (tolerance → 22, team-kill → 3), so a nonzero count with a cleared enable bit is
  normal, which is why the enables must gate the counts (as `applyHostSettings` does).
- **The base-game weapon roster is a strict subset of Nomad's table**: "All Lock" per tab set
  knife/P90/Vz.83/M4/AK-102/M870/Mosin/SVD/shield (primary), Mk.2/GSR (secondary),
  grenade/stun/chaff/smoke/ELOC/claymore/magazine (support). Every Nomad bit that stayed dark is
  expansion-era gear (MP5, Patriot, G3A3, Mk.17, XM8, M60, Saiga, VSS, DSR-1, M14, Operator,
  Mk.23, DE, G18, RPG, WP, colored smokes, SG-mine, C4, SG-satchel) — the pairing of individual
  weapon to bit within a tab is roster-level evidence, not per-weapon single-variable proof.
- **`0x142` bit 5 (Nomad: auto-aim) is set in every capture** including all-disabled baselines,
  and no aim setting exists anywhere in this build's Create screens — later-patch content or fed
  from player settings. Pinned as an oddity where it is decoded.
- **`0x142` bit 2 is likewise always set** (the "always" bit our game-list packer has carried
  from the start); still no observed meaning.
- **Unique characters could not be tested** — absent from this build's UI; see BACKLOG.
- **50,000 experience renders as level 22** — first calibration point for the exp→level curve;
  the level-limit base field is not freely chosen, it tracks the hosting character's level.

### The weapon-restriction table, confirmed weapon by weapon

*2026-07-22, continuation of the sweep: one weapon unlocked per hosted game against an
all-locked baseline, each a single-variable diff.* Nomad's per-weapon bit table went
**nineteen for nineteen** — every base-game item confirmed individually, names exact (the one
apparent mismatch, "SBMC.GUN", turned out to be a menu grouping; the weapon's in-game name is
Vz.83). This retires the earlier "roster-level evidence" caveat: the pairing is now per-weapon.

| item (UI name) | byte | bit |
| --- | --- | --- |
| restrictions enable | `0xD5` | `0x01` |
| Knife | `0xD5` | `0x02` |
| Mk.2 Pistol | `0xD5` | `0x04` |
| GSR | `0xD5` | `0x80` |
| P90 | `0xD7` | `0x10` |
| Vz.83 | `0xD7` | `0x80` |
| M4 Custom | `0xD8` | `0x01` |
| AK-102 | `0xD8` | `0x02` |
| M870 Custom | `0xD9` | `0x20` |
| Mosin-Nagant | `0xDA` | `0x08` |
| SVD | `0xDA` | `0x10` |
| Grenade | `0xDB` | `0x10` |
| Stun G. | `0xDB` | `0x40` |
| Chaff G. | `0xDB` | `0x80` |
| Smoke G. | `0xDC` | `0x01` |
| E.Locator | `0xDC` | `0x80` |
| Claymore | `0xDD` | `0x01` |
| Magazine | `0xDD` | `0x20` |
| Shield | `0xDE` | `0x02` |

Every other bit in Nomad's table (MP5, Patriot, G3A3, Mk.17, XM8, M60, Saiga, VSS, DSR-1, M14,
Operator, Mk.23, DE, G18, RPG, WP, colored smokes, SG-mine, SG-satchel, C4, and the attachment
bits) belongs to expansion-era gear this build's UI cannot express — dark in every capture,
reference-only, same standing as the uniques fields.

## The admin-action sweep and the stats layout, settled live

*Evening 2026-07-22, two-client session with the host admin menu worked action by action.*

- **`0x4390` cracked and confirmed applying.** This build sends 167-byte reports (not Nomad's
  ≥0xB8): target chara id at `0x00`, u32 **seconds-in-game at `0x23`** (matched the joiner's
  connect-to-report interval exactly), u32 **absolute experience at `0x27`** (matched a
  50,000-exp account to the byte), flag bytes `01` at `0x20/0x22/0x2E`, all else zero in a
  kill-less match. After the length-guard fix, live application verified: "stats for character 1
  — experience 50000". Sent at natural round end and on kick teardown, NOT only at match end.
- **`0x4392` confirmed twice** — "Restart (Next)" sends the one-byte rotation index; handler
  applied it both times.
- **`0x43ca` and `0x43a2` do not exist in this build's observed vocabulary.** Not sent at
  staging, any admin restart (round/stage/next), team change, kick, pass-host, or a natural
  round end with a declared winner. The end-of-round conversation is re-registration + `0x4390`
  per player, nothing else.
- **`0x4110` identity settled**: 304 bytes (the `0x4120` layout minus trailer), sent by a joiner
  alongside two `0x4114` chat-macro write-backs (769 bytes each, the `0x4121` layout) in one
  non-blocking burst when saving options. It is the personal-options write-back, and the old
  48-byte-rules-header theory is disproven a second way. `0x4114` is now parsed and persisted;
  `0x4110` is acked but unparsed (BACKLOG).
- **`0x4500` fired from both roles**: host-on-kick (`…02`, the kicked player's id) and
  joiner-toggling-ADDLIST (`…01`, the host's id). ADDLIST is one cycling state (friend → blocked
  → none); isolated tests eliminated mute, unmute, unfriend and unblock as triggers. Open
  suspicion: it may be a *query*, and our constant `{result=0}` ack may be why the target renders
  permanently as "friend" (observed). Not yet pinned — isolated add-side toggles are the pending
  experiment.
- **Crash teardown verified**: an RPCS3 host crash produced a clean "left game 85 (on
  disconnect), which it hosted; removing it", zero orphan rows; and a crashed joiner's straggler
  stat report was correctly rejected — which also exposed that the `game_round` snapshot never
  populated at the time (its then-trigger, `0x43ca`, never arrives). Since resolved: the
  handler is renumbered to `0x43c8` and the snapshot populates on create/join. See BACKLOG.

## ADDLIST (friend/blocked) solved from the ELF

*Evening 2026-07-22.* The in-game friend/blocked toggle had wedged all session — set a state, and
it stuck, "server unstable" on further changes. Chasing the reply shape (bare result, {result,
state}, start/end triple, full-list echo) was the wrong track: an Opus ELF trace found the real
cause and the real layouts.

- **A change is remove-then-add.** friend→blocked sends `0x4510 {state 0}` (remove friend) then
  `0x4500 {state 1}` (add block); clear-to-none sends `0x4510` alone. **`0x4510` had no handler**
  and was silently dropped every time — that was the entire wedge. The client blocks on its
  `0x4512` reply.
- **Replies are single packets, not triples.** The client has no parser for `0x4501`/`0x4503`
  (they hit −0x46 no-handler); `0x4502` (add, 25 B: `u32 0, u32 id, u8 state, name[16]`) and
  `0x4512` (remove, 9 B: `u32 0, u8 state, u32 id` — note the reordered fields) each stand alone.
- **`0x4580`** is a separate bulk roster fetch (`{u8 state}` → `0x4581`/`0x4582`×N/`0x4583`,
  59-byte entries); never seen live, answered empty for now.

Implemented all three, storing relations in `chara_relation` and replaying them into the `0x4101`
login arrays (the first non-zero bytes those friend/blocked regions have ever carried). **Verified
live**: a full none→friend→blocked→none cycle in one session, every transition sticking, no
relog. The lesson repeats an old one — the answer was in the binary; the session lost an hour to
guessing reply shapes before tracing the actual dispatch.

## The 0x4390 scoreboard, decoded from a live match

*2026-07-22.* A two-round TDM match (Sean char 1 vs rawr char 2) captured all four `0x4390`
reports at DEBUG, and the end-of-game scoreboard totals were read off the screen. Summing each
report's stat-struct-A slots across both rounds matched the reported per-player totals **exactly**,
labelling the scoreboard:

| slot (off) | Sean total | rawr total | stat |
| --- | --- | --- | --- |
| A0 `0x05` | 10 | 4 | kills |
| A1 `0x07` | 4 | 10 | deaths |
| A3 `0x0b` | 53 | 0 | score (signed; rawr's round 2 was −3) |
| A4 `0x0d` | 0 | 1 | stun / knockout |
| A6 `0x11` | 10 | 2 | headshots dealt |
| A7 `0x13` | 2 | 10 | headshot deaths — **inferred, not validated**: equals the enemy's headshots, which a 1v1 can't tell apart from other received stats (needs 3+ players) |
| A13 `0x1d` | 2 | 2 | rounds played |

rawr's score reproduced the client's formula exactly: `4·3 − 10·2 + 2·2 (hs) + 1·2 (stun) + 2·1
(other) = 0`. The reports are **per-round** (A0 = 5 kills each round → 10 total), which is why
`accumulateStats` sums every report into lifetime `chara_stats`. The A6/A7 "duplicate" pair from
the earlier single-round capture turned out to be headshots-dealt / headshots-received, not a
second kills counter — the ambiguity only resolved once round 2 made the columns diverge.

Left unlabelled (all zero this match): `0x0f` (one player had 1), the hacking/assist/wake/"other"
categories, and the 58-slot struct-B detail block at `0x2f`. Struct B is a separate itemised
breakdown (probably per-weapon/per-category), not the eight scoreboard categories — one slot
(`B36`, 12/2) was numerically near the "Other" count (13/2) but that is an off-by-one coincidence,
not a confirmed link.
A match exercising those would pin them the same way.

## The 0x4390 stat layout is mode-independent; scoring categories are mode-specific

*2026-07-22, Rescue Mission capture (rule 2, map 12 Midtown Maelstrom) compared to the earlier
TDM match.* The stat report's byte layout does **not** change with game mode: kills (`0x05`),
deaths (`0x07`), score (`0x0b`), stun (`0x0d`), headshots (`0x11`) all held their offsets and read
correctly for Rescue. What changes is which slots the results screen surfaces as **scoring
categories** and how they weight into the total:

- **TDM categories:** Kill, Death, Headshot, Hacking, Assist, Stun, Wake, Other.
- **Rescue categories:** Kill, Headshot, Stun, **Team Win**, Assist, **Goal**, **Target Defence**,
  Other. (No "Death Count" line — deaths are still tracked in the report at `A1`, just not scored;
  and a death is not penalised in Rescue, where rawr kept score 22 with 1 death.)

So the report is a fixed-layout superset; each mode displays/scores a subset with its own
weights. This is good for persistence: the fixed slots we store (`chara_stats`) are correct in
every mode without mode-branching.

**Mode-specific scoring weights**, from Sean's Rescue row (score 25 reproduced exactly):
`kill·7 + headshot·3 + stun·7 + teamWin·5 + goal·3 + targetDefence·3 + other·1`. Compare TDM's
`kill·3 − death·2 + headshot·2 + …`. So the same counts score differently per mode — the client
computes the total; we just store its score field, which stays correct.

Objective categories (Rescue's Team Win / Goal / Target Defence / Assist) occupy the fixed slots
that are zero in deathmatch, but the capture had **every objective count equal to 1**, so they
cannot be told apart yet:

- **`A14` (`0x21`) = Team Win *or* Target Defence** (both were 1 for Sean; 0 for rawr, who won
  neither). NOT Goal — Sean's Goal count was 0. The other of the two sits in the `0x2f` struct-B
  block (Sean B had several 1-valued slots). A match where these differ would split them.
- `A7` = **headshot-deaths, now strongly supported**: across all three rounds rawr's `A7` exactly
  equalled Sean's headshot count (5/5/1), i.e. rawr's deaths-by-headshot. Still 1v1 so not
  airtight, but consistent three times.

Rule/map numbers confirmed this session: rule 1 = Team Deathmatch, rule 2 = Rescue Mission;
map 2 and map 12 (Midtown Maelstrom) observed.

## The personal-stats screen fingerprinted: 0x4107 record 1 mapped slot by slot

2026-07-23, live. After the `0x4102` family was traced and handled (see PROTOCOL.md), the reply
was re-sent as a **fingerprint payload** — every unmapped u32 carrying its own wire position
(`0x4105` matrix cells 1–144; `0x4107` record 1 = 1001–1073, record 2 = 2001–2073) — and the
values read back off the screen. Results:

**`0x4107` record 1 is the personal-scores record.** The on-screen value names the slot
(u32 index, 1-based, at wire offset `4 + (i−1)·4`); time fields display seconds as `hh:mm:ss`
and confirmed the mapping arithmetically (e.g. "00:16:55" = 1015):

| slot | stat | | slot | stat |
| --- | --- | --- | --- | --- |
| 1 | Consecutive Kills | | 22 | Cardboard Box Uses |
| 2 | Consecutive Deaths | | 23 | Melee Hits |
| 4 | Suicides | | 25 | Consecutive Survivals (TDM page) |
| 5 | Times Stunned | | 26 | Bases Conquered (Base page) |
| 6 | Friendly Kills | | 27 | SOP Destabilizer Uses (Base page) |
| 7 | Friendly Stuns | | 28 | GA-KO Saved (Rescue page) |
| 8 | Salutes | | 29 | GA-KO Defended (Rescue page) |
| 9 | Preset Radio Message Uses | | 31 | Fully Defended Matches (Rescue page) |
| 10 | Text Chat Uses | | 36 | Number of Soldiers Trained |
| 11 | CQC Attacks Given | | 46 | Training Mode Time (s) |
| 12 | CQC Attacks Taken | | 47 | Combat Training Time, Instructor (s) |
| 13 | Rolls | | 48 | Combat Training Time, Student (s) |
| 14 | Total Time Using ENVG (s) | | 63 | Victories as Snake |
| 15 | Time as Dedicated Host (s) | | 64 | Knife Kills |
| 16 | Catapult Uses | | 67 | Snake Kills |
| 17 | Number of Boosts Given | | 72 | Total Time as Snake (s) |
| 18 | Falling Deaths | | 19 | Times Caught in Trap |
| 20 | Scans Performed | | 21 | Time in Cardboard Box (s) |

Slots 3, 24, 30, 32–35, 37–45, 49–62, 65–66, 68–71, 73 did not surface on this screen —
unmapped, possibly feeding the (empty) title/awards histories.

Negative results, equally valuable:

- **`0x4107` record 2 (2001–2073) appeared nowhere** on the stats screens. Hypothesis: a
  second period/variant (weekly?) shown elsewhere. Open.
- **The per-mode stat grids (Rounds/Wins/Score/Headshot–Lockon–Other kills/deaths/stuns) and
  the per-mode "Total Time Playing" fields all showed 0** even though the `0x4105` matrix
  carried 1–144. So either those grids read the `0x4103` regions that were still zeroed, or
  the `0x4105` count field (sent as probe value 7) gated the matrix out. Fingerprint v2
  (matrix 3001–3144, count 8, `0x4103` tail fingerprinted with 4xxx/5xxx/6xxx + ASCII string
  markers) is the discriminating experiment.
- The stats screen has a **"Headshot Deaths" label per mode** — the client does track that
  category, consistent with (not proof of) the `0x4390` `A7` = headshot-deaths reading above.
- Screen header showed **level 22** with experience sent as 1234, and an empty clan field and
  comment — sources not yet located in the payload.

### Fingerprint v2–v4: the mode grids read none of the 0x4102 reply

Same session, three follow-up rounds, each varying one region of `0x4103` (everything else held):

- **v2** (aligned u32 ranges + ASCII markers in the guessed string fields): grids zero. The
  ASCII leaked into unrelated UI ("Instructor: 1312902468th generation" = the bytes `NAME`;
  Instructor Score denominator `0x43000000` = the `C` of `FP-NAME-C`) — so the trace's guessed
  u32/16-byte-string layout for the tail is misaligned. Four titles (Foxhound, Fox, Doberman,
  Hound) and five awards appeared: title/award unlocks decode from somewhere in the tail.
- **v3** (211-byte middle region as dense u16s 7001–7105): grids zero. The player **comment
  field** showed `{|}~`+block — bytes `0x7B–0x7F`, the low bytes of u16s 7035–7039, placing a
  byte-string comment field from middle-region offset ≈69 (wire ≈414); v2's NULs there had
  shown an empty comment, consistent.
- **v4** (the only never-fingerprinted bytes: "login times" 9001/9002, flag=1, and the 256
  bytes labelled friend/blocked ids as 8001–8032/8501–8532): grids zero, nothing else changed.

Elimination: the confirming observation would have been grid cells showing a fingerprint range,
and no round produced it while collectively covering every byte of `0x4103`, the `0x4105`
matrix and both `0x4107` records. So the per-mode stat grids (and per-mode play times) are
**not fed by the `0x4102` reply burst** — client-local accumulation or another command. Caveat:
a display gate that needs a specific field *combination* (e.g. a plausible rounds count) could
in principle mask a real source; the parser trace under way should settle which.

### The grid mystery solved: v1–v4 tripped 0x4105's page gate

The second ELF trace (2026-07-23) dissolved the elimination above: `0x4105`'s second u32 is not
a count but a **page selector that must be 0 or 1** — the parser bails on anything greater and
never writes the matrix. Every fingerprint round had sent 7 or 8 there, so the matrix (which IS
the per-mode grid: 8 modes × 18 u32, mode-major; reader at `0x9193BC`+) was silently discarded
each time. The "grids read none of the reply" conclusion was an invalid elimination — the varied
thing could not have mattered while the gate value was wrong. Lesson re-learned: v1's `7` was a
probe value dropped into a field whose parse-side constraint had not been read.

Also settled by the same trace: friend/blocked in `0x4103` are genuinely flat id arrays (v4's
null result was predicted); the comment field is at wire 413 (`T+0x1E24`, confirmed by the v3
`{|}~` leak); the v2 titles/awards were pre-loaded by a different flow, not our fingerprint; and
the tail is a flat packed field list — the first trace's "intermediate table / 5-record table"
reading was wrong. Fingerprint v5 (page=0, matrix 3001–3144, byte-aligned tail values, real
comment in the comment slot) is deployed.

### Fingerprint v5: the full per-mode grid mapped; ~~titles and awards are client-derived~~

> **SUPERSEDED 2026-07-30 on the titles/awards half only.** The grid mapping below stands. The
> conclusion that titles and medals are computed by the client does **not** — see
> [Titles and medals](#titles-and-medals-server-driven-catalogue-extracted-from-the-elf) below and
> `AWARDS.md`. Both are carried on the wire in `0x4103` and are server-driven. Kept because the
> reasoning is instructive: the observation was real and the inference from it was wrong.

With `0x4105` page=0 the grid populated and the whole matrix fell out (values 3001–3144,
mode-major, cell = 3001 + mode·18 + column):

- **Mode rows (wire order):** 0 Deathmatch · 1 Team Deathmatch · 2 Rescue · 3 Capture ·
  4 Sneaking · 5 Base · 6 **hidden seventh mode** (no page of its own, but included in every
  Total-row sum and in the header play-time total — Combat Training?) · 7 unused (excluded from
  all sums).
- **Stat columns (0-based):** 2 Lockon Kills · 3 Score · 6 HS Kills · 7 HS Deaths · 8 HS Stuns ·
  9 HS Stuns Received · 10 Lockon Stuns · 11 Lockon Deaths · 12 Lockon Stuns Received ·
  14 Rounds · 16 Wins · 17 Play time (seconds; the "Total Time Playing X" lines and the header
  Time = Σ column 17 over modes 0–6, e.g. 05:58:24 = 21504 = Σ3018..3126). Columns
  **0, 1, 4, 5, 13, 15 unmapped** (v6 probes them with large per-column markers in mode 0).
- **Computed client-side, not wire fields:** the whole Total page (Σ modes 0–6 per column), the
  ALL rows (HS + Lockon + Other), and OTHER itself (showed 0 with every wire cell nonzero —
  plausibly some-total-minus-components clamped at 0; v6 will tell).
- `0x4103` tail confirmations: instructor name = the 16-byte string at `T+0x32FC` (showed
  FP-STR-B); Host Rating denominator = `T+0x32DC`; Instructor Score denominator = `T+0x32F4`;
  comment end-to-end correct (empty in DB, blank on screen). `FP-STR-A`/`FP-STR-C` and the clan
  header field did not surface — clan is not any of this packet's strings.
- ~~**Titles and awards are computed by the client from the stat values themselves**~~ — **WRONG,
  corrected 2026-07-30.** The observation was sound: the award list did regenerate to exactly the
  thresholds our fingerprint numbers crossed ("10/25 consecutive kills" ↔ slot 1 = 1001; "2/4
  consecutive TDM survivals" ↔ 1025; "100 SOP destabilizer uses" ↔ 1027; "500/10000 total
  kills/deaths" ↔ the 42k computed totals), and the title set did change with the stats (v2's
  Foxhound/Fox/Doberman/Hound → v5's HOUND/CROCODILE/EAGLE/…).

  **The inference was not.** Both are carried on the wire, in the same `0x4103` this page was
  already dissecting: **wire 563** is a 22-bit title mask, **541** the 1-based worn title, **615** a
  16-byte medal bitfield. The client draws those bits and computes nothing (`GATES.md` §5a).

  What actually happened is that *our own fingerprint sender* recomputed the fields from the stats
  it was writing, so the correlation was with our server's arithmetic, not the client's. **A stat
  and an award moving together does not say which side did the deriving** when the same process
  emits both — that is the general lesson, and it is why an elimination has to name the observation
  that would have distinguished the two.

  Threshold enumeration is therefore **operator policy**, not presentation-mapping: the numbers are
  ours to choose and live in `src/main/resources/awards.json`. See `AWARDS.md`.

### Fingerprint v6: the ALL columns are stored; OTHER is derived

Large markers in Deathmatch's six unknown columns (51000/51100/51400/51500 in columns 0/1/4/5;
52300/52500 in 13/15) settled the arithmetic both ways:

- **Column 0 = All Kills, 1 = All Deaths, 4 = All Stuns, 5 = All Stuns Received** — stored
  totals *including* the "other" category. Display path (pinned by v5+v6 jointly, not either
  alone): OTHER = max(0, col − HS − Lockon), and the ALL row shows HS + Lockon + OTHER — not
  the wire value verbatim (v5: col0 was 3001, ALL showed 6010 = HS+Lockon+0; v6: OTHER 44990 =
  51000 − 3003 − 3007 in all four categories, so the column provably feeds the subtraction).
  With self-consistent data (col ≥ HS + Lockon) ALL renders equal to the stored total; with
  inconsistent data the clamp silently repairs ALL upward to HS + Lockon and shows OTHER 0.
  Server-side invariant unchanged: keep all_* ≥ hs + lockon.
- **Columns 13 and 15 surfaced nowhere** — not on any stats page. Left unmapped and unstored;
  candidates for post-game or ranking views. Matrix probing stops here: 16/18 columns named.

### The Total page's OTHER derives from summed columns, not summed OTHERs

v6's Total page (reported live): ALL KILLS 69384 = Σ column 0 over modes 0–6
(51000 + 3019 + 3037 + 3055 + 3073 + 3091 + 3109), and OTHER KILLS 26558 = 69384 − 21427
(Σ HS kills) − 21399 (Σ lockon kills) — NOT the sum of the per-mode OTHER cells (which was
44990, the six unmarked modes clamping to 0). So the client sums each wire column across modes
0–6 first, then applies OTHER = ALL − HS − Lockon per page after summation. All four ALL/OTHER
pairs check out the same way. Confirms columns 0/1/4/5 as stored ALL totals.

### The hidden mode row, demonstrated and parked

Manually summing the six visible pages' HS kills (18312) against Total (21427) isolated wire
mode row 6's contribution (3115) exactly — the row is real, summed into every Total and the
header time, and has no page. Working hypothesis: a slot reserved for modes that never shipped
(the earlier Combat Training guess is unsupported — training stats live in 0x4107 slots 46-48).
Identity is deliberately parked as not-current-work; the only operational rule is that the
server must send zeros in rows 6 and 7 so the player's visible pages account for every Total.

### v8 settles the ALL row: client-summed, like Total — the totals model was wrong

Direct probe (Deathmatch: HS kills 10, lockon kills 5, wire column 0 = 3 — deliberately too
small to be a sum): the screen showed **ALL KILLS = 15**, i.e. the client sums the displayed
rows; the wire value never renders. The earlier "ALL renders the stored total" reading is
retracted. Column 0/1/4/5's only display role is recovering OTHER (= wire value − HS − lockon,
clamped ≥ 0 — v6's 44990 = 51000 − 3003 − 3007 stands). Consequence for the server: nothing
"ALL" is stored; the schema stores other_* and the 0x4105 sender computes each of wire columns
0/1/4/5 as other + hs + lockon.

## Titles and medals: server-driven catalogue, extracted from the ELF

**`AWARDS.md` is the current page for this, and it supersedes the framing here.** What survives
below is the static extraction — the catalogue, the tier table, the slot mappings — which is still
good. What does not is the sentence about who computes them.

Static extraction 2026-07-23 (medal tier table VA 0xe139c0, title resource keys VA 0xe14eb0,
sprites VA 0xe152d0). "Awards" are "MEDALS" in the client's own tab naming (TAB_TITLE /
TAB_MEDAL). The two record tables earlier suspected as their source (T+0x26d14, T+0x3330) are
actually match-history list storage (0x4682 / 0x4212 records) — that note is corrected.

> **CORRECTED 2026-07-30.** This section used to read *"Both are derived client-side from the raw
> stats; no command carries them."* **Three commands' worth of wire carries them**, all in
> `0x4103`: wire **563** (22-bit title unlock mask, LSB-first), **541** (worn title, 1-based, 0 =
> none) and **615** (16-byte medal bitfield, keyed by medal **id**, not row index). The client
> renders those bits and derives nothing.
>
> Implemented server-side in `AwardService` against `src/main/resources/awards.json`; titles latch
> once unlocked, medals derive from current stats, and the worn title is the best unlocked one by
> `rank`. **Every threshold on this page is therefore operator policy** — the original service's
> rules are unobservable — and the title numbers in particular should be assumed wrong until
> somebody tunes them.
>
> Hard constraint worth repeating here because this section lists 22 titles: **never set title bit
> 22 or above.** The client's popcount loop runs 23 iterations over a 22-entry table and corrupts
> the scrollbar.

**Titles (22, table order):** Foxhound, Fox, Doberman, Hound, Crocodile, Eagle, Shark?, Water
Bear, Sloth, Flying Squirrel, Pigeon, Night Owl (indices 0–11, the playstyle/rank animals;
names 0–5 and 7–11 observed live or read, Shark inferred from key "SHA"), then ten
special/unlock titles known only by key codes: TSU, S.E, KER (Kerotan), GAR, CHA, CHI, BER,
TOR, MAN, RAT (indices 12–21, inferred names). Per-title selection predicates are in
menu-driven code, not a static table; observed behaviour says the set shifts with the stat
profile (low stats → indices 0–3; varied high stats → 3–11).

**Medal thresholds (READ from the binary; 13 types × 3 tiers, id tens-digit = type):**

| tiers | medal | stat source |
| --- | --- | --- |
| 5 / 10 / 25 | Consecutive kills | 0x4107 slot 1 (confirmed live) |
| 3 / 10 / 30 | Consecutive headshots | confirmed live; slot TBD |
| 5 / 10 / 25 | unknown streak medal | unobserved |
| 500 / 2000 / 10000 | Total kills | Σ 0x4105 col 0 (confirmed live) |
| 500 / 2000 / 10000 | Total deaths | Σ 0x4105 col 1 (confirmed live) |
| 2 / 4 / 6 | Consecutive TDM survivals | 0x4107 slot 25 (confirmed live) |
| 50 / 100 / 500 ×3 (grouped trio) | three related medals — plausibly the GA-KO family (slots 28/29/31), inferred | |
| 50 / 100 / 200 | SOP destabilizer uses | 0x4107 slot 27 (inferred from live "100") |
| 50 / 100 / 500 ×2 | two more of the observed family (matches-without-a-scratch, targets captured, spotted-Snake-first, Mk.II destructions distribute over these five 50/100/500 slots) | |
| 10 / 100 / 300 | People finished training | 0x4107 slot 36 (confirmed live) |

Medal names are external localized resources referenced by 24-bit hash — not ASCII in the ELF —
so the five 50/100/500 medals cannot be told apart statically; a live pass setting one source
stat at a time would finish the mapping if ever needed. Presentation-mapping only; nothing here
changes what the server sends.

### The cumulative/weekly toggle: page 1 and record 2 are the weekly stats — confirmed

v9 sent a second 0x4105 with page selector 1 (cells 6001-6144). The stats screen's
cumulative/weekly toggle (spotted live) showed the weekly grid with exactly those values —
including the weekly play times (01:40:18 = 6018 s = page-1 DM column 17) — and the weekly
Personal Scores showed 0x4107 record 2 (2001-2073) in the same slot layout as record 1,
time slots included (00:33:35 = 2015 s = slot 15). Host Rating / Instructor Score kept their
0x4103 values on both panes: per-character, not per-period. So: 0x4105 page = period
(0 cumulative / 1 weekly), 0x4107 record 1/2 = cumulative/weekly personal scores. Schema
follows: chara_mode_stats keys (chara, page, mode); chara_personal_scores keys (chara, period).
Weekly reset cadence is operator policy.

### Epistemic correction on columns 0/1/4/5: role proven, meaning not

The v6/v8 entries above call these columns "stored ALL totals" — an over-interpretation. What
the probes prove is only the derivation: OTHER = column − HS − lockon (clamped, v6) and the
column never renders directly (v8). "Total" was inferred from that arithmetic (any server
wanting OTHER = x is forced to send x + HS + lockon), then repeated as if observed. The specs
and PROTOCOL.md now name these fields `*_minuend` — the proven role — and leave the original
semantic explicitly unknown.

## The SaveMGO Nomad capture blobs: dev-era test data, not Konami captures — but useful

2026-07-23, investigating the match-record design. GHzGangster/Nomad ships `.bin` payloads
wired (commented out) for playback on history/stats commands. Hypothesis was original-era
Konami captures; **decode disproved it**: `match-history.bin`'s leading u32 is `0x58AB6955` =
2017-02-20, and the record's name is "president trump" — SaveMGO dev-era test data, tier 4.

Still worth keeping (fetched to scratchpad, findings only recorded here):

- `match-history.bin` (25 B = exactly one `0x4682` record; the size matching our ELF-traced
  grid cross-validates the trace): their placement = {u32 Unix timestamp, u32 id = 2,
  16B name, u8 = 0}. Candidate labels only.
- `search-player.bin` (59 B = exactly one `0x4602` record; string boundaries land precisely
  on our traced offsets — mutual validation): their placement = {u32 id, 16B name,
  u16 = 36, 16B "dev-lobby", u32 = 1, 16B "Host Name", u8 = 4} — a presence card.
- `personal-stats-1.bin` (1024 B ≠ our 648): their own ASCII-position-marker **fingerprint
  payload** ("A0A1A2A3…X9") — the same technique this project used this week, nine years
  earlier. The size difference suggests they targeted a different client build; not usable
  as labels for ours.
- `player-overview.bin` (207 B): likely the `0x4212`-family player card (name + "Master the
  grid." comment + small ints); parked until that family is traced.

The `%Y/%m/%d %H:%M:%S` date-format resource found in the ELF menu blob during the
title/medal extraction (previously unrecorded) is now noted in PROTOCOL.md's `0x4680`
section: the history UI renders a timestamp, so the record's leading-u32-as-timestamp
candidate is structurally plausible. Fingerprinting the live screen is the confirmation path.

### No public original-era capture exists (searched 2026-07-23)

A genuine 2008-2012 capture of Konami's MGO2 servers DID exist — Derrik Touve (GHzGangster,
SaveMGO lead) captured live traffic before the June 2012 shutdown (his account at derrik.dev;
corroborated on ResetEra) — but it was **partial and never published**, surviving only as
seed/placeholder data inside the SaveMGO servers. That partialness is exactly why so much had
to be reversed from the ELF. No shareable pcap/dump is on GitHub, archive.org, or the PS3
Capture Project (which post-dates the shutdown and structurally cannot hold original MGO2
server bytes).

Chased the one lead — the `.bak` blob variants in GHzGangster/Nomad: `personal-stats-2/3.bin.bak`
(144 B) and `match-history.bin.bak` decode as the SAME 2017 ASCII-marker fingerprint sea and
"president trump" test record as the non-.bak files — older dev fakes, not capture fragments.
Conclusion: no original-server bytes are publicly recoverable. Live fingerprinting of the retail
client (this project's method) is the authoritative path; a direct ask to the SaveMGO team is
the only route to the surviving partial capture, if ever wanted.

## Error 1032:00000005 — the list-triple start/end u32 is a result code, not a count

2026-07-23, first live test of the match-history fingerprint payload. Opening match history
produced "Unable to acquire match history. (1032:00000005)" — no stall, no `FFFFFF60`, and the
lobby log showed the request handled. The `00000005` is our own byte reflected back: the server
sent `0x4681` with u32 = 5, intended as the record count.

ELF trace (same day) settled it. The `0x4681` handler (`0xD3ADF4`) branches on the payload u32:
**nonzero** marks the transaction complete-with-error and stores the value verbatim in a
per-subsystem result slot (`ctx + 0x33C + idx*4`, idx `0x1D` for match history); the history UI
polls that slot (`0x91F958: li r3,0x1032` → error dialog `0x885A08(0x1032, result)`), which is
exactly the observed dialog. **Zero** initialises the entry count to 0 and lets the transaction
proceed. The `0x4683` end handler (`0xD3ACF8`) stores its u32 into the same result slot
unconditionally and marks completion — so both start and end must carry **0**. The client counts
the 25-byte `0x4682` records itself (`0xD3B5FC`, count capped at 64, stored stride 28 bytes);
no packet ever tells it a count.

Why the earlier "bare u32 count" reading survived: every prior live answer in this family was
the **empty** triple, and a count of 0 is byte-identical to a result of 0. The mistake only
became visible the first time a nonzero list was served.

Same-day trace of the sibling families (player search `0x4601`/`0x4603`, match details
`0x4685`/`0x4687`) — see PROTOCOL.md for the per-family verdicts.

## The 0x4680 history fingerprint read live: a met-players list; Player Details sends 0x4220

2026-07-23, immediately after the result-code fix above. The five FP rows rendered, settling
three questions and opening one:

- **Leading u32 = Unix timestamp, confirmed.** Row 1 carried 2001-01-02 01:01:01 UTC and
  rendered as "01-02-2001 04:01:01": date exact, time +3h (emulated PS3 clock/timezone,
  unresolved — note before trusting server-side timestamps to render as intended). Rendered
  format was MM-DD-YYYY, not the `%Y/%m/%d` resource found in the ELF menu blob.
- **16-byte string = player name, confirmed** — rendered verbatim as the row label.
- **The screen is a met-players history**, one row per player encountered: selecting a row
  opens a player context menu — Player Details / Create Mail / Add to Friend List / Add to
  Block List. The second u32 (fingerprint 91xx) is therefore a strong character-id candidate;
  the u8 (fingerprint 40+row) rendered nothing visible.
- **"Player Details" sent `0x4220`** — the parked player-card family — not `0x4684`. It went
  unhandled (`No handler for command 4220`), stalling that screen. Payload not captured (the
  no-handler log did not dump hex then; it does now). No observed UI path reaches `0x4684`.

## The 0x4221 player-details card fingerprinted; square = 0x4102; 1036:00000001 explained

2026-07-23, minutes after the 0x4220 handler shipped. Clicking "Player Details" on FP-ROW-1
rendered the card and settled, in one pass:

- **The 0x4682 history record's second u32 is the character id, confirmed** — the row carried
  fingerprint 9101 and the client sent `0x4220` with payload 9101 (server log).
- **0x4221 card fields confirmed:** the 16B string at wire 0x08 is NAME (FP-DTL-NAME rendered);
  the 128B string at 0x27 is COMMENTS; the u32 at 0x22 (dest T+0x494) is **play time in
  seconds** — 9503 rendered as "02:38:23" = 9503 s.
- **LEVEL rendered 22 — a value never sent.** Likely derived from an exp-like u32 through a
  level table; candidates are the unrendered u32s 9501 (T+0x120) and 9502 (T+0x484). Varying
  one at a time next fingerprint round splits them.
- **CLAN rendered "---" despite FP-DTL-CLAN being sent** in the 16B slot at 0xAB — the clan
  label is wrong or the display is gated (perhaps on the preceding u32 at 0xA7 being a valid
  clan id; 9504 was sent).
- **The card's square button ("more details") sends `0x4102`** — the personal-stats burst —
  for the card's character. With fake id 9101 the server correctly answered not-found
  (status 1 in `0x4103`), and the client rendered "Unable to acquire character information.
  (1036:00000001)": our own status code echoed. Not a bug — resolves itself once history rows
  carry real character ids. Bonus mappings: screen `0x1036` = character information, and the
  ELF-traced context-menu arm that sends `0x4102` (idx `0x16`) is this button.

## Quit-before-round-end on a SaveMGO server: no history row, no stat change (tier 4-ish)

2026-07-23, user experiment against a live SaveMGO (Nomad-lineage) server: kill, die, then
leave before the round ended → no met-players/history record appeared and personal stats were
unchanged (no XP penalty either). Two explanations are indistinguishable from outside:

1. The host client sends no `0x4390` report for a player who already left — a client-behaviour
   claim we can test authoritatively on our own server (every report's target id is logged).
2. The host does report quitters at round end and SaveMGO drops the report — the exact
   current-membership bug our round-snapshot path exists to fix (see BACKLOG, "The round
   snapshot never populates", resolved).

Incidentally confirms SaveMGO populates the 0x4680 history at (at latest) round end, not at
join time. Next live round on our server with an early quitter settles which explanation is
right for this client build.

## Equipped skills vanished after a game: 0x4130 acked but never persisted

2026-07-23, native client. Equipping CQC 3 survived menu navigation but reset to blank after
joining a game. DEBUG packet trace caught it: the skills menu saves via **`0x4130`** (the
wardrobe/personal-info update — appearance, skills, levels, comment in one 158-byte frame; the
equip showed as skill id `0x0a`, level `3` at the documented offsets). The handler stored
appearance and comment, **echoed** the skills in `0x4131` (which is why the menu kept them
in-session), and dropped them — while the read path (`0x4122` in the connect burst) serves
`chara_equipped_skills`, which nothing ever wrote. The entire persistence apparatus existed;
only the `update` call was missing. Fixed same day (`CharacterService.updateEquippedSkills`),
regression IT added.

Motive for the whole chase: whether the CQC skill transforms R1 grab behaviour (VM keyboard
and DualSense both lack the DS3's pressure-sensitive R1, so skill level is the remaining
lever for CQC holds/chokes). Retest pending the fix.

### New: `0x4b46` observed, unhandled, non-blocking

Same trace: the client sent `0x4b46` (2 bytes, `0000`) shortly after the lobby connect burst
and proceeded normally with no reply — the first observed command that does NOT stall unanswered.
Family `0x4bxx` is otherwise unknown. Parked: harmless as-is, payload now hex-logged if it
recurs.

### Skill ids read off the 0x4130 trace (persistence verified live)

Post-fix retest 2026-07-23: equips survived logout/login in every arrangement. The DEBUG
trace of each equip maps the ids: **0x01 = Handgun**, **0x0A = CQC**, **0x11 (17) =
Instructor** (level byte 1 — likely single-level). Slot-aligned skills[4] + pad + levels[4],
level follows the slot when skills are rearranged. Note: the 0x4125 catalogue special-cases
skills 17/20/22 (0x2000, not 0x6000) — 17 is now known to be Instructor, the first anchor in
that trio.

## The OTHER-field experiment: single-variable rounds label the 0x4390 counters

2026-07-23, seven deliberately single-variable DM rounds (sean = chara 1 vs rawr = chara 2,
one kill type per round, both players' results screens read after each), plus grab-practice
reports — the first systematic use of `round_report` rows as the capture medium. Full detail
in PROTOCOL.md's revised 0x4390 tables; the headline results:

- **A `0x09` = lock-on kills; A `0x1b` = deaths to lock-on** (dealt/received pair, like
  headshots/headshot-deaths). One 3-lock-on-kill round moved exactly these two slots to 3;
  five kill rounds without lock-on held both at zero. **This was the experiment's goal**: the
  personal-stats grid's OTHER category is the remainder `minuend − headshots − lockon`, and
  every operand now has a known source in the round reports.
- **A `0x21` = round won** — winner-only for seven rounds, then transferred on the reporter's
  first lost round. A `0x1f` = 1 for both players of completed rounds, 0 in teardown reports.
  A `0x1d` ("rounds played" per the old capture) never moved — label doubtful.
- **Score decomposes as `kills·3 − deaths·2 + stun·3 + kill1st·5 + combo·1`, clamped at 0**,
  exact across five rounds (15/17/17/17/0-with-implied-−6). Revisions vs the capture era:
  stun·3 not ·2, no round-win bonus, and "score can go negative" was never actually observed.
- **Struct B is an event ledger with dealt/received pairs**: B10↔B11 (CQC-contact-flavoured)
  and B22↔B23 (slam/knockdown-flavoured) matched exactly on both sides in every round; slams
  tick B23 without a faint while the scoreboard stun (A `0x0d`) requires the knockout. B3 =
  suicides. B39 = kill-1st-place (matches the KILL 1ST PC screen line 4/4). B0/B1 and B36
  have *matched* kills/deaths in 7/7 rounds — recorded as correlations, not duplicates, per
  the no-mirror rule; no divergence test has split B0 from B36 yet.
- **Results-screen behaviour**: the category line set varies by context, zero-valued lines do
  render, environmental kills present as COMBO (no ENVIRONMENTAL category), knife stabs to
  the head are not headshots, and "KILL 1ST PC" means killing the current first-place player.
- **Open**: B8 (one-off 1 in the rifle round), B12 (3 per explosive-kill round, a stray 1 in
  knife/rifle/CQC rounds, 0 in lock-on/practice — the user's one-off action those rounds is
  unidentified), B21 (stun-adjacent, one observation), the B0/B36 split, and victim-side
  `0x0f` (loser-side 1, twice).

Migration V17 renames the two confirmed columns (`lockon_kills`, `lockon_deaths`). The CQC
detour also fixed skill persistence (see "Equipped skills vanished") — CQC turned out to be
skill-gated, not pressure-gated: with CQC 3 equipped the grab works from any input device.

### 0x4390 is host-only, per-connection-verified; the host reports crashed players

2026-07-23 TDM (game 107), DEBUG per-connection trace: every inbound 0x4390 arrived on the
host's connection — the joiner, alive and playing through round 1, sent none for himself. The
host speaks for all players (one 167-byte packet each), so the server-side stats pipeline
trusts the host entirely; a joiner has no channel of his own. A batch including the joiner
(all-zero) arrived around his mid-round-2 crash, but the crash time relative to the batch
was never established — **inconclusive** for the does-the-host-report-departed-players
question. The evidence on that question stands at exactly one observation (2026-07-22): a
**crashed** joiner's end-of-round report arrived (and was then rejected by the pre-snapshot
membership check). A **voluntary mid-round quit** has never been tested on this server and
may behave differently (a crash leaves the host's peer FSM to time out; a menu-quit may
remove the player from the host's round model immediately — the SaveMGO no-stats result is
consistent with that). The clean experiment: joiner menu-quits mid-round with DEBUG tracing
on; watch for a 0x4390 naming him at quit time, at round end, or never. Same round also upgraded A `0x0f` to **stuns received**
(matched opposing stuns-dealt in every round to date), added new one-observation slots A
`0x15` (dealt) / A `0x17` (received) and B24 — candidate events: stun-sniper headshot,
knife-kill on a sleeping body (the dart headshot did NOT tick the headshot counter, matching
the knife-head-stab finding) — and produced the first garbage `seconds_in_game` (66157 on the
host's own row vs a sane 100 for the joiner). The two-reports-per-stage question from the
2026-07-22 TDM capture remains open: the crash prevented a completed multi-round stage.

### The two-round TDM stage: per-round reporting holds; struct B has per-stage state

2026-07-23 evening, game 107 (TDM, two-round stage, completed naturally then manually
restarted). Findings:

- **One 0x4390 batch per round, none at stage end** — the stage boundary added nothing. The
  "two score reports" remembered from the 2026-07-22 capture were that capture's own two
  per-round batches (it was also a two-round TDM).
- **B24 = own team's stage score at report time** (strong candidate): 1 / 1-after-the-crash-
  reset-the-score / 2, and 0 in every teamless DM round. First confirmed cross-round state
  inside struct B — it is NOT a uniform per-round ledger; slots have individual scopes.
- **First A/B divergence, no-mirror rule vindicated**: the stage's FINAL round reported
  A-kills=1, A-headshots=1, score 5 — with B0=0 and B2=0. Round 1 of the same stage had
  B0=1, B2=1. Candidate: the client zeroes per-round B slots at stage end before building
  the last report. Prediction to test: every multi-round stage's last batch shows zeroed
  per-round B slots.
- **B2 = headshots dealt** (candidate, first appearance with the first bullet headshot).
- A `0x15`(dealt)/`0x17`(received) pair and the round-1 score's +1 residue track the
  sleep-stab kill (0x15 scoring ×1 fits both rounds); dart headshots do not tick headshots.
- Host-side `seconds_in_game` garbage recurred (66157 then 65831 — non-monotonic, host row
  only; joiner rows stay sane). Open.

### 0x43a2 exists after all: sent at natural TDM round ends

2026-07-23: each TDM round end delivered host→server `0x4390` (player A) → `0x43a2` (15 or
22 bytes, content-dependent) → `0x4390` (player B), each acked (`0x4391`/`0x43a3`). The
2026-07-22 "never observed on any path" verdict was DM-era; whether DM round ends also send
it is now unknown (pre-restart DEBUG logs were lost). Payload hex recorded in PROTOCOL.md;
meaning unparsed everywhere.

### The host-rating prompt fires when a JOINER quits a live game — `0x43c4` traced end to end

*2026-07-29.* "Rate this host" had been seen exactly once in the project's history, and nobody knew
what produced it. It is not the server, and it is not the instructor rating — those are two
different flows that had been conflated.

**The one sighting, reconstructed from the capture** (`dev/analysis/logs/mgo2server-gamelobby-1.log`,
2026-07-28; the only `0x43c4` in the whole log corpus). Game 234 was created by **character 2**
(`rawr`, .122) at 05:28:02; **character 1** (`Sean`, .100) joined:

```
05:43:52.466  host    0x4390 x2   round-end stats for both players
05:44:31.695  joiner  0x4312  ->  game info for game 234
05:44:31.729  joiner  0x43c4  ->  00000005      the vote, 34 ms after the reply
05:44:36.651  joiner  0x4380  ->  QUIT_GAME     4.9 s AFTER the vote
05:44:36.747  host    0x4390  ->  "character 1 ... left mid-round"
05:45:09.081  host    game 234 advanced to rotation entry 0
05:50:18.738  host    "Character 2 left game 234, which it hosted"
```

So: **the joiner quit first, out of a live round, while the host stayed in** — the host played on
for six more minutes. And the vote goes out *before* `0x4380`, not after: the star picker is part of
the quit sequence, and the quit only proceeds once it is answered.

**Why it has never fired for a host.** Ending a session by quitting as host tears the game down and
ejects everyone through teardown rather than through their own quit path, so no joiner ever enters
the state that opens the picker. Nobody is asked because nobody chose to leave.

**The code, so the trace is not re-derived.** `0x43c4` has one sender, `0xD40E2C` (`r3` session,
`r4` stars, range-checked 1..5 at `0xD40E44`), called from three star-picker screens —
`0xA322A8`, `0xA3310C`, `0xA33F70` inside `0xA30BF0` / `0xA327F4` / `0xA3313C`. The widget is
initialised by `0xA30A38`, which defaults the rating to 3 (`stw r0,204(r3)` at `0xA30A50`), and
`0xA33AC4` is its up/down clamp. `0xA30A38` has exactly **four** call sites — `0x9DCB28`,
`0x9DCD68`, `0xA12C14`, `0xA13710` — two end-of-game state machines reaching it from two states
each. Those four states are the gate; which is which is **not yet resolved**.

**Do not reason from the instructor prompt to this one.** Dialog event `0x150022` ("Choose a
rating") has only two posters in the entire binary, `0xA35F70` and `0xA36050`, and both are inside
the *combat-training* end-of-session machine at `0xA35788` (see BACKLOG.md). The in-game host rating
does not use that event at all.

**Still open:** which of the four states corresponds to which exit path. The cheap experiment is
four games varying only the teardown — host ends the round naturally, host quits, joiner quits from
the results screen, joiner quits mid-round — since the gate is a branch on live session state, not
on anything we send. Note also that `host_review` was **empty** as of 2026-07-29: the `0x43c4`
handler only landed on 2026-07-28, so the one recorded sighting predates any storage.

### Voluntary quitters ARE reported — at quit time, with real stats; SaveMGO question closed

2026-07-23 late, three-player game 109: character 3 ("poop", tester03) CQC-grabbed and
throat-slit rawr, then menu-quit mid-round. The host filed poop's 0x4390 **84 ms after the
0x4380 leave command** — 1 kill, score 3 (kill·3), real values — before the 0x4342 disconnect
notice; our server accepted it via the round snapshot ("left mid-round; accepted from the
round snapshot"), the exact case the snapshot fix exists for. So the earlier open question
resolves: the host reports departed players immediately on voluntary quit (and the crashed
case has its 2026-07-22 observation) — **SaveMGO's missing quitter stats were their server
dropping the report**, not the host staying silent. Bonus labels from the same rows: the
quitter carried 0x1f=0 while the round-completing winner carried 0x1f=1 — first per-player
discrimination for the "completed the round" reading; B10↔B11 grab pair confirmed a third
time (slit = grab + finisher); the slit is otherwise an ordinary kill (score 3, no 0x15, no
special A slot); B12 stayed 0 despite a CQC kill, further narrowing its DM-round one-off.

### Three-player TDM: 0x23 decoded (team id + seconds), B12 = the OTHER category

2026-07-23 late, game 111 (sean+poop blue vs rawr red; sean hosted). Key results:

- **Wire 0x23 is two u16 fields**: hi = team slot index (constant per player per game; 0 in
  every DM round; grouped poop with sean; NOT the color — sean's blue was 1 in game 107,
  rawr's red was 1 in game 111), lo = seconds (identical for co-present players). The
  "garbage seconds" anomaly was hi=1 read as part of a u32.
- **Σ B12 = the stage screen's OTHER count**: rawr's stage results (full category set:
  Kill/Death/Headshot/Hacking/Assist/Stun/Wake/Other) showed Other=2 = his per-round B12
  (1+1); adding B12·1 to the score formula closes his previously-undecomposable 9 and 11
  exactly. What earns the per-round other-point is unidentified; the DM env/grenade "combo
  3×1" line was plausibly the Other line (B12=3 both), but the knife round's reported
  Combo=3 with B12=1 keeps round-screen Combo distinct pending a re-read.
- **Host reports kills against itself faithfully** (rawr 2+2 headshot kills of the host,
  mirrored in the host's own deaths/headshot_deaths).
- **Stage-final rows: losers fully zeroed struct B (2/2 observed), winners keep a residual
  set** (sean kept b24 in 107; rawr kept b12/b24/b36 in 111) — the zeroing prediction held,
  the residual rule is not yet systematic.
- **0x21 demoted to OPEN**: with teams known, "won this round" fails (rawr won round A with
  0x21=0) and "won previous round" fails the DM suicide round (sean 0 after winning the
  prior round). Seven earlier correlations plus one transfer still unexplained by any single
  model. B24 similarly open (1 on a 2-0 stage win).
- Quitter reporting reproduced exactly on the second run (immediate report, kill·3, 0x1f=0).

### The token never leaves the client on the LOBBY link — but it does leave over P2P

2026-07-23, closing ELF trace. The 0x43c9 start-round token is written to
session+0x57d8+0x32f8 and read at exactly one site in the binary — a UI record populator
using memory-copy helpers, not packet writers; the 0x43c8/0x43a2/0x4390 builders never
reference the slot. So no packet can carry a game identifier: connection identity is the
whole attribution mechanism, by construction.

**Corrected 2026-07-26, and the correction matters.** The conclusion above is right about the
lobby protocol and wrong about the slot being inert. The single reader is `0x8842AC`, the packer
that builds a player's **join announcement**: it copies `profile+0x32F8` to `struct+12`, which
`0x2762A0` publishes as replicated player variable **352**, which the host broadcasts as P2P
opcode `0x24` to each peer, which lands in `G->0x1C0` on the receiving client and is tested at
`0xA359A4` — non-zero there **skips the instructor recognition prompt**. It is not a UI record
populator and it is not inert; it is the "an instructor is already saved" flag, and it travels
over the in-game link rather than ours.

The write at `0xD3FF6C` is guarded by `!= 0`, so only a nonzero token sets it, and nothing in the
client ever clears it. We were sending the game id, which permanently stamped every character who
started a round or graduated — which is why the recognition prompt never appeared for anyone.
`HostGameController` now sends zero. 0x43c8's {u32,u8} = two config bytes from a
settings buffer (round/rule pair, not the token). 0x43a2 fully decoded as a count-prefixed
per-slot tally list (see PROTOCOL.md) — our three captured payloads decode exactly; what the
127-slot table indexes is the new open question.

**Resolved 2026-07-26, and it was not `0x43c9`.** Zeroing the `0x43c9` token did not raise the
prompt. The field has a *second* writer: the `0x4122` personal-info parser at `0xD3D624`, which
reads the payload's last u32 into the same `profile+0x32F8` **unguarded** — no `!= 0` test, so it
stores whatever we send on every personal-info reply. We were sending `00 A7 00 0D`, a fixed suffix
copied from another server, which is why the prompt never appeared for anyone and why the `0x43c9`
change alone did nothing. `PersonalInfoWriter` now sends 0.

Two corrections to the chain as first written here. `0xA359A4` reads **`G+0x1C0`**, not
`profile+0x32F8`; the two are linked by the P2P hop, not by a direct read (`G+0x1C0` has one writer,
`0x9D17C8`, reachable only from arm 36 of the P2P table at `0x9D1500`, and one reader, `0x9CD5D0`).
And the prompt's text is real in this build — stage `n002a` string resource 3099, extracted with
Solideye + Gcx, with the rating prompt we do get at 3105. The sender of P2P message 36 was never
located; the receive side is proved, so the fix does not depend on it, but that is the open gap.

### Game 112 (two identical AK102 rounds): per-round model pristine; winner-flag asymmetry

2026-07-24. Two TDM rounds, each 2 AK102 kills (1 headshot + 1 body), stage ended naturally.
Wire: two per-round batches with identical struct A (kills 2, headshots 1) and identical
0x43a2 lists ({AK102: 2,1,0}) — identical because the rounds were; NO stage-end extra report
(natural stage end now observed twice adding nothing). Third confirmation of the stage-final
struct-B signature (last batch: per-round slots zeroed, b24 stepped 1→2 with the team score,
b36 kept). New hypothesis from contrasting games 111/112: **0x21/b24 update synchronously
when the HOST's side wins (112: exact) but lag when the JOINER's side wins** (111: rawr's
round-A win showed 0x21=0/b24=0, correct only from round B) — a host-perspective bookkeeping
artifact candidate. b36 reshaped: equals kills in DM (3), 1 in TDM rounds with a 2-kill
streak, 0 in TDM single-kill rounds — combo-flavoured, no closed model.

### Punch-combo ground truth: B22/B23 = melee hits; melee faints never reach 0x43a2

2026-07-24: the three knockouts in the AK102-equipped round were rifle-melee punch combos
(punch-punch-kick, ~3 hits each) — so that round's B22/B23=9 = 3×3 melee hits, and the pair
re-fits every prior observation (slams 3, practice 8, slit 1, dart round 3) as **melee hits
dealt/received** — the strongest label yet for the pair. PUNCH has weapon ids (108/109) yet
tallied nothing in 0x43a2, second independent confirmation (after CQC id 112) that
melee-caused faints are excluded from the per-weapon list: they exist only in the scoreboard
stun pair (0x0d dealt / 0x0f received). B10/B11's "grabs" reading takes a counterexample
(1 with zero grabs, punches only) — demoted to contact-flavoured, open.

### Headshots are killing/terminal blows, not hits — proven with a helmet

2026-07-24: two GSR headshot WOUNDS on a helmeted target (then Vz.83 body-shot finishes)
ticked nothing anywhere — scoreboard headshots 0, struct-B B2 0, and no GSR entry in 0x43a2.
With the AK102 headshot-kill and Mosin headshot-faint both counting, the rule everywhere is:
a headshot registers only as the qualifier of a terminal event (kill or faint). 0x43a2 rows
themselves require terminal events — damage alone never creates an entry. New anchor: slot
23 = the in-game Vz.83 (table string SKORPION — first likely real name divergence, pending a
UI read). The recurring kill-round other-point (b12=1, score +1) appeared again.

### Replicated within one weapon: GSR round of killing-blow + wounding headshot

2026-07-24, user-designed follow-up: one close-range GSR headshot kill and one GSR headshot
wound (victim finished with body shots) in the same round → 0x43a2 {GSR: 2 kills, 1
headshot, 0 faints}; scoreboard kills 2, headshots 1. The killing-blow-only rule confirmed
with both cases inside a single weapon entry. Slot 7 = GSR anchors (table SIG GSR, name
matches UI). Score 9 = 6 + 2 + 1(other-point) — b12's kill-round +1 again.

### Team slot ≠ color (mapping theory killed same night); teammates share the win flag

2026-07-24: a deliberate red pick landed slot 1 — and a deliberate BLUE pick the next game
ALSO landed slot 1 (game 111's blue was slot 0). So team_slot is a per-game internal team
index; the color-to-index assignment varies per game (join/creation order suspected).
Same session, first teammate observation: sean and poop on one team (same slot), both
carrying 0x21=1 for a round sean won — supporting 0x21 = TEAM round-win flag — while their
b24 differed (2 vs 1), killing plain "team stage score" for b24 and suggesting "team round
wins while this player was present." The 0x43a2 header u32 remains 1 in every capture, and
every observed winner has been the slot-1 side — the discriminating observation is a round
won by the slot-0 side, still unplayed.

### 0x43a2 header solved: the reporter's character id — the packet is fully decoded

2026-07-24, closing ELF trace: the leading u32 is the reporting client's character id, read
from the cached 0x4101 record (session+0x57d8: u32 char id + 16B name + constant block),
snapshotted into each round record (+0x14c) and forwarded verbatim. "Always 1" was the test
host's char id; the winner-slot correlation was coincidence (only hosts send, and char 1
hosted every game). Candidates killed on mechanism: set pre-round (not completion/count),
network-parsed and identity-compared (not constant), never recomputed from scores (not
winner). Prediction: a game hosted by chara 2/3 sends header 2/3. Every field of 0x43a2 is
now decoded. Nuance recorded on the reporting-model truths: 0x43a2 does carry one in-frame
identity (its sender's), unlike 0x4390; the no-game-identifier truth stands.

### Correction: the 0x43a2 header is NOT the reporter's id — falsified within the hour

2026-07-24: a poop-hosted (chara 3) round still sent header 1, killing the reporter-chara-id
verdict the ELF trace had just delivered. The trace's mechanics stand (the value comes from
the cached char-record buffer at session+0x57d8, snapshotted per round) — the error was
assuming that buffer always holds the OWN character's record; it evidently can hold
another's. Every surviving capture (10/10; game 111's rawr-won packets were lost to the
23:16 container restart) is a round chara 1 won → winner's-chara-id is the leading
candidate. Discriminator: any round won by chara 2 or 3 with DEBUG on.

### 0x43a2 header = the WINNER's character id — closed by controlled flip; DM sends it too

2026-07-24, final: in one fresh poop-hosted (chara 3) game, sean's win sent header 1 and
poop's slit-kill win sent header 3 — same game, same host, only the winner varied. The
eleven earlier 1s were chara 1's win streak. Eliminated en route: reporter/host id
(falsified by a poop-hosted sean-win), host-transfer artifact (fresh game), constant (it
moved). Two lessons banked: an ELF trace's mechanical finding (where the value comes from)
survived while its semantic leap (whose record lives there) did not — live falsification
outranks trace confidence; and the user's host-transfer confound catch forced the clean
2x2. Bonus: these rounds were DEATHMATCH and sent 0x43a2 — the "never sent in DM" belief
(2026-07-22, pre-tracing) is dead; the packet fires in every mode, entries permitting.

### 0x43a2 is the round-winner card: top-scorer id + THEIR weapon breakdown only

2026-07-24, the 2v1 experiment (rawr 4 kills, sean 1 kill, same winning team; poop 5
deaths): header 2 = the winning team's top scorer (third distinct id), and the tally list
held ONLY rawr's weapons ({Vz.83: 4,4,0}) — sean's kill was absent. Every prior capture
re-checked: the tallies always matched the winner's own actions (indistinguishable from
"whole round" until a second scorer existed). So the packet is a winner/MVP card, not a
round aggregate. Also confirmed this session: header follows the winner across ids 1/2/3,
and DM sends the packet (pre-tracing "never sent" verdict dead).

### Correction: 0x43a2 is the MVP card, not the winner card — losing-team MVP takes it

2026-07-24, user-designed three-way discriminator (losing rawr 4 kills; winning sean 2
incl. the round-ender; winning poop 3): header 2 = rawr — the OVERALL top performer,
independent of team outcome. Bytes: 00000002 00000001 17 0004 0004 0000 (rawr's Vz.83
tally alone, again). Kills-vs-score ranking still confounded (MVP led both).

### Score clamp was wrong: negatives are real; suicides just don't deduct

2026-07-24: wire scores −4 (2 deaths) and −10 (5 deaths) — deaths·−2 exactly, no clamp.
The suicide round's 0 (which founded the clamp theory) was actually "suicide deaths deduct
nothing." Also first round ever recorded with NO winner flags (all 0x21=0, the 04:13
three-player round) — round-end-by-timer suspected, ground truth pending. The 0x43a2 header
model is OPEN again: top-scorer fits all rounds except one where the finishing-blow player
took it over a higher scorer; no single-factor rule survives. Data table in the session
log; no replacement theory documented until discriminating ground truth arrives.

### 0x43a2 SOLVED, for real: per-player weapon appendix — the theories were a sampling bug

2026-07-24, closing correction: 0x43a2 is sent ONCE PER PLAYER with a non-empty tally
(right after that player's 0x4390; empty lists skipped via the count==0 early return).
Header = that player's own chara id. The 04:13 three-scorer round emitted THREE packets
(headers 1/3/2, tallies exactly each player's own kills); the 04:17 round two (rawr, zero
kills, skipped). Every winner/MVP/top-scorer/finishing-blow theory of the night was an
artifact of reading only the LAST packet per round (tail -1) — single-scorer rounds masked
it, multi-scorer rounds manufactured patterns from whichever packet happened to be last.
The user cracked it by asking "aren't there three of these, one per player?" Lesson banked:
count the packets in an exchange before interpreting any of them.

### 0x4390 internals traced: per-round deltas, rebaseline, B0 running-max candidate

2026-07-24, deep ELF pass on the stat pipeline (builder 0xD42178). Tier-1 mechanics: every
counter is sent as a per-round DELTA (live-snapshot minus baseline, both in the profile
blob; baseline is rewritten after each report — which is why reports are per-round — and
round aborts restore live from baseline, a rollback that also explains stats lost to
crashes). Post-build code maintains B0's storage as a RUNNING MAX (store-if-greater) —
candidate: a best-round record, not a kill tally (fits its kills-matching in single rounds
AND its stage-final zeroing; unconfirmed). B8's source = live gameplay struct G+0x3a4
(G = *(player+0x6c)) — the tractable next trace target; the blob has mixed field widths
under the u16 wire reads (B12 may straddle two u8 fields). The per-weapon 0x43a2 table has
its own four increment fan-outs, independent of A/B. NOT achieved: the gameplay increment
sites for B12 / 0x21 / 0x15-0x17 / B36 (dynamic-base writes; needs symbolic tracking via
the G struct). The agent's "17 A + 71 B" recount is not adopted (self-inconsistent with
its own offsets; 58 B u16s stand). Flag 0x04's "self-row marker" candidate conflicts with
live data (always 0 incl. hosts' own rows) — open.

### Second G-layer trace: central claims REJECTED by live data; the A-block wall is real

2026-07-24. A deep continuation trace claimed B10/B11/B12 are hardwired zeros and
B8/B21/B24/B36 are duration fields — all falsified by repeatable wire captures (B12 nonzero
in seven rounds, B10/B11 carried grab counts to 11, B36 matched kills seven rounds running;
1-4 magnitudes are wrong for tick durations). Per the evidence hierarchy, the trace's
blob↔wire linkage is misattached — it likely followed a DIFFERENT serialization (an async
end-of-round career/profile submission task it discovered, real machinery but not proven to
feed 0x4390). Adopted from the pass: (1) both traces independently confirm the A-block
event counters (0x1f/0x21/0x15/0x17) are written via a raw pointer no static search
attributes — that wall is real; (2) a per-category duration+count table exists in the
gameplay struct (unattached); (3) a catalogue of mode-clustered writer addresses for future
work. Decision: pause ELF tracing at this layer — two passes hit the same wall and the
second began producing confidently-wrong linkages; the empirical lever (objective-mode
rounds for dark slots, one timer-ended round for 0x21) is cheaper and falsification-proof.

### Tranq-stun round: 0x0f vs 0x17 split; assist credit absent again; b36=COMBO reconfirmed

2026-07-24. Sean tranq-headshot-stunned rawr twice (recorded in 0x43a2 as {RUGER: 0,0,2}
faints — dealt stuns live in the weapon list, not struct A), rawr killed by poop 3× headshot.
Findings: rawr's report shows 0x0f=2 AND 0x17=2 (stuns received), while melee-slam rounds
moved 0x0f but NOT 0x17 — candidate split: **0x0f = all knockouts received, 0x17 = ranged/
tranq knockouts received** (sleep-stab round's 0x17=1 fits). ~~0x15 (dealt side) stayed 0 on
the dealer~~ **[WRONG — falsified hours later by the wire itself: the dealer's packet has
`0002` at 0x15, and game 107 R1 already had 0x15=1. 0x15 = ranged/tranq knockouts dealt;
see the next entry.]** ~~**Assist absent a SECOND time**: two
health-setups (round 1) and two tranq-stuns (round 2) before a teammate's kill produced zero
credit for the setup player (score 0, no slot) — assist·3 in the score formula looks inert or
requires an unknown trigger~~ **[WRONG — the credit was there the whole time, in B37 (=2)
and in the score (14 = stun·4 + dart-headshot·4 + assist·6); we just hadn't decomposed it.
Screen-confirmed the next round. Only the health-setup half survives: damage-only setups
earned nothing.]** b36=3 with poop's 3
headshot kills and score 18=9+6+3 reconfirms b36 as the ×1 COMBO/OTHER category (b12 stayed
1, contributes nothing to score — b12's Other label was a b36 confound, now retracted).

### The B-block's running-max family; mode-specific stun; the score clamp; assists were never inert

2026-07-24 (late). Re-reading all 66+ stored `round_report` rows against the server's own
"advanced to rotation" log lines cracked the B-block's semantics, and a live round read off
the result screen (categories × multipliers × totals) settled the score formula. Everything
below is in PROTOCOL.md's revised tables; the discoveries and their falsifications:

- **B0/B1/B2 are per-stage best-round records, not counts** — store-if-greater, zeroed on
  stage rotation, wired as deltas like every counter. Sean's constant-2-kills game wired B0 =
  2,0,2,0 across two 2-round stages, exactly tracking "new stage best or nothing"; rotation
  timestamps in the lobby log match every reset (DM rotates each round, so DM rounds always
  wire full counts — which is why the old single-round captures read "matched kills N/N").
  This live-confirms the ELF pass's B0 running-max candidate and extends it to B1 (deaths)
  and B2 (headshots, bullets only — a 3-terminal-headshot round wired B2=1 because the stage
  best was 2, killing the "B2 = terminal blows" reading against 0x43a2's independent count).
  B12 showed the same 1-then-0 signature across identical rounds: max-family, base unknown.
- **B24 = TDM rounds survived/won this stage** — absent in every DM round, 1,2-then-reset in
  TDM, 0 the moment the player died or lost, quit-teardown snapshots the pre-round value.
  "Survived" vs "won" needs a win-but-die round; absolute-vs-triangular-delta also open.
- **B36 = kills·(kills−1)/2 exactly, all rows** — including a 4-kill/5-death round (B36=6),
  so deaths don't reset it: a pure function of round kills, not a streak mechanic. It is the
  screen's OTHER row (×1), confirmed 6-for-6 on a 4-kill player.
- **B37 = assists (screen ASSIST row, ×3)** — wire B37=3 with screen "Assist=3x3", total
  exact. The two "assist inert" verdicts are dead: the tranq-setup round paid 6 points of
  assist credit we hadn't decomposed. Damage-only setups (health experiment) still earned 0.
- **0x15 = ranged/tranq knockouts dealt** (2/2 mirror of the victim's 0x17; 0 in melee
  rounds) — the same-day "stayed 0 on the dealer" note was a misread of the victim's packet.
- **Stun multiplier is mode-specific: ×2 TDM (screen-confirmed), ×3 DM** — resolving the
  stun·2-vs-stun·3 whiplash in this file: both were right, for their mode.
- **The wire score is the delta of a clamped store.** Two 5-death/0-kill rounds wired 0 (no
  banked score) and −10 (16 banked the round before); the quit teardown wired −4 off a
  26-point bank. So "suicides deduct nothing" (2026-07-23) is confounded — that round had
  nothing banked and the clamp alone explains its 0. Suicide deduction reopened.
- **The screen's HEADSHOTS row counts tranq-dart headshots** (6 on screen vs 0x11=1 on the
  wire); 0x11/B2 are bullets-only. Every dart stun so far was a headshot, so headshot·2
  counting darts vs a separate 0x15·2 term are numerically indistinguishable — a body-shot
  tranq round discriminates.

A corrected re-read of the screen (first transcription had slipped rows) reconciled all three
players field-by-field and added two things. (1) There is a **WAKE×2 row** — the capture-era
"wake·2" guess is a real category, still never nonzero. (2) One real anomaly: **the loser's
OTHER row read 5 while his wire B36=0** (0 kills, so combo=0). His only nonzero B slot was
B1=5; what distinguished this round from his earlier 5-death round — which wired −10 exactly,
leaving no room for OTHER credit — is that here he was **knocked out 5 times** (0x0f=5). So
the screen's OTHER is B36-combo **plus** a component tracking knockouts received (or the
recoveries from them) ·1. Both sightings of that component sat under the score clamp
(−10+5=−5 in this round, −6+2=−4 in the earlier 2-knockout round, all displaying/wiring 0), so whether it feeds the wire score at all is
unproven — a stunned-often player with banked score would show it in a wire negative.

Open discriminators, in rough order of value: a **body-shot tranq stun** round (splits
headshot·2-with-darts from 0x15·2); a **get-stunned-with-banked-score** round (does the OTHER
knockout component feed the wire score?); a **win-but-die TDM round** (splits B24
survived/won); a **same-stage-banked suicide round** (settles suicide deduction regardless of
bank scope — see the bank-scope entry below); a **timer-ended round** (0x21 ground truth, still pending); hacking/wake rounds
(untouched categories); B8/B21/B10-11/B22-23 single-variable rounds as before.

### Wake round: B35 = wakes ×2, exact on the wire; the dart-headshot ambiguity survives again

2026-07-24, engineered wake round (Sean+rawr vs poop; poop dart-stunned rawr 3×, Sean woke
him 3×, poop killed 5 across both). Sean's report: **B35=3 — first nonzero ever — and wire
score 2 = wake·2·3 − deaths·2·2 exactly**, matching the screen's WAKE=3x2 row. B35 = wakes,
×2, paying into the wire score. Cross-checks in the same round: poop's 3 dart stuns wired
`0x15`=3 against rawr's `0x17`=3 (dealt/received mirror again); poop's screen HEADSHOTS=8 =
wire `0x11`=5 bullets + 3 dart headshots, B2=5 (bullets only, new stage best); poop's
OTHER=10 = B36 = 5·4/2; poop's 47 decomposed exactly — but his darts all hit heads AGAIN, so
screen-headshot·2-counting-darts vs a separate `0x15`·2 term remain numerically identical.
rawr's OTHER=3 = his 3 knockouts received (second sighting of the OTHER knockout component),
still invisible on the wire because he had nothing banked (−6+3 clamps to the observed 0).
Also noted: rawr's reports in two adjacent rounds carried `0x1f`=0 with everyone else at 1 —
in one his seconds ran ~40 short of the others (left before round end, consistent with the
quit-report pattern); in the other they matched, unexplained but benign.

### The score bank is per-game-or-stage, not career; the suicide verdict is still open

2026-07-24, prompted by "do we have suicides?". One suicide round exists (game 105 R3,
2026-07-23: 3 grenade suicides, wire 0). Reconstructing banks by telescoping wire scores
falsified the "profile store" phrasing of the clamp model written hours earlier: rawr summed
to ~+22 career points before game 120's losing round yet wired 0, so the bank resets **per
game or per stage** — and every observed negative wire (−4, −10) had its bank earned in the
same stage, leaving game-vs-stage undetermined. Game 105 was DM (no B24 in any row; B0
re-fired 3,3 across two consecutive 3-kill rounds — which under the max model doubles as
independent 07-23 corroboration of DM's per-round stage rotation), so the suicide round
opened a fresh stage and its wire 0 is clamp-confounded under the per-stage reading. Also
reconfirmed from the same rows: **B39 pays ·5** (DM round: 17 = kills·9 + B36·3 + B39·5
exact). Settling experiments: **same-stage suicide** — TDM, bank points in R1, suicide 3× in
R2 of the same stage; wire −6 ⇒ suicides deduct, 0 ⇒ they don't, regardless of scope. Then a
**stage-2 deaths-only round after stage-1 banking** splits per-game from per-stage.

**Addendum, same night:** a 5-suicide round was played as game 127 R1 — but as the first round
of a fresh game its bank was 0 under both scopes, so the wired 0 is predicted by both
hypotheses and discriminates nothing. (It did give B3 its second observation: 5, tracking the
suicide count exactly, alongside B1=5 as the fresh-stage deaths best; and the opponent took
0x21=1 with zero kills — suicides alone lose the round.) The clean experiment needs no bank at
all: **kills and suicides in the same round** (e.g. 3 kills + 3 suicides → 6 if suicides
deduct, 12 if free — both positive, clamp never engages).

### Hacking prerequisites, from the ELF: S. PLUG exists; a SCANNING skill gates it

2026-07-24. Prompted by the Scanning Plug being absent from loadout items. ELF strings pass
(tier 1): the item-name table (ASCII, ~0xdde520–0xddf000, calibrated against CLAYMORE/
MAGAZINE/CHAFF G etc.) contains **`S. PLUG` at 0xddee30** (with companion `S.PLUG_SPR` at
0xddee40) — the Scanning Plug exists in this retail build, under an abbreviated internal
name a "SCANNING PLUG" search would have missed. A skill token **`Skill_Eng_SCANNING` at
0xe0b720** exists alongside the other skill identifiers — consistent with the plug being
granted by equipping the Scanning skill rather than appearing as a free item (matches the
restriction sweep, whose 19 base items do not include the plug). Untested in-game yet.
Also: **no literal `HACK`/`HACKING` string anywhere in the ELF** — the result screen's
HACKING row text presumably comes from localized string tables outside the binary. The ELF's
own score-label cluster (0xdfcaf8–0xdfcbf8) reads `KILLS, HEADSHOTS, DEATHS,
(KILL + STUN) COUNT, WAKE COUNT, (DEATH + STUN DAMAGE) COUNT, TOTAL SCORE` — composite
labels worth remembering when mapping the stats screens.

### The body-dart round settles the headshot category and relabels 0x15/0x17

2026-07-24, engineered discriminator (game 129: Sean 3 body-shot dart stuns + 5 headshot
kills on rawr). Wire score **41 = kills·15 + 0x11·2 (10) + stun·2 (6) + B36 (10) exactly** —
the competing model (a separate `0x15`·2 term) predicted 47 and is dead. Better: **`0x15`
wired 0 despite three ranged dart knockouts, and the victim's `0x17`=0** while his `0x0f`
counted all 3 — so the pair is **stun headshots dealt/received** (hit location, not weapon
class), and the screen's HEADSHOTS row = `0x11` + `0x15`, both ·2. Every earlier "ranged/
tranq knockouts" reading was a coincidence of darts always hitting heads. The sleep-stab
round's `0x17`=1 now reads as the neck syringe counting as a stun headshot (unverified).
Same pull, two more: **B24 = wins, not survivals** — poop survived-but-lost game 127 R2 and
his B24 stayed at 1 (win-but-die remains the last split); **B12** logged a 7 (not
kills+stuns=8) in the dart round and — strangest — a **1 in game 128 whose report was
otherwise entirely zero**: something that neither scores nor registers anywhere else ticks
B12. Worth asking what was done in that round (scan attempts? hold-ups?).

### The hacking round: B19 = hacks ·5; hacks credit assists; the score formula is complete

2026-07-24, engineered 1v1 (game 131: Sean 3 successful SOP scans on poop, 5 kills, 3 stuns,
1 dart headshot). Screen total 67 decomposed exactly on the wire: kills·15 + (0x11=5 +
0x15=1)·2 + stun·2·3 + B36·10 + B37·3·3 + **B19·3·5** — B19's first nonzero ever, equal to
the hack count, matching the screen's HACKING=3x5. That was the last unexercised score
category: **every screen row now has a labelled wire source** (kill 0x05, death 0x07,
headshot 0x11+0x15, hacking B19, assist B37, stun 0x0d, wake B35, other B36+knockout
component). Two extras: **hacks credit assists** — B37=3 in a 1v1 with no teammate, tracking
the hacks (game 129, same kills/stuns but no hacks, had B37=0); and B39's kill-1st ·5 is
DM-only in all sightings, so both ·5 categories coexist (capture-era ambiguity resolved).
First sighting of **B7=1** (unknown); B10/B11 pair hit 11 in this hold-up-heavy round; B22/23
= 3 with the slam-stuns. B12 wired 1 here vs 7 in the body-dart round — candidate "darts
that connected" (7 body darts for 3 stuns vs 1 here), though the old 2-dart-headshot round's
1 doesn't fit; still open. The Scanning skill route to the plug (previous entry) worked
in-game: skill equipped → plug available → crouch-scan on the downed enemy.

### The Personal Stats list is the B-block's Rosetta stone

2026-07-24. The Personal Stats screen enumerates career counters: Consecutive Kills,
Consecutive Deaths, Suicides, Friendly Kills, Friendly Stuns, Times Stunned, Preset Radio
Message Uses, Text Chat Uses, CQC Attacks Given, CQC Attacks Taken, Rolls, Salutes, Catapult
Uses, Number of Boosts Given, Falling Deaths, Times Caught in Trap, Melee Hits, Scans
Performed, Knife Kills, Time in Cardboard Box, Cardboard Box Uses. This recontextualizes
struct B: it is the per-round delta feed for these career stats. Already-labelled slots line
up: Suicides=B3, Scans Performed=B19, CQC Given/Taken=B10/B11, Melee Hits (+taken)=B22/B23,
Times Stunned=0x0f. Consequences: (1) **B0/B1's "best-round kills/deaths" reading now has a
rival — best consecutive kills/deaths (streak)** — indistinguishable in every captured round
because all testing killed one target in unbroken runs (the user's own observation), so
streak = round total throughout. The per-stage reset and store-if-greater machinery hold
under either reading; only the tracked quantity is open. One weak lean: game 121 R1 wired
B0=4 for a 4-kill/5-death player, which under the streak reading requires an uninterrupted
4-run amid five deaths. An engineered kill-die-kill-die-kill round (round kills 3, streak 1)
splits it. (2) The dark slots have candidate names — B12's value history (1 in an otherwise
all-zero round, 7 in the body-dart round, 3 per grenade round, 0 in the stationary lock-on
round) fits **Rolls** or **Preset Radio Uses**. (3) The closing method is gesture rounds:
a counted number of exactly one action per round (rolls, salutes, radio, chat, catapult,
boost, falling death, trap, knife kill, box time/uses); Friendly Kills/Stuns need a
friendly-fire-enabled host (commonA bit 3). Time in Cardboard Box implies a seconds-valued
slot somewhere in the block.

### The kill-die-kill round: B0/B1/B2 are streaks, B36 is streak-combo, and 0x21 is the flawless win

2026-07-24, the engineered discriminator (game 131 R2: Sean kill,kill,die,kill,kill,die,kill
= 5 kills in streaks 2,2,1, deaths never consecutive; poop 2 separated headshot kills, 5
deaths in runs 2,2,1). Four resolutions in one round:

- **B0 = best consecutive kills** (poop: 2 kills wired 1); **B1 = best consecutive deaths**
  (Sean: 2 deaths wired 1); **B2 = best consecutive headshots** (poop: 2 wired 1) — all
  per-stage streak records under the same store-if-greater delta machinery. The user called
  it: all earlier testing killed in unbroken runs, making streak ≡ round total everywhere.
  Sean's own B0/B2 wired 0 (streak 2 vs the same-stage record 5 from R1), doubly confirming
  the records persisted across the round boundary — no rotation between R1 and R2.
- **B36 = streak combo, not a function of round kills**: streaks 2,2,1 → 1+1+0 = 2 on the
  wire, score 23 = 15 − 4 + 10 + 2 exact (round-total triangular would have said 10). The
  "deaths don't reset it" claim from the 4-kill/5-death row is retracted — that row was a
  genuine unbroken 4-run.
- **0x21 = won the round WITHOUT dying** (flawless win): Sean won this round and wired 0.
  Every historical anomaly refits — the 04:13 all-zero round (nobody survived-won; the
  timer-end hypothesis is retired), game 111's "rawr won round A with 0x21=0" (d=1 that
  round), all survive-but-lose zeros, the seven "winner-only" rounds (all flawless), and the
  "transfer on first loss". The oldest open A-slot is closed.
- **B24 counts exactly the 0x21 events per stage** (absolute): the win-but-die round ticked
  neither. Flawless TDM wins this stage — the natural feed for "Consecutive TDM survivals".

### Gesture round one: B7 = salutes, B8 = preset radio, B12 = rolls

2026-07-24, three counted gestures in one round (4 rolls, 3 salutes, 2 preset radio; game
131 R3, plus 5 unbroken kills). Wire: **B12=4, B7=3, B8=2** — three labels in one pull, the
distinct counts making each unambiguous. All prior stray sightings refit: B12's entire value
history is rolls (the "all-zero" game-128 report = one roll; 7 = dodge-rolling the body-dart
round; 3 per grenade round; 0 in the stationary lock-on round — the "darts that connected"
candidate is dead); B7's hack-round 1 was a pre-scan salute; B8's plain-rifle-round 1 was a
radio call. B12 is additionally a **plain per-round count, not max-family** — two 1-roll
rounds in the same stage each wired 1, so the earlier max classification (from poop's
1-then-0 pair) was an over-read; that pair was just one roll then none. Round cross-checks:
new stage (R3) so B0=B2=5 fresh streak records; B36=10 for the unbroken 5-run; score
35 = 15 + 10 + 10 exact; flawless win ticked 0x21 and B24.

### Gesture round two: B20 = box seconds, B21 = box uses; knife kills live in 0x43a2, not B

2026-07-24 (game 131 R4: 4 knife kills + 1 rifle kill, box equipped once and occupied ~60s).
Wire: **B20=66 (time in box, seconds), B21=1 (box uses)** — B21's earlier "stun-adjacent"
reading (a lone 1 beside the slam-faint) is retracted as a coincidence, almost certainly an
unremembered box use in that round. **No slot carried the 4 knife kills**: score 27 = 15 +
1·2 + 10(B36) exact with no knife term, and the round's 0x43a2 tally read {weapon 0x01: 4
kills} + {0x17: 1 kill, 1 hs} — weapon id 1 = knife, so the Personal Stats "Knife Kills"
(and every weapon-specific stat) derives from the per-weapon tallies, not struct B. This
gives round_weapon_tally storage (BACKLOG) a consumer, ending its "no known screen" deferral
rationale. Cross-checks: B24=2 (second flawless win of the stage — absolute count
reconfirmed), B0/B2 masked by the same-stage records from R3 as predicted. Also observed:
**in-game text chat SEND is greyed out** on this client — cause unknown (candidate: RPCS3
keyboard input rather than anything we serve); text-chat-uses slot still unlabelled.

### Struct B ↔ 0x4107: B-index = personal-stats slot − 1, thirteen pairs deep

2026-07-24. Laying tonight's B-block labels beside the 2026-07-23 0x4107 fingerprint table
("The personal-stats screen fingerprinted") shows a systematic correspondence — **the 0x4390
struct-B index is the 0x4107 slot number minus one** — exact for all thirteen
independently-confirmed pairs: B0/B1→slots 1/2 (consecutive kills/deaths), B3→4 (suicides),
B7→8 (salutes), B8→9 (radio), B10/B11→11/12 (CQC given/taken), B12→13 (rolls), B19→20
(scans), B20→21 (box time), B21→22 (box uses), B22→23 (melee hits), B24→25 (consecutive
survivals); B2 = consecutive headshots lands on slot 3, one of the slots the screen never
displayed — consistent. **Predictions for the untested slots** (tier: inference from this
rule, to be confirmed by gesture rounds): B5/B6 = friendly kills/stuns, B9 = text chat uses,
B13 = ENVG time (s), B14 = **unknown** (the dedicated-host-time reading was falsified — see
"Dedicated host sends no report for itself"), B15 = catapult uses, B16 = boosts given,
B17 = falling deaths, B18 = times caught in trap, B25+ = the mode-page stats (bases, SOP
destabilizer, GA-KO...). **Two conflicts, kept honest**: slot 5 "Times Stunned" ↔ B4 — but B4
never ticked across rounds where a player was stunned 5 and 3 times (Times Stunned probably
accumulates from A-block 0x0f instead); slot 36 "Number of Soldiers Trained" ↔ B35 — but B35
is empirically wakes (screen row + exact ·2 score decomposition), so the n−1 rule bends
somewhere in the 30s. The rule also means the server-side accumulation of B deltas per index
IS the 0x4107 record-1 backing store — the serving path for Personal Stats is now fully
sketched: sum round_report detail_counters per slot, plus 0x0f for Times Stunned and 0x43a2
tallies for the weapon lines.

### Greyed-out chat SEND: client-side (RPCS3 OSK), no server lever exists

2026-07-24, ELF trace closing the observation above. The game's only free-text input path is
the PS3 on-screen-keyboard utility (`cellOskExtUtility` in the PRX import table; no `cellKb`
raw-keyboard symbols exist — physical keyboards route through the OSK ext utility). No
command in the protocol carries a text-chat permission: the settings blob, session/profile
families and chat-macro commands have no mute/allow bit (voice chat's `0x0d`/`0x0e` are
recognition/volume only), and the only GUI SEND button in the ELF resources belongs to the
mail composer. The chat bar's `/all`–`/team` labels are hash-resolved text-table entries
(`STRING_ST_CHAT*`, scene `8CHAT_SCBAR`) with no pointer xrefs, so the literal enable branch
was not reachable — the classification rests on the input-path and protocol-field facts. The
one server-relayed candidate, silent mode (commonB bit 2), was already decoded clear
(0x143 = 0x00) in this session's blob audit. Conclusion: RPCS3's OSK commit path never
delivers the buffer; keystrokes echo via passthrough but SEND stays disabled. Emulator-side;
nothing we serve affects it. B9 (predicted Text Chat Uses) stays unconfirmable until the OSK
behaves.

### Gesture round three: B17 = falling deaths, B18 = trap catches; falls are suicides

2026-07-24 (game 132: Sean 3 falling deaths + 6 trap triggers of which 2 fatal; poop owned
the traps). Wire: **B17=3, B18=6** — both exactly as the slot−1 rule predicted (slots 18/19),
and B18 counts triggers, not deaths. **B3=3: falling deaths tick the suicides slot** —
"Suicides" includes environmental self-deaths. Poop's own B18=1 (stepped in his own trap);
his 2 trap kills credited as ordinary kills (score 7 = 6 + B36·1 exact, B0 streak 2).
Sean's B1=5 (all five deaths consecutive), B12=8 rolls, B7=1 (another salute). Suicide-
deduction question still masked: Sean's 0 sits on a fresh-game bank either way. Remaining
unconfirmed gesture slots: B15 catapult, B16 boosts, B5/B6 friendly kills/stuns, B9 text
chat (blocked on the RPCS3 OSK).

### Gesture round four: B15 = catapult, B16 = boosts; suicides DO deduct; the clamp shown mid-flight

2026-07-24 (game 132 R2: Sean boosted rawr 4×, rawr catapulted 3×). Wire: **B16=4 (boosts
given, slot 17), B15=3 (catapult uses, slot 16)** — the slot−1 rule is 17/17. Two score-model
closures rode along: (1) **suicides deduct −2 after all** — rawr's only death was his own
catapult fall (B3=1, B17=1, d=1, no enemy credited a kill on him) and his positive score
decomposes only with the deduction: 29 = 15 − 2 + 10 + 6 exact. The 2026-07-23 "suicides
deduct nothing" is fully retired as clamp artifact; the kills+suicides discriminator round is
no longer needed. (2) **The clamp shown mid-flight**: poop wired −7 for a 5-death (−10)
round on a +7 same-stage bank — store 7→0 clamped, wire = the delta, exactly as modelled.
Remaining unlabelled among ever-observed slots: B5/B6 (friendly kills/stuns — needs the FF
host toggle), B9 (text chat — blocked on the RPCS3 OSK). Bank scope (game vs stage) and the
OTHER knockout component's wire effect stay open.

### Friendly-fire round: B5/B6 labelled; the observable B-block is complete

2026-07-24 (game 133, FF enabled: Sean team-killed poop 3× and team-stunned him 2×, then woke
him twice). Wire: **B5=3 (friendly kills), B6=2 (friendly stuns)** — the B-index =
0x4107-slot−1 rule closes at 19/19. Facts: friendly kills/stuns do NOT tick the dealer's
`0x05`/`0x0d`; the victim's received counters (`0x07` deaths, `0x0f` knockouts) count them
indistinguishably; team kills are score-neutral in this build (Sean's score 2 = wake·2·2 −
death·2 exact — no TK penalty, no credit; operator policy elsewhere, not protocol here).
B35=wakes reconfirmed (2, from waking the team-stunned victim). With this, every struct-B
slot ever observed nonzero is labelled except B9 (text chat, blocked on the RPCS3 OSK).
Remaining 0x4390 opens: bank scope (game vs stage), the OTHER knockout component's wire
effect, flag 0x04, and the never-nonzero `0x19`/`0x1d`/trailing word.

**Verification addendum (same night):** the suicide-deduction decomposition above originally
*inferred* the headshot count from the score rather than reading it — circular as written
(hs=4 would have decomposed the same 29 with no deduction). Pulled from the wire: hs=5, so
29 = 15 − 2 + 10 + 6 uniquely and the conclusion stands, now properly grounded. Also placed
on record after an evidence audit: every score multiplier is confirmed by wire-only
decompositions; the gesture-slot labels depend on the user's action counts (distinct counts
per round make transcription error implausible); the ONE claim resting solely on transcribed
screen values from other players' rows is the OTHER knockout-received component, which
remains marked unproven.

### The full Personal Stats screen, and the 58-slot bound

2026-07-24. The complete screen, in display order (user-read, total list): Instructor,
Consecutive Kills, Consecutive Deaths, Suicides, Friendly Kills, Friendly Stuns, Times
Stunned, Preset Radio Message Uses, Text Chat Uses, CQC Attacks Given, CQC Attacks Taken,
Rolls, Time as Dedicated Host, Salutes, Catapult Uses, Number of Boosts Given, Falling
Deaths, Times Caught in Trap, Melee Hits, Scans Performed, Knife Kills, Time in Cardboard
Box, Cardboard Box Uses, Total Time Using ENVG, Total Time Playing
DEATHMATCH/TEAM DEATHMATCH/BASE/CAPTURE/RESCUE/SNEAKING, Training Mode Time, Combat Training
Time (Instructor/Student), Number of Soldiers Trained, Host Rating, Instructor Score.
Display order differs from 0x4107 slot numbers — the fingerprint table remains the slot
authority. Sources: most rows are 0x4390 struct-B slots (see the rewritten
dev/proto/inbound/mgo2_cmd_4390_c2s.ksy); Times Stunned feeds from A `0x0f`; per-mode play times derive
from seconds+mode per report; Knife Kills is 0x4107 slot 64 — and **struct B has exactly 58
slots, so every stat in slots ≥59 (Victories as Snake 63, Knife Kills 64, Snake Kills 67,
Snake Time 72) cannot be B-fed** — an independent corroboration of knife kills arriving via
the 0x43a2 weapon tallies. Host Rating and Instructor Score have no identified wire source
yet. Total Time Using ENVG (B13 predicted) is testable: the ENVG is a map pickup.

**ENVG addendum (same night):** wearing a picked-up ENVG for "roughly 30 seconds" wired
**B13=28** — Total Time Using ENVG (s), slot 14, confirmed; the slot rule holds 20/20 where
testable. (The same report logged 18 rolls searching for the pickup.) Remaining
[PREDICTED]-only slots are the mode-specific ones (Base/Rescue objectives, training times)
plus text chat (emulator-blocked). *(Later: the dedicated-host-time prediction for B14 was
falsified, and the Base/Rescue/Capture objective slots have since been confirmed — see the
0x4390 ksy for current status.)*

**B24 precision addendum (user challenge, same night):** the "count of flawless wins this
stage" reading is over-specific — every observed stage was 2 rounds, where a count and a
best-consecutive-run are indistinguishable. Tested facts only: the event is win+no-death
(survive-but-lose and win-but-die both proven inert), TDM-only, per-stage with rotation
reset, absolute snapshot. Count-vs-run needs a ≥3-round stage with a flawless/non-flawless/
flawless pattern (count 2 vs run 1); the slot-25 name "Consecutive Survivals" favours run.

### The 6-round stage settles B24: best consecutive flawless-win run, not a count

2026-07-24 (games 135/136, user-engineered after challenging the count reading). Game 136,
six rounds in one stage (rotation logged only after R6): Sean went flawless ×3, died in R4,
then flawless ×2 — B24 wired **1,2,3,3,3,3**. A count of flawless wins would have ended
4,5; the best-consecutive-run record holds at 3 because the post-death run only reached 2.
**B24 = best consecutive flawless-win run this stage** — the slot-25 name "Consecutive
Survivals" was the correct hint, and the earlier count reading was an artifact of every
prior stage being 2 rounds (the user's diagnosis, verbatim). Serving consequence: career
slot 25 = max(career, B24) — the same store-if-greater convention as the other record
slots; runs cannot span rotations on the wire since B24 resets per stage. Game 135
(F,F,F,death → 1,2,3,3) agrees. Same rounds: score 11 = 6+4+1 and 8 = 6−2+4 per round,
B36=1 per 2-kill round, all exact under the settled formula.

### First Sneaking round: nine new B slots; the combo and score formulas are TDM/DM-scoped

2026-07-24 (game 138, ~11 min: rawr as Snake, 9 wire kills / 4 deaths / 4 stuns dealt /
score 94, won; Sean 4 kills / 9 deaths / score 27. User remembered "10 kills" — wire says 9;
unresolved, noted). First data from the B47–B56 region, all previously dark: rawr B47=3,
B48=3, B49=1, B50=4, B54=4, B56=1; Sean B51=4, B53=4, B55=4. Apparent dealt/received pair
structure (rawr B50/B54=4 ↔ Sean B51/B55=4, tracking his 4 stuns = Sean's 0x0f=4); B56=1
matches "one win as Snake" — all candidates only, no labels; SNE needs its own
single-variable rounds. Two TDM-proven models FAIL here and are now scoped accordingly:
**B36=5 with 4 kills is unreachable under the kill-streak combo formula** (possible: 0/1/2/
3/6) — SNE feeds combo from more than kills; and **neither score decomposes under the
TDM/DM formula** (rawr ~65 predicted vs 94; Sean's deaths·−2 would sink his 27) — SNE has
its own categories, consistent with the ELF's SP_SCORE_SNE01/02 tokens. Models intact:
0x21 flawless-win (rawr won but died → 0), CQC pair (6↔6), 0x1f, per-player reporting.
The Snake career stats (0x4107 slots 63/67/72) had no B carrier — nothing above B56 fired;
their delivery path is still unidentified.

**SNE constraint (user domain knowledge, same night):** the Sneaking stats surface shows the
same standard tracking as other modes plus exactly THREE snake-specific stats — Time as
Snake, Kills as Snake, Wins as Snake (0x4107 slots 72/67/63, all beyond struct B's 58). So
the nine SNE-lit B slots are NOT nine hidden career stats: most are presumably SNE score
categories (rawr's 94 carries ~29 points the TDM-style terms cannot explain) or round
bookkeeping, like B36/B37 in TDM. The snake trio must be server-derived from A-block kills/
seconds + mode + role — and ROLE attribution is the open question: nothing obvious in the
frame says who was Snake (both players wired team_slot 0); B56=1 on the winning Snake is the
strongest marker candidate (win-as-snake or the role itself).

**flag_0x04 first light (same round, caught by a full-column re-check):** the 0x04 flag byte
— zero in every report ever captured — is **1 on the Snake's report**. Candidates: Snake-role
marker or SNE-win marker (confounded: the observed Snake also won). One losing-Snake round
splits it, and B56's role-vs-win question, simultaneously. If it is the role marker, all
three snake career stats derive from it + the A-block (seconds=644 and kills=9 on the same
report — no dedicated slots exist for them, verified across every field of both reports).

### Losing-Snake round: flag_0x04 IS the role marker; B56 demoted; B49 the wins candidate

2026-07-24 (game 139: rawr as Snake again, 0 kills, ~2.5 min wire, LOST; Sean 5 kills,
flawless). The discriminator landed: **flag_0x04=1 on the losing Snake → Snake-role marker
confirmed**, win-marker reading falsified. Time-as-Snake and kills-as-Snake are now fully
servable (Σ A seconds / Σ A kills over flag=1 reports). **B56=1 also fired on the loss** —
demoted from wins-as-Snake to rounds-as-Snake candidate. **B47/B48/B49 (3/3/1) appeared only
in the WON Snake round** — B49 is the new wins-as-Snake candidate; B47/B48
objective-flavoured. Sean's B51/B53/B55 trio = his kills both rounds (4 then 5) — degenerate
in 1v1 with snake-deaths readings; open. Model checks: 0x21 flawless-win behaves in SNE
(Sean 1 here; nobody in the died-while-winning round); **B36=7 from 5 kills — second
unreachable value under the TDM combo rule**, confirming SNE feeds combo differently.

### First Rescue round: B28 = GA-KO defended (slot-rule hit); B29/B41/B42 first light

2026-07-24 (game 140 R1: rawr defended the GA-KO and won flawlessly; Sean attacked, picked
it up but never delivered, died once). **B28=1 on the defender** — slot 29 "GA-KO Defended",
the slot rule's prediction, first Rescue data point. **B27 (GA-KO Saved) correctly absent**
— pickup without delivery saves nothing. **B29=1 on the attacker who picked it up** (slot
30, hidden on the stats screen) — GA-KO-pickups candidate. **B41=1, B42=7 first light**
(slots 42/43, hidden) on the attacker, unlabelled (B42=7 ≈ carry-seconds is a guess only).
B30 "Fully Defended Matches" did not fire — either the pickup spoiled it (user's suspicion)
or it ticks per MATCH, not per round. flag_0x04=0 for all — still SNE-only. Rescue scoring
(18 for the defender's 1 kill, 5 for the attacker with a death) is unmapped like SNE's.
Next round of the same game is an engineered idle-out: the long-awaited timer-end null probe.

### The idle timer round: B30 = fully defended (user-predicted); 0x21 refined to non-loss

2026-07-24 (game 140 R2, engineered: both players idle, 327 s timer expiry). The user
called the outcome in advance — "fully defended without a defended": **B30=1 on the
defender with B28 absent** — B30 = round where the GA-KO was never taken (fires per ROUND
despite the "Fully Defended Matches" name), B28 requires an actual defense event. The
defender scored exactly **5 with zero activity** — first Rescue score category sighted
(B30·5 candidate). And **both players wired 0x21=1**: the timer expiry reads as a draw, and
draws flag every zero-death player — same as the historical 0-0 TDM round — so 0x21 is
refined from "won + no deaths" to **"did not lose + no deaths"**. B41/B42 stayed 0 (attack-
run stats, consistent). Row 169 was the usual 4-second exit teardown.

### The goal round: B27 = goals confirmed; the Rescue score table mapped; 0x21 is mode-scoped

2026-07-24 (game 141: Sean picked up and DELIVERED the GA-KO — 1 goal, team win, score 26).
**B27=1 on the delivery** — GA-KO saved = the screen's GOAL×3 row, closing the Rescue slot
trio (B27 saved/goal ✓, B28 defended = TARGET DEFENCE×3 ✓, B30 fully-defended ✓, B29
pickups 2/2). The user's screen gave Rescue's full category table (KILL×7, HEADSHOT×3,
STUN×7, TEAM WIN×5, ASSIST×5, GOAL×3, TARGET DEFENCE×3, OTHER×1) and it validated
immediately: rawr's round-1 18 = 7+3+3+5 EXACT. Rescue HAS a team-win bonus (TDM provably
none) — the idle round's mystery 5 was this, not B30 scoring. B42 (carry magnitude) went
7→21 across the two carry rounds; the Rescue OTHER row tracks it imperfectly (screen 18 vs
wire 21 with rolls=2/B41=1 also present — gap unresolved; the no-delivery round decomposed
OTHER=7 − death·2 = 5 exactly). And **0x21 is mode-scoped**: all six Rescue observations
equal "died zero times" (losing-team survivors flag too), while TDM/DM provably require
not-losing as well. B24 did not tick on the Rescue team win — TDM-only reconfirmed.

### Named-categories SNE round: B50/B51 labelled, B49 sealed, OTHER knockout component wire-proven

2026-07-24 (game 142, rawr as Snake, lost; both score screens read with SNE's own category
names). Wire vs screens: **B51 = SNAKE KILL** (2=2, kills of the Snake, worth 6 points each
— Sean's 22 decomposes exactly only with snake-kills at 6); **B50 = HOLDUP COUNT ×2**
(1 holdup vs 3 stuns this round breaks the earlier stun confound; 138's B50=4 was 4
holdups); **B49 = wins-as-Snake sealed** (absent in both losses, present in the sole win);
B54 = Snake's deaths 3/3 *(**SUPERSEDED** — B54 is times-Snake-was-spotted; it equalled deaths
only because 1v1 spotting is degenerate with killing. See "SNE spotting trio split" below)*;
B56 = rounds-as-Snake 3/3; B47=B48 again (2,2 — dogtag-related
pair; DOGTAG SCORE=16 has no direct slot, so tag values vary) *(**SUPERSEDED** — B47/B48 are
body-searches-yielding-items / dogtags-collected, and are NOT equal in general: B47 >= B48)*. Screen HEADSHOT = 0x11+0x15
holds in SNE (4 = 1 lethal + 3 darts). **The OTHER knockouts-received component is
wire-proven**: Sean's screen OTHER=3 = his c0f=3 with B36=0, and his wire 22 includes it
with no clamp — the last screen-only claim in the file is now tier-2 wire fact; the two old
clamp-hidden sightings validate retroactively. New opens: rawr's OTHER=6 (stuns-dealt ·2
candidate), MK.II KILL ×4 category carrier, the B47/B48 pair, and the b51/b53/b55 trio needs
a multi-player SNE round to split its degenerate copies. *(**RESOLVED 2026-07-26** — the
multi-player rounds were run and the trio is fully split; see "SNE spotting trio split".)*

### First Base round: B25 = bases conquered (slot-rule hit); B40 first light; 0x21 pattern extends

2026-07-24 (game 143: Sean captured 4 bases and won, rawr captured 2 and lost; both screens
read). **B25 = 4/2 = the CONTROL row (×5)** — slot 26 "Bases Conquered", another slot-rule
hit. **B40 first light: 16/8 = exactly captures×4 for both players = the OTHER row** — a
hidden capture-points counter (4 per capture; single round, follow-up pending). B26 (SOP
destabilizer, ×10 category on screen) correctly 0 — awaiting a positive use. Base's
multiplier table: KILL×3, SOP DESTAB×10, TEAMWIN×5, CONTROL×5, STUN×3, WAKE×3 (vs TDM's
×2!), ASSIST×3, OTHER×1; both totals decomposed exactly on the wire (41 = 20+5+16,
18 = 10+8). **0x21: Base behaves like Rescue** — the zero-death loser flagged 1 (8/8 across
the two modes), confirming the mode-scoped condition. flag_0x04 = 0 — still Snake-only.

**SOP Destabilizer addendum (same night):** one engineered use (bought from the Drebin shop)
wired **B26=1**, and the round's 42 decomposed exactly as bases·5 (15) + destab·10 +
teamwin·5 + B40·1 (12) — the ×10 confirmed on the wire, B40's captures×4 rule at 3/3
(16/8/12 for 4/2/3), and the Base slot region closed. (The earlier "client froze" scare
during the shop purchase showed no unhandled commands on any service — client-side hitch.)

### First Capture round: B34 = goals, B46 = put count; every mode has now been entered

2026-07-24 (game 146: Sean 1 goal, 30 puts, won; rawr all-zero). **B34 first light = the
GOAL×5 row** (Capture goals — distinct from Rescue's B27); **B46 = 30 = PUT COUNT×1** —
killing the second training-time slot-rule prediction in that region (fingerprint said
Combat Training Instructor for slot 47). Score 45 = put 30 + goal 5 + teamwin 5 + OTHER 5
exact, but **OTHER's 5 has no carrier slot** (nothing wired 5) — unlike Base's B40-backed
OTHER; client-computed 5-per-goal candidate, open. Capture's table: KILL×5, HEADSHOT×3,
PUT×1, STUN×5, TEAMWIN×5, WAKE×5, GOAL×5, OTHER×1. 0x21: both zero-death players flagged —
objective modes now 10/10 for the result-independent reading. With this, all six rules
(DM, TDM, SNE, RES, BASE, CAP) have been entered and their primary slots labelled.

### Dedicated host sends no report for itself — slot 15 is NOT dedicated-host time (falsified)

2026-07-24. Three dedicated-host games (`0x4310` with `0xA1 dedicated=0x01`, and the client's
max-players bump 16→17, at 17:54:09 / 18:05:50 / 18:14:18) were run to test slot 15 "Time as
Dedicated Host" (struct-B **index 14**). **The host's client emitted no `0x4390` for its own
character in any of them** — the host connection (the same one that sent `0x4310`) reported only
the two participants, ch2 and ch3, and the hosting character has no report of any kind after
17:39:41. **Not a capture miss:** 189 `In - command 4390` frames in the freebattle1 log against 189
archived `.bin` files in `dev/proto/samples/4390` — `watch_4390.py` dropped nothing (its one silent
drop path, an interleaved log line between the DEBUG header and its hex line, would have shown as a
count divergence).

The absence of a host report is, on its own, a non-experiment: a report that never exists cannot
carry the field. The observation that would falsify the label is a report *for the hosting
character* with slot 15 = 0. Under the established delta semantics `0x4390` is per-participant and
a dedicated host is not a participant, so the accumulated hosting seconds stay in the client's live
store — the baseline is rewritten only when a report is emitted for that character — and should
flush in one lump on that character's next played round.

**RESOLVED 2026-07-26: that test had already been run, and the label is FALSIFIED.** The archive
contained the answer the whole time; nobody read frame 190. ch1's reports either side of the
hosting session:

| frame | time | character | struct-B index 14 |
|---|---|---|---|
| #177 | 17:39:41 | ch1 | 0 — last report **before** hosting |
| #179–#189 | 17:59–18:19 | ch2 / ch3 only | ch1 emits nothing across all three hosting games |
| **#190** | **18:54:46** | **ch1** | **0** — ch1's **next played round after hosting** |
| #190+ | — | ch1 ×61 | 0 in every one |

Three stints' worth of hosting seconds had a report to flush into and did not appear in it.
Dedicated-host time is **not** struct-B index 14, and on this evidence is not anywhere in struct B
— the slot has never been nonzero in any of 360 archived frames. Remaining candidates: another
command, or no wire source at all (Host Rating and Instructor Score are already in that category).

Index 14 is now `unknown_b14` / `[UNKNOWN]` in the ksy.

**Container negatives (2026-07-26), which also refine b20/b21.** Two container items were tried
against index 14: sitting in a **trash can** (frame 325) and wearing the **drum can** — a wearable
cardboard-box facsimile, and therefore the closest possible near-miss to the item b20/b21 actually
count. Both wired 0 at index 14, *and* 0 at b20 (`box_time_s`) and b21 (`box_uses`). So:

- `box_time_s` / `box_uses` are **cardboard-box-specific**, not generic "in a container" counters —
  a distinction that had never been tested and was quietly assumed the other way.
- No generic container counter exists anywhere in struct B: if one did, one of these two rounds
  would have lit some slot, and both rounds came back with nothing but `rolls` and the survival
  counter.

Note on method: the slot is `s2`, exactly like all 58 struct-B slots, so the encoding carries no
hint as to whether it is a duration or a count. Only magnitude on a live trigger distinguishes the
two families (time slots read as plain seconds — `envg_time_s` wired 28 for ~30 s, `box_time_s` 66
for ~a minute; counters sit in single digits), and index 14 has never fired. Settling what it *is*
wants the ELF, not more wire guessing.

### SNE spotting trio split — B51/B53/B55 were one mechanic misread three times

2026-07-26. The `b51/b53/b55` trio, logged above as "needs a multi-player SNE round to split its
degenerate copies", is resolved. Three-player SNE rounds had in fact already been captured; the
split was sitting in the archive unread.

**The mechanic: a "spot" is triggered by SHOOTING Snake**, not by passively sighting him — the
alert symbol is the reveal a hit causes. That single fact explains every wrong label this cluster
has carried. A one-shot kill fires a kill, a spot and a first-spot in the same Snake life, so any
round decided by clean kills makes all three numerically identical. `sum(B53) == sum(B51)` in
**11 of 22** completed rounds — half the corpus was degenerate by construction, which is why
"kills-of-Snake", "deaths-as-Snake" and "third copy of kills-of-Snake" all fitted at the time.
They were not three independent mistakes.

Readings, over completed (`round_completed=1`) reports only:

| slot | reading | evidence |
|---|---|---|
| B51 | Snake kills | screen SNAKE KILL row, 6 pts/kill exact |
| B53 | times **this player** spotted (hit) Snake | Snake's B54 == Σ others' B53, **22/22** rounds, 15 with three players |
| B54 | times Snake was spotted, **total** | same relation, Snake side |
| B55 | **first** player to spot Snake, once per Snake life | Σ B55 == Snake's death count, **22/22** (== 1 in the four rounds he survived but was spotted) |

B55 counts **lives, not spots** — round `091106` is the clean separation: `sum(B53)=10` spots
against `sum(B55)=5`, with the Snake dead 5 times. Three-player rounds are what make B53/B54 real
rather than a 1:1 identity: 1+3→4, 3+7→10, 1+1→2, 1+3→4.

Naming is snake-specific because the mechanic is: **Snake is the only character the alert/spotted
state applies to**, in any mode. There is no generic "spotted a player" counter for these to be a
facet of, which is why B53/B54 are 0 in every non-SNE report across all 360 archived frames.

**Method note, applies to every slot, not just these.** All four apparent violations of the
B53/B54 role split were `round_completed=0` teardown frames from crash disconnects. Teardown
reports carry unreliable role and marker fields — `flag_0x04` reads 0 even for the Snake (frame
201, `flag_0x04=0` with `B56=1`) — and mixing them into a population manufactures counterexamples
that look like unmodelled game mechanics. Excluding them took the role split from "four exceptions,
possible Snake-role handoff" to **zero exceptions**, and the B54 sum relation from 22/23 to 22/22.
There is no handoff mechanic; that hypothesis was an artefact of a dirty sample. Filter
`round_completed=0` out before deriving anything from struct B.

**Test design consequence:** a round intended to separate this cluster must **hit Snake without
killing him**. Kill-based rounds cannot distinguish B51/B53/B55 no matter how many are run.

### B47/B48 are Snake-side only

2026-07-26, from the same 360-frame archive. The dogtag pair fires **exclusively on the Snake's
report**: all 13 completed frames carrying either slot have `flag_0x04=1` and `B56=1`, and no
attacker report has ever carried them. Mechanically consistent — dogtag collection is the Snake's
objective — but it was not recorded, and the previous wording ("the player…") invited looking for
these on an attacker's report, where they cannot appear.

`B47 >= B48` in 13/13 completed frames where either is nonzero: equal in 9, **strict in 4** —
frames 233 (4/3), 238 (1/0), 266 (1/0), 196 (5/3). Those four are what establish these as two
distinct slots rather than one counter: a body search can yield an item without a dogtag being
collected, so B48 is structurally bounded by B47. Counts exclude the `round_completed=0` teardown
frame at 070239, which would otherwise read 14/14 — see the filtering rule under "SNE spotting
trio split".

Still open: the SNE DOGTAG score row's multiplier, **and which of the pair feeds it**. The single
decomposed round (~16 points across two tags) had `B47 == B48`, so it cannot separate them. Needs
a round where the two differ with the DOGTAG row read off the result screen.

## The mailbox, live — 2026-07-26

A single session in the automatching lobby brought the mail family up from nothing. Every claim
below is from that session's traffic or the client's visible behaviour; the ELF addresses are the
mechanism, the observation is the evidence. The `.ksy` files carry the byte detail —
`dev/proto/{inbound,outbound}/mgo2_cmd_48*.ksy`.

### The first live capture to validate a generated blank spec

`0x4800` was specced from the disassembly alone on 2026-07-26, before any capture of it existed:
`{u8, char[128], char[128], char[708], s8, s8}`, 967 bytes. The operator then composed a letter —
recipient `poop`, subject `hi`, body `poop` — and pressed send with no handler registered, so the
server logged the whole payload.

It was **967 bytes**, and the three typed strings landed exactly on the three blocks the spec had
marked as candidates: `poop` at `0x001`, `hi` at `0x081`, `poop` at `0x101`. Three distinct values
in three distinct fields from one action — the fingerprint pass the spec had asked for, run by
accident. Field order, widths and total size were all correct sight-unseen.

A second send (`sub` / `mes`) reproduced it. The leading byte read **1** both times, and the two
trailing bytes **0**.

### The leading byte of a 0x4822 entry is a routing index, and 0x0F corrupts the client heap

Our first served mailbox echoed the `0x4820` request's selector (`0x0F`) into wire byte 0 of the
entry. The client accepted the packet, displayed nothing, and the **GM tab disappeared from the
mailbox screen** and did not return on re-login.

`0xD347E4` uses that byte as an unchecked array index (`extsb r3,r11` at `0xD34844`; the only
guard is `count < limit`). Valid values are 0..3 — four arrays of 16 records, 280-byte stride, at
`mailBlock+0x1E268` — plus 4, a flat view aliasing 0 with a limit of 64. With 15 it reads its
count from `mailBlock+0x1E26F`, which is `name[5]` of category 0's first record, then writes 280
bytes at `mailBlock+0x2E8E8` — **26,816 bytes past the end of a 0x28028-byte allocation**, once
per entry.

The UI-facing wrappers (`0xD5415C`, `0xD542A8`) *do* validate this value; only the packet path
does not. The `0x0F` itself is legitimate in the `0x4820` **request**, where it is a compile-time
literal at `0xD534C8` — it simply has no business in the record.

*Caveat kept deliberately:* the tab-strip construction was traced and found unconditional (five
widget ids set in one straight-line block at `0x8E3E64`, `0x8EA66C`, `0x8EB948`), and no
server-supplied field gates it. That is a strong negative, not an exhaustive one — the widget that
instantiates the five tab items was never positively identified. The corruption is proven; that it
is what removed the GM tab remains inference.

### Category 1 is the Sent tab, and the client echoes the category back

With inbox served as category 0 and sent as category 1, a letter appeared under **Sent**. Opening
it produced `0x4840` with payload `01 00`, and deleting the second letter produced `0x4880` with
`01 01` — so both commands are `{s1 category, u1 index}`, both echo the category **we** assigned,
and `index` is a per-category message handle rather than a display position.

Which tab categories 0 and 3 draw is still unproven: the labels live in the language resource, not
the binary. Category 2 has no UI reference at all. The settling experiment is four entries with
categories 0/1/2/3 and distinct subjects, then read the tabs.

### Both tabs request the same mailbox selector

Every `0x4820` in the session carried `0x0F`, whichever tab was open. The inbox/sent split is
therefore entirely client-side, driven by the entry's category byte — the request cannot express
it. This is why both lists are served in one reply.

### 0x4581 carries a result code, and sending a count fails the screen

Serving the entry **count** in the roster start packet gave *"Unable to acquire Friend List.
(1002:00000001)"* for a character with exactly one friend — the dialog number **was** the count,
stored verbatim as the transaction's failure code (`0xD46AB4`–`0xD46B20`). Identical mechanism to
the `1032:00000005` already recorded for the `0x4680` family.

It hid because an empty roster sends a count of 0, which is also the success code. Every list
triple in this protocol works the same way: start and end are results, and the client counts the
item records itself.

### Read state does not survive a re-login unless the server stores it

Opening a letter marks it read in the client's own record (`0x8E2CD8`), but `0x4821` zeroes all
four category counters and the lists are rebuilt from the `0x4822` entries that follow, so an
unrecorded read comes back as new. Observed directly: open, log out, log in, still "new". There is
no "mark as read" command — opening is the only signal, which is why `0x4840` has to persist it.

The same argument applies to deletion, which has **no wire representation at all**: the 266-byte
entry is fully accounted for without a deleted flag, and no mailbox command carries one. A letter
is deleted by not being sent next time the list is built — so "deleted by the recipient but still
in the sender's Sent list" exists only in server storage.

### Re-send is a new letter

The client's "re-send" on an existing letter emits a plain 967-byte `0x4800`. There is no edit or
update command anywhere in the flow, and the second letter arrived as a second row.

## 0x4400 — in-game chat, decoded live 2026-07-26

Typing in the in-game message box sends `0x4400`, 129 bytes, and nothing in the server answered
it — the only `No handler` line in a full session across all six servers. Four samples, typed in a
GAME lobby, trailing NUL padding elided:

| typed | payload head | reading |
| --- | --- | --- |
| `hi` | `00 30 68 69 00` | channel 0, `'0'`, `"hi"` |
| `hello` | `00 30 68 65 6c 6c 6f 00` | channel 0, `'0'`, `"hello"` |
| `/team team` | `01 31 74 65 61 6d 00` | channel 1, `'1'`, `"team"` |
| `/all all` | `00 30 61 6c 6c 00` | channel 0, `'0'`, `"all"` |

Layout: `u8 channel` (0 = all, 1 = team), then the 128-byte blob the ELF could only see as an
opaque copy, which is one ASCII digit followed by the NUL-terminated message text, zero-padded to
width. Full field notes in `dev/proto/inbound/mgo2_cmd_4400_c2s.ksy`.

### The `/all` and `/team` prefixes never reach the wire

`/all all` arrived as `"all"` and `/team team` as `"team"`. The client parses its own command word,
sets the channel byte from it, and sends only the body. A server that tries to parse a leading
`/all` out of the text field will be looking for something that is not there.

### The ELF's "not a string" inference was wrong

`mgo2_cmd_4400_c2s.ksy` argued from the builder's missing length check (`0xD52D90` copies 128 bytes
unconditionally, unlike `0x43C0`'s length-checked comment field) that the payload must be a
fixed-size record rather than a string. It is a string. The caller pre-pads the buffer to 128 bytes,
so the builder has nothing left to check — absence of a length check at the send site says nothing
about whether the content is text.

### The second byte is the real channel, and the first is only a coarse flag

Byte `0x01` was `0x30 + byte 0x00` in 4 of 4 captures, recorded at the time as a tracking
relationship pending a divergence test. **The ELF supplied the divergence without an experiment
[2026-07-26].** The send path builds four channel digits, `'0'` to `'3'`, and sets the leading
`kind` byte to `0` for digits 0, 2 and 3 and to `1` for digit 1 (`0xCA0A70`, `0xCA0B30`-`0xCA0B48`).
So:

- **the ASCII digit carries the channel**, and the receiving client computes it as `digit - 0x30`
  (`0xC9FF94`);
- **`kind` is a coarse public/team flag only**, and the two disagree for channels 2 and 3.

Our four captures only exercised channels 0 and 1, where they happen to agree — which is exactly
how a tracking relationship turns out to be a coincidence of the sample. Neither byte may be
derived from the other, and a relay must echo the digit the sender sent.

Channel 3 is not a game channel at all: it resolves speakers against a server-supplied table at
`netctx+0xD928` (`0xD491F8`, entries stride `0x1C` from `+0x17C`) instead of the game roster
(`0xCA00CC`-`0xCA0168`). Clan or friends is the obvious guess; [UNKNOWN] which, and untested.

### A missing chat reply does not stall immediately

The message silently vanished and the session carried on (`0x4398` two seconds later), so the
absent `0x4401` is a latent `FFFFFF60`, not an immediate one — some UI path waits on it and the
send path does not. Which path is [UNKNOWN].

### The server must fan 0x4401 out to every player, sender included — settled from the ELF

Traced 2026-07-26 and **not ambiguous**. Three findings, each read from the disassembly:

- **There is no local echo.** The `0x4400` caller falls straight into its epilogue at `0xCA0A98`
  after `bl 0xD52CEC` and never touches the display record. The sender's own line can only arrive
  as an inbound `0x4401` — which is exactly what we saw live, four messages typed and none
  displayed.
- **`0x4401`'s parser is the only producer of the display fields in the whole binary**
  (`0xD52C84`, `0xD52C98`, `0xD52C9C`). Nothing in the P2P/session code writes them, so there is no
  second route by which another player's text could reach the screen.
- **The `u32` is the speaker's character id**, matched against all 24 roster slots at `0xC9FFD8`
  (`entry+0x60`, populated from the peer-join stream at `0x276660`/`0x27687C`) to attribute the
  line. It is the same value the server put at offset `0x000` of that speaker's `0x4101`
  (`netctx+0x57D8`, written by the `0x4101` parser at `0xD3C160`). Plain big-endian binary, not
  ASCII decimal. If it were only a self-echo the client would not need the scan — it already knows
  its own slot (`0x26E980`).

A sanitising/filtering server is still possible on top of this — the client displays whatever text
it is given — but filtering cannot be the *only* mechanism, because other players' text has nowhere
else to come from.

**Field offsets corrected.** The earlier trace recorded these as `ctx+0x14C8/0x14CC/0x14D0`. The
parser does `addis r9,r28,1` at `0xD52C74` first, so they are `+0x114C8`, `+0x114CC` and `+0x114D0`
on the global net-session object (`0x2810E0`). Searching for the un-adjusted offsets finds only
unrelated objects, which is why the consumers were not found before. The three fields are one
record — `{u8 flag; u32 speaker; char text[129]}` — reset together by `0xD34304`, consumed by a
read-and-clear at `0xD33FF4`.

**UI event `0x30` carries no independent meaning.** `0xD33CD8` is a generic "command N arrived"
notifier with a callback table at `netctx+0x11388 + 4*id`; event `0x30` is fired only by the
`0x4401` parser (`0xD52CB0`) and `0x31` only by `0x4442`'s (`0xD52900`). The `0x31` branch
(`0xCA0060`) is the error-ish shape — a canned system line from two string ids, touching none of
the three fields — which is what a "request completed" notification looks like here, and `0x30` is
not that.

### Wrong speaker ids degrade to unattributed lines, not errors

The parser validates nothing beyond the reads succeeding, and the consumer displays the text
whether or not the `u32` matches a roster slot — unmatched leaves the slot at `0xFF`. So a wrong id
looks like a *rendering* bug, not a protocol failure, and will not stall the client.

This matters for us specifically: `roster_entry+0x60` is populated by the in-game session
peer-join stream (`0x276660`), not by any TCP command. It is the first word of the 20-byte peer
descriptor the port check feeds — layout and addresses in `dev/docs/STUN.md` "Where the checked
address actually goes". If our server does not drive that path so
each entry holds the peer's `0x4101` character id, chat text will appear with no name attached.
Untested.

### Chat served and confirmed live — 2026-07-26

`0x4400`/`0x4401` implemented and tested with two clients in a Combat Training lobby. Confirmed:

- **The fan-out design is right.** Every message logged `delivered to 2 of 2 players in the game`,
  with two different characters (1 and 3) sending, and the messages rendered.
- **The `u32` is the speaker's character id — now tier 2, not just tier 1.** Lines render *with the
  speaker's name attached*, which is only possible if the id matched a roster slot at `0xC9FFD8`.
  That also retires the risk flagged when this was implemented: `roster_entry+0x60` is populated
  under our deployment, so we do drive whatever fills it. Untested whether that holds in a real
  game as opposed to training.
- **The channel digit and `kind` pair as the ELF said.** The handler logs a warning on any
  combination outside `0/0, 1/1, 0/2, 0/3`, and across all four sends it never fired.

Open, and the cheapest experiment outstanding:

- **Team chat (channel 1) was delivered to both clients, but reportedly only the sender saw it.**
  The sender was the instructor, so this is not conclusive — the second player was never asked. If
  the second player genuinely cannot see it, the client filters team chat by team membership
  locally, our whole-game over-delivery is harmless, and persisting the `0x4440` team byte is
  cosmetic rather than required. If they *can* see it, team scoping has to be enforced server-side
  and the team byte must be persisted first. One observation from a second player decides it; do
  not implement team scoping before asking.

Note the server relays message text verbatim — no word filter. The retail game had one, so any
filtering here is operator policy, and the client will display whatever it is handed.

## The clan family, live end to end — 2026-07-27

Twenty-three commands answered in one session, with a real client in front of every screen. The
byte-level result is in `PROTOCOL.md`, "Clans"; what belongs here is **how it was found and what
was believed that turned out to be false**, because almost none of it came from disassembly.

The method: answer every id at once in the shape its parser demands, open each screen, and watch
which branch comes alive. Every field we started populating **truthfully** unlocked a branch that
had been dormant, and those unlocks were the real instrument. `0x4b48` did not appear at all until
a character actually had a clan. `0x4b42` (Apply to join) refused to transmit — returning `-24`
without sending a byte — until `0x4b81` carried a non-zero `subject_id`, because the sender checks
the session clan record first. Neither could have been provoked by a better trace.

### Falsified live, and worth keeping

- **"`0x4b46` does not block."** Recorded in its own spec as proven by a live trace, with a warning
  against replying speculatively. True in the connect burst, where it fires unprompted; false from
  the clan menu, where it stalls with `1933:FFFFFF60`. One command, two contexts, one of them
  tested. This is the single most reusable lesson of the session: **a non-blocking observation is
  scoped to the screen it was made on.**
- **The 768-byte block is an opaque blob.** It is the clan **emblem**. It was briefly filled with
  pending applicant names on the theory that 768 = 48 × 16 made it a name table — i.e. we were
  writing text into the client's emblem buffer.
- **`0x4b11` carries `{total, offset}`.** It carries `{offset, total}`. The indicator read "2 out
  of 1" and the record count never enters that string at all, which is why changing the rows
  changed nothing.
- **`T+0x904` is the founding date.** It is the **notice's** date. The field had been found
  honestly — by sending every candidate slot the date offset by a different number of days and
  reading which one the screen showed — and then a label was layered onto a real observation. ~~The
  founding date is `T+0x18`.~~ **That replacement was itself wrong** — `T+0x18` is the leader's
  character id, and the ELF shows this struct has **no founding-date field at all** (2026-07-29, see
  the leader-badge entry above). Correcting a mislabel by moving the label is the same mistake twice.
- **`T+0x48` is the emblem re-display cooldown.** [ELIMINATED] Sending the real display time
  changed nothing; the emblem could still be re-displayed immediately with a fresh `0x4b21` in
  hand. This one is a *valid* elimination: the confirming observation (a countdown appearing) was
  well defined, and it did not appear.
- **Emblem editing is a privilege bit.** It is not. Granting a leader all sixteen bits of the word
  at `profile+6838` produced a "!" badge and a **hard poll loop, re-sending `0x4b46` every ~73 ms**,
  because `0xAB0074` returns without advancing its state machine while any intolerable bit
  survives. Bit 8 alone — the one bit a leader's `-257` mask tolerates — gave the badge and no menu
  row, and emblem loading worked with or without it. The word is a **notification mask the client
  drains**, and applying an emblem is gated on membership state 2 alone.
- **Applicants are a roster concept.** They are **mail** (`0x4820` type `0x10`). There is no
  applicant-list command in the client's flow, which is why it never sent one however we answered.
- **Two `0x4b71`s, by analogy with `0x4105`'s cumulative/weekly pair.** The first reply completes
  the request slot and the second arrives unexpected: `1931:FFFFFF60`.

### The acknowledge-only table

A dozen ids were answered with a bare success while doing nothing. It stopped the stalls, and it
converted "unimplemented" into "silently reports success" — disband, banish, transfer leadership
and set-emblem-editor all reported working. It is gone and must not come back. **A command with no
implementation should stall visibly or return an error.** A stall is a bug report; a false success
is a bug that never gets reported.

## The character list broke the moment a second character existed — 2026-07-27

Two independent errors in `0x3049` that **cancelled to exactly 52 bytes**: the writer introduced
the first entry with its name and every later one with a 4-byte index, and wrote 28 bytes of
appearance where the layout has 31. There was even a documented explanation for why the
inconsistent writer was nevertheless right (an index `00 00 00 nn` has three leading zeros that
complete the previous entry's trailing `u32`). It was wrong, and it was invisible for as long as
every account had one character.

Then the same shape of bug again, hours later: `selected_slot` was hardcoded to 0. The client
**re-fetches the list after `0x3103` and takes its selection back from that header**, so choosing
the second character and entering the lobby logged the player in as the first.

The common cause is worth stating on its own: **every field in a single-entry list looks right
whether or not it means what we think it means.** Any list packet validated against one row is
untested.

The entry's trailing `u32` at `+0x30` is the **per-character delete cooldown in seconds**, which
the client formats itself (`0x9510B4`) — the one cooldown of three this build can display.

## `0x4221` carries real data; the level field is still open — 2026-07-27

The player-details card had been left serving its own fingerprint payload — `FP-DTL-*` strings and
numbered constants. The probe worked, the field map was written down, and then nobody filled it in,
so the clan rendered `----` until the player opened More Details (which fetches `0x4103`, and that
*does* carry a clan). The value looked like it was arriving late when this packet simply never had
it.

**Sending the clan name was not enough.** Wire `0xa7`/`0xab`/`0xbb` are `{u32 id, char name[16],
u8 state}`, and every reader traced so far **checks the id first** and treats 0 as "no clan"
whatever the name says.

**Play time has one definition now**: the sum across game modes, because the client totals the
per-mode column itself. Sending the raw stored aggregate read six times short. (That the total is
inflated at all is a separate, open problem — we store one number and write it into every mode
row.)

**Open: LEVEL renders as 0.** Four candidates sit between the name and the play time — wire `0x18`
(u32), `0x1c` (u8), `0x1d` (u8), `0x1e` (u32) — and a live probe is in flight carrying 1450 / 250 /
130 / 500, chosen so each maps to a *distinct* level (10 / 2 / 1 / 4) through the client's own
experience table. Whichever level the card renders names the field. **Nothing is concluded yet.**

## The search "case sensitive" byte means the opposite — 2026-07-27

Searching for `bob` with **Case Insensitive** selected on screen arrived as `{0, 1}` and matched
nothing against a character named `Bob`; the client reported "Unable to locate that character" —
correctly, since we ran a case-sensitive query. `1` means **ignore case**.

The polarity is the client's, not a per-screen quirk: the clan-search screen sends the same
`{0, 1}` from its own toggles. Both `0x4600` and `0x4b90` now read it that way.

Note where the wrong reading came from. An integration test asserted it, and **its only authority
was the field's own name** — no capture, no disassembly. The ELF cannot settle this either: the
builder stores the argument and never tests it. Per `CLAUDE.md` that assertion was a regression
guard wearing the clothes of a correctness check.

## `0x4112` blocks — the wait-slot prediction paid off — 2026-07-27

`COMMANDS.md` had listed `0x4112` as reachable-but-never-stalled, while noting from the ELF that it
registers **wait slot `0x18`** (`li r4,24` at `0xD3BEDC`) and therefore *should* block. It fired
after a player search and stalled the screen exactly as predicted. It is answered now with a bare
`0x4113` result; the 32 bytes it carries are still unidentified:

```
0000 1000 0000 0000 1110 0000 0000 0000 0000
```

Whatever setting they hold will not persist until someone works out what they are. Answering it
only stops the stall, and saying so is the point.

## The TIPS panel is an HTTP document, not a packet — 2026-07-27

Full write-up in `HELP.md`. Two misdiagnoses preceded it: Community Support was assumed to be a
lobby command, and the Personal Data tips panel was assumed to be the **news list** — every news
row was replaced to test that, which changed nothing, because the panel was showing the probe's
fallback stub for a path we did not serve.

The client fetches `help/<category>_<id>.txt` over HTTP and parses exactly two tags: `<title>` and
`<page-break>`. **Pages are a property of the file, not the request** — the page counter is
`page-breaks + 1`, parsed from the document — so serving one page per file yields a single page
with no counter and no L1/R1, which was the symptom. The caption is chosen by category alone, so
the server cannot change the word "TIPS"; only the title node is ours.

## The 0x4390 frame traced end to end — 2026-07-27

Five parallel ELF/disc passes closed the command. Field-by-field evidence lives in
`dev/proto/inbound/mgo2_cmd_4390_c2s.ksy`; the narrative and the score table are in `PROTOCOL.md`. What
follows is what *changed*, including the readings that turned out to be wrong.

**The storage model.** The frame is built by a dumb serializer at `0xD42178` — 58 identical
`lwz`/`sth`/`put_u16` triples, no logic — whose single caller `0x27D5B0` holds every semantic
decision. Both structs are views of one 152-byte per-player blob of 76 u16 counters (index `n`),
live at blob `+0x1a + 2n`, baseline at `+0xb2 + 2n`, base `0x1610568 + slot*0x510`. Struct A
carries n00..n15, struct B carries n17..n74 **through a permutation**. n16 is dead at both ends;
**n75 is alive but never transmitted** — it is the result screen's OTHER row.

**Why the writers were hard to find, and the correction that unblocked them.** The first pass
concluded the counters were bumped by direct stores, because a sweep of constant keys at the
record-API call site found only the whole-block zero and two running-max updates. That was half
wrong. Gameplay reaches the blob through a thin wrapper `0x6A9758(base, key, len, u16)`; the
constant key is one frame up, at the `bl 0x6a9758` site. Enumerating all 152 of those sites is
what named the remaining slots. **Every bump computes `min(v+1, 0xFFFF)` — counters saturate,
they do not wrap**, so PROTOCOL.md's old "any above 65535 wrap" was wrong.

**Readings that were wrong and are now corrected:**

- **`0x23` was never a team slot index.** It is a **team win flag** — column 5 of the score table,
  worth 5 in Rescue/Capture/Sneaking/Base/TSNE, the long-missing wire source for the "TEAM WIN ×5"
  category. A slot index is constant per player per game; this flips 50/22/32 times for ch1/ch2/ch3
  across 239 archived rounds, and where players disagree the round's top scorer holds the 1 in
  **96 cases against 5**. Both readings predict 0 in DM, which is how the wrong one survived.
  *The server's `round_report.team_slot` column still carries the old name and now stores a win
  flag under it.*
- **B45 was not `training_mode_time_s`.** It is the Team Sneaking goal-delivered count. The trap
  was well set: slot 46 on the stats screen genuinely IS one of exactly six time-formatted slots
  (14, 15, 21, 46, 47, 48), so every check short of finding the writer would have confirmed it.
  Fifth failure of the "B-index = slot − 1" rule in that region.
- **The score is not a banked store.** It is recomputed every tick by `ComputeScore` (`0x6FA408`)
  and clamped to [0, 65535] by `0x71B470`. "Does the bank reset per game or per stage?" was a
  malformed question and is retired.
- **The missing stun deduction was half guessed correctly.** It is on `knockouts_received`
  (−2 DM, −1 TDM, −1 SNE) and **B4 self-stuns have no coefficient at all**.
- **The OTHER row cannot be reconstructed from the wire** — it is n75, which the frame omits.
  Years of fitting it to B36 + knockouts-received + "mode extras" were fitting around an absent
  counter. B42, the prime suspect for Rescue's OTHER, scores zero in every rule.
- **A blanket "exclude round_completed=0 frames" rule was wrong for counters.** Right for role
  fields, wrong for everything else — and it was manufacturing the anomalies this file recorded as
  unexplained. Frame 058's "unexplained residual" was simply frame 056, an excluded teardown
  report from the dealer one second earlier. Including teardown frames takes four separate
  conservation laws to exact (deaths 97/98 → 100/100, headshot deaths 85/86 → 86/86, b53/b54
  23/23 → 25/25, knockouts 25/26 → 26/26).
- **The dealt/received pairs are round-level conservation laws, not pairwise mirrors.** Pairwise
  they hold only in 1v1 (5/14 in three-player rounds). The knockout law needed a third term
  nobody had noticed: `Σreceived == Σdealt + Σb04 + Σb06`, where b06 is friendly stuns.

**A hypothesis raised and killed the same day.** The struct-B permutation looked like the
explanation for the slot-rule exceptions at b35/b46/b47/b48 — wire order vs storage order. Tracing
the 0x4107 parser `0xD3DB1C` killed it: that record follows the same slot order as struct B for
slots 1..63, and its only permutation is above slot 63 (wire 64 → mem 71, 65 → mem 72,
66..73 → mem 63..70, confirmed live because Knife Kills is drawn from `rec+0x11C`). The two
permutations never interact. **The exceptions are genuine and still unexplained.**

**Five slots are Team Sneaking, which is why they read 0 across the whole archive.** Rule 7 is
identified from the UI's rule-name jump table at `0x9C2864`, and each slot's writer sits in a
`cmpwi 7` branch whose sibling `cmpwi 2` arm writes a confirmed Rescue slot: B45/B27 goal,
B43/B41 first pickup, B44/B42 carry time, B32/B53 and B33/B54 the spot pair. Nothing was wrong
with these slots — the mode had simply never been played.

**One slot is provably inert.** B14 has no writer anywhere in the binary. That is a stronger
statement than "never observed nonzero", and it is the only slot in the frame that earns it.

**Still open:** B38 (writer found, but it is a script-bound listener with no caller, no string and
no notifier id — naming it needs the GCX layer or a live watchpoint); the b35/b46/b47/b48
slot-rule exceptions; and the `experience_total` anomaly, now known to be a **u16** (blob key
`0x164`, writers at `0x276340`/`0x2780BC`) that will wrap — the archive maximum is already 49900.

## A confident negative about b14 was overstated — 2026-07-27, later

The 0x4390 write-up above published b14 (live n31, blob key `0x58`) as **structurally incapable of
ever being nonzero**: an exhaustive sweep of all 152 `bl 0x6a9758` bump sites had found no site
carrying `li r4, 0x58`, and the conclusion drawn was "no experiment will ever move it; treat as a
permanent zero". That went further than the evidence supported, and it is retracted pending a
re-audit.

**What broke it.** Chasing b38 through the GCX layer found that its supposed sole writer — a
"script-bound listener with no caller" — is **dead code**: the block at `0x6EC250`..`0x6ECA98` has
a descriptor (`0x1014868`) absent from the native-command registry, its byte pattern occurs nowhere
in the 17 MB binary at any alignment, and no branch targets it. The real writer is **event 8 of a
host-only player-event dispatcher `0x6ED650`**, storing key `0x72` at `0x6ED784` from a `li r4,114`
at `0x6EDA00`.

The dispatcher routes ~15 events through **one shared increment tail** at `0x6ED760`. That is
fatal to the method the sweep used: recovering a key by scanning backwards for the nearest
preceding `li r4, KEY` cannot distinguish keys that converge on a single store, and it
demonstrably missed `0x72` entirely. A method that missed one key can have missed `0x58`, and the
dispatcher's higher event ids are precisely where a lone writer would sit unseen.

**The rule this violated is already written down** in CLAUDE.md: *an elimination is only valid if
you can state the observation that would have confirmed it, and check that the experiment actually
produced that observation.* The sweep's confirming observation would have been "a site carrying
`li r4, 0x58`" — but the search could not reliably produce that observation for any key behind a
shared tail, so its absence proved nothing. The negative was accepted because the sweep was
described as exhaustive over call sites, which it was; exhaustive over call sites is not the same
as sound about keys.

Both "no writer" negatives — b14 (`0x58`) and the unwired n16 (`0x3a`) — are therefore back to
[UNKNOWN] until each `bl 0x6a9758` key is re-derived by following control flow into the call.
Nothing else from that pass is affected: the slots named by mode-guarded twin branches
(`cmpwi 2` Rescue against `cmpwi 7` Team Sneaking) were each read from their own branch, not from
a shared tail.

**b38 itself came out well.** It is host-side, fires on a self-inflicted death in player state 191
(sole raiser `0x778D20`, preceded by a kill whose victim is the killer, on the `player->[0x90] ==
191` branch of the death-cause classifier `0x778380`), and is gated on bit `0x4` of the round flags
byte the host pushes in `0x4310`. State 191 and bit `0x4` are attached to no string, hash, error
code or script token anywhere, so it stays deliberately unnamed. Falsifiable prediction: b38 and
b03 (suicides) must move together on the same player in the same report.

**Also settled, exhaustively:** the score table's missing rows do not exist. Only five stages carry
real scripts (n002a, n003a, n004a, n007a, n012a — r_sneak_n and r_sna01_n are stubs with a single
print statement), each emits exactly seven `command [35706d]` blocks, and the seven rows are
byte-identical across all five. No hidden BASE variant behind rule 6, no COOP table behind rule 8.
And the GCX layer binds no stat keys at all — the only stat-adjacent directive in any `.gcl` is
`-rule/-score`, so "targets captured" is not named there either.

## One GA-KO pickup moved two slots, and the partition reading died — 2026-07-27

Two live Rescue rounds (game 227, one pickup by the same player in each) wired **b41 = 1 and
b29 = 1 in both**. That refutes the partition published hours earlier — "b41 = the round's first
grab, b29 = every grab after it" — which predicts b29 = 0 when there is only one pickup.

The ELF trace behind the partition was real as far as it went: `0x706BB8` keeps a per-round latch
(bit `0x100` of `[this+0x668]`, tested `0x706CA8`, set `0x706D08`); the first grab takes the
unlatched path to b41's writer at `0x706E30`, later grabs fall to `0x706D7C` and reach b29's at
`0x706DD0`. The error was reading those two arms as mutually exclusive. A fall-through — the first
grab bumping both, later grabs bumping only b29 — fits the counts, gives 1 grab -> (1,1) and
2 grabs -> (1,2), and restores the original capture-era note that b29 shows "1 on the picking-up
attacker in both pickup rounds". The control flow has not been re-read, so the counts are the
established fact and the mechanism is open.

**This is the second time in one day that the same failure mode has produced a wrong reading**:
two arms of a branch treated as exclusive when they share a continuation. The other was the
`0x6ED650` dispatcher's shared increment tail, which mis-attributed keys and put b14's "no writer
anywhere" claim under re-audit. Worth naming as a pattern for whoever traces the next slot — when
a trace concludes "X or Y, never both", the cheap live check is a round that produces exactly one
of the triggering events and sees whether both counters move.

Also recorded from those rounds, as a testing rule rather than a finding: **the Rescue score could
not be validated and never can be.** Score-table column 36 reads live n75, which the 0x4390 frame
does not serialise, and it is nonzero in exactly Rescue, Capture and Team Sneaking. The two rounds
left residuals of 2 and 19 against otherwise-exact predictions, and both land where an invisible
counter absorbs them. Coefficient tests belong in DM, TDM, Sneaking or Base, where column 36 is
zero and every scoring input is on the wire — the friendly-kill −5 in particular belongs in Base.

Neither round tested the team_win rename: the same character won both, so a constant team-slot
index and a per-round win flag predict identical output. That test wants a round the *other* side
wins.

## team_win flipped inside one game, and the Base row decomposed exactly — 2026-07-27

**The team_win rename is live-proven.** Game 227 ran three Rescue rounds with the same two
characters. Chara 1 wired the flag 1, 1, 0; chara 3 wired 0, 0, 1. A team slot index is constant
per player per game — that is the whole content of the reading it replaced — so a mid-game flip
refutes it outright. Every earlier round had the same side winning, which is exactly why the
archive analysis (50 flips for one character over 239 rounds, top scorer holding the 1 in 96 cases
to 5) could point at the answer but not close it.

Round 3 also decomposed cleanly on its own: chara 3 wired score 5 with `b30 fully_defended = 1`
and nothing else, and b30 has no score-table column — so the 5 is `team_win 1x5` alone.

**The Base row is confirmed exactly, on the wire.** A three-player Base round (game 229): one
player captured three points and won, wiring `b25 = 3`, `b40 = 12`, `team_win = 1`, and a score of
**32**:

    team_win 1x5  +  bases_conquered 3x5  +  capture-time 12x1  =  32

Base has score-table column 36 at zero, so every scoring input is on the wire and that total is
complete — no residual, nothing absorbed by an invisible counter. It is the first end-to-end
confirmation of a whole mode row from live bytes rather than from a screen. `b12 rolls = 5` in the
same report contributed nothing, as expected for a slot with no column.

**The friendly-kill −5 was the point of the round and still escaped.** The team-killer wired
`b05 = 1`, `kills = 0` (friendly kills again not counting as kills) and a score of **0**. Raw
would be −5 and the clamp at 0 absorbed it, so the observation is consistent with the coefficient
and equally consistent with zero. Third time a clamp has hidden a deduction. The round that would
show it: capture one base and team-kill once, so the score reads 20 instead of 25 — the killer has
to stay positive or the clamp eats the evidence.

## The b14 negative was right by luck, not by method — 2026-07-27, re-audit

The retraction above is itself partly retracted, and the shape of that is worth keeping.

**b14 (live n31, blob key `0x58`) is identically zero — but not for the published reason.** The
original claim, "no writer anywhere", is **literally false**: three sites write blob byte `0x58` —
`0x27D4DC` (`SET(base, 0x1a, 152)` from a zeroed buffer) and `0x71B3B8`/`0x71BDC0`, a host-only
per-slot loop copying the baseline block back over the live block. What holds is stronger and
narrower: **nothing can make `live[n31]` differ from `baseline[n31]`**. Init zeroes both, the reset
loop assigns live := baseline, and the post-report store assigns baseline := live. The wire field
is exactly that difference, so it is identically 0 — "written only in ways that move both copies
together", not "unwritten".

**The re-audit's real lesson is about the first sweep.** It was wrong at exactly 2 of 152 sites:
`0x6ED784` (11 keys, not 1) and `0x6EFF98` (4 keys — `0x5c`, `0x62`, `0x64`, `0xa0` — the CQC
handler's shared tail, which nobody had spotted). The other 150 attributions were correct, and
critically **no key left the inventory**: every mis-attributed key has another correct writer
elsewhere, which is why no slot reading changed. So the b14 negative was true, and the method that
produced it could not have known that. Right by luck.

What makes the second pass trustworthy where the first was not: call sites enumerated from raw
branch encodings; keys recovered by forward *and* backward CFG dataflow; and — the check the first
pass never made — a proof that all 152 `r4` values are in-function `li` constants, so no site takes
a computed or parameterised key. That is precisely the assumption the original sweep rested on
without testing. The 19 direct `0x27F258` sites with non-constant keys are excluded individually by
length against the descriptor table. Residual gap, stated rather than hidden: a record pointer
spilled to stack and reloaded would evade the taint trace; the settling experiment is an RPCS3
write watchpoint on `0x1610568 + 0x510*slot + 0x58`.

**Dispatcher `0x6ED650` fully resolved:** 15 entries, 32 callers (not 31 — a tail `b 0x6ed650` at
`0x6EDC58` carries `li r3,0xe` and is the sole raiser of event 14). **Events 11–14 write no stat
key at all** — they are pure `0x6FC760(id, slot)` notifier raises, and event 13 runs an 18000-tick
(6 s) accumulator first. Key `0x58` is nowhere in the dispatcher, which was the specific hole the
re-audit was opened to check.

b38's chain reproduces instruction for instruction: `cmpwi 0xbf` at `0x7787DC`, host test,
`bl 0x6ef930(slot,slot,0,0)` at `0x778D0C`, `li r3,8; bl 0x6ed650` at `0x778D18`/`0x778D20`; the
arm at `0x6ED9B8` consults `0x6A9948` bit `0x4`, `li r4,0x72` at `0x6EDA00` with a matching
`lhz r9,0x58(r3)`, then `b 0x6ed760` into `bl 0x6a9758` at `0x6ED784`.

## The friendly-kill penalty and the cumulative-score model, in one round — 2026-07-27

A three-player Base round (game 229, round 2) engineered to beat the clamp: sean team-killed rawr
once, killed poop three times, and captured two points. All three reports reproduce exactly, and
the round settles two open questions at once because the two candidate models differ by precisely
one application of the disputed coefficient.

**Decompose against CUMULATIVE counters, not round counters.** `ComputeScore` reads the LIVE
counters, which accumulate across the whole game — only the baseline is rewritten per report. So

    wire = clamp(ComputeScore(cumulative)) − clamp(ComputeScore(as of the last report))

and a per-round decomposition is correct only for a game's first round. Sean had already
team-killed once in round 1, so his cumulative b05 was 2, not the 1 on the wire:

    per-round  (b05 = 1):  3*3 + 1*5 − 1*5 + 2*5 + 8*1 = 27     wire 22   wrong
    cumulative (b05 = 2):  3*3 + 1*5 − 2*5 + 2*5 + 8*1 = 22     wire 22   exact

Round 1 wired 0 from a raw −5 clamped at 0, so the round-2 delta is 22 − 0 = 22. Rawr reproduces
the same way (`team_win 1*5 + b25 1*5 + b40 4*1 = 14`, wire 14) and poop, with three deaths and
nothing else, wires 0 — deaths score nothing in Base.

**The friendly-kill −5 is therefore live-confirmed**, after escaping three earlier rounds. Every
previous attempt had the killer at or below zero, where the clamp makes −5 and 0 indistinguishable.
The fix was to put him in credit: two captures and three kills kept the total positive, so the
deduction had somewhere to show. That is the general lesson for any negative coefficient in this
game — **a deduction can only be observed by a player who stays positive**, and engineering that is
part of designing the round.

**Also confirmed:** headshots score nothing in Base (three headshots contributed zero, matching
column 4 = 0 for rule 5); friendly kills again do not count in A kills (3 enemy kills wired 3);
and the streak-record slots b00/b02 contributed nothing, as expected for slots with no column.

## The Sneaking row closes, and the stun deduction is confirmed at −1 — 2026-07-27

Sneaking game 230 round 1, three players, Sean as Snake (b56 = 1). His report decomposes exactly
against the rule-4 coefficients, and Sneaking has score-table column 36 at zero, so the total is
complete with nothing off-wire:

    kills 3*3  +  headshots 3*2  +  combo(b36) 3*1  −  knockouts_received 1*1  =  17,  wire 17

**This closes the file's original INCOMPLETE note.** The missing "deduction for BEING stunned" is
`knockouts_received × −1`, and this is the first round to show it directly: without the term the
prediction is 18, at the once-guessed −2 it is 16, and the wire says 17. Combined with the Base
round earlier the same night, four of the six playable rules (DM, TDM via the table's own TDM row
matching, Sneaking, Base) are now confirmed from live bytes; Rescue and Capture never can be,
because their column 36 is nonzero.

The same round re-confirmed the Snake conservation laws with three players: Sean's b54 (times
Snake was spotted) = 1 against rawr's b53 (times this player spotted Snake) = 1, and rawr's b55
(first to spot per life) = 1.

**The lock-on stun test was inconclusive, not negative.** The round was played to move
`lockon_stuns_dealt` / `lockon_stuns_received` (wire `0x19`/`0x1d`, live n10/n12). A stun was
landed with `auto_aim` ENABLED in the lobby, and both fields wired 0 while the plain knockout pair
`0x0d`/`0x0f` wired 1/1. But the round's three kills also wired `lockon_kills = 0`, so nothing in
it used lock-on at all — there is no evidence the lock was ever engaged. Two possibilities stay
open: the lock simply was not acquired, or **lock-on does not apply to stun weapons**, which would
make this pair structurally unreachable in the same way b38 is. Settling it needs a round with a
confirmed reticle lock on a stun weapon AND a control lock-on kill in the same round to prove the
mechanic was working.

## Lock-on stuns confirmed, and a zero that meant nothing — 2026-07-27

Sneaking game 231, three players, poop as Snake. Sean landed three lock-on stuns on poop and wired
`lockon_stuns_dealt = 3` (wire `0x19`); poop wired `lockon_stuns_received = 3` (wire `0x1d`); the
third player wired 0. A clean cross-player pair with known counts, on a field that had been 0/517
for the entire archive. **Both labels — derived from the binary earlier the same day off the
`hitClass == 2` arm of the stun handler `0x6EDC90` — are now live-confirmed.**

The round's score decomposes exactly and independently, which also re-confirms the Sneaking row and
`snake_kills` at ×6:

    kills 3*3 + knockouts_dealt 3*2 + team_win 1*5 + combo(b36) 3*1 + snake_kills(b51) 3*6 = 41,
    wire 41

**Lock-on stuns score nothing.** Three of them contributed zero to that total — n10 is not a column
in the score table. Counted but never paid, which is worth knowing before anyone tries to reconcile
a Sneaking score against them.

**The methodological point is the earlier attempt.** A round hours before wired 0/0 for this pair
after a stun with `auto_aim` enabled, and it was recorded as *inconclusive rather than negative*.
That call was correct: the operator had not yet worked out how to engage lock-on, and the tell was
already in the same frame — the round's three kills wired `lockon_kills = 0`, so nothing in it used
lock-on at all. **A zero in a "does X tick this?" test means nothing unless the same round contains
a control proving the mechanic was live.** Had that null been written up as a refutation, two
correct labels would have been discarded on the strength of a round where the feature was switched
off.

The confirming round makes the same point from the other side: a fourth stun on a second victim
also failed to register, and that victim wired 0 received. The wire, not the recollection, is the
authority on which stuns carried a lock.

Snake conservation laws held again with three players: sean's b53 (spots) 4 against poop's b54
(times spotted as Snake) 4, and b55 (first-to-spot per life) 3 against the Snake's 3 deaths.

## The Mk.II names itself, and needs twelve players — 2026-07-27

`mk2_kills` (b52) and `mk2_knockouts_dealt` (b57) drop `[PREDICTED]`. The decisive evidence is the
game's own Sneaking rule text, pulled off the disc with gcx
(`n012a/scenerio_strres/507.bin`, English; the same sentence in 508-511 for fr/de/it/es):

> "(If 11 or more characters are playing, one player becomes Metal Gear Mk.II and can support
> Snake.)"

That is the only entity in the whole string corpus gated on a player count, and the binary has
exactly one role gated on a player count — the `+0x80` byte of the Sneaking singleton, which is
the role the writer trace had already reached. Three corroborations: the holder is forcibly moved
to **team 2** (`li r0,2; stb r0,1(r3)` at `0x71CA0C`), the team the kill-credit path tests at
`0x6FC254` before crediting snake_kills/mk2_kills — the role joins Snake's side; `MK2_SKILL` and
`SNAKE_SKILL` are the only two unique-character skill names the ELF references; and `MK2 SPARK` is
damage-source id `0x72`, the taser, which is exactly what b57 counts.

**The gate is a hard player-count threshold with randomised selection.** `cmpwi cr7,r28,11` / `ble`
at `0x71C7FC`, same literal in the request handler at `0x71C6CC` (refusal writes status `0xFF`),
where r28 counts slots 0..23 with `team != 0xFE`. The Snake role in the same function uses
`cmpwi cr7,r28,1`, i.e. 2+ players — same counter, different literal, which is what makes the
comparison meaningful. Selection is an LCG (`seed*0x5D588B65 + 1`, `0x71CBD8`..`0x71CBF8`) mixed
with round elapsed time and a profile byte, modulo the pool, drawn from the larger of team 0/1. An
already-seated Mk.II is not demoted if the count later drops.

**Note the off-by-one and do not paper over it:** the code requires **> 11, i.e. 12 or more**,
while the manual sentence says "11 or more". That could not be reconciled from the binary. Plan any
test for 12+.

**Consequence for the report:** b52 and b57 are **untestable in a 2-3 player rig, not merely
untested** — a different documentation category from the Team Sneaking slots, which only need a
mode nobody has hosted. These need twelve human participants.

The operator's recollection — "no way to deploy it, pretty sure it's random when you hit 11
players" — was right on both counts, and was what prompted looking. Worth recording as a case where
a player's memory of the game correctly aimed a binary search that then produced tier-1 evidence.

Two loose ends left open in the write-up: the code site loading the `MK2_SKILL` pointer was not
located (base-register indirection defeats a grep; it would only be a fourth corroboration), and
whether the Snake/Mk.II machinery is rule-4-only or a "Snake can join" host option overlaid on
other rules is unresolved. Bonus: `0x6A9488` is `clamp(x, 0, 3)`, not a settings getter, which
makes the branch at `0x71C8FC` dead.

## Community research on the post-launch modes — 2026-07-27 (TIER 3-4, not read from the binary)

Everything in this section is community and patch-note knowledge — wikis, day-of press coverage,
Konami's own archived pages. It ranks BELOW the binary and below observed client bytes, and it is
recorded here because it explains *why* certain content is unreachable, not because it settles
anything about behaviour. Nothing in it contradicts the binary. Same standard LOBBIES.md already
applies to the "Survival in Ver. 1.10, Tournament in Ver. 1.20" claim.

**Team Sneaking was enabled server-side, three weeks after launch, free.** 2008-07-04, against a
2008-06-12 launch. Engadget and Gematsu day-of coverage and the 2ch MGO2 wiki
(「7/4のメンテナンスで追加された」) all describe a *maintenance*, not a client patch; Konami's archived
VERSION UPDATE page lists no client version adding it, and the first mention is 1.11 (07/25)
tuning a rule that already exists. **A mode switched on server-side must already be on the disc**,
which is exactly what `Rule_Eng_TSNE`, `TSneAlertSec` and the rule-7 coefficient row show. This is
now a backlog item: the gate may be on our side of the wire.

**No documented player minimum for Team Sneaking.** Konami's rules page, Konami's patch notes,
Wikipedia, Fandom and two Japanese player wikis were checked. The 2ch wiki says the target count
scales with participants and that briefing auto-balances lopsided teams — both suggest the mode is
designed to flex. That is a well-supported *absence*, not a positive finding; treat the question as
one for the ELF.

**The Mk.II "11 players" figure is corroborated, and the source disagreement mirrors our
off-by-one.** Both Japanese wikis say 11+ (「参加PCが11人以上で」), as does TV Tropes; Wikipedia and
Fandom say 12+. Konami ducks the number entirely ("If many players join"). Our binary requires
`> 11`, i.e. **12**, while the disc's own English rule string says "11 or more" — so the split in
the sources reproduces the split in the game's own materials. The code is the authority: plan for
12.

**"Random" was the wrong word, and the distinction matters.** No source describes the Mk.II's
*appearance* as randomised — it is a headcount threshold. What IS random, per the binary, is *which
player* gets the role once the threshold clears (the LCG at `0x71CBD8`). Community and binary agree
once the two are separated.

Also from the community side, none of it load-bearing but useful context: the Mk.II is controlled
by a human player allied to Snake (Sneaking is a three-way Red/Blue/Snake fight, and Snake and the
Mk.II notably cannot SOP-link); it can be destroyed by either team for 4 points against 3 for a
normal kill, but never permanently — it self-repairs, and the 2ch wiki explicitly warns that
destroying it does not affect the round result. **Timeline caveat worth keeping**: dogtag-carrying,
Display Magazine and the camera were all added to the Mk.II in 1.20 (2008-11-25), so its
June-2008 on-disc kit is smaller than every wiki describes.

**BOMB Mission was real and free**, roughly 2009-01-27, with full mechanics on Konami's own rules
page. Whether it was server-side or shipped quietly in the 1.21 client a week earlier could not be
determined.

**No MGO2 rule was ever paywalled.** TSNE, Bomb, Interval, Stealth DM, Solo Capture and Race were
all free; the clincher is Konami's producer on PlayStation.Blog announcing Race Mission for "all
players, not just those who have purchased SCENE". Expansions sold maps, characters and *lobby
entry*. That independently supports this project's existing position that Survival and Tournament
are LOBBY TYPES rather than rules: 1.20's "new game mode Tournament" sits under "For MEME EXPANSION
only" as a lobby, and 1.30 refers to public Survival and Tournament matches "using RES/TSNE" — a
lobby running a rule. Wikipedia calling GENE's Survival "a new game mode" is the sloppy phrasing;
Konami's own text is not. (Expansions were GENE / MEME / SCENE — there was no "ARSENAL".)

## The slot-rule "breaks" are all training statistics — 2026-07-27

The "B-index = 0x4107 slot − 1" rule has carried four documented exceptions for weeks, treated as
an unexplained defect in the mapping and as the reason to distrust any label inferred from it. The
exceptions are not random. Line each one up against what the career slot it lands on is actually
called:

    b35 wakes              -> slot 36  Number of Soldiers Trained
    b45 tsne_goals         -> slot 46  Training Mode Time
    b46 capture_put_count  -> slot 47  Combat Training Time (Instructor)
    b47 sne_bodysearches   -> slot 48  Combat Training Time (Student)

**Those four are the only training statistics in the 73-slot record, and they are the only
exceptions.** The slots immediately around them — 35, 37, 45, 49, 50 — are all unlabelled, so
there is nothing there for a struct-B counter to conflict with. That also retires the supposed
fifth exception: b48 lands on slot 49, which is `unknown_49`, so it never conflicted with anything.

**The cause is a category difference, not a broken mapping.** Training statistics cannot be
sourced from a host's per-round report. "Soldiers Trained" is a count of students instructed;
"Training Mode Time" and the two Combat Training times are durations accumulated across sessions
against an instructor/student relationship. None of that is a round event, so no struct-B slot
feeds them — they are server-side accounting, and the index arithmetic merely collides with them.

This server already implements exactly that split, which is the corroboration:
`CharacterService.trainingSeconds` reads `chara_training_time`, accumulated from
`game_player.joined_at` presence, and its own documentation records that this **replaced** a
derivation from `round_report.seconds_in_game` because the host only reports when a player leaves
early — a host who quit first reported nobody and lost a whole session.

So the rule restated: **B-index = personal-stats slot − 1, among those career slots that are fed by
round reports at all.** Nothing about it is unexplained, and the last "real mystery" in the 0x4390
write-up closes.

The practical warning it generated stays valid, and b45 is the case that proves it: "Training Mode
Time" was inferred from the rule, sat in the field NAME for weeks, and was wrong — it is a Team
Sneaking goal counter. An inferred label is a hypothesis. The difference now is that we know
*where* the rule mislands rather than merely that it sometimes does.

## The Team Sneaking gate is a byte we send — 2026-07-28

Rule 7 does not appear in the client's create-game selector, and the reason is now traced end to
end: **the rule list is the AND of two gates, and only the server-side one refuses.**

**The disc already permits it.** GCX native command hash `0xAB3201` (OPD `0x101B740`, function
`0x8E0A64`) loads a 32-bit `rule_bit` mask from the decrypted lobby stage script
`o/stage/lobby/scenerio.gcx`, `proc17`:

    command [ab3201] -rule_bit 191 -map_bit 4252 ×9 -ruleopt_bit 6 6 6 6 4 6 0

`191 = 0xBF` = rules {0, 1, 2, 3, 4, 5, **7**}. The loader's store offsets skip the rule-6 and rule-8
slots entirely but DO allocate `map_bit[7]` and `ruleopt_bit[7]`, and `countSelectableRules()`
(`0x8E0824`) returns **7**, not 6.

**The veto is `0x4101` payload byte `0x12A`, bit 0.** The create-game menu builder at `0x8AFD84`
special-cases rule 7 alone:

    008afd84  cmpwi r9, 7          ; rule 7 only
    008afd88  bne   -> emit row
    008afd98  lwz   r3, 0x60(r9)   ; network context
    008afd9c  bl    0xd382f8       ; featureBit(ctx, 0)
    008afdac  bne   -> emit row    ; bit clear -> skip Team Sneaking

`0xD382F8` computes `(ctx[0x117D0 + bit/8] >> (bit & 7)) & 1` and rejects any bit above 5 — six
feature flags in a single byte. `ctx+0x117D0` has **exactly one writer in the whole binary**:
`0xD3C348`, a 16-byte raw read inside the `0x4101` parser (`0xD3C120`). Walking that parser's reads
reproduces PROTOCOL.md's 322-byte grid exactly and places the block at offset **`0x12A`** — inside
the 25-byte tail this server currently zero-fills (`CharacterConnectController`,
`BLOCKED_END = 0x129`). The same gate is enforced at four further sites (`0x8996DC`, `0x89ADB8`,
`0x8AD794`, `0x8ADC78`), so it is a genuine feature flag, not menu cosmetics.

Bit 0 also unlocks one Sneaking-Mission rule option (`ruleopt_bit[4] = 4`). One bit turning on Team
Sneaking *and* a new rule option is exactly the shape of the tier-3 community account of the
2008-07-04 server-side maintenance — an independent corroboration of that story from the binary,
which is as close as we will get without a capture.

**Consequence:** the five TSNE struct-B slots are unexercised **by policy, not by limitation**, and
a future version toggle is a known one-byte change rather than a research project. We are not
enabling it (CLAUDE.md, "Target version: release day"). The falsifiable test, if it is ever wanted,
is to set `0x4101[0x12A] = 0x01` and watch a seventh selector row appear.

**Rules 6 (BOMB) and 8 (COOP) are a different answer: hardcoded off, unreachable from the server.**
All three enumerators carry literal `cmpwi 6` / `cmpwi 8` skips *before* the mask is consulted, and
the GCX loader has no storage slot for their map or option data. They would need a client patch —
which settles the open question of whether BOMB Mission arrived server-side. It did not.

Dead ends closed in the same pass: `0xE13BB8` / `0xE1B834` are hash caches of string bank
`0x654515` (labels come from `0x8E15E8` → `0x240708(bank, 2*rule)`) and are referenced by nothing;
`0x9C2708` is a widget text setter with no rule argument; and `0x4902` carries no rule mask.

## b38 is the Headshots-Only penalty death — the frame is complete — 2026-07-28

The last unnamed field in `0x4390` has a name, and it is testable on demand.

**Round-flags bit `0x4` is "HEADSHOTS ONLY"**, a per-round host toggle in Create Game. The game's
own English tooltip: *"When enabled, if a player is not taken down by a headshot, a penalty will be
handed to the shooter."* **Bit `0x2` is "Drebin Points Enabled".** The two are a **three-way radio,
not independent bits** — 0 Normal, 2 Drebin Points, 4 Headshots Only — which is exactly why only
those two values are ever tested anywhere in the binary.

Recovered from a plain-text-labelled lobby menu table at `0xFE7084/88/8C`, whose neighbours are
`obj_4_select_others`, `icon_drebin_point` and `icon_HSonly`; rows built at `0x8AD6B4`..`0x8AD838`
with label ordinals 400/402/403 and tooltips 409/411/412. Note this is a PER-ROUND option and so is
none of the `game` table's columns — those come from a different field, the `S+0x3A0` bitfield
expanded into the `0x4310` settings word at `0x8CA2BC`..`0x8CA420`.

**Player state 191 is the Headshots-Only penalty state.** One entry point in the whole binary:
`li r4,191` at `0x77B0DC` / `bl 0x3A5620` at `0x77B0E0`, reachable only when bit 63 of
`[chara+0x368]` is set — written only at `0x76C27C` inside `0x76C1D0`, whose only caller is
`0x77864C`, itself gated on `roundFlags & 0x4` at `0x778610`. Nothing else in the game can put a
player into state 191.

So **b38 counts deaths caused by the Headshots-Only penalty**, and its 0/551 is explained rather
than mysterious: every archived round carried `flags = 0`, and the flag is a precondition.

**How to move it:** host a round with the third "others" row selected; `checkHostSettings` should
log `flags=4`. There is a free visual tell — the round list draws Headshots-Only rounds **light
blue** (`0x3BCFFF`) and Drebin-Points rounds **pink** (`0xE12682`). Those two constants an earlier
pass could not place are RGB colours, not resource hashes.

**Predictions that would confirm it, and falsify it if wrong:** b38 and b03 (suicides) move together
(the raiser is `kill(slot, slot, 0, 0)`); `deaths` also increments; the death names **no killer and
no weapon** (damage cause 0 = `NONE`); and b38 stays 0 in Normal and Drebin rounds. Reach is not
host-only — events 6/7 come from the same host-gated function and appear on charas 1, 2 and 3 in
the archive.

**Honest gap, stated rather than smoothed:** the arming site tests only the victim's down-state, NOT
whether the takedown was a headshot. So either those down-states are themselves headshot-specific,
or the penalty is broader than the tooltip claims. One live headshot kill in a Headshots-Only round
settles it. Also unresolved: which rules ALLOW bit `0x4` lives in runtime `.bss` (read it off the
greyed-out row live), and the single inferred link in the chain is who sets bit 56 of
`[controller+0x368]` — sole writer `0x7907E8`, a virtual slot-`0xC4` method whose callers do not
resolve statically.

**The frame is now complete.** All 23 struct-A fields and 57 of 58 struct-B slots are named; the
one exception, b14, is not unknown but *proven identically zero* — nothing can make live differ from
baseline, so it can never carry a value. Three reusable finds came out of the same pass: the
damage-source name table at `0x1035818` (which independently re-confirms b17 and b18), the
per-object 896-bit flag API at `0x305A60`, and the labelled lobby menu table above.

## Automatching, end to end with three clients — 2026-07-29

The first three-client automatch. Three clients each requested a **different** rule and were matched
into one game carrying all three:

```
02:24:27  Chara 1 -> rule 4  (Sneaking)
02:25:16  Chara 2 -> rule 2  (Rescue)
02:25:31  Chara 3 -> rule 1  (Team Deathmatch)
02:29:18  Automatch formed: host 1 of 3 players, rules [4, 2, 1], map 2
```

Nobody sent the wildcard; the mode relaxation brought three explicit requests together after ~3m45s.
Earlier the same evening, two-client runs settled the rest of the matrix: **rule 0 + rule 0** formed a
Deathmatch game (so rule 0 is a real filter, not a sentinel), **wildcard + wildcard** rolled a mode at
random and picked differently twice (4, then 3), **wildcard + explicit** adopted the explicit request
rather than rolling, and **two incompatible explicit requests correctly did not match** until one side
changed.

**Why the three-rule case matters beyond the milestone.** One or two rotation entries cannot always
distinguish the wire's interleaved `[rule, map, flags]` triples from the parallel-array form — which
is exactly how the earlier loading hang survived two test suites and a hand-decode, all three of which
shared the same wrong layout. Three distinct rules rendering as three modes is the case that only
passes if the encoding is right.

Full detail in [AUTOMATCH.md](AUTOMATCH.md).

## The clan emblem was being cleared at the end of every round — 2026-07-29

**Symptom:** emblems rendered after login and were gone later in the session. **Cause:** `0x4129`,
the end-of-round results packet, writes thirteen fields of the local profile and clears none of them,
into the same profile the connect burst filled. Its **last payload byte is the clan emblem flag**, and
the server sent a hardcoded 0 there.

`0` is not "no picture", it is **"never ask"** — the fetch is skipped and the emblem is silently
absent, with no error dialog, only a 6000-tick backoff. Nothing in-game can correct it either: the
flag reaches peers through the **P2P announce**, not from us.

Confirmed fixed live: emblems and animal-rank badges both rendered in the three-client game above.

**The generalisable finding is about `0x4129`, not about emblems.** It is a partial re-send of the
connect-burst character record after a match, so *every* field in it must agree with what `0x4122`
sent. The worn title was the same defect three lines earlier in the same function, already fixed once.
Anything hardcoded there silently reverts the connect burst at the end of the first round.

## `team_win = 0` in Sneaking is correct client behaviour — 2026-07-29

A completed Sneaking stage reported `team_win = 0` for every player in every round and ended in a
draw, despite one player winning all four rounds as Snake. **That is what the binary says should
happen.** The Sneaking round-end handler awards the counter on reasons 2 and 3 (an attacking team
winning) and **awards nothing on reasons 4 and 5, the Snake-axis outcomes**.

It is deliberate: **Team Sneaking's handler is the control** — same shape, same team 2, but its
reason-4 arm *does* award. One line different between two otherwise identical handlers.

Corroborated from live data in the same game, same host, minutes apart: the TDM stage recorded
`team_win = 1` for the winner and 0 for the loser; the Sneaking stage recorded 0 for both.

**Do not "fix" this.** A server that manufactured a Sneaking team win would diverge from the client.


## What we think the remaining unknown fields are — all unproven (2026-07-29)

Recorded so the guesses are visible **and labelled**, because this project's most expensive mistakes
have all been a plausible label layered on a real observation and then inherited as fact. Nothing
below is evidence. Each entry states what would settle it.

| field | value we send | hypothesis | how to settle it |
| --- | --- | --- | --- |
| settings block `+72` (u32) | `0x02000000` | A **u8 holding 2** with three padding bytes — a server writing one octet into a u32 slot produces exactly this, and the neighbours at `+66`/`+67`/`+68` are small counts | Nothing in the binary can: no reader exists. Needs a capture of the original server sending a *different* value |
| settings block `+179` (u8) | `0x20` | A **second bank of toggles this build does not implement** — bits 8-23 of the same word are the ~16 Common Settings, bits 0-7 are unused, and the accessor for this byte exists but is dead code, which is what a compiled-out feature leaves behind | Compare against a later client version; a bit that goes live there names itself |
| `0x4120` trailer bytes 0-7 | `01 00 10 00 00 00 00 10` | **Per-list display preferences** — sixteen 4-bit fields with a generated getter/setter each, used by readers as sort-key and filter selectors | Disc assets: the labels are in the settings-screen resources, not the binary |
| `0x4602` field at struct `+0x18` | zeros | **Current lobby name** (schema's candidate) — our code called it a clan name, which is a *different* guess for the same bytes | Send three distinguishable strings in the three unknown fields and read a live search result; whichever slot renders names the field |
| `0x4991` `name_a` / `name_b` | zeros | **Team name**, by analogy with the clan record's 16-byte name fields | Unfalsifiable from the client — nothing reads them. Only an original-server capture would show it |
| `0x3049` trailer index 3, bit 1 | set (we send `0x03`) | Unknown. **Bit 0 is proven live** to unlock the 32 codec / preset messages (not loadout items — see below); bit 1 has no reader | Toggle it against a live client; bit 0's effect is now known, bit 1's is not |

**Two of these are actively contested rather than merely unknown**, which is worth flagging: the
`0x4602` 16-byte field has two incompatible candidate labels in our own tree, and `+72`'s width is
proven u32 while the hypothesis argues its *meaning* is a u8. Do not let either quietly harden.

**Fields where "we don't know" is now a settled answer, not an open question** — no reader exists in
the client, so no amount of ELF work will help: settings block `+72` and `+179`, the four `0x4101`
u16, `0x4120` trailer bytes 8-31, seven of the eleven `0x4991` fields, and `0x4602`'s three unknown
fields insofar as the client only stores them.


## The inherited `0x4120` trailer was hiding every password-locked game (2026-07-29)

The 32 bytes closing `0x4120` were carried over from the original server as an opaque constant —
`01 00 10 00 00 00 00 10 11 10 …`, commented "undocumented; reproduced byte for byte". Extracting the
disc labels named every field, and three of them were not neutral:

| nibble | field | we were sending | effect |
| --- | --- | --- | --- |
| b0lo | Filter (master) | **Enabled** | filtering on for everyone |
| b2hi | Password Lock | **"Display Only Disabled"** | **every password-locked game hidden from the browser** |
| b7hi | Match Case | **Case Sensitive** | player search fails on the wrong capital |

Every other filter row was already `----`, which is what made these three stand out rather than look
like a coherent default.

**The client's own default for the whole region is zero** — its validator memsets 33 bytes at
`0x9472E8` — so zeros are the game's answer and not just ours. Changed to all zeros: no filtering,
sort by name ascending, partial and case-insensitive search.

**Worth verifying live**, because the symptom is an absence: host a password-locked game on one
client and check it appears in another client's browser. Before this change it should not have.

### The map, and how it was read

`lobby/scenerio.gcx`, string set `-set [2f0293] $strres:9789 $strres:11033`; `string id = headerIndex
− 9789`. Each nibble is pinned by **two independent paths** — its own getter, and its own help-string
and value-label ids — so this is READ, not inferred from ordering.

Bytes 0..7 are sixteen 4-bit fields across three screens: **FILTERING SETTING** (`0x9084BC`, nine
rows), **SORT HOST LIST** (`0x90C010`) and **PLAYER SEARCH** (`0x90E264`, the `ST1_ON-OFF` /
`ST2_ON-OFF` widgets). `0` means `----` on every filter row.

```
b0lo Filter (master)      b1hi Number of Players     b2lo Level Limit
b2hi Password Lock        b3lo Weapon Restrictions   b3hi Friendly Fire
b4lo Voice Chat           b4hi Network Quality       b5lo Friends
b5hi Blocked Players      b6lo Sort key (3-state)    b6hi Sort order
b7lo Search match         b7hi Search case
b0hi, b1lo — dead, no callers anywhere
```

The ELF also carries a **developer name table** at `0xE0D548`–`0xE0DBF0` naming these same screens and
fields (`FILTER HOST LIST`, `SORT KEY`, `MATCH CASE`, `PASSWORD LOCK`, …) — better field-naming
material than the player-facing labels, and a resource worth remembering for other subsystems.

**A prior reading is corrected.** These nibbles were documented with a clamp table (b6lo ≤ 1, b6hi
forced to 0). The setters `0x906DC8`/`0x906DE0` contain no clamp at all — they mask to four bits —
and b6lo is genuinely three-state, cycling 0..2 at `0x90C4C0`, with b6hi a live toggle at `0x90C694`.

**Future feature:** these are per-player preferences and we push one set to everybody. The client does
not send them back in `0x4110` — its write-back is 304 bytes, exactly this packet minus these 32 — so
whatever persisted them used another path, and that path is not yet identified.


## The Rankings card's PLAY TIME — two triggers, one fixed, one open (2026-07-29)

**Symptom.** The Rankings → Player Rankings card showed PLAY TIME as `00:00:00` while More Details
showed the correct `16:43:20`.

**Not a delay, and not the stats grid.** `0x4105` column 17 is correct — it sums to exactly **60200
seconds**, which *is* 16:43:20, the figure More Details renders from the client's own per-column sum.

**Two separate triggers, and they were conflated at first:**

1. **Clicking yourself on a fresh Rankings load.** Zeroed before the 2026-07-29 deploy; correct
   after it. **Which change fixed it is not established** — that deploy carried the whole cleanup
   batch, and no single change in it obviously touches play time. Recorded as observed rather than
   attributed, because a plausible-sounding attribution here would be exactly the kind of guess this
   file exists to prevent.
2. **Opening More Details and backing out.** Still zeroes, and this is the deterministic trigger.

**Mechanism for the remaining one.** The card reads the **local** record until `0x4103` populates the
**viewed-player** struct, after which it reads that instead — which is why backing out of More
Details is the moment the zero appears. `0x4103` writes the same struct `0x4221` does
(`T = *(obj+0x11904)` is `*(session+0x10000+6404)`, the same base under two names), and we send zero
for the slot that holds this. Same defect as `0x4129` and the emblem: a packet sharing another's
destination slots and zeroing a field the other fills.

`0x4221` carries the real figure, which is why selecting *Player Details* from the context menu on
another character populates it.

**SOLVED 2026-07-29: `0x4105` matrix 0 memsets the cell, and the cell is ours to fill.**

The card's PLAY TIME is `*(u32*)(T+0x494)`, rendered at `0x9060EC` by the popup builder `0x905818`
through `"%.2d:%.2d:%.2d"`. **The renderer clamps to 9999:59:59**, so a huge value would print
`9999:59:59` — only **zero** can produce `00:00:00`.

`0x4105`'s parser (`0xD3E53C`) memsets `T+0x138` for **3456 bytes** when the matrix index is 0
(`0xD3E5F4`-`0xD3E604`), and `T+0x494` is inside that range. `0x4103` cannot restore it — its
destinations stop below the range and resume above it. So every More Details visit wiped the cell,
and only a fresh `0x4221` could put it back.

**The cell is not a mystery slot: it is the last u32 of the `0x4105` index-0 payload.** The parser
computes `base = T + 312 + index*864 + row*72 + col*4` and skips memory rows 6, 8, 9 and 10, so the
eight wire blocks land in memory rows **0,1,2,3,4,5,7,11**. The eighth is row 11 —
`312 + 11*72 + 17*4 = 1172 = 0x494`. ~~The card's LEVEL is column 13 of the same row
(`T+0x484`).~~

> **The LEVEL half is WRONG, corrected 2026-07-30.** The arithmetic survives — `312 + 11*72 + 13*4`
> really is `0x484`, and `0x4105`'s index-0 memset really does clear it — but the identification
> does not. **The card's LEVEL comes from `T+0x120`**, the experience slot: `0x905F28` does
> `lwa r3,288(r25)`, passes it to the level walker `0x6F9260`, clamps to 99 and prints `"%d"`.
> `T+0x120` is the same slot `0x4101` wire `0x01c` and `0x4103`'s `experience` write, so the card
> derives level from experience exactly as every other screen does.
>
> `T+0x484` is a bare `"%d"` at `0x90606C` — the only instruction in the entire text section at
> displacement 1156 with a character-block base, out of 178 — and it is **gated on `0x4101` feature
> bit 2**, which we send clear. It has therefore never been on screen, which is why nothing was ever
> observed to move with it.
>
> Consequence: the server writing `level` into `0x4105` column 13 is **mislabelled, not harmful** —
> the client does not read it as the level and the cell is invisible on this build.

So the eighth row block is **not a mode**; it is the card's summary row. The server fills its
column 17 with total play seconds and column 13 with a value labelled "level", in the cumulative
matrix only — see the correction above for what that column actually is.

**The probe was worthless and its "elimination" was invalid.** All four probed slots (`T+0x1AD0`,
`T+0x1DEC`, `T+0x1E20`, `T+0x124`) lie *outside* the memset range, so none could ever have suppressed
the field — two of them have no reader anywhere in the binary. The `00:00:00` the probe produced was
the memset, exactly as before. The experiment could not have distinguished the two causes, which is
the definition of an invalid elimination.

### What remains: the first render only, and the server cannot reach it

Confirmed fixed live 2026-07-29 — backing out of More Details keeps the time, and the zero cannot be
reproduced once any burst has landed.

**One symptom survives, and it is first-render-only.** Opening your own card for the first time after
login still shows `00:00:00`. The login sequence explains it: `0005, 3003, 4820, 4100, 4700, 4b48,
4900, 4130, 4990` — **no `0x4102`**. The viewed-player struct is untouched until the player opens
something, so on the very first draw `T+0x494` is genuinely zero. The `0x4102` that follows fills it,
and it stays filled.

So the card draws **before** our reply arrives and does not repaint until the screen is left and
re-entered. That is also what the earlier *"if I wait a bit, it starts showing up"* observation was.

**Nothing is missing on our side** — a log sweep across every game server shows no
`No handler for command` since the fix, so the client is not asking for anything we fail to answer.

The server has no earlier opportunity. The only writers of that struct are `0x4103`/`0x4105` — replies
to a request the client has not yet made — and `0x4221`, which the self-click path never sends.
Clicking *another* player's Player Details does send it, which is exactly why that path always
worked.

Whether retail behaved the same way is **not knowable from our artifacts**: the struct would be
equally empty on a real server, so this is plausibly original behaviour. Left alone rather than
worked around.

### ELIMINATED: the shared viewed-player struct is not leaking between players

There is exactly one viewed-player struct, so a natural worry was that one character's total was
being written onto another's card. **It is not.** Opening one character's Player Details populated
both cards, and **both showed their own correct figure** — the confirming observation would have
been both showing the *same* number, and it did not happen. The struct is repopulated per view
rather than shared across simultaneously-displayed rows.


## Lock-On reverted every session because the write-back was discarded (2026-07-29)

**Symptom, reported live:** Lock-On Settings returned to its previous value after every game.

**Cause:** `0x4110` — the client's gameplay-options write-back — was acknowledged and its body
thrown away. `0x4120` had always sent the stored `chara_settings` row correctly, so the round trip
was broken on exactly one side, and *every* Gameplay Option behaved the same way. Lock-On was simply
the one anybody noticed: view speeds, inverts, HUD size, volumes and codec entries all reverted too.

**The layout needed no probing.** `0x4110` is 304 bytes, which is `0x4120`'s payload truncated at
`0x130` — the same 48-byte header and four 64-byte codec names, minus the 32-byte list-preferences
trailer. Two independent sources already agreed on that: the live 2026-07-22 capture, and the
builder at `0xD3BFC0` (one 48-byte blob write, then a four-pass loop of 64-byte writes).

**Fixed** by `GameplaySettingsReader`, which is `GameplaySettingsWriter` inverted, plus
`CharacterService.saveSettings`.

### The one trap in it

**Lock-On shares a byte with the music volume at `+0x14`, and the volume travels one HIGHER than it
is stored.** Inverting that backwards would drift the volume by one on every save — slow corruption
that would present as a client bug rather than a server one, and would take a long time to notice.
It is asserted across the volume's whole range.

The test is a **round trip**, not either side in isolation: a one-sided test passes happily while the
reader and writer disagree, and a subtly wrong reader corrupts the player's options on every save
instead of failing loudly.

### What still does not persist, and why it is different

The **filter / sort / search preferences** in `0x4120`'s 32-byte trailer are *not* returned by the
client — that is precisely the 32 bytes `0x4110` omits. So there is no write-back to parse, and
persisting them would need a mechanism we have not identified. See the `0x4120` trailer entry above.


## The host-settings blob is gone, and two "confirmed" constants were circular (2026-07-29)

Both stored settings blobs are dropped. Every byte of the 352-byte block is now a typed column, and
the block is rebuilt from those columns byte-for-byte for both the game-details reply and the Create
Game pre-fill.

**What the decode found, none of it visible while the bytes were kept whole:**

- the **rotation was truncated to its first entry**, so a game's later rounds did not survive a round
  trip through storage;
- **three fields had never been stored at all** — the lobby subtype the host sends and two
  no-reader fields — and only surfaced when something tried to reproduce the block;
- the **Common Settings toggle bytes cannot be rebuilt from their booleans**: bits 1, 2 and 6 are
  undecoded, and a rebuild produced `0x22` where the client had sent `0x24`. The booleans were
  *correct* and reconstructing from them would still have been wrong;
- the block is **352 bytes, not the 345** the last named field implies. The round-trip test missed
  it because the test built its own fixture at the wrong length and agreed with itself.

### The circular capture — worth reading before trusting any echo test

`HostSettingsReply` wrote two inherited constants, `0x02` at reply `0x0ED` and `0x20` at `0x147`. A
live capture showed both coming back in the next `0x4310` push, which reads exactly like
confirmation.

**It proved nothing about the fields.** Create Game entry memcpys the whole 968-byte saved object
into the screen (`0x89B90C`) and the `0x4310` builder re-emits it, with no code path writing either
byte in between — so the values coming back were *our own bytes completing a round trip*. The capture
confirmed the transport worked.

Both are now identified: reply `0x0ED` is struct **+824**, and it is a **u32** rather than a byte, so
it spans `0x0ed`..`0x0f0` — writing one byte plus three zeros is what produced the `0x02000000`
everyone kept seeing. Reply `0x147` is struct **+931**, the low byte of the flags word at +928, whose
bits 0-7 no site tests. Neither is read anywhere in the client; both are echoed from the request now.

**This is the second time in one day that a confirming observation constrained something other than
what it appeared to.** The first was the `T+0x18` swap that only ever pinned `T+0x58`. The shape to
watch for: an experiment whose result is equally consistent with the hypothesis and with the
mechanism carrying the value round unchanged.


## The two no-reader settings fields track TRAINING lobbies (2026-07-29)

`+824` (block `+72`, wire `0x0ea`) and `+931` (block `+179`, wire `0x144`) have no reader in this
build, and they **co-vary perfectly**: a capture carries either the pair `(0x02000000, 0x20)` or
`(0, 0)`. 214 captured `0x4310` pushes, split by the lobby subtype the host was in:

| subtype | `(0, 0)` | `(0x02000000, 0x20)` |
| --- | --- | --- |
| 0 — Free Battle | 2 | 134 |
| 1 | 4 | 36 |
| 2 — automatching | 0 | 12 |
| **7 — training** | **8** | **0** |
| **8 — training** | **18** | **0** |

**Every training-lobby capture zeroes the pair, and no training capture sets it.** The handful of
zeros in subtypes 0 and 1 are the earliest captures of all, consistent with fresh state before the
value was first established.

So these bytes are not inert noise: they carry something the client sets in ordinary lobbies and
clears in training. Given nothing in this build reads them, the shape that fits is **a feature
written by a path that still runs and read by code that was compiled out** — and one that was
disabled in training lobbies.

### The circularity that had to be ruled out first

We had been zeroing exactly these two fields in the automatch settings block since 2026-07-29 06:48
(`MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS`). Since an automatch host memcpys our block into its own
settings object and re-emits it in `0x4310`, the `(0, 0)` rows could have been **our own zeros coming
home** — the same circular shape as the `0x4305` constants earlier the same day.

**Ruled out from the capture timestamps.** The `(0, 0)` captures run 2026-07-22 13:53 to 2026-07-28
21:11 and stop *before* the switch was turned on; the pattern is present in the very first capture
ever taken. And the one capture after the switch (07-29 07:11) is **non-zero**, so the zeroed block
did not propagate back in that instance either.

Worth stating plainly because it nearly went the other way: this was the third observation in one day
whose obvious reading was circular, and it is the first that survived the check.


## The 14-byte tail is inert, and `non_stat` was reading our own echo (2026-07-29)

`0x4310` wire `0x14b`..`0x158` (struct `+942`..`955`) has **exactly three touch points in the whole
binary**: the builder that emits it (`0xD44C3C`), the `0x4305` parser that reads it (`0xD45A54`), and
the create-game initialiser that **memsets it to zero** (`0x89B5E8`). No access at any byte, on any
alias, anywhere else — searched across the direct displacement, both screen-embed aliases (`+108`,
`+112`) and both context globals.

**So the client never reads it and never writes it. Its default is fourteen zero bytes.** All 214
archived captures carry it entirely zero, byte for byte.

### The retraction

This file and our code both claimed the server decodes `non_stat` from byte 10 (wire `0x155`), and
that this was capture-proven. **It was circular.** `HostSettingsReply` writes reply `0x158` from the
request's `0x155`; the client's parser lands that in the struct; its builder sends the struct byte
back as request `0x155`. The bit can only ever read back what we put there — and it never has,
because every capture is zero.

`game.non_stat` has therefore been false for every game ever recorded, and the "host options" label
was tier 4 with no support. The read is kept rather than hardcoded, so the value flows if a client
ever genuinely sets it, and the inert-field tripwire watches this block for exactly that.

**The post-launch-timer label is refuted too.** Our tier-4 comment called the first eight bytes
"SDM/INT/DM/SCAP/RACE byte-sized timers". Those mode names **do not exist on this disc**: the
online-lobby string set enumerates exactly eight rules — Deathmatch, Team Deathmatch, Rescue,
Capture, Sneaking, Base, Bomb, Team Sneaking — and the ELF developer name table agrees
(`BS CAP RES TDM CP BOM TSN` + `ALL RULE`). No Stealth Deathmatch, Interval, Solo Capture or Race
string appears anywhere in the set.

**This is the fourth circular observation found in a day**, and the first three all had the same
shape: a value we sent coming back, read as confirmation. The others were the `0x4305` constants, the
`T+0x18` slot swap, and the automatch zeroing that looked like it explained the training-lobby split.
Only that last one survived scrutiny.

### Side finding: the Common Settings word is 64-bit, not 32

The create-game initialiser writes `std r9,1032(r31)` at `0x89B620` — a **64-bit** store covering
struct `924`..`931`. Our notes describe a 32-bit flags word at `+928`. Same low byte, wider
container; only bytes 929, 930 and 931 reach the wire (`0x142`, `0x143`, `0x144`).
