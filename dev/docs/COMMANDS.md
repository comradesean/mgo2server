# Command map — the full duplex protocol from the ELF

Every command id in the protocol, enumerated directly from `MGO2.elf` (retail BLUS30109), split
by direction. This is the *complete* set, not what any reference documents: the send side comes
from an exhaustive scan of the packet builder (`0xD5CF40`, 115 literal-id call sites, nothing
table-driven); the receive side from the inbound reply dispatcher. Where a command's meaning and
byte layout are worked out, `PROTOCOL.md` holds the detail — this file is the index.

## Two architectures — what is ours and what is not

The binary has **two fully independent packet stacks**, proven from the ELF to share no builder,
no dispatcher, and no serialization primitive. Everything in this file is **Channel A**. Channel B
is the emulator-level peer link the P2P work in `BACKLOG.md` concluded "is not our protocol" — and
now that conclusion is exact, not inferred.

| | **Channel A — lobby TCP (our server)** | **Channel B — in-game host ↔ peer** |
| --- | --- | --- |
| what | gate/account/game lobby, characters, hosting, browser, mail, ADDLIST | the direct console-to-console gameplay link during a match |
| reaches our server? | **yes — this is the entire server** | **no — never touches us** |
| send builder | `0xD5CF40` | `0xD824D0` (separate) |
| parse dispatchers | `0xD361E8` / `0xD37074` / `0xD38804` | `0xD78CC8` (its own session object) |
| framing | 24-byte header + XOR + selective Blowfish | its own; **zero** calls to any lobby primitive |
| id space | `0x0004`/`0x0005`, `0x2xxx`, `0x3xxx`, `0x41xx`–`0x4Exx` | `0x1101`–`0x1918`, `0x2101`–`0x240c`, `0x3001`–`0x3632`, `0x4004`–`0x4080`, `0x52xx`/`0x56xx` |
| size | 112 sent / 204 parsed | 212 dispatched |

**The two id spaces are disjoint except for one value: `0x3004`** — a lobby check-session ack in A,
an unrelated session message in B. Every other number belongs unambiguously to one channel.

The crux for our scope: **join (`0x4320`/`0x4321`) and peer-register (`0x4340`–`0x4346`) are
Channel A** — the client telling the *lobby server* about a peer event over TCP, which we answer.
The `0x43xx` range is entirely absent from B. So the boundary is clean: **we implement all of A,
none of B**, and B's gameplay traffic (the host↔peer link that the join hands off to) is the
emulator's, exactly as the P2P backlog concluded. Channel B is not enumerated here; its 212 ids
live in the P2P task output, which was a `/tmp` file and is gone; that layer would need re-enumerating from `0xD78CC8` if it is ever investigated.

Legend: **✓ handled** — the server sends/answers it today. **gap** — the client uses it but we do
not. **dead** — code *in the ELF* that goes nowhere: an unreachable builder, a stub parser, a
dispatcher arm that falls through. No id is labelled dead today, and no reachability pass has been
run, so the absence of the label is not evidence of liveness.

**Corrected 2026-07-26.** This legend previously read "**dead** — we have code for it but the
client never uses that id", which applied the word to the wrong side of the wire. We do not
control the client; it *is* the specification. An id **our server** touches which the client
neither sends nor parses is a **defect**, not inert leftover:

- **misnumbered** — we implement a neighbour of the real id. `0x43ca` was this, and reading it as
  harmless vestige is precisely why start-round stalled; the real id is `0x43c8`.
- **phantom** — we emit a reply the client has no parser for (`0x4115`, `0x4140`, `0x4142`).
- **imported fiction** — inherited from a reference server targeting a different build.

Per-id status in this vocabulary is tabulated in [`PACKETS.md`](PACKETS.md), which indexes every
id in both directions with a one-line summary.

---

## Client → server (the client SENDS these)

**112 unique ids** from 115 call sites; **83 are handled and 29 are gaps** (recounted from the
source 2026-07-30 — see the note below the Handled list). Source: send-builder
scan 2026-07-22 (`0xD5CF40`; every site a literal `li r4, imm`, so the list is exhaustive for the
lobby packet library — the pre-lobby handshake carrying `0x0001` is outside it), **re-derived
independently 2026-07-26** into [`dev/analysis/c2s_ids.txt`](../analysis/c2s_ids.txt) with the
call-site address of each.

