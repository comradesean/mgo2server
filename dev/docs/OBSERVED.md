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

`dev/runtime/stun_probe.py` already emits MAPPED + SOURCE + CHANGED with `peer` as the mapped address
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
captured `port=fd37 ip=c498fd81` exactly. `dev/runtime/stun_probe.py` now sends this by default.

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

Serving `dev/runtime/www/cert-expired.pem` — the same CA, key and common name as the working chain,
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

### Fingerprint v5: the full per-mode grid mapped; titles and awards are client-derived

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
- **Titles and awards are computed by the client from the stat values themselves** — the award
  list regenerated to exactly the thresholds our fingerprint numbers crossed ("10/25 consecutive
  kills" ↔ slot 1 = 1001; "2/4 consecutive TDM survivals" ↔ 1025; "100 SOP destabilizer uses" ↔
  1027; "500/10000 total kills/deaths" ↔ the 42k computed totals), and the title set changed
  with the stats (v2's Foxhound/Fox/Doberman/Hound → v5's HOUND/CROCODILE/EAGLE/…). No separate
  command feeds them; the earlier "different command flow fills the tables" reading conflated
  storage with source. Award/title threshold enumeration is presentation-mapping, not protocol.

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

## Titles and medals: the client-side catalogue, extracted from the ELF

Static extraction 2026-07-23 (medal tier table VA 0xe139c0, title resource keys VA 0xe14eb0,
sprites VA 0xe152d0). "Awards" are "MEDALS" in the client's own tab naming (TAB_TITLE /
TAB_MEDAL). Both are derived client-side from the raw stats; no command carries them. The two
record tables earlier suspected as their source (T+0x26d14, T+0x3330) are actually match-history
list storage (0x4682 / 0x4212 records) — that note is corrected.

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

### The token never leaves the client: attribution model binary-proven; 0x43a2 decoded

2026-07-23, closing ELF trace. The 0x43c9 start-round token is written to
session+0x57d8+0x32f8 and read at exactly one site in the binary — a UI record populator
using memory-copy helpers, not packet writers; the 0x43c8/0x43a2/0x4390 builders never
reference the slot. So no packet can carry a game identifier: connection identity is the
whole attribution mechanism, by construction. 0x43c8's {u32,u8} = two config bytes from a
settings buffer (round/rule pair, not the token). 0x43a2 fully decoded as a count-prefixed
per-slot tally list (see PROTOCOL.md) — our three captured payloads decode exactly; what the
127-slot table indexes is the new open question.

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
B13 = ENVG time (s), B14 = dedicated-host time (s), B15 = catapult uses, B16 = boosts given,
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
