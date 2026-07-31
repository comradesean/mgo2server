# Setup

Everything outside this repository that has to be true before an unmodified client can play.

The server side is `docker compose up`. Everything else is emulator and host configuration, and it
comes down to **four required changes** plus one host address for the port check.

Assumed throughout: stock **RPCS3 v0.0.41**, retail disc **BLUS30109**, and a server reachable at
`<SERVER_IP>` — written below as `192.168.1.200`, the value the defaults use. The server owns its
own address, distinct from the machine's primary (`.100`), so a native RPCS3 client can run on
the same machine without sharing an IP with the server — see the host section below.

## Server

```
docker compose up -d
```

Brings up postgres, the migrations, the three lobby servers (gate, account, game), the web service,
and the HTTP/HTTPS/STUN probes.

### Seed the lobbies — required

**The migrations create no lobby rows, and an empty `lobby` table is a silent dead end.** The gate
answers the lobby-list request with a start and an end packet and no entries, so the client has
nowhere to go and reports nothing useful.

```
docker compose exec -T postgres psql -U mgo2server -d mgo2server < dev/tools/seed.sql
```

That inserts one lobby of each type — gate, account, game — on ports 15731/15732/15733, plus a test
account and a news item. **Order matters and is by id**: the client refers to a lobby by its index
in the list it was sent, so the rows must be inserted so that index equals type.

### Create an account

There is **no registration endpoint**. `dev/tools/seed.sql` adds a `tester` account with the password
`nomad`. For any other, insert it by hand — the client sends the password already MD5-hashed, so
that hash is what is stored:

```sql
insert into account (username, password, slots)
values ('<game id>', md5('<password>'), 3);
```

The `username` is whatever is typed into the game's ID field. **The client rejects an ID shorter
than 8 or longer than 32 characters before contacting the server** ("gameid is not long enough"),
so pick a username in that range — observed against a real client, not yet located in the
binary. Unresolved: the 6-character seed account `tester` has logged in successfully, so the
check may not run on every entry path. Passwords are MD5 because the client hashes them before sending; see
`dev/docs/CRYPTO.md`.

## RPCS3 — four changes

All four are required. The game fails differently for each, and none of the failures name their
cause.

### 1. IP swap list

> **This is the emulator route, and it is no longer the only one.** It rewrites the resolver
> *inside* RPCS3, so it changes nothing about the client and cannot help a real PS3. The client's
> own addresses live in disc string resources and can be overridden with a single file,
> `d/testhk` — confirmed live 2026-07-29. See [HOSTS.md](HOSTS.md) for that route and for where the
> addresses actually come from. Either works for an RPCS3 setup; the swap list is the one with
> fewer moving parts, so it stays the documented default here.

Redirects Konami's hostnames to the server. **Settings → Network → IP swap list**, or in
`config/config.yml`:

```
IP swap list: "mgo2web.konami.com=192.168.1.200&&info.service.konamionline.com=192.168.1.200&&mgo2gateus.konamionline.com=192.168.1.200&&mgo2stunna.konamionline.com=192.168.1.200&&mgo2auth.konami.com=192.168.1.200"
```

### 2. The CA certificate

The PS3 validates the server certificate against its own store and **drops the connection before
sending a request** if the chain does not verify — which looks exactly like the server never being
contacted. A self-signed certificate is not enough.

The leaf certificate must cover **every hostname in the swap list**, not just one. The login is on
`mgo2auth.konami.com` and the version check on `mgo2web.konami.com`; a certificate naming only one
fails the other, and both failures look identical (`090B`). The chain in `dev/runtime/tls` already carries
`DNS:mgo2web.konami.com`, `DNS:*.konami.com` and `DNS:*.konamionline.com` — see `dev/runtime/tls/ext.cnf`
if regenerating.

Copy this repository's CA over one of the emulator's certificate slots:

```
cp dev/runtime/tls/ca-cert.pem  <rpcs3>/dev_flash/data/cert/CA30.cer
```

