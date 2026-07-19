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
account servers. `dev/stun_probe.py` implements just enough of it: the classic binding
request/response plus XOR-MAPPED-ADDRESS.

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
