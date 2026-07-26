# Lobbies

## What a lobby is

MGO2 does not connect a player to one server. It walks a chain: a bootstrap server that hands out
addresses, an account server where a character is chosen, and then a game server where play
happens. The game calls each link in that chain a **lobby**, and a lobby is fundamentally **an
address the client will dial** — not a room, and not a place people idle in. Our `lobby` database
table is a list of such addresses.

Two things about a lobby are configurable and mean entirely different things:

- **type** — *where you connect*. Three values only: the bootstrap server (0, "the gate"), the
  account server (1) and a game server (2). The client keeps one connection per type.
- **subtype** — *what the lobby is*, and only meaningful for type 2. Free Battle, training,
  automatching and so on. It is what the in-game menus dispatch on.

After login the client shows a **hub** screen. Its **Lobby Select** entry lists lobby *categories*
— one row per subtype, labelled by the client, not by us — and picking a category opens a sub-list
of the actual lobbies in it. Those two screens come from different data than the addresses do,
which is the single most confusable thing here:

| | source | where the client keeps it | what it is for |
| --- | --- | --- | --- |
| **gate list** | `0x2003`, from the gate | `ctx+0x750`, 52-byte stride | **addresses.** Every connect resolves through this |
| **hub list** | `0x4902`, from a game lobby | `ctx+0xB790`, 120-byte client struct (99 bytes on the wire), 64 max | **the menus.** Lobby Select and its sub-lists |

A lobby row appears in both, keyed by the same **lobby id**. The hub list carries no address at all
— picking a lobby looks its id up in the gate list to find the ip and port.

## How to read this file

