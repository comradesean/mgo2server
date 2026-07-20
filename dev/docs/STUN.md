# The port check (STUN)

MGO2 runs NAT discovery before it will allow online play, shown as **"Adjusting port settings"**.
Matches are peer to peer, so the client needs to know how its UDP port looks from outside. If the
server gets this wrong the game hangs on that screen with no error and no timeout.

Our responder is `dev/runtime/stun_probe.py`, run as the `probe-stun` service. `dev/docs/PROTOCOL.md` covers the
TCP lobby protocol and has no bearing here: this is UDP, on its own thread in the client, sharing
nothing with the lobby servers — and none of the ciphers in `dev/docs/CRYPTO.md` either. STUN packets
are plaintext.

## The dialect: draft-ietf-behave-rfc3489bis-02

The client is a standard STUN implementation, but of a **2005 working draft**, not of RFC 5389.
That single fact explains everything which otherwise looks like a Konami invention.

| draft | dated | XOR-MAPPED type | magic cookie | transaction id |
| --- | --- | --- | --- | --- |
| `-00`, `-01` | Oct 2004, Feb 2005 | `0x0020` | no | 128 bit |
| **`-02`** | **Jul 2005** | **`0x8020`** | **no** | **128 bit** |
| `-03` … `-18` | Feb 2006 → 2009 | `0x0020` | yes | 96 bit |

`0x8020` appears in exactly one published version. Draft `-03` §11.15: *"Version -02 of this
Internet Draft used 0x8020 for this attribute, which was in the Optional range… This attribute has
been moved back to 0x0020."* The magic cookie arrived in that same revision (`-03` §6), carved out
of RFC 3489's 128-bit transaction id — so `0x8020` and transaction-id XOR are not two quirks but
one consistent snapshot of the spec.

MGO2 shipped June 2008; RFC 5389 was published October 2008. The client predates the final RFC.
RFC 3489 (2003) has no XOR-MAPPED-ADDRESS at all.

The same dialect appears in Microsoft's [MS-TURN] §2.2.2.1, which cites `draft-02` and uses
`0x8020`, and is emitted by Vovida `stund` — whose response builder produces exactly the four
attributes below, in exactly this order, with exactly this XOR key. `stund` or a derivative is the
most likely origin of the server Konami ran.

## Message format

Standard STUN framing: 20-byte header (type, length, 16-byte transaction id) then 4-byte-aligned
attributes. No magic cookie. Everything big-endian.

**Requests the client sends** — three shapes, and no others have been observed:

| body | attributes | what it is |
| --- | --- | --- |
| 12 | `0xf000` sub-type 2 | Test I (`0x2401`) |
| 24 | `CHANGE-REQUEST` value `6` + `0xf000` sub-type 4 | Test II (`0x2402`) |
| 0 | none | keepalive — see Confidence, its origin is not identified |

Tests I′ and III (`0x2403`, `0x2404`) exist and are documented under Classification, but only run
when Test II goes unanswered, which has never happened here.

**Binding Response (`0x0101`)** — echo the request's transaction id, then four attributes in this
order. Order matters: Stuntman carries a comment that Vovida-era clients are hardcoded to it.

| type | name | contents |
| --- | --- | --- |
| `0x0001` | MAPPED-ADDRESS | the client's address and port as observed; the port must be unmodified |
| `0x0004` | SOURCE-ADDRESS | the address and port this reply is sent *from* |
| `0x0005` | CHANGED-ADDRESS | the server's *other* socket — see Table 1 |
| `0x8020` | XOR-MAPPED-ADDRESS | MAPPED-ADDRESS obfuscated |

XOR-MAPPED is keyed on the **transaction id**, not a magic cookie: `port ^ txid[0:2]`,
`ip ^ txid[0:4]`, big-endian (`draft-02` §10.2.12). Verified against a capture of the real Konami
server: txid `eb55d721…`, client `47.205.42.160:5730` → port `fd37`, ip `c498fd81`.

## The `0xf000` attribute

Konami's private attribute, carrying an address in their own encoding alongside the standard
`CHANGED-ADDRESS`. It sits in the `0x8000-0xFFFF` comprehension-optional range, so a conformant
server ignores it — which is what we do.

The client parses it with the format string `"nnN"` (two `u16`, one `u32`):

```
0573 0000 00000002              magic, unused, sub-type 2   (basic probe)
0573 0000 00000004 + 00000004   magic, unused, sub-type 4   (change request)
```

`0x0573` is a hardcoded immediate, emitted at the three attribute builders with no derivation
anywhere in the binary.

| sub-type | direction | meaning |
| --- | --- | --- |
| 1 | server → client | no alternate address (stores `-1` / `0`) |
| 2 | client → server | basic probe |
| 3 | server → client | an alternate address: `u32` address, `u16` port |
| 4 | client → server | change request |

Requests are even, responses odd.

