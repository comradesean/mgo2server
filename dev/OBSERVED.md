# Observed client behaviour

Everything here came from a real client — MGS4, disc `BLUS30109`, running on RPCS3 v0.0.41 — not
from documentation or from other preservation projects. That distinction matters: every value
inferred from the MGO1 and Portable Ops emulators turned out to be wrong for MGO2, including the
policy path, the gate hostname, the gate port and the version-check response byte.

Sources of truth used, in order of usefulness:

1. **RPCS3's own log** (`log/RPCS3.log`) — `DnsHook: DNS query for …` gives real hostnames, and
   `Attempting to connect on <ip>:<port>` gives real ports.
2. **The HTTP/TLS probe** (`dev/http_probe.py`) — exact paths, methods and bodies.
3. **[MiguelRipoll23/mgo2-server](https://github.com/MiguelRipoll23/mgo2-server)** — an independent
   MGO2 server covering the web API that Nomad does not. Nomad is only the game server.

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
