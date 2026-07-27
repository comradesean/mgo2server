# Handoff — next session

Five items, all scoped and evidenced. Nothing here needs a live client except where marked.
Ground rules as always: `mvn verify` (never `mvn test`, expect two counts — currently 151 unit
and 136 integration), ksy sizes and types are evidence and must not change, no AI attribution in
commits, and other servers are not specifications.

---

## 1. `0x4b90` is registered twice, so `memberAction` is dead code

`ClanGameController` puts `0x4b90` into the handler map twice — once as `MEMBER_ACTION`, then
again as `CLAN_SEARCH`. The second registration wins, so clan search works (which is why live
testing never caught it) and `memberAction` is unreachable.

Decide which one the command actually is. The evidence says search: the payload's two selector
bytes are `{partial_or_exact, ignore_case}`, matching the two toggles on the Clan Search screen
("Partial and Exact Matches" / "Exact Matches Only" and "Case Sensitive" / "Case Insensitive"),
and search was verified working live. `memberAction`'s reading of the same bytes is a guess that
predates that.

- Delete `memberAction` and its registration, or, if the ELF shows a second opcode it was meant
  for, register it there instead.
- Its javadoc still describes the bytes as `{exact_only, case_sensitive}`. The second byte means
  **ignore case** — 1 ignores. Note the polarity where it lands; it caught us once already, on
  `0x4600`, where a test asserted the wrong reading on no authority but the field's own name.
- A duplicate key in a handler map should not be silent. Consider making registration reject a
  repeat, and see whether any other command is shadowed the same way.

## 2. `0x4122`'s emblem flag is hardcoded to zero

`PersonalInfoWriter` line ~144 writes `0` for the emblem flag at wire `0xf0`, with the comment
"Emblems are not modelled, so never." That comment is now out of date — emblems are modelled,
stored, and served by `0x4b47`. The result is that a clan's emblem shows up when you open Clan
Info but not in the connect burst.

The value is documented as `3` when the character's clan has one. **Confirm that 3 before
shipping it** — read the client's parser rather than trusting the comment, since the same field's
neighbour (the saved-instructor u32) was a transcribed constant that cost a day. The write is at
`profile+6872`; find its readers and see what values they distinguish.

`write()` already receives the `ClanService.Membership`, so the plumbing exists if `Membership`
carries an emblem-present flag; otherwise add one there rather than doing a second lookup inside
the writer.

Needs a live check: set an emblem, relog, and confirm it renders without opening Clan Info.

## 3. The `0x3049` tail framing only holds below eight characters

`CharacterGameController` frames the tail as `0x1b4` + 35 bytes. The layout is `0x1b7` + 32.
Those are equivalent at small character counts and diverge as the list grows — above eight
characters the zero-fill length goes negative.

Not currently reachable: slots cap at 4. Fix it anyway and add a unit test that builds a list at
the maximum slot count and asserts the total length, so the cap and the framing cannot drift
apart. This is the packet that broke twice in one session from two errors that cancelled each
other out (28-vs-31 appearance bytes, 4-byte index vs 1-byte slot), which is the argument for
asserting the length rather than eyeballing the arithmetic.

## 4. `mgo2_cmd_4b00_c2s.ksy` claims a precondition the client contradicts

The spec records that clan creation requires a non-zero session clan id, else `-1201`, citing
`0xD579AC`. The 2026-07-27 capture came from a character with **no** clan and the create packet
went out and succeeded.

So either that call sits on a branch create does not take, or the citation is misattributed to
the wrong command. Resolve it against the ELF — this is an opus subagent job, ELF at
`dev/ref/MGO2 (decrypted).elf` — and correct the spec's note. Do not delete the observation;
record which of the two it was, the way the other falsifications in that directory are recorded.

Related, from the same sweep: `-1201` may still be the right refusal for some create path. If it
is not create's, find out whose.

## 5. `server.env` — one file for the tunables

Requested: "anything with a cooldown should probably just be defaulted to a week, but we should
also provide a global config file in root that stores these values for the docker container for
easy editing."

**Current state, verified:**

| Cooldown | Where | Default now |
| --- | --- | --- |
| Character delete | `CharacterService.DELETE_COOLDOWN` | `Duration.ofDays(7)` — correct |
| Clan disband | `ClanService.DISBAND_COOLDOWN` | `Duration.ofHours(168)` — correct |
| Clan emblem | `ClanGameController.DEFAULT_EMBLEM_COOLDOWN_MINUTES` | **60 minutes — wrong, make it a week** |

Only the emblem one is configurable today, via `MGO2SERVER_EMBLEM_COOLDOWN_MINUTES` read through
a bare `System.getenv` rather than through `Config`. The other two are compile-time constants.

**What to build:**

- A root `server.env` holding every operator-tunable value, each with a comment saying what it
  does and what the default means. Cooldowns in **hours**, so all three read alike; the emblem
  variable's `_MINUTES` name should change with it.
- Wire it into `compose.yaml` with `env_file:` on the shared `*server-env` anchor, so every lobby
  picks it up. Compose reads `.env` for interpolation and `env_file:` for the container's
  environment — these are different mechanisms, and this wants the second.
- Read the values through the existing `mgo2server.common.Config` pattern rather than scattered
  `System.getenv` calls. Three cooldowns, at minimum; fold in the strays while you are there
  (`MGO2SERVER_GRADUATION`, `MGO2SERVER_LOGIN_PERKS`, `MGO2SERVER_TRAINING_PARAMS`, the three
  `MGO2SERVER_MAIL_CATEGORY_*`).
- Defaults must stay in the code. `server.env` is an override file; a missing or deleted one
  should leave the server running the documented defaults, not crash it.
- Label each entry **operator policy**, because that is what all of it is. None of these numbers
  are protocol — the client never sends or validates them. The 168 hours is what players
  reported, not something read out of the binary, and the file should say so.
- `server.env` is committed (it holds no secrets); `MGO2SERVER_DB_PASSWORD` stays out of it and
  keeps its current injection path.

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