**The decoded address is never used.** The parser stores it at offset `+0x30`/`+0x34` of the
response record, and nothing in the worker ever reads that offset — the record lives on the
worker's stack, so nothing outside can either. `CHANGED-ADDRESS` (`0x0005`) is consumed separately
and is what actually drives Test I′ and Test III. So omitting `0xf000` changes no decision the
client makes; its only functional weight is the hang below.

### Never echo it back

**The client hangs forever on a sub-type it does not expect.** Its decoder dispatches on the
sub-type; 1 and 3 have handlers, and anything else falls through an assert into an infinite branch.
Since the client sends 2 and 4, echoing its own attribute back guarantees the hang — presenting as
"Adjusting port settings" with no error and no timeout.

Send no `0xf000` at all. That is both the fix and the standards-correct behaviour: comprehension-
optional attributes are meant to be ignored, and `stund`, coturn and Stuntman all drop it silently.

`echo_vendor` defaults to off; `--echo-vendor` exists only to reproduce the hang deliberately.

## Classification (RFC 3489 §10.1)

**Confirmed from the binary**, not inferred from behaviour. The client runs the standard tree, and
the worker at `0xD89B78` drives it from a static test list at `0xE2CD08+0x5c`:

```
2401  2402  2403  2404  240B          (240B terminates)
```

| id | destination | body | RFC role |
| --- | --- | --- | --- |
| `0x2401` | primary | 12 (with `0xf000` sub-type 2) | Test I |
| `0x2402` | primary | 24, CHANGE-REQUEST value **6** (change IP + port) | Test II |
| `0x2403` | CHANGED-ADDRESS | 0 | Test I repeated, for symmetric detection |
| `0x2404` | CHANGED-ADDRESS | 8, CHANGE-REQUEST value **2** (change port only) | Test III |

The tree, with the verdict each branch assigns:

| outcome | verdict | meaning |
| --- | --- | --- |
| Test I no reply | `2` | UDP blocked |
| Test II replies, local == mapped | **`0x10`** | **open Internet** |
| Test II replies, local != mapped | **`0x90`** | **full-cone NAT** |
| Test II silent, local == mapped | `0x30` | symmetric UDP firewall |
| Test I′ mapping differs | `0xD0` | symmetric NAT |
| Test III replies / silent | `0xB1` / `0xB3` | restricted / port-restricted cone |

The verdict is a `u16` written by a **single instruction** — `sth r14, 0xa18(obj)` at `0xD8A538`,
the worker's one exit. It surfaces to the game as key `0x2102`; the classifier at `0xBBEA48` masks
off a flag bit and **passes on `0x10` and `0x90`, failing everything else**.

Retries and timeouts also match the RFC: four attempts, timeout `100 << retry` ms.

So on a LAN with no NAT the client gets `0x10`; a player behind a router gets `0x90`. Both pass, and
**Test II succeeding is the single load-bearing fact** — tests `0x2403`/`0x2404` still run but their
validators preserve an already-nonzero verdict.

One behaviour not in the RFC: if Test I's mapped **port** differs from the local port, the worker
runs an extra probe (`0x2409`) and re-runs Test I before continuing, and can then yield `0x50`
(address preserved, port translated).

## Server requirements

### Four sockets

RFC 3489 §8.1: *"A STUN server MUST be prepared to receive Binding Requests on four address/port
combinations — (A1, P1), (A2, P1), (A1, P2), and (A2, P2)."*

`P1` is the port the client dials, 3478. **`P2` is simply `P1 + 1`, i.e. 3479** — the standard does
not fix it, and the client learns it from the CHANGED-ADDRESS we send, so any free port works as
long as it is reported consistently. Our responder uses `primary + 1`.

```
python3 dev/runtime/stun_probe.py 3478 <A1> <A2>
```

RFC 5780 §6 goes further: a server that cannot provide a second address **MUST** reject
CHANGE-REQUESTs with a 420 rather than answer from the wrong place.

**A single address will still pass this client's check.** The client never inspects where a reply
came from — §9.3 imposes no such check and §10.1 branches purely on whether a response arrived. But
it misclassifies: a restricted cone filters on *address only* (§5), so answering change-ip from
another port on the same address passes its filter, and that player is reported full-cone. They
then attempt direct connections only a real full-cone peer could accept. Matches are peer to peer,
so use two addresses.

### Table 1: reply source and CHANGED-ADDRESS

RFC 3489 §9.2. Everything is relative to where the request **arrived** (`Da:Dp`); `Ca:Cp` is the
server's other socket. CHANGED-ADDRESS is `Ca:Cp` on every row — it describes the other socket, not
this reply's route.

| flags | source address | source port | CHANGED-ADDRESS |
| --- | --- | --- | --- |
| none | Da | Dp | Ca:Cp |
| change IP | Ca | Dp | Ca:Cp |
| change port | Da | Cp | Ca:Cp |
| change IP and port | Ca | Cp | Ca:Cp |

Deriving CHANGED-ADDRESS from the reply address instead is wrong for exactly the requests that ask
the server to move, and it hides on a LAN: Test I is the only test that completes there, and for
Test I the two derivations agree. It surfaces on branch 4, where the client re-runs Test I against
CHANGED-ADDRESS and would compare the primary socket against itself.