**Count corrected 2026-07-26: 112 unique, not 110.** The 115-site figure reproduced exactly, and
all 115 resolved to a literal `li r4` with none unresolved or table-driven, so the exhaustiveness
claim holds — but only **three** ids have two builders each (`0x3003` at `0xd381fc`/`0xd39fd4`,
`0x4820` at `0xd53414`/`0xd53518`, `0x4860` at `0xd53a50`/`0xd53c04`), giving 115 − 3 = 112.
Reaching 110 would need five duplicates. Two independent completeness cross-checks agreed: the
paired ctor `0xd5cf98` (116 sites, the one unpaired site being a receive path) and the flush
`0xd34cc0` (115 sites, 1:1 with the builders). The old subtotals were also internally
inconsistent — the handled header said 50 over a 49-item list, and 49 + 60 = 109.

Address convention: `c2s_ids.txt` anchors on the `bl` to the builder; the addresses quoted in this
file anchor on the preceding `li r4`, i.e. four bytes lower. Same sites.

### Handled — **83 ids as of 2026-07-30**, not the 50 this section lists

> **The enumeration below is stale and was never the count.** Recounted mechanically from
> `src/main/java/mgo2server/`: 80 distinct ids registered via `handlers.put(...)`, plus 2 registered
> by `ClanGameController`'s `BLOCK_768` loop (`0x4b48`, `0x4b4c`) which a constant scan misses, plus
> `0x0001`, which is answered in the pre-lobby handshake and has no builder. **83 handled, 29 gaps,
> 83 + 29 = 112.**
>
> The drift is mostly the 23-command clan block, which landed 2026-07-27 — the day after this
> section was last written. `PACKETS.md`'s per-command status column **is** current and was verified
> against the source on 2026-07-30; prefer it over the prose lists here.
>
> The list that follows is kept because its per-command annotations are useful, not because its
> membership is right.

`0x0001` echo · `0x0003` disconnect · `0x0005` ping · `0x2005` lobby list · `0x2008` news ·
`0x3003` check session · `0x3048` char list · `0x3101` create char · `0x3103` select char ·
`0x3105` delete char · `0x3107` check name · `0x4100` connect burst · `0x4102` personal stats ·
`0x4110` options write-back ·
`0x4114` chat-macro write-back · `0x4128` post-game info · `0x4130` update personal info ·
`0x4132` outfit commit · `0x4150` lobby disconnect · `0x4300` game list · `0x4304` get host
settings · `0x4310` push host
settings · `0x4312` game details · `0x4316` create game · `0x4320` join game · `0x4322` join
failed · `0x4340`/`0x4342`/`0x4344`/`0x4346` peer register · `0x4380` quit game · `0x4390` stats ·
`0x4392` set game · `0x4398` pings · `0x43a0` pass host · `0x43a2` round end? · `0x43c0` in-game
info · `0x43c8` start round *(renumbered 2026-07-23 from `0x43ca`, which has no builder — our
misnumbering, not a client id)* · `0x4440` team/spectator · `0x4500` add
relation · `0x4510` remove relation · `0x4580` roster fetch · `0x4600` player search ·
`0x4680` match history · `0x4684` match detail · `0x4700` connection info ·
`0x4820` get messages · `0x4900` game-lobby info · `0x4990` game entry info ·
**added 2026-07-26:** `0x4800` send mail · `0x4840` read mail · `0x4880` delete mail ·
`0x4400` in-game chat *(reply `0x4401` is fanned out to every player in the game, not just the
sender — the client has no local echo)*

### Gaps — sendable, unanswered — **29 as of 2026-07-30**, not the 63 below

> Recounted from the source. The 29 are: `0x2006` `0x3040` `0x4210` `0x4348` `0x4394` `0x43B0`
> `0x4860` `0x4904` `0x4908` `0x4910` `0x4912` `0x4914` `0x491B` `0x4920` `0x4923` `0x4930`
> `0x4940` `0x4980` `0x4984` `0x4986` `0x4992` `0x49A0` `0x49B0` `0x49C0` `0x49C2` `0x4A25`
> `0x4A30` `0x4A40` `0x4E00`.
>
> **Four of them are reachable in ordinary play and are the live stall candidates:**
> `0x4210`, `0x4348`, `0x4394`, `0x43B0`. All four have real ELF-derived layouts in `dev/proto/`,
> so they are implementable now rather than blocked on research. Everything else in the list sits
> behind an unmodelled subsystem a player has to open deliberately.
>
> The grouped list that follows is from 2026-07-26 and over-counts; its reachability groupings are
> still the useful part.

