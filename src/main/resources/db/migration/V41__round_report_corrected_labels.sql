-- Three round_report columns carried names the 2026-07-27 ELF trace refuted. The stored VALUES
-- are correct — they are whatever the client sent at those wire offsets — so this is a pure
-- rename. No backfill, no data change. See PROTOCOL.md "0x4390" and mgo2_cmd_4390.ksy.
--
-- team_slot -> team_win (wire 0x23)
--   V18 split 0x23 into {u16 team slot index, u16 seconds} and named the high half a team slot
--   index: "0/1, constant per player per game, 0 in DM". The split is right; the label is not.
--   It is a TEAM WIN flag. It is column 5 of the client's score table (ComputeScore, 0x6FA408),
--   worth 5 in Rescue/Capture/Sneaking/Base/Team Sneaking and 0 in DM/TDM — the wire source for
--   the "TEAM WIN x5" category every mode table listed and nobody could locate. A slot index is
--   constant per player per game; this flips 50/22/32 times for ch1/ch2/ch3 across 239 archived
--   rounds, and where players of a round disagree the top scorer holds the 1 in 96 cases to 5.
--   Both readings predict 0 in DM (no teams), which is how the wrong one survived.
--
-- rounds_played -> lockon_stuns_received (wire 0x1d)
--   The capture-era "rounds played" guess, never observed nonzero in 517 frames — and it could
--   not have been right: a once-per-round counter would wire 1 in every report under delta
--   semantics, not 0 in all of them. It is the victim side of the lock-on stun pair.
--
-- counter_0x19 -> lockon_stuns_dealt (wire 0x19)
--   Placeholder name, now known. Stun handler 0x6EDC90 switches on a hit-class argument:
--   ==1 writes the confirmed stun-headshot pair, ==2 writes 0x19/0x1d. The same enum appears in
--   the kill handler 0x6EEAF0 selecting headshot vs lock-on, so four confirmed labels pin it.
--
-- Both lock-on stun columns are 0 in every archived row; renaming them changes nothing that is
-- currently read, and stops the next reader believing "rounds_played".
ALTER TABLE public.round_report RENAME COLUMN team_slot TO team_win;
ALTER TABLE public.round_report RENAME COLUMN rounds_played TO lockon_stuns_received;
ALTER TABLE public.round_report RENAME COLUMN counter_0x19 TO lockon_stuns_dealt;