### Host networking

The responder must run with `network_mode: host`. Docker's UDP proxy rewrites the source port of
replies, and a STUN client identifies *which address and port answered* — that is the entire
classification mechanism. Behind the proxy every reply appears to come from a random port and
discovery never concludes. Published ports look like they work, because the reply does arrive.

The second address must exist on the host (`ip addr add <A2>/24 dev <iface>`). It does **not**
survive a reboot, and the interface is renamed across WSL restarts (`eth1` → `eth8` → `eth0` have
all been seen), so check the current name. A missing secondary makes `probe-stun` crash-loop on
bind with `Errno 99`.

## Checking the responder

`dev/tools/stun_selftest.py` asserts the reply format against a running responder: the four attributes and
their order, the `0x8020` tag, XOR-MAPPED decoding back to MAPPED under the transaction-id key,
SOURCE and CHANGED pointing where they should, and no `0xf000` echoed. Thirteen checks.

It exists because a regression here produces no error — just a hung game.

The CHANGE-REQUEST leg cannot be checked from inside WSL: mirrored networking will not loop a packet
from the secondary address back to a WSL-local socket, though the same reply reaches the emulator
normally. The script skips it and points at the log line that confirms it by hand.

## Off-the-shelf alternatives

**Stuntman** (`github.com/jselbie/stunserver`) speaks this dialect natively and auto-detects it — a
128-bit transaction id with no magic cookie puts it in legacy mode, where it emits
SOURCE-ADDRESS/CHANGED-ADDRESS, tags XOR-MAPPED `0x8020`, XORs against the transaction id, and
preserves Vovida attribute ordering. Being conformant it ignores `0xf000`.

```
stunserver --mode full --primaryinterface <A1> --altinterface <A2>
```

**coturn will not work as a drop-in.** It defines `OLD_STUN_ATTRIBUTE_XOR_MAPPED_ADDRESS (0x8020)`
but never uses it: in old-STUN mode it sends MAPPED-ADDRESS, SOURCE-ADDRESS and CHANGED-ADDRESS and
no XOR attribute at all.

## Confidence

**Verified against the real client** (`BLUS30109`, stock RPCS3): the request shapes, the
four-attribute reply and its XOR key, the vendor-echo hang (reproduced in both directions), and a
completed port check that proceeds to login. Our frame validator has never rejected a client packet
as malformed and the client has never sent an attribute outside the set above — on the paths
exercised it is byte-for-byte conformant.

**Confirmed from the binary, though never exercised here:** the whole of the decision tree,
including the branches our LAN client never takes. The test list, every builder and validator, the
verdict values and the single instruction that writes them are all read out of `MGO2.elf`. So
branch 4 is understood even though no client has driven it, and the Table 1 routing serving it was
checked across all sixteen arrival/flag combinations.

**Not established:**

- Whether MAPPED, SOURCE and CHANGED are each individually required. **XOR-MAPPED is not in
  question: it is mandatory.** An early responder sent three attributes and the client rejected the
  reply; adding `0x8020` is what made the port check proceed. That was an accidental bisection, but
  a decisive one. (coturn's old-STUN mode sends no XOR attribute at all, so it would not work here
  as a drop-in — noted under Off-the-shelf alternatives.)
- Behaviour against a STUN error response, or under packet loss.
- **Where the keepalives come from.** The heartbeat in this module (`0x2408`, via
  `mrdUPnP_STUN_hartbeat` at `0xD8AB78`) sends a 40-byte request with a `0x14` body. What we
  actually receive is a **20-byte header-only** Binding Request with no attributes — our validator
  asserts datagram length equals `20 + declared length` and has never fired, so this is certain, not
  a parsing artefact. Something outside the traced module is sending them. Harmless, since answering
  them keeps the client happy, but unexplained.

## Eliminated

**A separate "STTN" text protocol is not required, and now we know why.** An earlier disassembly
pass concluded a passing verdict could only come from a Konami text/HTTP protocol on a secondary
server. It was wrong twice over: it missed the UDP worker's own writer at `0xD8A538`, and the
protocol is chosen by `obj+0xa40`, whose **default is `0x2203`** (set at object init) routing to the
UDP worker. `STTN` runs only when that field is `0x2202`. The pure-STUN path is the default, which
is why a plain responder passes.

**A mapped address equal to the server address does not force a symmetric verdict.** We pass with
both equal.

## Sources

`draft-ietf-behave-rfc3489bis-02` §10.2.12 (the dialect), `-03` §6 and §11.15 (the move away from
it). RFC 3489 §§5, 8.1, 9.2, 9.3, 10.1, 11.2. RFC 5389 §18.2. RFC 5780 §6. IANA STUN Parameters
registry (`0x8020` and `0xf000` both unassigned). Microsoft [MS-TURN] §2.2.2.1. Vovida `stund`,
Stuntman, coturn, Wireshark `packet-stun.c`. `MGO2.elf` for the `0xf000` decode and the builders.