Everything here is derived from the decrypted `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) unless it
says otherwise. Wire layouts live in `PROTOCOL.md` under their command; this file is about the
model, not the bytes.

- A bare `0x` value with six digits, like `0x890410`, is an **ELF virtual address** — a function
  entry unless the text says otherwise.
- A `+0x` value, like `+0x294`, is an **offset inside a runtime struct**.
- A four-digit `0x` value, like `0x4902`, is a **TCP command id**; `→` marks client-to-server and
  `←` server-to-client. `PROTOCOL.md` documents each one.
- `ctx` is the client's networking context object, which every accessor takes as its first
  argument.
- **echo** and **mgo2-server** are other people's MGO2 server implementations. Under `CLAUDE.md`'s
  evidence hierarchy they are tier 4 — never a specification — and anything sourced from them is
  labelled as such below.

---

## Lobby types

The `type` column, `0x2003` offset `0x04`, u32. Three values, and they are not a taxonomy — they
are **connection slots**. The client holds one connection per type in a table indexed by type at
stride `0x44` (`mulli r4,68` at `0xD34C64`, `0xD358D8`, `0xD4742C`), read straight out of a live
client's memory during the stall investigation with all three slots `FF FF FF FF` (`OBSERVED.md`).
Its own debug string carries both numbers: `mgo_connect_server_by_index() index=%d, type=%d`. That
is why the list must be **ordered by id so index and type coincide** for the first three rows —
ordering by name broke it in practice.

**There are exactly three, and no fourth is reachable.** Eleven independent guards across the
lobby-list accessors reject `type > 2` unsigned before touching anything (`0xD358A0`, `0xD358D0`,
`0xD35900`, `0xD35948`, `0xD3598C`, `0xD359E8`, `0xD35B80`, `0xD35C44`, `0xD35DA8`, `0xD35E6C`,
`0xD35F38`), returning 0 or `-24`. A row with type 3+ is inert: it can sit in the table, be sent in
`0x2003`, and be counted by nothing. (`seed.sql` deletes `type IN (0..7)` purely as a broad reset;
it does not imply 3–7 mean anything.)

Our `LobbyType` enum mirrors these three and `fromId` throws on anything else.

### Type 0 — GATE

The only address the client knows without being told. It dials **15731** directly (observed; not
5730 as reference material suggests), before any session exists.

- **Answers**: `0x2005` lobby list, `0x2008` news, plus the universal disconnect/ping. No session
  check on either — there is no session yet.
- **Client flow**: connect → `0x2005` → parse `0x2002`/`0x2003`/`0x2004` into `ctx+0x750` → event
  `0x0A` on channel 2 → disconnect. The whole exchange is verified from inside the client.
- **Gotcha**: the gate is where every later address comes from. An `ip` here that the console
  cannot route to fails much later and looks like a lobby fault, not a gate fault.
- Our server registers `LobbyGameController` and `NewsGameController` for this type only, so a gate
  physically cannot answer a character command.

### Type 1 — ACCOUNT

Reached from the gate list. Character selection lives here, and nothing else does.

- **Answers**: `0x3003` check-session — the command a client sends immediately after connecting,
  to prove who it is — plus the character list/create/select/delete family.
- **Check-session identifies by account.** The u32 at payload `0x00` is the **account id**, and
  there is no trailing byte. This is the same command id as on a game lobby with different
  semantics — the single most confusable thing in the protocol.
- **Client flow**: connect → check-session → character list → the player picks or creates one →
  the chosen character id is stored behind accessor `0xD3A094` and is what the game lobby will
  claim. Until that happens the stored id is **zero**, which is why the port check's `0x3003`
  legitimately claims character id 0.

### Type 2 — GAME

Where the game actually happens, and the only type that can appear more than once. Everything
about subtypes below applies only here.

- **Answers**: check-session, the connect family, hub (`0x4900`/`0x4990`/`0x4150`), game list and
  hosting, messaging, social, personal info and stats. This is the bulk of `PROTOCOL.md`.
- **Check-session identifies by character**, and the game-lobby sender at `0xD39F18` appends a
  **trailing flag byte** — traced to `+0x294` of the `0x883F20` object, which is the subtype of the
  lobby being entered (see below).
- **Multiple instances are normal.** The client counts them (`0xD384D8`), connects to one by
  **ordinal** at login — position among game lobbies in gate-list order, counting from 0, *not* the
  lobby id — and lists them by subtype in the hub. Each needs its own server: our
  `MGO2SERVER_LOBBY_ID` and `MGO2SERVER_LOBBY_SUBTYPE` tell an instance which row it is.
- **Gotcha**: a game lobby is contacted twice for different reasons — once by the port check before
  the main menu (ordinal-chosen, address from the gate list) and once when the player picks a
  lobby (id-chosen, address also from the gate list). Both paths must land on a live server.

Accessors, all taking the mgonet context:

| address | signature | notes |
| --- | --- | --- |
| `0xD35FC4` | `entries_base(ctx)` | returns `ctx+0x750`; `{marker u32, count u32, entries[]}` |
| `0xD35F1C` | `count_of_type(ctx, type)` | scans `entry+0x0C`, stride 52. Wrappers: `0xD38154` type 1, `0xD384D8` type 2 |
| `0xD35D84` | `ordinal_to_index(ctx, type, n)` | nth entry of that type, or -1 |
| `0xD35E44` | `connect_by_ordinal(ctx, type, n, …)` | resolves then calls `mgo_connect_server_by_index`. Wrappers: `0xD38120` type 1, `0xD384A4` type 2 |
| `0xD35C7C` | `find_by_lobby_id(ctx, *type, *ordinal, id)` | reverse lookup; wrapped by `0xD47CE0` |

Full `0x2003` field layout is in `PROTOCOL.md`; the fields that matter for this file are the
**type** at `0x04`, the **lobby id** at `0x2b`, and the ip and port the client dials.

The `0x2002`/`0x2003`/`0x2004` parser arms are in the packet dispatcher `0xD361A4`; completion
fires event `0x0A` on channel 2. This exchange is verified from inside the client — parsed entries
read back correctly out of its own memory (`OBSERVED.md`, "The lobby-list handshake is verified
inside the client"). The base is `ctx+0x750`, whose first two words are a marker and a count, so
the entries themselves start a little past it; the live read that confirmed the fields was taken at
`ctx+0x75C`.

---

## Lobby subtypes

The `subtype` column. **Type is where you connect; subtype is what the lobby is.** It is not sent
in the gate list at all — only in `0x4902`, at offset `0x04`, and it is the only field the hub menu
dispatches on.

### The categories this build has

Complete: the menu builder (function at `0x890030`, scans at `0x890410`–`0x8905D8`) runs exactly
six scans over the hub list, in this order — **2, 1, 7-or-8, 5, 3, 4** — each stopping at its first
match and emitting at most one row. A subtype with no scan can never produce a row.

Rows appear in scan order, so **an Automatching lobby is always the topmost row when one exists**.
The `scan` column is where each loop begins; the table is ordered by that address, which here
happens to match execution order.

| subtype | our name (source) | scan | row emitted | string ids | action | status |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | Automatching (tier 4) | `0x890410` | `0x89097C` | 251 / 260 | 9 | **in use** |
| 1 | Free Battle (tier 4) | `0x89044C` | `0x890908` | 245 / 261 | 10 | **in use** |
| 7 | Basic Training (observed) | `0x890488` | `0x890894` | 249 / 262 | 11 | **in use** |
| 8 | Combat Training (observed) | `0x890488` | `0x890894` | 249 / 262 | 11 | **in use** |
| 5 | *unnamed — tournament/survival family* | `0x8904CC` | inline `0x890504` | 264 + entry text | 12 | present, unused |
| 3 | *unnamed — tournament/survival family* | `0x890578` | `0x890820` | 246 / 263 | 13 | present, unused |
| 4 | *unnamed — tournament/survival family* | `0x8905B4` | `0x8907AC` | 248 / 265 | 14 | present, unused |
| 6 | — in the title resolver's range, but no scan | — | — | — | — | unused |
| 9, 10 and up | — out of range everywhere | — | — | — | — | **do not exist** |

Subtypes 7 and 8 share one scan because that loop tests a *range* (`subtype - 7 <= 1` unsigned)
rather than a single value. Every other scan is an exact comparison.

The **string ids** are the pair the row is built from — the client resolves both through
`0x8E0C24` — and the **action** is the code stored on the menu item that decides what selecting it
does. Neither is a value we send; see "What the ELF does and does not name" below. Where the "our
name" column says *tier 4*, the name comes from another server implementation and has never been
verified against this client.

### The range the client accepts

The menu scans say which subtypes get a Lobby Select row. A second, independent structure says
which subtypes the client considers to *exist at all*: the title resolver at `0x8F4F14` computes
`subtype - 1` and rejects **that value** above 7 unsigned — so subtypes 1 through 8 pass, 0
underflows out, and 9 and up are rejected — then dispatches through an 8-entry jump table at
`0x8F4F40`. Every arm loads a distinct message id and asset constant:

| subtype | arm | title string id | asset constant |
| --- | --- | --- | --- |
| 1 | `0x8F4F94` | 275 | `0x007389B2` |
| 2 | `0x8F4F6C` | 904 | `0x00904A08` |
| 3 | `0x8F500C` | 634 | `0x008AC2A7` |
| 4 | `0x8F5034` | 635 | `0x00D6A909` |
| 5 | `0x8F4FE4` | 636 | `0x00BC3E0E` |
| 6 | — falls to the default at `0x8F4F60` | — | `0x002705B4` |
| 7 | `0x8F4FBC` | 842 | `0x00DCF3A0` |
| 8 | shares subtype 7's arm | 842 | `0x00DCF3A0` |

So **seven subtypes are real in this build — 1, 2, 3, 4, 5, 7, 8** — each with its own title and
artwork. **6 is not**: it is inside the table's range but routed to the fallback. 0, and anything
above 8, is out of range entirely. This is independent confirmation of the menu scans, and it
carries the string ids anyone with the disc's message resource needs to put names to 3, 4 and 5.

Two further structural facts about them:

- **3, 4 and 5 are a family.** Their title ids are consecutive (634/635/636), and `0x891D80` tests
  `subtype - 3 <= 2` to route exactly those three to a different screen (`0x8BBA90`) from everyone
  else (`0x8965A4`).
- **Six subtypes get their own background asset** in the chain at `0x8AB9F4`–`0x8ABAE0`: 1, 3, 4,
  5, 7 and 8 each select a distinct resource; subtype 2 is absent from that chain and takes the
  default.

### Per subtype

**Subtype 1 — Free Battle.** *In use.* Menu row `0x890908`, strings 245/261, action 10. Title
string 275. Own background asset. Nothing conditional anywhere: the plainest of the seven, and the
one everything else is a variation on.

**Subtype 2 — "Automatching".** *In use.* Menu row `0x89097C`, strings 251/260, action 9 — scanned
first, so it is the topmost row when present. Title string 904, which matches the lobby-entry
machine's 904/905 pair for this subtype (`0x897114`) — the two agree, which is a useful
cross-check. Alone among the seven it has **no dedicated background asset**. Observed live
2026-07-25: the row appears, is selectable, and the lobby is entered without error; nothing about
what the screen behind it *does* has been tested. The name is tier 4, inherited from mgo2-server
and never verified — note that the binary's own taxonomy has `TYPE_COOP` where that mapping would
put Automatching (see below).

**Subtypes 7 and 8 — Basic and Combat Training.** *Both in use.* They share everything above the
lobby door: one category row (`0x890894`, strings 249/262, action 11), one title (842), one
jump-table arm, and the lobby-entry machine tests them together (`0x897138`/`0x89714C` → strings
842/843). The sub-list at `0x89147C` groups them and splits by **lobby id**, which is why two
subtype-7 lobbies both list — that part is real and was confirmed on echo.

**Inside the lobby they are not interchangeable.** Every row of the training menu
(`0x895E80`–`0x896238`) is gated by `0x884584(n)`:

```
count = 0xD48D10(ctx)          ; hub-list entry count
want  = lhz 0xD38504(ctx)+0x3E ; the lobby this connection is to
for i in 0..count:
    e = 0xD49040(ctx, i)
    if lhz e+0x08 == want and lbz e+0x04 == n: return 1