Potential `FFFFFF60` stalls *if the triggering menu is reached*; grouped by reachability.
(63 as of 2026-07-26, when `0x4400` was implemented; it was 64, and 60 before the corrected
112/48 split above.)

**Corrections the scan forced:**
- `0x43c8` (`0xD40CB4`, `{u32, u8}`) — the client's real "start round"; our handler was bound
  to `0x43ca`, which **has no builder** and is never sent. **Resolved 2026-07-23:** handler
  renumbered to `0x43c8`/`0x43c9`; `game_round` also populates on create/join now (BACKLOG).
- `0x3040` (`0xD37B6C`, `u8`) — has a live builder after all; still unanswered by any reference.
  The byte is bounds-checked `<= 7` by the client, the same bound `0x3103`/`0x3105` use on the
  character-slot index [ELF, 2026-07-26].

**Reachable in ordinary flow (priority):** ~~`0x4112`~~, `0x4210`, `0x4220`
(connect-family write-backs / card) · `0x4348`, `0x4394`, `0x43a6`, `0x43b0`,
`0x43c8`, `0x43d0`, `0x43e0`, `0x43e2` (in-match / host family). ~~None has surfaced as a
stall yet~~ — **`0x4112` did, 2026-07-27**: it fired after a player search, and unanswered it
stalled the screen exactly as its wait slot predicted. It is answered now with a bare `0x4113`
result; the 32-byte body is still [UNKNOWN]. The rest are gated on actions not exercised.
(`0x4102` and `0x4132` were here until
2026-07-23, when both stalled live, were traced, and moved to handled — the prediction model of
this list works. `0x4400` left 2026-07-26: it surfaced live as the in-game chat send and was
decoded from four captures — the first entry to surface *unhandled but without stalling*, so this
list predicts reachability, not stalls. See OBSERVED.md "0x4400 — in-game chat". Still a gap: no
handler exists, because answering it properly needs a broadcast mechanism the server lacks.)

> **This list is stale in two directions [2026-07-26].**
>
> *Already implemented:* `0x4220`, `0x43a6`, `0x43d0` and `0x43e0` (with their replies `0x4221`,
> `0x43a7`, `0x43d1`, `0x43e1`) have handlers in `src/main/java/mgo2server/game/controller/`.
> They are listed as gaps here but are served; `PACKETS.md` marks them `served †`.
>
> *Shapes now known:* `0x4112` is a 32-byte opaque blob that registers **wait slot `0x18`**
> (`li r4,24` at `0xD3BEDC`) — it therefore **blocks**, which was borne out live on 2026-07-27
> when it stalled a player-search screen; the prediction from the wait slot was right (reply
> `0x4113` is a bare u32 ack, parser `0xd3b148`, slot 24). `0x4394` is 203 bytes from 45
> straight-line writes. **`0x43a4` and `0x43c4` are no longer gaps — both were identified and
> handled on 2026-07-29:** `0x43a4` is the host's per-skill experience report (the only route by
> which skill progression persists) and `0x43c4` is the 1-to-5 host-rating vote. Both are now
> answered; `0x43a4` in particular opens wait slot 53, so leaving it unanswered hung a client
> live. `0x43a4` puts its record count **on the wire** (cap 127) whereas `0x4398`
> carries **no count** at all — opposite conventions inside one family. `0x43c4` only ever sends
> the values 1–5 (`0xD40E44` aborts otherwise), which rules out the character-id reading the rest
> of the `0x43xx` family invites. Per-id layouts: `dev/proto/inbound/`.

**Unmodelled subsystems (reached only by opening that feature):**

| block | ids | subsystem |
| --- | --- | --- |
| ~~`0x4bxx`~~ | ~~23 (`0x4b00`–`0x4b90`)~~ | **clans — all 23 answered as of 2026-07-27; see PROTOCOL.md** |
| `0x49xx`+ | `0x4904`–`0x49c2` (~18) | game-lobby / roster / GHQ |
| `0x4axx` | `0x4a25`, `0x4a30`, `0x4a40` | unidentified — **not rankings**, see below |
| mailbox | `0x4840`, `0x4860` | read / file mail (`0x4800` send and `0x4880` delete are served) |
| misc | `0x2006`, `0x4e00` | lobby-layer / isolated |

