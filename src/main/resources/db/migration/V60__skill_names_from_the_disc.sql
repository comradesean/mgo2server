-- The 17 skill names, read from the disc's own string resources.
--
-- V20 left eleven of them NULL because only six were safely derivable from the ELF (0x6FCD48
-- maps a weapon id to the skill that receives its experience; cross-referencing the weapon master
-- table pins those six). It also recorded the rule that would resolve the rest: skill labels are
-- message ids, name = 100 + 2*id and level descriptions = 179 + 3*id, in a message resource "which
-- we do not have". We do have it now.
--
-- Source: resource set [40eff4] declared at scenerio.gcl line 2330 as
--   -s[1d914] [40eff4] $strres:0 $strres:341
-- so header records are entries 0..341, string id = header index, and string base = 342 with
-- file index = 342 + ordinal - 1. Header records parsed with the varint format in AUTOMATCH.md
-- section 10; every skill record carries group hash 0x654515. Files verified by direct read, e.g.
-- 660.bin = 'HANDGUN+', 772.bin = 'MONOMANIA', 754.bin = 'BLADES+'.
--
-- V20's rule is confirmed exactly by the data: header 100 + 2*id is the name and 179 + 3*id is the
-- level-1 description, with +1 and +2 being levels 2 and 3.
--
-- THE RUN ENDS AT 17, independently of the ELF bound V20 cites: header 136 (id 18) is 'NONE'
-- (805.bin) and 138 onward point back into the weapon-category strings.
--
-- Two corroborations that were not used to derive anything:
--   * id 13 = MONOMANIA matches a live 0x43a4 report on 2026-07-29 -- a player using SMG and
--     Monomania moved exactly skills 2 and 13.
--   * id 17 = INSTRUCTOR, and its three level-description headers (230/231/232) all point at the
--     SAME string, consistent with V20's ELF finding that skill 17 has no experience path and
--     renders without a level bar.
--
-- No contradiction with the six ELF-derived names. Ids 1-5 match verbatim. Id 11 was 'Knife' and
-- is really labelled 'BLADES+', whose own description string reads "Skill wielding knives" -- the
-- same skill under the disc's label, so it agrees rather than conflicts.
--
-- These are the disc's strings verbatim, capitalisation and trailing '+' included, so a name here
-- can be grepped against what the UI renders. Presentation, not protocol: nothing keys on them.

UPDATE public.skill AS s SET name = v.name
FROM (VALUES
    ( 1, 'HANDGUN+'),
    ( 2, 'SMG+'),
    ( 3, 'ASSAULT RIFLE+'),
    ( 4, 'SHOTGUN+'),
    ( 5, 'SNIPER RIFLE+'),
    ( 6, 'HAWKEYE'),
    ( 7, 'SURVEYOR'),
    ( 8, 'QUARTERBACK'),
    ( 9, 'TRICKSTER'),
    (10, 'CQC+'),
    (11, 'BLADES+'),
    (12, 'RUNNER'),
    (13, 'MONOMANIA'),
    (14, 'SIXTH SENSE'),
    (15, 'NARC'),
    (16, 'SCANNER'),
    (17, 'INSTRUCTOR')
) AS v(id, name)
WHERE s.id = v.id;
