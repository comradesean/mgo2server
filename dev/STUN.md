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

Three request shapes, and that is all the client ever sends:

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

Two details that are easy to get wrong, both settled against a real-server capture:

- The XOR-mapped attribute is tagged **`0x8020`**, not the RFC-5389 `0x0020`.
- It is XORed against the **request's transaction id**, not the RFC-5389 magic cookie:
  `port ^ txid[0:2]`, `ip ^ txid[0:4]`, both big-endian. Verified by reproducing a captured
  packet exactly: for txid `eb55d721…` and client `47.205.42.160:5730` it yields port `fd37`,
  ip `c498fd81`, matching the capture byte for byte.

MAPPED-ADDRESS must report the port the client actually sent from (`5730`), unmodified.

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

**Unknown:** what `0xf000` actually means, what its sub-types 1 and 3 do, and whether there is any
circumstance where the real server sends one. We simply never send it.

## Why two addresses

**Reference, and partly unverified — read the caveat.**

RFC 3489 classification needs the server to be able to answer *from a different IP*: the client
sends CHANGE-REQUEST and infers its NAT type from whether that reply arrives, and from which
address. A responder with one address cannot distinguish a full-cone NAT from a symmetric one.

This is why `boiln/echo`'s `stun.conf` requires two `listening-ip` entries, and why SaveMGO ran its
STUN server on a different address from its gate (its DNS mapped the gate to `192.3.217.61` and the
STUN host to `192.3.217.162`).

Our responder serves the full four-socket layout when given a second address:

```
python3 dev/stun_probe.py 3478 192.168.1.100 192.168.1.201
```

binding `.100:3478`, `.100:3479`, `.201:3478`, `.201:3479`. With one address it falls back to
answering change-IP from the alternate *port*, which lets the client conclude something rather than
hang, but cannot express a full-cone verdict.

**Caveat, and an open question.** Both addresses were present on the run that passed, so the
two-address layout is *sufficient*. Whether it is *necessary* has never been tested: nobody has run
single-address mode with `echo_vendor` off. It is entirely possible the vendor echo was the only
real blocker and one address would pass too. The experiment is cheap — drop the second argument,
restart `probe-stun`, boot the game — and until someone runs it, "you need two IPs" is inherited
belief rather than a result.

Note also that the run which passed had the **primary responder address equal to the client's own
address** (`192.168.1.100` for both), so the mapped address and the server address were identical.
An earlier theory held that this collision would force a symmetric verdict and had to be avoided.
That theory is **refuted**: it passed anyway.

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

1. **What `0xf000` carries.** Sub-types 1 and 3 have handlers in the client; the values it sends
   (`…0002`, `…0004…`) are neither. Whether the real server ever sent one, and what it meant, is
   unknown. We avoid the question by sending nothing.
2. **Whether the second address is actually required** with the vendor echo off. Untested; cheap to
   test. See "Why two addresses".
3. **What NAT verdict the client actually settled on.** We know it passed and stopped complaining.
   We never read the verdict byte back out of the client to see whether it concluded full-cone,
   restricted, or something else — so we do not know how much headroom the current setup has, or
   whether a stricter real-world NAT would still pass.
4. **Whether any of the four reply attributes are optional.** We send all four because the real
   server did. Nobody has bisected them against this client with the vendor echo off.
5. **The `CHANGED-ADDRESS` semantics when only one address is configured.** The fallback answers
   change-IP from the alternate port and reports something plausible in `CHANGED-ADDRESS`, but what
   the client makes of that has not been checked.