**The `0x4Axx` block is not the ranking subsystem [ELF, 2026-07-27].** The id looks inviting and
the block has three list replies, so it has been guessed at more than once. It is not: the
`0x4A24`/`0x4A31` records embed the 204-byte game-settings sub-record, which puts the family with
games. **Rankings are not in the command protocol at all** — the screen POSTs to
`rank/mgogetrank.html` and `rank/mgogetrank_clan.html` and parses a little-endian, XOR-scrambled
binary body. Implemented in `web/controller/RankingWebController`; the wire format is in
`OBSERVED.md`, "Rankings — an HTTP feature, not a command". Nothing in this file needs to serve it.

**`0x4e00` is not isolated — it is a forced follow-up [ELF, 2026-07-26].** The server→client
`0x4e10` *opens* a request (slot 90 → state 1) and the client immediately builds and sends
`0x4e00` back (`li r4,19968` into the builder at `0xD5B0CC`). Anything that sends `0x4e10` must be
ready to answer `0x4e00`. `0x2006` likewise has a shape now: empty payload, wait slot `0x0b`,
sender `0xd36900` — a near-clone of `0x2005`'s sender, so its reply is plausibly the otherwise
unexplained `0x2007` (single u32, parser `0xd36498`, notify slot 11), which no doc mentions.

The `0x4bxx` "23" and `0x49xx` "~18" counts both reproduced exactly on re-derivation. Three ids in
those blocks are **odd-numbered** — `0x491b`, `0x4923`, `0x4b73` — where every other client→server
id is even; odd ids are reply-shaped elsewhere in this protocol, so they are worth a second look
before either subsystem is modelled. The `0x4b90` sender is at `0xD55CE4`, payload
`{u8 (0..1), u8, bytes[16] name}`.

(The social family `0x4600`/`0x4680`/`0x4684` — player search and match history — stalled live,
was traced and moved to handled 2026-07-23; see PROTOCOL.md.)