return 0
```

It looks up **this** lobby's own hub entry and requires an **exact** subtype match — no 7/8
grouping here. `0x884584(7)` unlocks the basic rows (strings 844/848, 845/849); `0x884584(8)`
unlocks the combat rows (855/856, plus an 866/867 row gated separately on a byte at `+0x2D80`).

So a Combat Training lobby seeded as subtype 7 lists correctly and then renders the **basic**
training menu — Solo/Novice only. Observed live 2026-07-25, and the reason the two must be 7 and 8.
The distinct background assets at `0x8ABAB0` (7) and `0x8ABAD4` (8) point the same way.

**Subtype 3.** *Present, unused.* Menu row `0x890820`, strings 246/263, action 13. Title 634. Own
background. Member of the 3/4/5 family screen.

**Subtype 4.** *Present, unused.* Menu row `0x8907AC`, strings 248/265, action 14. Title 635. Own
background. Member of the 3/4/5 family screen.

**Subtype 5.** *Present, unused.* The odd one. Its row is emitted **inline** at `0x890504` rather
than by a shared helper, action 12, string 264 — and it is the only category with a precondition
(`0x8904F0`: the entry's byte at `0x06` must equal 3) and the only consumer of the entry's 64-byte
text block, which it passes to the string formatter at `0x94AD8C`. Title 636, own background,
member of the 3/4/5 family screen.

**Subtype 6.** *Not a lobby subtype.* In the jump table's range but routed to the fallback title,
and no menu scan. Treat it as unused rather than reserved.

**Subtype 0.** Out of the title resolver's range and unscanned. We use it on the gate and account
rows, where it is never read — the hub list only carries game lobbies.

**Subtypes 9, 10 and above.** No representation anywhere. Reference schemas place "tournament
registration" at 10; **it does not exist in this build.**

### Why 3, 4 and 5 are here at all

Survival and tournament are reported as post-launch additions — survival in **Ver. 1.10**,
tournament in **Ver. 1.20**. That is community/patch-note knowledge, not something read from the
binary or observed here; treat the version numbers as uncorroborated. That does **not** date this binary: shipping the code dormant and switching it
on server-side later fits the same evidence, and is the ordinary way a feature like this lands.
Nothing here distinguishes "patched build" from "disc build with unreleased code", and the binary
does not state its own version (the only `Ver[…]` string belongs to the UPnP library). Do not infer
a patch level from feature presence.

What it does mean for us is narrower and still useful: **a subtype being reachable in code is not
evidence anyone ever ran that lobby**, so 3/4/5 stay marked unused until one is seeded and entered.

### What the ELF does and does not name

It does embed plenty of displayed text — `TEAM DEATHMATCH`, `BASE MISSION`, `CAPTURE MISSION`,
`SNEAKING MISSION`, `RESCUE MISSION`, and the in-match HUD labels are all there as plain strings.

It does **not** contain the Lobby Select labels. Searched, 8-bit and 16-bit, for every spelling of
*Free Battle*, *Automatching*, *Training*, *Survival*, *Tournament* and *Registration*: no hits,
and `Lobby Select` itself is absent too. That screen's text goes through `0x8E0C24` into the
message resource keyed `0x00F914BF`, which lives outside the binary. Title ids **634, 635, 636**
are the lookup keys for subtypes 3, 4 and 5 if that resource becomes available.

What the binary does carry is the game's own **taxonomy of game types**, a contiguous six-pointer
array of UI object names at vaddr `0xFE85F0`, among the personal-record screen's assets:

```
TYPE_FREEBATTLE  TYPE_COOP  TYPE_TOURNAMENT  TYPE_SURVIVAL
TYPE_TOURNAMENT_OFFICIAL  TYPE_SURVIVAL_OFFICIAL
```

Tournament and survival by name, matching the patch history and the 3/4/5 family screen. **The
index-to-subtype mapping is unproven** and is deliberately not asserted here: the array is reached
through a base register loaded from the TOC, so nothing in the image points at it directly, and the
naive `index = subtype - 1` reading puts `TYPE_COOP` on subtype 2 — which we have been calling
Automatching on a reference server's authority, never on ours.

**Whether these screens work end to end is also unproven.** Code, titles and artwork exist with no
expansion check on any path; that is not the same as the flow behind them being complete, nor as
Konami having run such lobbies. The cheap experiment is to seed one, enter it, and watch the lobby
log for `No handler`.

### Sub-lists: how two lobbies share a category

Picking a category opens a list built at `0x89147C` from the *same* hub array. It walks every
entry, accepts any whose subtype matches the current lobby's — treating 7 and 8 as one group — and
separates them **by lobby id**, not by subtype. So two subtype-7 lobbies both appear. Confirmed
against echo and against this loop.

Listing is the only place this grouping applies. What a training lobby *does* once entered is
decided by its own subtype, exactly matched — see subtypes 7 and 8 above.

Each entry's id is resolved through `0xD47CE0` → `0xD35C7C` as the list is built. **An id that is
not in the gate list takes the error path** (`0x891474` → `0x8910A8`), so the hub list must never
advertise a lobby the gate did not.

### Subtype leaves the menu with you

Selecting a row stores its subtype at `+0x294` of the object behind `0x883F20` (`0x890640`). That
is the same byte the game-lobby `0x3003` appends as its trailing flag: **the check-session trailing
byte is the subtype of the lobby being entered**, which had been an open unknown.

The lobby-entry state machine then branches on it (`0x897110` onward): subtype 2 takes strings
904/905, subtype 7-or-8 takes 842/843, everything else falls to `0x8973D0`.

---

## What actually gates entry: the port check

**Not the UDP one.** `STUN.md` describes a NAT-discovery exchange also called "the port check";
both sit behind the same *Adjusting port settings* screen, which is why the name is reused. This
section is the TCP half — the client opening a socket to a game lobby and sending check-session.

It is the reason a lobby table can be internally consistent and still fail login. Waiting machine `0x946F00`, jump table `0x946F5C`, state 0 at
`0x946F8C`:

1. Count type-2 entries in the **gate** list (`0xD384D8`). Zero → error `0x908`.
2. Read a 2-byte client setting — group 25, id `0xFE` (`0x27EF90` / `0x27F160`). This is an
   **ordinal among game lobbies**, not a lobby id. The client zeroes the variable before reading,
   so an absent setting gives ordinal 0 — but the value is client-side persisted state, so a
   returning player's may be anything.
3. Connect to that ordinal (`0xD384A4`). `-102`/`-64` poll again **with no timeout** — this is why
   a bad address hangs forever instead of erroring; anything else raises `0x91E`.
4. State 1 sends `0x3003` over that connection, with the trailing subtype byte.

Consequences, all of which have bitten this project:

- The lobby at that ordinal **must have a server listening**. Rows the player never picks are never
  dialled, so a table full of dead addresses can look fine until the ordinal lands on one.
- **Inserting a game-lobby row ahead of the others moves the target.** Adding an Automatching row
  at id 3, ahead of the working lobbies, pointed the port check at a port nothing was bound to and
  failed login before Lobby Select was ever reached (2026-07-25).
- The ordinal is client-side state. Do not assume 0.

---

## The hub list — `0x4900` → `0x4901` / `0x4902` / `0x4903` ←

Request built at `0xD47C08`, empty body. Replies parsed at `0xD4780C` (`0x4901`: result; sets
count 0 and marker -1), `0xD47E18` (`0x4902`: entries), `0xD47714` (`0x4903`: result; marker 0,
fires event 56). `0xD49040(ctx, index)` hands out an entry and refuses while the marker is nonzero;
`0xD48D10` returns the count.

The reply is **multi-packet**: a start, then one `0x4902` per batch of entries, then an end. Count
the packets before reading them — a single `0x4902` is not the whole list.

**Entries are 99 bytes, not 35.** Both reference servers write 35 — correct field order, but
missing a 64-byte text block between the name and the open time. The readers bound-check the
1023-byte packet buffer rather than the payload length, so a short entry does not error: entry 0
parses (the first 26 bytes of the two layouts coincide), then the parser resumes 64 bytes into the
middle of entry 2 and stores rubbish. Symptom is **exactly one lobby in Lobby Select, always the
first one sent**. Full field table in `PROTOCOL.md`; machine-readable spec in
`dev/proto/mgo2_cmd_4902.ksy`.

The 64-entry cap is hard (`0xD480B4`): entry 65 onward is dropped silently.

### Known gap: `0x43d0`

Sent from the lobby-entry machine (`0x897758`) with a single u8 argument, value 8; blocks on the
reply. `0x43d1` is five u16s copied to `ctx+0x117EC`. **We do not answer it.** See `PROTOCOL.md`.

---

## Deployment rules

Not protocol — the operational consequences of the above, and the shape of `dev/tools/seed.sql`
and `compose.yaml`.

- **Every game-lobby row needs its own server instance.** A row is an address. `compose.yaml` runs
  one container per row; `MGO2SERVER_LOBBY_ID` must be the row's id and `MGO2SERVER_LOBBY_SUBTYPE`
  its subtype, because hosted games are filed against that id and the game list filters on it.
- **Ids are not an implementation detail.** They are wired into compose, so a reseed that lets the
  identity column drift silently repoints every instance at the wrong row. Seed with explicit ids.
- **The `ip` must be routable from the console.** It is what the client is told to dial next, so
  `127.0.0.1` only works when the emulator runs on the same machine. Wrong addresses here surface
  much later, as a lobby fault rather than a gate one.
- **Order the gate list by id.** Index/type identity for the first three rows, and the port-check
  ordinal counts game lobbies in this order.
- **Keep the first game lobby the most reliable one**, since that is what an unset ordinal dials.
- **A subtype is a behaviour, not a label.** Naming a row "Combat Training" does nothing; its
  subtype decides what the lobby does. Basic and Combat Training must be 7 and 8 respectively.
- The `0x2003` player count is players *in games* per lobby, not lobby occupancy — operator policy,
  not protocol.

Current layout (2026-07-25):

| id | type | subtype | name | port | container |
| --- | --- | --- | --- | --- | --- |
| 1 | 0 | 0 | Gate | 15731 | `gate` |
| 2 | 1 | 0 | Account | 15732 | `account` |
| 3 | 2 | 2 | Automatching | 15740 | `automatching` |
| 4 | 2 | 1 | Game | 15733 | `gamelobby` |
| 5 | 2 | 7 | Basic Training | 15737 | `basictraining` |
| 6 | 2 | 8 | Combat Training | 15738 | `combattraining` |

Automatching sits first deliberately: it has its own instance on 15740, so the ordinal-0 dial lands
on a live server. The 2026-07-25 failure above was that row existing **without** an instance behind
it, not the ordering itself.

---

## Open questions

- What subtypes 3, 4 and 5 are called, and whether their screens work end to end. Needs the disc's
  message resource for the names — the lookup keys are title ids 634, 635 and 636 — and a live
  entry attempt for the rest.
- **Why the training Graduate action does nothing** (open, 2026-07-25). It is not a missing reply:
  the client sends no command at all when it is pressed, and `0x43d0` is now answered. The gate is
  player state. At `0x8972F4` a training lobby (subtype 7 or 8) only enters its special state when
  `profile[+0x2D80] != 0` **and** `profile[+0x2D88] == 0`, and the same `+0x2D80` byte gates the
  menu row with strings 866/867 at `0x896054`. `profile` is `ctx+0x57D8` (accessor `0xD3A094`),
  which is populated by the connect-family parsers `0x4121`, `0x4122`, `0x4124`, `0x4125`,
  `0x4129` and `0x4131`.

  **Both flags are already satisfied by what we send, so this gate is not the blocker.** Traced to
  **`0x4129`**, the post-game results payload: its parser (`0xD3C9B0`) scatters each skill record
  into `base + 11440 + 4 + index*12`, so `+0x2D80` is skill **17**'s index byte and `+0x2D88` is
  that record's trailing u8. `HostGameController` writes records 1–25 with a zero trailing byte,
  which gives exactly `17` and `0` — the two values the gate wants. That also explains why
  the Graduate row renders at all. Equipping the instructor skill in-game changes neither byte,
  and was confirmed not to help.

  What remains unread is the **action handler**: the row stores action code 50, and pressing it
  emits no traffic, so something in that path refuses silently. Serving 60 in the first `0x43d1`
  slot did not unlock it either (2026-07-26), so that value is not the stored training total.
  Deferred with the full state of the investigation in `BACKLOG.md`, "Training graduation".
- The meaning of the `0x43d1` values, and which screens send `0x43d0`.
- Hub entry fields `0x05`, `0x06` (outside the subtype-5 check) and the eight-bit flags byte at
  `0x07`: parsed into distinct booleans, no consumer identified.
- The gate list's restriction bits (`0x2003` offset `0x2d`) have never been exercised — we always
  send 0.
- What reads the hub entry's 16-byte **name**. Lobby Select uses the string table, and the
  sub-list separates by id; the name's presentation surface is unidentified.