Back up the original first. The client was observed reading `CA29`–`CA31`; `CA30` works. The
matching leaf is already served by `probe-https`.

### 3. PSN status: RPCN

**Settings → Network → PSN status → RPCN.** The game gates online play on an NP sign-in, and stock
RPCS3 supplies that only through RPCN. With PSN disconnected it refuses with **`0519:8002AA0C`**.

An RPCN account is required, but it is unrelated to the game account above — it only satisfies the
sign-in check.

### 4. Internet enabled

**Settings → Network → Internet → Connected.** Self-evident, but it is off by default.

## Host — the server's own addresses

The host machine carries **three** addresses on the primary Ethernet adapter (layout since
2026-07-23; before that the server shared the machine's `.100`):

- `.100` — the machine's DHCP primary. **Not used by the server.** Free for a native RPCS3
  client, whose game UDP port would otherwise conflict with nothing but whose separation keeps
  client and server observably distinct on the wire.
- `.200` — the **server's** address: every game/web/probe bind, the lobby rows, the client swap
  list, and the STUN primary.
- `.201` — the STUN **secondary**. NAT discovery needs the responder to answer from a
  *different* address than the one asked: the client infers its NAT type from whether that
  reply arrives. The responder is **coturn** (see `dev/runtime/turnserver.conf`); edit both
  `listening-ip` lines there for a different deployment. Without a bindable secondary, the
  client classifies symmetric and cannot host.

**The winning configuration (verified end-to-end against two clients 2026-07-21; `.200` added
by the same recipe 2026-07-23).** Add each server address as a **secondary IP on the primary
Ethernet adapter, with `SkipAsSource`** — in an **admin** PowerShell on the host:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.200 -PrefixLength 24 -SkipAsSource $true
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.201 -PrefixLength 24 -SkipAsSource $true
```

Two things about this command are load-bearing:

- **Use `New-NetIPAddress`, not `netsh ... add address`.** On a DHCP adapter the positional `netsh`
  form *replaces* the primary instead of adding (confirmed, and it is documented that a DHCP
  adapter refuses a second static via the GUI/`netsh`). `New-NetIPAddress` adds a Manual secondary
  that coexists with the DHCP primary — `ipconfig` then shows all of `.100`, `.200` and `.201`.
- **`SkipAsSource $true` is what makes peer-to-peer work, not just the port check.** Without it,
  when the host also runs a game client, native RPCS3 can send its P2P reply out a *secondary*
  address, and the joiner — expecting the host at `.100` — never sees a usable reply, so the
  connection never forms. `SkipAsSource` pins every outbound to `.100` while `.200`/`.201` still
  receive traffic addressed to them. (Server sockets bound to a specific address reply from that
  address regardless — `SkipAsSource` only steers unbound outbound connections, i.e. the client.)

Under WSL mirrored networking the Windows-owned secondaries are mirrored into WSL on `eth0`
automatically — **no `ip addr add`, no policy route, no second interface.** Those were earlier
dead ends:

- `sudo ip addr add … dev eth0` inside WSL works only for a client on the *same* host — a
  WSL-only address is not ARP-reachable on the LAN, so a real client's Test II times out.
- The Wi-Fi adapter with a static no-gateway `.201` worked but is fragile: Windows treats a
  gateway-less adapter as "no connectivity" and keeps dropping the Wi-Fi, taking `.201` with it.
- Single-address STUN lets a client *online* but not *host* — it can't prove full-cone, so Create
  Game fails `0693:00000001`. Two addresses are mandatory for hosting.

### Client machines: firewall must allow the whole P2P range

Each client's firewall must allow inbound UDP **5730–5740** from the LAN — not just 5730. echo's
coturn config uses `min-port 5730 / max-port 5740`, i.e. MGO2's P2P uses that whole range, and a
default-deny firewall silently drops the ports above 5730. On a Linux (ufw) client:

```
sudo ufw allow in proto udp from 192.168.1.0/24 to any port 5730:5740
```

On a Windows client, an inbound allow rule for UDP 5730-5740. The port check's Test II reply also
arrives from a different ip:port than contacted, so a stateful default-deny firewall that only
opens a single port reads the machine as a symmetric UDP firewall (`0692`, `0693:00000001`).

## What is *not* needed

- **DNS.** RPCS3's DnsHook resolves inside the emulator, so the IP swap list does all the
  redirection and the `DNS address` setting changes nothing. Confirmed by pointing a diagnostic DNS
  server at the emulator and watching it receive **zero** packets while the game connected happily.
  A DNS container was run during early debugging and has been removed; nothing in `compose.yaml`
  provides one.

  `dev/tools/dnsmasq.conf` is kept as a **diagnostic**, not a dependency: run it and point the emulator's
  DNS setting at the machine to discover the hostnames a *different* disc or region asks for, which
  is how the swap list above was built. Stop it again afterwards.

  RPCS3's `DNS address` should therefore point at a **real resolver** — `1.1.1.1`, or your router —
  not at this server. The setting is inert for the five hostnames above, which the swap list
  intercepts before any lookup, but a hostname outside that list would still try to resolve and
  should reach something that answers.
- **A patched or custom emulator build.** Stock RPCS3 is sufficient. Custom builds exist for other
  MGO2 servers; none is required here.
- **Router port forwarding.** The game asks its own UPnP client to forward, and the port check is
  satisfied by the STUN responder regardless.

## Crypto constants

Some are recoverable from your own disc rather than taken on trust:

```
python3 dev/tools/extract_keys.py "<disc>/PS3_GAME/USRDIR/o/MGO2.elf"
```

prints the raw packet key, the whole-packet XOR key, the HMAC key, the Blowfish pi table and the
session master context, with offsets.

**`packet.key` is fully derivable**: expand the 56-byte raw key it prints through the standard
Blowfish schedule and you get the shipped file byte for byte. Only **`session.key`** needs anything
more — mode 6's blob is zeroed on disc, so it requires a memory dump from a running client.
`dev/docs/CRYPTO.md` gives the six-step procedure and a test vector to check the result.

## Gotchas

- **One RPCS3 instance at a time.** The game binds UDP `5730`; a second instance, including a stale
  one, silently takes the port and the port check fails. Check with
  `netstat -ano | findstr :5730` on Windows.
- **`probe-stun` must use host networking**, not published ports. Docker's UDP proxy rewrites reply
  source ports, and the source port is the entire mechanism the client classifies on. Already set
  in `compose.yaml`; do not "fix" it into a ports mapping.
- **A hang with no error is a missing reply.** The client stalls and then fails with `FFFFFF60`
  under whatever screen was open. Read `No handler for command …` from the lobby log.

## Verifying the pieces

| symptom | check |
| --- | --- |
| Stuck on the terms/network screen | swap list; `probe-https` logs should show a `gidauth5.html` POST; also confirm `dev/runtime/www/us/mgo2/policy/policy.txt` has been swapped for the real EULA text (`policy.txt.original`, gitignored) — the tracked file is a placeholder and real hardware stalls on it |
| `0519:8002AA0C` | PSN status is not RPCN |
| Login screen rejects, `090B` | certificate not installed, or wrong slot |
| Stuck on "Adjusting port settings" | `probe-stun` running? `python3 dev/tools/stun_selftest.py` should pass every check it runs (13 under WSL, where the change-request leg skips; 17 from a separate host) |
| `0692:00000003` after the check | client classified symmetric — a Test II reply never arrived. Repeated `change_ip=True` lines in the `probe-stun` log are the tell. See "a second IP for the port check": WSL-only secondary, missing policy route, or the client machine's own firewall |
| `0693:00000001` on Create Game | same cause as `0692` — the stored NAT verdict forbids hosting |
| `0910:C0FFEE02` | no account row, or its password hash does not match |
