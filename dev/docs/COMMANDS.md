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
| size | 110 sent / 204 parsed | 212 dispatched |

**The two id spaces are disjoint except for one value: `0x3004`** — a lobby check-session ack in A,
an unrelated session message in B. Every other number belongs unambiguously to one channel.

The crux for our scope: **join (`0x4320`/`0x4321`) and peer-register (`0x4340`–`0x4346`) are
Channel A** — the client telling the *lobby server* about a peer event over TCP, which we answer.
The `0x43xx` range is entirely absent from B. So the boundary is clean: **we implement all of A,
none of B**, and B's gameplay traffic (the host↔peer link that the join hands off to) is the
emulator's, exactly as the P2P backlog concluded. Channel B is not enumerated here; its 212 ids
live in the task output (`/tmp/p2p_set.txt`) if that layer is ever investigated.

Legend: **✓ handled** — the server sends/answers it today. **gap** — the client uses it but we do
not. **dead** — we have code for it but the client never uses that id.

---

## Client → server (the client SENDS these)

110 unique ids; we answer 45. Source: send-builder scan 2026-07-22 (`0xD5CF40`; every site a
literal `li r4, imm`, so the list is exhaustive for the lobby packet library — the pre-lobby
handshake carrying `0x0001` is outside it).

### Handled (50)

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
info · `0x43c8` start round *(renumbered from dead `0x43ca`, 2026-07-23)* · `0x4440` team/spectator · `0x4500` add
relation · `0x4510` remove relation · `0x4580` roster fetch · `0x4600` player search ·
`0x4680` match history · `0x4684` match detail · `0x4700` connection info ·
`0x4820` get messages · `0x4900` game-lobby info · `0x4990` game entry info

### Gaps — sendable, unanswered (60)

Potential `FFFFFF60` stalls *if the triggering menu is reached*; grouped by reachability.

**Corrections the scan forced:**
- `0x43c8` (`0xD40CB4`, `{u32, u8}`) — the client's real "start round"; our handler was bound
  to `0x43ca`, which **has no builder** and is never sent. **Resolved 2026-07-23:** handler
  renumbered to `0x43c8`/`0x43c9`; `game_round` also populates on create/join now (BACKLOG).
- `0x3040` (`0xD37B6C`, `u8`) — has a live builder after all; still unanswered by any reference.

**Reachable in ordinary flow (priority):** `0x4112`, `0x4210`, `0x4220`
(connect-family write-backs / card) · `0x4348`, `0x4394`, `0x43a4`, `0x43a6`, `0x43b0`, `0x43c4`,
`0x43c8`, `0x43d0`, `0x43e0`, `0x43e2`, `0x4400` (in-match / host family). None has surfaced as a
stall yet — each is gated on an action not exercised. (`0x4102` and `0x4132` were here until
2026-07-23, when both stalled live, were traced, and moved to handled — the prediction model of
this list works.)

**Unmodelled subsystems (reached only by opening that feature):**

| block | ids | subsystem |
| --- | --- | --- |
| `0x4bxx` | 23 (`0x4b00`–`0x4b90`) | clans / GHQ |
| `0x49xx`+ | `0x4904`–`0x49c2` (~18) | game-lobby / roster / GHQ |
| `0x4axx` | `0x4a25`, `0x4a30`, `0x4a40` | unidentified |
| mailbox | `0x4800`, `0x4840`, `0x4860`, `0x4880` | send / read / file / manage mail |
| misc | `0x2006`, `0x4e00` | lobby-layer / isolated |

(The social family `0x4600`/`0x4680`/`0x4684` — player search and match history — stalled live,
was traced and moved to handled 2026-07-23; see PROTOCOL.md.)

Builder addresses and per-gap payload shapes live in the enumeration task output; they are not
transcribed as field layouts here, per this project's rule against unparsed specs. Each gap needs
its own parser trace before implementation — a bare ack does not satisfy commands that expect a
bodied reply (the ADDLIST `0x4510` proved this).

---

## Server → client (the client PARSES these)

**204 inbound ids**, routed by three literal compare-chain dispatchers (`0xD361E8` for `0x2xxx`,
`0xD37074` for `0x3xxx`, `0xD38804` for the game range `0x41xx`–`0x4Exx`); nothing table-driven,
so the set is complete. A fourth dispatcher `0xD78CCC` (131 ids, `0x2100`–`0x4080`) is the
**separate in-game P2P session channel**, not the lobby TCP reply path — out of scope here.

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

`0x4442` is the mirror case: the client parses it but we only ever send `0x4441` — check whether
the `0x4440` team/spectator flow expects `0x4442` as well.

### Parsed but never sent — unimplemented subsystems (~146)

The client is wired to receive replies for whole features we don't serve. Sending nothing is fine
**unless the client requested the feature and blocks on the reply** — these become `FFFFFF60`
stalls only when that menu is opened (see the send-side gap list). Grouped:

| block | what |
| --- | --- |
| `0x4601`–`0x4687` | friend/roster lists beyond ADDLIST (the search/history triples `0x4601`–`0x4603`, `0x4681`–`0x4687` are now sent) |
| `0x43e*`/`0x43f*` | an in-match subsystem the client sends `0x43e0`/`0x43e2` into |
| `0x4801`/`0x4802`/`0x4841`/`0x4861`/`0x4881` | the rest of the mailbox |
| `0x49xx` (`0x4905`–`0x49c3`) | clan / GHQ / roster |
| `0x4axx` (`0x4a00`–`0x4a50`) | a whole unidentified subsystem (lists at `0x4a11`/`0x4a33`/`0x4a42`) |
| `0x4bxx` (`0x4b01`–`0x4b93`) | the 23-command clan/GHQ subsystem — client fully wired to parse its replies |
| `0x4d00`, `0x4e10`–`0x4e23` | small tail subsystem |
| result singles | `0x4113`, `0x4211`/`0x4213`, `0x4317`, `0x4395`, `0x43a5`/`0x43a7`, `0x43b1`, `0x43c5`, `0x4401` (`0x4133` moved to sent — and proved not to be a result single at all; see PROTOCOL.md) |

Per-parser addresses and read-primitive shapes are in the enumeration task output; not transcribed
as layouts here, per the project's rule against unverified specs.
