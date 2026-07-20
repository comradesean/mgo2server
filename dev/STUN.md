# The port check (STUN)

Before MGO2 will let a player online it runs a NAT discovery pass, shown on screen as **"Adjusting
port settings"**. Matches are peer to peer, so the client wants to know how its UDP port is seen
from outside before it will enter a lobby. Get this wrong and the game either hangs on that screen
forever or refuses lobby access with `0692`.

This file is the whole of what is known about it. `dev/PROTOCOL.md` covers the TCP command protocol
and says nothing about STUN; this is deliberately separate, because the port check is UDP, runs on
its own thread, and shares nothing with the lobby servers.

The implementation is `dev/stun_probe.py`, run by the `probe-stun` service in `compose.yaml`.

Confidence levels, used throughout:

- **Confirmed** — observed from the real client (`BLUS30109` on stock RPCS3 v0.0.41) against this
  responder, with the log to show it.
- **Ours** — what our responder does today. It works, which does not prove every part is required.
- **Reference** — taken from a capture of the real Konami server, or from another project.
  Unverified against our client unless separately marked.

---

## The exchange that works

**Confirmed.** This is a complete, verbatim classification round from `probe-stun`, captured on the
run where the client passed the port check and proceeded to log in. The client is `192.168.1.100`
sourcing from port `5730`; the responder holds `192.168.1.100` and `192.168.1.201`, ports `3478`
and `3479`.

```
vendor 0xf000 = 0573000000000002
192.168.1.100:3478 <- 192.168.1.100:5730  len=12  attrs=[0xf000]
    -> replied from 192.168.1.100:3478,  mapped 192.168.1.100:5730

vendor 0xf000 = 057300000000000400000004
192.168.1.100:3478 <- 192.168.1.100:5730  len=24  attrs=[CHANGE-REQUEST, 0xf000]
                                          change_ip=True change_port=True
    -> replied from 192.168.1.201:3479,  mapped 192.168.1.100:5730

(the pair repeats once)

192.168.1.100:3478 <- 192.168.1.100:5730  len=0   attrs=[none]      <- keepalive, indefinitely
    -> replied from 192.168.1.100:3478,  mapped 192.168.1.100:5730
```

Three request shapes — **but only because Test II succeeded here.** See the classification tree
below: a player whose Test II gets no answer goes on to re-send Test I to CHANGED-ADDRESS and then
a change-port-only Test III. Those will appear in the wild even though they never appear on a LAN
bench, which is why CHANGED-ADDRESS has to be right:

| len | attributes | meaning | we must reply from |
| --- | --- | --- | --- |
| 12 | `0xf000` | Test I, basic binding request | the address it was sent to |
| 24 | `CHANGE-REQUEST` + `0xf000` | Test II, "answer me from somewhere else" | the **other** address *and* the other port |
| 0 | none | keepalive, sent forever once the check passes | the address it was sent to |

The keepalives continue for the whole session. They are not part of classification, but the
responder must stay up to answer them.

## The reply

**Ours**, with the attribute set and the XOR key **Reference**-derived from a capture of the real
Konami server and then confirmed live.

A Binding Response (`0x0101`), echoing the request's 16-byte transaction id, carrying four
attributes in this order:

| type | name | value |
| --- | --- | --- |
| `0x0001` | MAPPED-ADDRESS | the client's address and port as we saw them |
| `0x0004` | SOURCE-ADDRESS | the address and port we are replying *from* |
| `0x0005` | CHANGED-ADDRESS | the *other* address and port, i.e. where a change-request would be answered from |
| `0x8020` | XOR-MAPPED-ADDRESS | the mapped address, obfuscated |

Two details that look like Konami peculiarities and are not:

- The XOR-mapped attribute is tagged **`0x8020`**, not the RFC 5389 `0x0020`.
- It is XORed against the **request's transaction id**, not the RFC 5389 magic cookie:
  `port ^ txid[0:2]`, `ip ^ txid[0:4]`, both big-endian. Verified by reproducing a captured
  packet exactly: for txid `eb55d721…` and client `47.205.42.160:5730` it yields port `fd37`,
  ip `c498fd81`, matching the capture byte for byte.

MAPPED-ADDRESS must report the port the client actually sent from (`5730`), unmodified.

### Where this dialect comes from

**Confirmed against primary sources.** This is not a custom protocol. It is
**`draft-ietf-behave-rfc3489bis-02`** (July 2005), the working draft that became RFC 5389 — and
`0x8020` appears in *exactly one* published version of it:

| draft | dated | XOR-MAPPED type | magic cookie | transaction id |
| --- | --- | --- | --- | --- |
| `-00`, `-01` | Oct 2004, Feb 2005 | `0x0020` | no | 128 bit |
| **`-02`** | **Jul 2005** | **`0x8020`** | **no** | **128 bit** |
| `-03` … `-18` | Feb 2006 → 2009 | `0x0020` | yes | 96 bit |

Draft `-03` §11.15 says so in as many words: *"Version -02 of this Internet Draft used 0x8020 for
this attribute, which was in the Optional range… This attribute has been moved back to 0x0020."*
And `-02` §10.2.12 specifies the XOR key as *"the most significant 16 bits of the transaction ID"*
for the port and 32 bits for the address — bit for bit what our responder does.

The two oddities are therefore **one** oddity: the magic cookie was carved out of RFC 3489's
128-bit transaction id in `-03`, and the attribute moved in the same revision. `0x8020` plus
transaction-id XOR is a single coherent snapshot of the spec as it stood in late 2005.

MGO2 shipped in June 2008; RFC 5389 was published in **October 2008**, after the game was on
shelves. The client could not have targeted the final RFC. RFC 3489 (2003) has no
XOR-MAPPED-ADDRESS at all.

Corroboration that this was a real deployed dialect rather than a misreading:

- **Microsoft [MS-TURN] §2.2.2.1** normatively cites *"[IETFDRAFT-STUN-02] section 10.2.12"*, sets
  the attribute type to `0x8020`, and XORs against the transaction id. Lync/OCS spoke it too.
- **Wireshark** carries `#define MS_XOR_MAPPED_ADDRESS 0x8020 /* MS-TURN */`.
- **IANA** never permanently assigned `0x8020`; it sits in `0x8005-0x8021 Unassigned`.

**The likely server:** Vovida `stund`, the RFC 3489 reference implementation. Its `stun.h` has
`const UInt16 XorMappedAddress = 0x8020;`, its response builder XORs against the transaction id
with the same 16/32-bit split, and `stunEncodeMessage()` emits attributes in a fixed order that for
a binding response is exactly `0x0001, 0x0004, 0x0005, 0x8020` — **the precise four attributes, in
the precise order, of the Konami capture**. One hypothesis explains the tag, the key, the attribute
set and the ordering at once, with nothing Konami-specific left over.

## Never echo the client's `0xf000` vendor attribute

**Confirmed, and this is the single most important fact in this file.**

The client tags its own probes with a private Konami attribute, type `0xf000`. The responder
originally echoed it back, on the untested theory that "a client that correlates requests by a
private attribute will not accept a reply without it."

That theory was wrong, and the echo is what hung the game on "Adjusting port settings" — no error,
no timeout, just a permanent stall.

The client's `DecodePacket` dispatches on the attribute's sub-type. Sub-types 1 and 3 have
handlers; **anything else falls through to a logging stub and then an infinite branch** (`b .`).
The values the client sends are not ones it can receive: the basic probe carries
`0573000000000002` and the change-request probe `057300000000000400000004`. Echoing either back
hands the decoder a sub-type it cannot dispatch, and it spins forever.

Sending **no `0xf000` at all** fixes it. This is also what the only reference server known to work
online does: `boiln/echo` runs stock **coturn**, which has no notion of Konami vendor attributes
and sends none.

The behaviour was confirmed in both directions — echoing reproduced the hang, omitting it produced
a pass — so this is causal, not correlation. `echo_vendor` therefore defaults to **off** in
`stun_probe.py`, and `--echo-vendor` exists only to reproduce the hang deliberately.

**Sending nothing is also what the standard requires**, which is a better reason than "it works".
RFC 3489 §11.2 and RFC 5389 §18.2 put attribute types `0x8000-0xFFFF` in the
**comprehension-optional** range: a conformant peer must ignore what it does not understand.
`0xf000` is in that range and is unassigned at IANA, and `stund`, coturn and stuntman all silently
drop it. So every conformant server ignores this attribute — our default is the standards-correct
behaviour, not a workaround.

### What the attribute actually contains

**Confirmed, read out of `MGO2.elf`.** This was an open question for a long time and it need not
have been; the client both builds and parses these, so the layout is in the binary.

`DecodePacket` unpacks the attribute at `0xD89A40` using the format string `"nnN"` taken from
`TOC-0x5c78` (`0x102F730` → `0xE2CDC8`). In this codebase's pack convention — the same one behind
the `nnx16nnNnnnnNN` builder format elsewhere — `n` is a big-endian `u16` and `N` a big-endian
`u32`. That resolves both observed values exactly:

```
0573 0000 00000002                 basic probe        magic, zero, sub-type 2
0573 0000 00000004  00000004       change-request     magic, zero, sub-type 4, + 4 bytes
```

So the leading `0x0573` is a fixed magic, the second halfword is unused, and the third field is a
**sub-type**. The client dispatches on it at `0xD89A64`, and the two handlers say what it is for:

| sub-type | handler | effect |
| --- | --- | --- |
| 1 | `0xD89B30` | stores `-1` and `0` into the result — **"no address"** |
| 3 | `0xD89B44` | unpacks `"nnN"` again and stores a `u32` address and `u16` port |
| anything else | `0xD89A78` | logs `ex_info[%08x]` through an assert, then `b .` — **hangs forever** |

`0xf000` is therefore **Konami's private address-carrying attribute**, running alongside the
standard `CHANGED-ADDRESS`: sub-type 3 conveys an alternate address and port, sub-type 1 says there
isn't one. The client **sends** sub-types 2 and 4 and **handles** 1 and 3 — requests even,
responses odd — which is why echoing its own attribute back is fatal rather than merely useless.
There is no handler for a request sub-type, so the decoder falls through to the assert and spins.

This also settles that the real server *did* send `0xf000`, and what it put in it. We still send
none, which is safe: the client passes without it, and the fields it would populate are only
consulted on the branch our client never takes. Sending sub-type 1 (or 3, with the alternate
address) would be the faithful thing to do if the branch-4 path ever needs exercising.

## What the client is actually doing, and why two addresses

**Confirmed against RFC 3489 §10.1.** The client is not running a cut-down or custom algorithm. It
is running the standard tree, and our server makes it terminate on the shortest branch:

1. **Test I** — basic Binding Request. No answer means UDP is blocked. On an answer, compare
   MAPPED-ADDRESS against the local socket address.
2. **If MAPPED == local** (no NAT in the path): run Test II. Answered → verdict **"open
   Internet"**. Unanswered → symmetric UDP firewall. *Terminal either way; Test III never sent.*
