# Handoff — next session

Ground rules as always: `mvn verify` (never `mvn test`, expect two counts — currently 159 unit
and 136 integration), ksy sizes and types are evidence and must not change, no AI attribution in
commits, and other servers are not specifications.

---

All five items below were done on 2026-07-27. What is left is the "Still open" list at the
bottom, plus two things that need a live client rather than a build:

- **The emblem flag now goes out at login.** That newly exercises `0x4b48` on the connect path,
  where `PROTOCOL.md` records that it blocks character select. Set a clan emblem, relog, and
  confirm the emblem renders and the lobby does not stall.
- **`0x4b42`'s precondition is an open conflict**, recorded in that spec rather than resolved. See
  item 4.

---

## 1. `0x4b90` registered twice — DONE

`memberAction` and its constants deleted; clan search keeps the opcode. Its javadoc's
`case_sensitive` renamed to `ignore_case` (1 ignores) — the read in `clanSearch` was already the
right way round, so only the name was wrong.

`GameServerHandler` now tracks which controller claimed each command and throws at construction on
a second claim, naming both. Registration was a `put` plus a `putAll`, so declaration order decided
in silence; here the *correct* handler happened to win, which is worse than the wrong one winning,
because the loser sat there looking maintained. Covered by `GameServerHandlerTest`.

## 2. `0x4122` emblem flag — DONE, and 3 is confirmed

Read out of the binary rather than trusted. The value is the client's own constant: the
emblem-upload commit path writes it at `0xAD4724` (`stb r29,56(r11)`, `r11 = profile+6816`)
immediately before `memcpy`ing the 768-byte bitmap to `profile+6873` — the flag physically
precedes the image it describes. Only upload mode 3 reaches that store; modes 2 and 4 leave the
byte alone.

It is **not** a boolean and not a bitfield. Every reader is an exact equality — `cmpwi cr7,r0,3`
at `0x8F9954` and `0x905A94` — so 1 and 2 behave exactly like 0. And it gates a **network fetch**,
not merely rendering: the lobby-entry state machine at `0x8F9914` advances only when the clan id
is nonzero, membership is 1 or 2, and (privilege bit 0 is set *or* this byte is 3), then sends
`0x4b48` and blocks on `0x4b49` for 6000 ticks.

So the hardcoded 0 was not conservative — a character in a clan with an emblem never fetched it.
`PersonalInfoWriter.write` takes a `clanHasEmblem` flag, and `CharacterConnectController` sets it
only when `emblemFlagOf` returns exactly 3, so a stored mode of 2 or 4 is not echoed. `clanInfo`
was sending the raw mode unclamped and now clamps like its two siblings.

Not chased: the peer-side reader of the join-announcement copy at `0x884164`, and what UI-global
value 99 (`0x8F9A44`, on reply `-1215`) is distinguished from 0.

## 3. `0x3049` tail framing — DONE

Now `LIST_HEADER_SIZE + LIST_SLOTS * LIST_ENTRY_SIZE` = 439 = `0x1b7`, with a 32-byte trailer.
Byte-for-byte identical output; the three bytes that used to lead the trailer are zero fill, which
is what they always were. Entries are capped at eight so a raised slot count cannot overrun the
grid, and the payload length is asserted.

## 4. `mgo2_cmd_4b00_c2s.ksy` — DONE, and it was neither option

The citation is real and *is* on the `0x4b00` path. **The test was read backwards.** `0xD57750`
returns -1 when `profile+6816` is nonzero and 0 when it is zero — it reads the character's own
clan id and never touches the membership state. This site compares against -1, so `-1201` on
`0x4b00` means **"you are already in a clan"**, and a clanless character passes. Which is exactly
what the capture showed.

All six callers are now tabulated in the spec with the direction of each test. Two corrections
fell out: `0x4b42` is also an "already in a clan" refusal, not a "must be in a clan" one, and
`0x4b04`/`0x4b30` do not call `0xD57750` at all (they use `0xD5709C` and `-1203`, which is what
their specs already said).

`-1201` is **no single command's** refusal. All four `li` of it in the image are in this family and
it is used with *both* polarities. Read it as "clan membership state is wrong for this operation",
with the calling command supplying the direction.

`mgo2_cmd_4b42_c2s.ksy` has the conflict written into it rather than resolved: the live
observation (with `0x4b81` serving zeros, Apply sent nothing) is not in doubt, but whether
`0xD57750` is what produced that `-24`, or whether `0xD585FC` and `0xD586A8` are two separate
gates, was not settled. Disassemble `0xD585FC` before rewriting that section.

## 5. `server.env` — DONE

Root `server.env`, committed, wired through `env_file:` on an anchor every service carries. The
three cooldowns moved into `mgo2server.common.Policy`, which keeps the defaults in code so a
deleted `server.env` degrades rather than breaks. Also folded in the five probe variables that
were reading `System.getenv` directly.

**The emblem cooldown defaulted to sixty minutes**, not the week its two siblings used — no
reason beyond the order the three were written. It is a week now and all three come from one
place. `PolicyTest` covers the defaults, blank-means-default (an empty `env_file` line must not
read as "no cooldown"), and rejection of negatives.

Precedence to remember: compose gives `environment:` priority over `env_file:`, so anything named
in a service's environment block cannot be overridden from `server.env`. That is deliberate for
the per-lobby wiring, and it is why `MGO2SERVER_LOG_LEVEL` is documented as *not* living there.

---

## Still open, lower priority

- Per-mode play time is not tracked. One aggregate is counted six times to produce the displayed
  figure, which matches the client but is not the real number.
- The emblem work-in-progress / review flow is unmodelled.
- 72 GAME/GMINFO entries in `ERRORS.md` are unresolved — their group bases are not registered in
  the lobby script.
- `0x4221` wire `0x1c`, `0x1d`, `0x1e` are still `[UNKNOWN]`, zeroed deliberately.
- `0x43a6` field 332 is inferred as the student's chara id, never confirmed.
- The emblem-buffer memset location was never found; it is why a refusal must use a code the
  client treats as recoverable (`-1216`), not a generic one.
