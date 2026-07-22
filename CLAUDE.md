# mgo2server

An MGO2 server targeting the retail MGS4 disc **BLUS30109** on RPCS3.

## Evidence hierarchy

This is the most important convention in the project, and the one that has been violated most
expensively. When deciding what the server should do, sources rank:

1. **`MGO2.elf`** — the decrypted game binary, at
   `PS3_GAME/USRDIR/o/MGO2.elf`. The only actual specification. Everything else is somebody's
   reading of it.
2. **A real client** — bytes observed from `BLUS30109` on RPCS3, or captures of the original
   Konami servers. Authoritative for behaviour, silent on intent.
3. **Published standards** — RFCs and drafts, where the game implements one (the port check is
   `draft-ietf-behave-rfc3489bis-02`; Blowfish is Blowfish).
4. **Other server implementations** — echo, mgo2-server, the Nomad servers. **Not specifications.**

   **Do not go read them.** They are deliberately not vendored in this repo. Trawling them has
   repeatedly burned six figures of tokens for no payoff, and every behaviour worth knowing from
   them is already transcribed into `dev/docs/PROTOCOL.md` and `dev/docs/OBSERVED.md` — read those
   instead. Only fetch one from GitHub if a *specific, named* question survives after the ELF and
   the docs have both failed to answer it, and say why first.

   Note the near-collision: this project is **`mgo2server`**; **`mgo2-server`** (hyphenated) is
   MiguelRipoll23's separate project, cited throughout as a reference. When the docs say
   "mgo2-server does X", they mean theirs, not ours. They target different
   client builds, and several of their behaviours are operator policy or outright hacks rather
   than protocol.

Tests should assert against tier 1 where a value is readable from the binary, and tier 2 where it
is not. An assertion whose only authority is tier 4 is a regression guard, not a correctness
check, and should say so in as many words.

### Why this is stated so bluntly

Copying an upstream has cost real time on six separate occasions: the policy path, the gate
hostname, the gate port, the version-check byte, the login perks field, and the two appearance
bytes character creation silently discarded. The perks field is the instructive one — it was
transcribed *correctly*. `Array(10).fill("1000000").join("_")` is genuinely what mgo2-server
sends, and it is genuinely wrong for this client. Faithful copying of a source that does not apply
looks exactly like diligence.

Two upstream behaviours were not merely inapplicable but actively broken here: `SessionIds`
invented a session model that never worked and hid it behind a hardcoded `"cafebabe"` sentinel,
and the STUN responder echoed a vendor attribute back on an untested theory, hanging the game with
no error. Both survived because nothing tested them against the client.

### Before crossing something off

An elimination is only valid if you can state the observation that would have confirmed it, and
check that the experiment actually produced that observation. "We tried it and it still failed" is
not an elimination if the thing varied could not have mattered.

## Documentation

- `dev/docs/OBSERVED.md` — what was observed and verified against a real client, including hypotheses
  that turned out to be wrong. Read it before re-testing anything.
- `dev/docs/PROTOCOL.md` — the TCP command protocol, command by command and byte by byte.
- `dev/docs/STUN.md` — the UDP port check.
- `dev/docs/CRYPTO.md` — every cipher, key and hash, and where each is applied.
- `dev/docs/SETUP.md` — the external setup: emulator settings, certificate, and host addressing.

## Distinguishing spec from policy

Not everything in the server is protocol. Three kinds of rule get conflated easily, and should be
labelled where they appear:

- **Protocol** — fixed by the game. A 16-character name field is protocol; the client will not
  send more.
- **Operator policy** — our choice, or an inherited one. Reserved name prefixes, delete cooldowns
  and slot counts are policy. Inheriting another project's policy is usually a bug, not a default.
- **Presentation** — what the client can render. Claims in this category are checkable against the
  binary and usually have not been checked.

## Running the tests

**Always `mvn verify`, never `mvn test`.** Surefire only picks up `*Test`; every `*IT` runs under
failsafe during `verify`. A green `mvn test` says nothing about the integration suite, and that gap
has hidden real breakage more than once.

There is no local `mvn`. Integration tests use testcontainers, hence the socket and host network:

```
docker run --rm -v "$PWD":/w -w /w -v "$HOME/.m2":/root/.m2 \
  -v /var/run/docker.sock:/var/run/docker.sock --network host \
  -e TESTCONTAINERS_HOST_OVERRIDE=localhost \
  maven:3.9-eclipse-temurin-25 mvn -B verify
```

Expect two counts in the summary — currently 129 unit and 76 integration. One number means the
integration tests did not run.

## Debugging

An unanswered command makes this client **stall and then fail with `FFFFFF60`**, prefixed by
whatever screen was open. It is never a malformed reply — it is a missing one. Read
`No handler for command …` out of the lobby log.

**`docker logs` can lie after a restart storm.** Observed 2026-07-21: after a container
crash-looped ~1300 times (postgres outage), `docker logs` served hours-stale output while the
process wrote normally. An absent `No handler` line is only evidence if the log shows *current*
activity — check for the startup banner after any restart, and when in doubt read the raw
json-file at the container's `LogPath` (via a bind-mounted container). `docker restart` resets
the stream.