Builder addresses are in [`dev/analysis/c2s_ids.txt`](../analysis/c2s_ids.txt); per-gap payload
shapes are in `dev/proto/inbound/`, one `.ksy` per id (2026-07-26 — this supersedes "the
enumeration task output", which was a `/tmp` file and is gone). They are still not transcribed as
field layouts *here*, per this project's rule against unparsed specs. Each gap needs its own
parser trace before implementation — a bare ack does not satisfy commands that expect a bodied
reply (the ADDLIST `0x4510` proved this).

The write primitives, for reading those builders: `0xD5C86C`/`0xD5C8A0` u8, `0xD5C8D4`/`0xD5C918`
u16, `0xD5C95C`/`0xD5CA1C` **signed** u32 (`sraw`) vs `0xD5C9BC` unsigned (`srw`), `0xD5CA7C` u64,
`0xD5CADC` NUL-terminated string, `0xD5D0AC` fixed-length blob. `0xD5C828` is the **seal** (banks
the cursor into the header as the payload length), so builder→seal brackets the payload exactly;
`0xD34CC0` is the flush and `0xD5D124` the in-place Blowfish, whose presence per path reproduces
`DECRYPT_COMMANDS` membership exactly.

---

## Server → client (the client PARSES these)

**204 inbound ids**, routed by three literal compare-chain dispatchers (`0xD361E8` for `0x2xxx`,
`0xD37074` for `0x3xxx`, `0xD38804` for the game range `0x41xx`–`0x4Exx`); nothing table-driven,
so the set is complete. A fourth dispatcher `0xD78CCC` (131 ids, `0x2100`–`0x4080`) is the
**separate in-game P2P session channel**, not the lobby TCP reply path — out of scope here.

The full list with per-id summaries is [`dev/analysis/s2c_ids.txt`](../analysis/s2c_ids.txt) and
[`PACKETS.md`](PACKETS.md); byte layouts for all 204 are in `dev/proto/outbound/`
(drafts, ELF-derived, 2026-07-26).

> **The dominant failure mode in this direction is a reply that is too short, and it is silent.**
> Every read primitive bound-checks against the **1023-byte receive buffer**, not against the
> payload length (`0xd5cc64`: `cursor > 1020` is the only test). An under-length reply therefore
> parses "successfully" off whatever the buffer already held — no error, no stall, wrong data.
> **Six** instances are known, and all the ones in our own replies were fixed on 2026-07-26:
> `0x4991` (sent 172 B, parser reads **236**), `0x4133` (sent 34 B, the loop runs **16**
> iterations → `36 + 5·count`), and `0x4399`, `0x4311`, `0x4381` and `0x4151` — all four
> documented as empty replies, all four read a u32 into a waiting request slot. `0x4841` is the
> sixth: a bare `{u32 0}` copies **708 bytes** of stale buffer into the mail object and reports
> success, so the read reply must carry the full 712.
>
> `0x4151` is the one that shows how quietly this hides: backing out of a lobby fed wait slot 116
> whatever four bytes the buffer happened to hold, and nothing ever misbehaved visibly.
>
> Sending explicit zeros is always safer than sending nothing.

### Replies we send that the client parses (handled, correct)

All the reply ids the server emits today resolve to a real parser: the lobby lists
(`0x2002`–`0x200b`), the character/account results (`0x3004`, `0x3049`, `0x3102`…`0x3108`), the
connect-burst payloads (`0x4101`, `0x4120`, `0x4121`, `0x4122`, `0x4124`, `0x4125`), the host and
game-list replies (`0x4111`, `0x4129`, `0x4131`, `0x4301`/`0x4302`/`0x4303`, `0x4305`, `0x4311`,
`0x4313`, `0x4317`, `0x4321`, `0x4323`), the peer-register replies (`0x4341`–`0x4347`), the
in-match acks (`0x4381`, `0x4391`, `0x4393`, `0x4399`, `0x43a1`, `0x43a3`, `0x43c1`), the ADDLIST
replies (`0x4502`, `0x4512`, `0x4581`/`0x4582`/`0x4583`), `0x4441`, `0x4701`, the mailbox
(`0x4821`/`0x4822`/`0x4823`), the game-lobby info (`0x4901`/`0x4902`/`0x4903`), `0x4991`, and —
added 2026-07-23 from the parser traces — the personal-stats burst (`0x4103`/`0x4105`/`0x4107`),
the outfit readback (`0x4133`), and the search/history triples (`0x4601`–`0x4603`,
`0x4681`–`0x4683`, `0x4685`–`0x4687`).

### ⚠ Replies we send that the client does NOT parse (phantom / misnumbered — real bugs)

The cross-check's most valuable output. If the client is waiting on the *correct* reply id and we
emit one of these instead, it never advances → `FFFFFF60`.

| we send | the client parses | verdict |
| --- | --- | --- |
| `0x43cb` (start-round reply) | `0x43c9` | **resolved 2026-07-23**: the pair is renumbered to `0x43c8`/`0x43c9` in code. |
| `0x4140` (skill sets, in the connect burst) | *no parser* | **latent**: client has no `0x4140` parser, so saved skill-set slots may never populate. (`0x4103`/`0x4105`/`0x4107` turned out to be the personal-stats burst, now sent — but the `0x4133` outfit readback is the likelier loadout path; its entry semantics are uncaptured.) Verify against a live character before changing — the burst otherwise works. |
| `0x4142` (gear sets, in the connect burst) | *no parser* | same as `0x4140` for gear-set slots. |
| `0x4115` (chat-macro write-back reply) | *no parser* | harmless: `0x4114` is fire-and-forget (observed non-blocking), so the ignored reply costs nothing — but it should not be sent. |
| `0x0001` | *(pre-lobby)* | not a bug — echo lives outside the lobby parser. |

`0x4442` was the mirror case — the client parses it but we only ever send `0x4441`.
**Answered 2026-07-26 [ELF]: no.** `0x4441` (`0xD52980`) drives the subsystem-`0x54` status and
result setters and so completes the `0x4440` transaction on its own; `0x4442` (`0xD52878`) touches
neither setter and instead fires UI event `0x31`. It is a **server-initiated push**, not the
second half of the reply, so nothing is missing from the `0x4440` flow.

### Parsed but never sent — unimplemented subsystems (~146)

The client is wired to receive replies for whole features we don't serve. Sending nothing is fine
**unless the client requested the feature and blocks on the reply** — these become `FFFFFF60`
stalls only when that menu is opened (see the send-side gap list). Grouped:

| block | what |
| --- | --- |
| `0x4601`–`0x4687` | friend/roster lists beyond ADDLIST (the search/history triples `0x4601`–`0x4603`, `0x4681`–`0x4687` are now sent) |
| `0x43e*`/`0x43f*` | an in-match subsystem the client sends `0x43e0`/`0x43e2` into |
| `0x4801`/`0x4802`/`0x4841`/`0x4861`/`0x4881` | the rest of the mailbox |
| `0x49xx` (`0x4905`–`0x49c3`) | **team / tournament / survival**, not clan — corrected 2026-08-01. The 680-byte record at `session+0xD928` is a team with an 8-slot roster at `+0x17C`, slot 0 the leader; a clan is a separate object the team references through `team+0x94` bit `0x40`. Error codes are the **−10xx** band throughout, disjoint from clan's **−12xx**. This makes the family Ver. 1.10 / 1.20 content — **not served in v1, but fully in scope for mapping now**. Exception: the senders for `0x4904`, `0x4908` and `0x4992` sit in the `0xD477xx`–`0xD48Dxx` lobby/entry block and touch no team state. See `FIELD_MAPPING.md`, "Settled 2026-08-01" |
| `0x4axx` (`0x4a00`–`0x4a50`) | **TOURNAMENT / SURVIVAL events** — identified 2026-08-02, see `FIELD_MAPPING.md`. Only three c2s commands in the whole block (`0x4A25`, `0x4A40`, `0x4A30`); their failure dialogs are 5522 "Unable to cancel Survival.", 5376 "Unable to cancel Tournament." and 5409 "Unable to acquire Tournament list." The 7296-byte event record at `session+0xDBD0` holds a 128-entrant table, per-round entrant bitmaps and standings. **Not rankings** — that 2026-07-27 negative stands. Post-launch (Ver. 1.10 / 1.20), so not served in v1. Lists at `0x4a11`/`0x4a33`/`0x4a42` — **and `0x4b12`**, a fourth, 48-byte records, 100-entry cap, parser `0xD56010` |
| `0x4bxx` (`0x4b01`–`0x4b93`) | the 23-command clan/GHQ subsystem — client fully wired to parse its replies |
| `0x4d00`, `0x4e10`–`0x4e23` | small tail subsystem (but `0x4e10` obliges us to answer `0x4e00` — see above) |
| result singles | `0x4113`, `0x4211`/`0x4213`, `0x4395`, `0x43a5`/`0x43a7`, `0x43b1`, `0x43c5` (`0x4133` moved to sent — and proved not to be a result single at all; see PROTOCOL.md) |

**Corrections to that last row [ELF, 2026-07-26].** `0x4317` was listed here *and* under "replies
we send that the client parses" — the duplicate is stale, and it is not a result single. `0x4401`
is not one either: it is `{u32, NUL-terminated string}` (`0xD5CE34`, delimiter 0, 129-byte buffer),
so the string is delimiter-terminated on the wire rather than fixed-width. **Resolved the same day:
`0x4401` is the in-game chat line to display, the `u32` is the speaker's character id, and it must
be fanned out to every player in the game including the sender — implemented and confirmed against
two clients. See OBSERVED.md "0x4400 — in-game chat" and "Chat served and confirmed live".** Two more entries in the
"parsed but never sent" blocks are misfiled: `0x4905` is an **822-byte record**, not a result
single, and it discards the entire packet unless its echo id matches the client's `ctx+0x6D04`
(`0xD4820C`); `0x4993` is the removal counterpart to `0x4991`, not a bare result.

Three structural facts about these blocks, each of which breaks a naive implementation:

- **`0x4bxx` contains three list triples** of the `0x4601`/`0x4602`/`0x4603` shape, documented
  nowhere: `0x4b53`/`54`/`55`, `0x4b74`/`75`/`76`, `0x4b91`/`92`/`93`. Items are size-driven with
  **no count field** — putting a count in the start packet reproduces the `1032:00000005` failure
  in OBSERVED.md.
- **One parser serves six ids.** `0xD4AF34` carries the same 420-byte clan record for `0x4911`,
  `0x4913`, `0x4985`, `0x4987`, `0x49A1` and `0x49B1` (624 B for `0x4987`, which alone inserts a
  204-byte sub-block). This file lists them as unrelated. Reading that function linearly yields a
  layout **no id actually uses** — each takes its own branch.
- **Every `0x49xx` notification is gated.** Helper `0xD49230` reads a u32 clan id and u16 serial
  and compares them to the client's cached record; a mismatch returns `-1018` and the packet is
  **discarded silently** — no dialog, no state change. `0x4960` is the only id waived from both
  comparisons.

Per-parser addresses and read-primitive shapes now live in `dev/proto/outbound/`, one
`.ksy` per id — superseding "in the enumeration task output", which was lost. Note the read
primitives are **not** the four listed in PROTOCOL.md line 1698; at minimum `0xD5CC64`/`0xD5CCD8`
(u32, instruction-identical twins — neither is a signed accessor), `0xD5CBC4`/`0xD5CC14` (u16),
`0xD5CD4C`/`0xD5CDC0` (u64) and `0xD5CE3C` (NUL-terminated string) also exist.
