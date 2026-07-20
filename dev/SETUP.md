# Setup

Everything outside this repository that has to be true before an unmodified client can play.

The server side is `docker compose up`. Everything else is emulator and host configuration, and it
comes down to **four required changes** plus one host address for the port check.

Assumed throughout: stock **RPCS3 v0.0.41**, retail disc **BLUS30109**, and a server reachable at
`<SERVER_IP>` — written below as `192.168.1.100`, the value the defaults use.

## Server

```
docker compose up -d
```

Brings up postgres, the migrations, the three lobby servers (gate, account, game), the web service,
and the HTTP/HTTPS/STUN probes.

There is **no registration endpoint**. Insert an account by hand — the client sends the password
already MD5-hashed, so that hash is what is stored:

```sql
insert into account (username, password, slots)
values ('<game id>', md5('<password>'), 3);
```

The `username` is whatever is typed into the game's ID field. Passwords are MD5 because the client
hashes them before sending; see `dev/CRYPTO.md`.

## RPCS3 — four changes

All four are required. The game fails differently for each, and none of the failures name their
cause.

### 1. IP swap list

Redirects Konami's hostnames to the server. **Settings → Network → IP swap list**, or in
`config/config.yml`:

```
IP swap list: "mgo2web.konami.com=192.168.1.100&&info.service.konamionline.com=192.168.1.100&&mgo2gateus.konamionline.com=192.168.1.100&&mgo2stunna.konamionline.com=192.168.1.100&&mgo2auth.konami.com=192.168.1.100"
```

### 2. The CA certificate

The PS3 validates the server certificate against its own store and **drops the connection before
sending a request** if the chain does not verify — which looks exactly like the server never being
contacted. A self-signed certificate is not enough.

Copy this repository's CA over one of the emulator's certificate slots:

```
cp dev/www/ca-cert.pem  <rpcs3>/dev_flash/data/cert/CA30.cer
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

## Host — a second IP for the port check

NAT discovery needs the server to answer from a **different address**, so the responder binds two.
Add the secondary to the interface holding the primary:

```
sudo ip addr add 192.168.1.201/24 dev <iface>
```

Override the defaults with `NOMAD_PUBLIC_IP` and `NOMAD_STUN_SECONDARY_IP` if using other
addresses. Without it `probe-stun` crash-loops on bind with `Errno 99`.

**This does not survive a reboot**, and on WSL the interface is renamed across restarts (`eth1`,
`eth8` and `eth0` have all been seen) — check `ip -brief addr` rather than reusing the old command.

A single address does get the client past the check, but misclassifies restricted-cone players as
full-cone, which breaks peer-to-peer for them. `dev/STUN.md` has the detail.

## What is *not* needed

- **DNS.** RPCS3's DnsHook resolves inside the emulator, so the IP swap list does all the
  redirection and the `DNS address` setting changes nothing. Confirmed by pointing a diagnostic DNS
  server at the emulator and watching it receive **zero** packets while the game connected happily.
  A DNS container was run during early debugging and has been removed; nothing in `compose.yaml`
  provides one.

  `dev/dnsmasq.conf` is kept as a **diagnostic**, not a dependency: run it and point the emulator's
  DNS setting at the machine to discover the hostnames a *different* disc or region asks for, which
  is how the swap list above was built. Stop it again afterwards.

  If you remove the DNS server, do not leave RPCS3's `DNS address` pointing at it. Set it to a real
  resolver (your router, or `1.1.1.1`) so that nothing can stall on a dead address — the setting is
  inert for the hostnames above, but a hostname outside the swap list would still try to resolve.
- **A patched or custom emulator build.** Stock RPCS3 is sufficient. Custom builds exist for other
  MGO2 servers; none is required here.
- **Router port forwarding.** The game asks its own UPnP client to forward, and the port check is
  satisfied by the STUN responder regardless.

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
| Stuck on the terms/network screen | swap list; `probe-https` logs should show a `gidauth5.html` POST |
| `0519:8002AA0C` | PSN status is not RPCN |
| Login screen rejects, `090B` | certificate not installed, or wrong slot |
| Stuck on "Adjusting port settings" | `probe-stun` running? `python3 dev/stun_selftest.py` should report 13 passes |
| `0910:C0FFEE02` | no account row, or its password hash does not match |
