-- Per-character skill ownership, the state behind 0x4125 and 0x4129.
--
-- Until now the skill table was generated from constants in LoadoutWriter: ids 1..25, experience
-- 0x6000 for all but 17/20/22, flag byte always 0, identical for every character. That is why
-- nothing is ever locked -- there was nowhere to record that a character has, or has not, earned
-- something (see BACKLOG, "Training progression").
--
-- The wire record is 4 bytes and the client scatters it into a 128-entry array at
-- profile+11444+id*12 (dev/proto/mgo2_cmd_4125.ksy):
--
--     u8  skill id      -- the array index; the parser requires > 0
--     u16 experience    -- the client derives level as min(exp >> 13, 3)
--     u8  flag          -- read by the per-skill gates; we have always sent 0
--
-- Two consequences drive the column types below. Experience is a u16 and PostgreSQL's smallint is
-- signed, so it is stored as integer with a range check rather than silently wrapping at 32767.
-- Flag is a u8, stored as smallint for the same reason.

-- The skills this client has, which is fewer than the wire can address.
--
-- The 0x4125 array is 128 entries, but the game only defines 17 skills. Three independent bounds,
-- all read from the binary 2026-07-26: the skill list's own check is `(id - 1) <= 16` (0x8DC3A8,
-- repeated at 0xB3B530 and 0xB3B5B0); the equip-cost table at vaddr 0xE11344 is exactly 18 rows of
-- 3 bytes (row = id, column = level, value = skill points) with a 00 00 00 terminator at row 18,
-- verified by reading the ELF directly; and every id-keyed lookup clamps to 17 (0x6FC528 and 28
-- clamp sites). Ids 18..127 are addressable by the parser and defined by nothing -- they are not
-- reserved slots for future skills, they fall off the end of every table the client owns.
--
-- Names start NULL and get filled as they are established. A name is presentation, not protocol —
-- unlike a wire size it costs nothing to be wrong and is cheap to check against the live UI — so
-- taking a list from an external source is fine here where it would not be for a layout. Evidence
-- for each id belongs in dev/proto/mgo2_cmd_4125.ksy, not in this table.
CREATE TABLE IF NOT EXISTS public.skill
(
    id smallint NOT NULL,
    name character varying(64),
    CONSTRAINT skill_pkey PRIMARY KEY (id),
    CONSTRAINT skill_id_range CHECK (id BETWEEN 1 AND 17)
);

-- Six names are ELF-derived and safe: 0x6FCD48 maps a weapon id to the skill that receives its
-- experience, and cross-referencing that against the weapon master table (WEAPONS.md) pins them
-- exactly. The rest stay NULL -- their labels are message ids (name = 100 + 2*id, level
-- descriptions = 179 + 3*id) in the disc's message resource, which we do not have. Any external
-- list adopted later must agree with these six or it is the wrong list.
INSERT INTO public.skill (id, name) VALUES
    ( 1, 'Handgun'),
    ( 2, 'SMG'),
    ( 3, 'Assault Rifle'),
    ( 4, 'Shotgun'),
    ( 5, 'Sniper Rifle'),
    ( 6, NULL),
    ( 7, NULL),
    ( 8, NULL),
    ( 9, NULL),
    (10, NULL),
    (11, 'Knife'),
    (12, NULL),
    (13, NULL),
    (14, NULL),
    (15, NULL),
    (16, NULL),
    (17, NULL)
ON CONFLICT (id) DO NOTHING;

-- What a character actually has. A row means "this character owns this skill"; no row means the
-- server omits it from 0x4125, and the client's memset leaves that slot zeroed -- level 0, flag 0.
--
-- This is the table that makes locking possible: granting the instructor skill on graduation is an
-- INSERT here, and requiring it before hosting combat training is a lookup here.
CREATE TABLE IF NOT EXISTS public.chara_skill
(
    chara_id bigint NOT NULL,
    skill_id smallint NOT NULL,
    -- u16 on the wire. Level is min(experience >> 13, 3), so only 0 / 8192 / 16384 / 24576 change
    -- what the client displays; intermediate values are stored faithfully rather than rounded.
    -- Skill 17 has no experience path at all and renders without a level bar (0x8DB8A8).
    experience integer NOT NULL DEFAULT 0,
    -- u8 on the wire. Read in exactly one place in the whole binary: skill 17's, at 0x897320,
    -- where "record present and flag == 0" enables the training menu entry drawn from messages
    -- 866/867. Never yet sent as anything but 0.
    flag smallint NOT NULL DEFAULT 0,
    CONSTRAINT chara_skill_pkey PRIMARY KEY (chara_id, skill_id),
    CONSTRAINT chara_skill_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_skill_skill_id_fkey FOREIGN KEY (skill_id)
        REFERENCES public.skill (id) ON DELETE RESTRICT,
    CONSTRAINT chara_skill_experience_range CHECK (experience BETWEEN 0 AND 65535),
    CONSTRAINT chara_skill_flag_range CHECK (flag BETWEEN 0 AND 255)
);

-- Backfill every existing character with what LoadoutWriter has been sending, restricted to the
-- ids the client defines. This is NOT quite behaviour-neutral and deliberately so: we have been
-- sending ids 1..25, and 18..25 are undefined -- the client stores them, lists them, and clamps
-- them to row 17 for cost and name. Dropping them is a behaviour change to verify against the live
-- skill list.
--
-- Experience keeps today's values: 0x2000 (level 1) for 17 and 20, 0x6000 (level 3) for the rest.
-- 22 is gone with the range. That 17/20/22 split came from a reference server and has no evidence
-- behind it; skill 17 in particular has no experience path in the binary at all, so its level is
-- probably meaningless rather than deliberately low.
INSERT INTO public.chara_skill (chara_id, skill_id, experience, flag)
SELECT c.id, s.id,
       CASE WHEN s.id IN (17, 20) THEN 8192 ELSE 24576 END,
       0
FROM public.chara c
CROSS JOIN public.skill s
WHERE s.id BETWEEN 1 AND 17
ON CONFLICT (chara_id, skill_id) DO NOTHING;
