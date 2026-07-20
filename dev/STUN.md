# The port check (STUN)

MGO2 runs NAT discovery before it will allow online play, shown as **"Adjusting port settings"**.
Matches are peer to peer, so the client needs to know how its UDP port looks from outside. If the
server gets this wrong the game hangs on that screen with no error and no timeout.

Our responder is `dev/stun_probe.py`, run as the `probe-stun` service. `dev/PROTOCOL.md` covers the
TCP lobby protocol and has no bearing here: this is UDP, on its own thread in the client, sharing
nothing with the lobby servers — and none of the ciphers in `dev/CRYPTO.md` either. STUN packets
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

| body | attributes | RFC 3489 role |
| --- | --- | --- |
| 12 | `0xf000` | Test I, basic Binding Request |
| 24 | `CHANGE-REQUEST` (change-ip + change-port, `0x06`) + `0xf000` | Test II |
| 0 | none | keepalive, repeated for the session once the check passes |

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

### Never echo it back

**The client hangs forever on a sub-type it does not expect.** Its decoder dispatches on the
sub-type; 1 and 3 have handlers, and anything else falls through an assert into an infinite branch.
Since the client sends 2 and 4, echoing its own attribute back guarantees the hang — presenting as
"Adjusting port settings" with no error and no timeout.

Send no `0xf000` at all. That is both the fix and the standards-correct behaviour: comprehension-
optional attributes are meant to be ignored, and `stund`, coturn and Stuntman all drop it silently.

`echo_vendor` defaults to off; `--echo-vendor` exists only to reproduce the hang deliberately.

## Classification (RFC 3489 §10.1)

The client runs the standard decision tree — not a cut-down or custom algorithm.

1. **Test I** — basic Binding Request. No answer → UDP blocked. On an answer, compare
   MAPPED-ADDRESS with the local socket address.
2. **MAPPED == local** (no NAT): run Test II. Answered → **open Internet**. Unanswered → symmetric
   UDP firewall. Terminal either way.
3. **MAPPED != local** (NAT'd): run Test II. Answered → **full-cone NAT**. Terminal.
4. **Test II unanswered**: re-run Test I against CHANGED-ADDRESS to detect symmetric NAT, then run
   Test III (change-port only) to separate restricted-cone from port-restricted-cone.

"Basic, then change-both, then stop" is the complete correct sequence for anyone whose Test II
succeeds — branches 2 and 3. Nothing is skipped.

On a LAN with no NAT the client takes branch 2 and concludes **open Internet**. A player behind a
router takes branch 3 and gets **full-cone**. Branch 4 is the only path that issues Test III or a
second Test I.

## Server requirements

### Four sockets

RFC 3489 §8.1: *"A STUN server MUST be prepared to receive Binding Requests on four address/port
combinations — (A1, P1), (A2, P1), (A1, P2), and (A2, P2)."*

```
python3 dev/stun_probe.py 3478 <A1> <A2>
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

`dev/stun_selftest.py` asserts the reply format against a running responder: the four attributes and
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

**Verified against the real client** (`BLUS30109`, stock RPCS3): the three request shapes, the
four-attribute reply and its XOR key, the vendor-echo hang (reproduced in both directions), and a
completed port check that proceeds to login. Across every frame the client has sent, our validator
has never rejected one as malformed and it has never sent an attribute outside the set above — on
the paths exercised it is byte-for-byte conformant.

**Understood from the binary but never exercised:** branch 4. Our client is on a LAN with no NAT, so
it takes branch 2 and terminates. Test III, the second Test I, and the `0xf000` sub-type 1 and 3
handlers have never run. The Table 1 routing serving them is correct by construction — checked
across all sixteen arrival/flag combinations — but has never been driven by a client.

**Not established:** whether all four reply attributes are required (never bisected; coturn's
old-STUN mode sends only three, hinting XOR-MAPPED is optional), how the client behaves against a
STUN error response or under packet loss, and how its internal verdict encoding maps onto the RFC's
named NAT types.

## Eliminated

**A separate "STTN" text protocol is not required.** A disassembly pass concluded a passing verdict
could only come from a Konami text/HTTP protocol on a secondary server. The client passes against a
pure RFC 3489 responder with no such endpoint in existence, so those paths are not the ones this
client takes.

**A mapped address equal to the server address does not force a symmetric verdict.** We pass with
both equal.

## Sources

`draft-ietf-behave-rfc3489bis-02` §10.2.12 (the dialect), `-03` §6 and §11.15 (the move away from
it). RFC 3489 §§5, 8.1, 9.2, 9.3, 10.1, 11.2. RFC 5389 §18.2. RFC 5780 §6. IANA STUN Parameters
registry (`0x8020` and `0xf000` both unassigned). Microsoft [MS-TURN] §2.2.2.1. Vovida `stund`,
Stuntman, coturn, Wireshark `packet-stun.c`. `MGO2.elf` for the `0xf000` decode and the builders.