3. **If MAPPED != local** (NAT'd): run Test II. Answered → verdict **"full-cone NAT"**.
   *Terminal; Test III never sent.*
4. **Only if Test II goes unanswered** does the client re-run Test I against CHANGED-ADDRESS to
   detect symmetric NAT, then run Test III (change-port only) to separate restricted-cone from
   port-restricted-cone.

So "basic, then change-both, then stop" is the complete and correct sequence for anyone whose
Test II succeeds. Nothing is being skipped.

**This also answers what verdict our client reached.** In the captured run the client was
`192.168.1.100:5730` and MAPPED-ADDRESS came back `192.168.1.100:5730` — identical, so branch 2
applies and the verdict was **"on the open Internet"**. A genuinely NAT'd player taking branch 3
would get **full-cone**. That is a derivation from a deterministic flow chart applied to our own
logged bytes, not a guess.

### Why two addresses

**Confirmed.** RFC 3489 §8.1: *"A STUN server MUST be prepared to receive Binding Requests on four
address/port combinations — (A1, P1), (A2, P1), (A1, P2), and (A2, P2)."* RFC 5780 §6 is stricter
still: a server that cannot allocate the same port on two addresses **MUST** answer any
CHANGE-REQUEST with a 420 error rather than fudge it.

Our responder serves all four when given a second address:

```
python3 dev/stun_probe.py 3478 192.168.1.100 192.168.1.201
```

**A single address will still get this client past the port check** — and that corrects an earlier
claim here that it "cannot distinguish full-cone from symmetric". Two things are now clear:

- The client never checks *where* a reply came from. RFC 3489 §9.3 imposes no such check, and
  §10.1 branches purely on whether a response arrived. So answering change-ip from another port on
  the same address is not detected, and the check passes.
- What it actually breaks is **full-cone vs restricted-cone**, not symmetric. Per §5 a restricted
  cone filters on *address only*, so a reply from the same address on a different port passes its
  filter. That player is told "full cone" and will then attempt direct connections that only a real
  full-cone peer could accept.

Symmetric NAT is detected by re-running Test I against CHANGED-ADDRESS (branch 4), not by Test II
at all — which is precisely why the CHANGED-ADDRESS bug below mattered.

Since MGO2 matches are peer to peer, the cost of a single address is misrouted P2P for
restricted-cone players rather than a failed port check. Keep two.

### CHANGED-ADDRESS is relative to where the request arrived

**Fixed here after being wrong.** RFC 3489 §9.2 Table 1 gives the source address, source port and
CHANGED-ADDRESS for each flag combination, and CHANGED-ADDRESS is `Ca:Cp` on **every** row — the
server's *other* socket relative to where the request arrived, never a function of where this
particular reply is being sent.

We previously derived it from the reply address. For a change-ip+port request arriving on `A1:P1`
that produced `CHANGED-ADDRESS = A1:P1` — pointing the client back at the socket it had just used.

It survived unnoticed because **Test I is the only test that completes on a LAN bench**, and for
Test I the two derivations agree. It would have mattered to a real player on branch 4: they re-run
Test I against CHANGED-ADDRESS to detect symmetric NAT, and would have been comparing the primary
socket against itself. `stun_probe.py` now implements Table 1 directly, verified across all
sixteen arrival/flag combinations.

## Off-the-shelf alternatives

**Confirmed from source.** Our Python responder is not the only option, and for anyone not wanting
to run it there is a maintained server that speaks this exact dialect.

**Stuntman** (`github.com/jselbie/stunserver`) implements it natively and auto-detects it:

- `stuncore/stuntypes.h` — `// 0x8020 is not defined in any RFC, but is the value that Vovida
  server uses`, `STUN_ATTRIBUTE_XORMAPPEDADDRESS_OPTIONAL = 0x8020`.
- `stunreader.cpp` — `_fMessageIsLegacyFormat = !(cookie == STUN_COOKIE);`. MGO2 sends a 128-bit
  transaction id with no magic cookie, so legacy mode engages automatically with no configuration.
- In legacy mode it emits SOURCE-ADDRESS/CHANGED-ADDRESS rather than RESPONSE-ORIGIN/OTHER-ADDRESS,
  XORs against the transaction id, and its handler carries the comment *"paranoia — just to be
  consistent with Vovida, send the attributes back in the same order… I suspect there are clients
  out there that might be hardcoded to the ordering"*. MGO2 is exactly such a client.

Run it as `stunserver --mode full --primaryinterface <A1> --altinterface <A2>`. Being conformant,
it ignores comprehension-optional attributes and so never echoes `0xf000`.

**coturn will not work as a drop-in.** It defines `OLD_STUN_ATTRIBUTE_XOR_MAPPED_ADDRESS (0x8020)`
but never uses the constant: in old-STUN mode it sends MAPPED-ADDRESS, SOURCE-ADDRESS and
CHANGED-ADDRESS and **no XOR attribute at all**. That is worth knowing for a second reason — the
claim below that `boiln/echo` runs stock coturn online could not be verified from public sources,
and if it *is* true then XOR-MAPPED-ADDRESS is optional to this client, since coturn never sends
one. Untested either way.

## Checking the responder

`dev/stun_selftest.py` probes a running responder and asserts every claim in the section above —
the four attributes and their order, the `0x8020` tag, that XOR-MAPPED decodes back to
MAPPED-ADDRESS under the transaction-id key, that SOURCE and CHANGED point where they should, and
that no `0xf000` comes back. Run it with the stack up:

```
python3 dev/stun_selftest.py
```

Thirteen checks, all passing as of the last run. It exists so that a change which would hang the
game shows up as a named failing assertion rather than as a client stuck on "Adjusting port
settings" with no other symptom.

The CHANGE-REQUEST leg cannot be checked from inside WSL: the responder answers it correctly and
the real client receives it, but WSL's mirrored networking will not loop a packet from the
secondary address back to a WSL-local socket, so the script would wait for a reply that reached
the emulator perfectly well. It skips that leg with instructions to confirm it from the responder
log instead. Running the script from a separate host would cover it properly.

## Docker networking

**Confirmed.** The responder must run with `network_mode: host`, not published ports.

Docker's UDP proxy rewrites the source port of replies. A STUN client identifies *which address and
port answered* — that is the entire mechanism by which it classifies. Behind the proxy every reply
appears to come from a random port, so discovery never concludes. Published ports look like they
work, because the reply does arrive, just from the wrong place.

The secondary address must also be a real address on the host, added with
`ip addr add 192.168.1.201/24 dev <iface>`. It does **not** survive a WSL restart, and the
interface may be renamed across restarts (`eth1` became `eth8` once), so re-check it after one — a
missing secondary makes `probe-stun` crash-loop on bind with `Errno 99 Address not available`.

## Eliminated hypotheses

The point of writing these down is not to re-test them.

**The "STTN" text protocol is not required.** A disassembly pass concluded that a passing verdict
could *only* be produced by a separate Konami text/HTTP-style protocol on a secondary server —
`STTN_init` at `0xD8AC50` returning `0x1201`, needing a reply with status `200` and a body
containing `RESULT`, `MAPPED-ADDRESS=` and the token `true`, with anything else forcing the verdict
byte to `2` and failing. It named real addresses and was internally coherent.

It is nonetheless **refuted by observation**: the client passes the port check against a responder
that speaks pure RFC 3489 and implements no text protocol whatsoever. Whatever those code paths do,
they are not on the path this client takes. This is a good example of a detailed static-analysis
result that was simply about a different code path than the one that runs — the observation that
settles it is that we pass, today, with no STTN endpoint in existence.

**The mapped-address-equals-server-address collision does not force a symmetric verdict.** See the
caveat above; we pass with both equal.

**`0692:00000003` was not our client's problem.** That verdict was seen on the MGO2PC custom build,
a different game build on a patched emulator, and its cause there was a local UDP `5730` collision
— a stale RPCS3 instance holding the port. Closing it let that client through. Our client's stall
on the same screen had a different cause entirely (the vendor echo), so the two should not be
conflated. The operational rule that survives is: **one RPCS3 instance at a time**, with `5730`
verified free (`netstat -ano | findstr :5730`).

**RPCS3 does not perform or assist the port check.** The `sys_net_infoctl` TODOs in the emulator
log are unrelated — the custom build that works has the identical stubs. The game's own `mrdUPnP`
code does all of it over ordinary UDP sockets.

## Still unknown

Three of the five entries that used to be here are now answered — see "Where this dialect comes
from" for the `0x8020` provenance, "What the client is actually doing" for the verdict, and "Why
two addresses" for the single-address question. What remains:

1. ~~**What `0xf000` carries.**~~ **RESOLVED** — read out of the binary: a magic `0x0573`, an
   unused halfword, and a sub-type; sub-type 3 carries an address and port, sub-type 1 says there
   is none. The even/odd request-response pairing that was a guess here is now derived from the
   dispatch table. See "What the attribute actually contains". What remains unknown is only why
   `0x0573` is that value.
2. **Whether any of the four reply attributes are optional.** We send all four because Vovida
   `stund` did and because the capture shows all four. Nobody has bisected them against this
   client. There is one indirect hint: coturn in old-STUN mode sends no XOR-MAPPED-ADDRESS at all,
   so if the `boiln/echo`-runs-coturn claim is true, that attribute at least is optional.
3. **Whether `boiln/echo` really runs stock coturn.** Used here as precedent, but the repository
   could not be found publicly and the claim is uncited. The conclusions it was supporting now rest
   on the RFCs instead, so nothing depends on it — but it should not be repeated as fact.
4. **What the client does with a single-address CHANGED-ADDRESS.** Untested. The reasoning above
   says a restricted-cone player would be misclassified as full-cone, which is an argument from the
   NAT definitions in RFC 3489 §5 rather than an observation.
5. **Whether `mrd` is a known middleware vendor.** No trace of `mrdUPnP`, `mrd_upnp`, or the same
   library in another PS3-era title. No public documentation, capture, or reimplementation of
   MGO2's own STUN server was found either — this file may be the only writeup of it.

## Sources

Primary sources, all read rather than cited second-hand:

- `draft-ietf-behave-rfc3489bis-00` … `-18`, IETF archive. `-02` §10.2.12 is the dialect we
  implement; `-03` §11.15 records the move back to `0x0020`, and `-03` §6 introduces the magic
  cookie.
- RFC 3489 §§5, 8.1, 9.2, 9.3, 10.1, 11.2 — NAT definitions, the four-socket requirement,
  Table 1, client processing, the classification tree, the optional-attribute range.
- RFC 5389 §18.2 — the comprehension-required/optional split. RFC 5780 §6 — the 420 requirement.
- IANA STUN Parameters registry — `0x8020` and `0xf000` both unassigned.
- Microsoft [MS-TURN] §2.2.2.1 — cites draft `-02` and the same `0x8020`.
- Vovida `stund` (`stun.h`, `stun.cxx`), Stuntman (`stuntypes.h`, `stunreader.cpp`,
  `stunbuilder.cpp`, `messagehandler.cpp`), coturn (`ns_turn_msg_defs.h`, `ns_turn_msg.c`,
  `ns_turn_server.c`), Wireshark `packet-stun.c`.
