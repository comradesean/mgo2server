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
3. **The HTTP/TLS probe** (`dev/http_probe.py`) — exact paths, methods and bodies.
4. **[MiguelRipoll23/mgo2-server](https://github.com/MiguelRipoll23/mgo2-server)** — an independent
   MGO2 server covering the web API that Nomad does not. Nomad is only the game server.

## How this file gets things wrong

Two failure modes have each cost real time here, and both are cheap to avoid.

**Another implementation is not a specification.** mgo2-server and the Nomad upstreams both work —
for their own targets. Neither was validated against `BLUS30109`, and the MGS4-integrated build
differs. That divergence has now been paid for five times: the policy path, the gate hostname, the
gate port, the version-check byte, and the perks field. The perks field is the instructive one,
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

## STUN

Matches are peer-to-peer, so the client discovers its public address before it will enter a lobby.
With no STUN server reachable it retries UPnP against the router and then fails — which presents
as a lobby error, not a NAT one, and is easy to misread.

`mgo2-server` lists a STUN server on 3478/udp as a required component alongside the gate and
account servers.

The client does not send a plain binding request. It sends CHANGE-REQUEST attributes — observed
as `len=12` and `len=24` requests, sourced from the game's own port — asking the server to reply
from a different port or address, and classifies its NAT from which replies arrive. A responder
that always answers from the same socket cannot satisfy that.

NAT classification fundamentally needs **two IP addresses**: the client asks the server to reply
from a different address and infers its NAT type from whether that reply arrives. SaveMGO ran its
STUN server on a different address from its gate for exactly this reason — its DNS handler maps
`mgo2gate` to 192.3.217.61 and the STUN host to 192.3.217.162, and its setup instructions give
users both addresses.

`dev/stun_probe.py` takes an optional second address and serves the full four-socket layout when
given one. With a single address it answers change-IP from the alternate port, which lets the
client conclude rather than hang, but cannot distinguish a full-cone NAT from a symmetric one.

It must run with host networking. Docker's UDP proxy rewrites the source port of replies, and
since a STUN client identifies which address answered, every reply appears to come from a random
port and discovery never concludes. Published ports look like they work — the reply arrives — but
from the wrong port.

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
`dev/upnp_probe.py` did, and it cost a test cycle. Echo back whatever target was asked for.

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
  each with the `0xf000` vendor attribute. The client never sends CHANGE-REQUEST, so it is not
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
python3 dev/upnp_probe.py --respond --ip 192.168.1.100
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
- **The game lobby must accept a check-session with character id 0 and no character selected.**
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

Serving `dev/www/cert-expired.pem` — the same CA, key and common name as the working chain,
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

`TODO` is RPCS3's marker for an unimplemented call. The game queries its network configuration,
receives nothing, and gives up. This is a strong candidate for the blocker and would explain why
no server-side change affects the outcome, and why MGO2PC ships a **custom RPCS3 build** rather
than instructions for the stock one. It is not proven: the calls are also made on attempts that
progress further.

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

A token is 32 hex characters. The first **8** are stored server-side; the first **16** are returned
to the client. The client encrypts the stored half into the `0x3003` check-session packet, which is
why `account.session` is `varchar(8)` and `SessionIds.decode` yields 8 characters.

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
