-- Saved loadouts. Each character gets three of each, addressed by index, which the client
-- expects to exist whether or not the player has ever configured them.

CREATE TABLE IF NOT EXISTS public.chara_skill_set
(
    chara_id bigint NOT NULL,
    index smallint NOT NULL,
    name character varying(63) NOT NULL DEFAULT '',
    -- Bitmask of the game modes this set is applied to.
    modes integer NOT NULL DEFAULT 0,
    skill1 smallint NOT NULL DEFAULT 0,
    skill2 smallint NOT NULL DEFAULT 0,
    skill3 smallint NOT NULL DEFAULT 0,
    skill4 smallint NOT NULL DEFAULT 0,
    level1 smallint NOT NULL DEFAULT 0,
    level2 smallint NOT NULL DEFAULT 0,
    level3 smallint NOT NULL DEFAULT 0,
    level4 smallint NOT NULL DEFAULT 0,
    CONSTRAINT chara_skill_set_pkey PRIMARY KEY (chara_id, index),
    CONSTRAINT chara_skill_set_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_skill_set_index_check CHECK (index BETWEEN 0 AND 2)
);

CREATE TABLE IF NOT EXISTS public.chara_gear_set
(
    chara_id bigint NOT NULL,
    index smallint NOT NULL,
    name character varying(63) NOT NULL DEFAULT '',
    -- Bitmask of the stages this set is applied to.
    stages integer NOT NULL DEFAULT 0,
    face smallint NOT NULL DEFAULT 0,
    face_paint smallint NOT NULL DEFAULT 0,
    head smallint NOT NULL DEFAULT 0,
    head_color smallint NOT NULL DEFAULT 0,
    upper smallint NOT NULL DEFAULT 0,
    upper_color smallint NOT NULL DEFAULT 0,
    lower smallint NOT NULL DEFAULT 0,
    lower_color smallint NOT NULL DEFAULT 0,
    chest smallint NOT NULL DEFAULT 0,
    chest_color smallint NOT NULL DEFAULT 0,
    waist smallint NOT NULL DEFAULT 0,
    waist_color smallint NOT NULL DEFAULT 0,
    hands smallint NOT NULL DEFAULT 0,
    hands_color smallint NOT NULL DEFAULT 0,
    feet smallint NOT NULL DEFAULT 0,
    feet_color smallint NOT NULL DEFAULT 0,
    accessory1 smallint NOT NULL DEFAULT 0,
    accessory1_color smallint NOT NULL DEFAULT 0,
    accessory2 smallint NOT NULL DEFAULT 0,
    accessory2_color smallint NOT NULL DEFAULT 0,
    CONSTRAINT chara_gear_set_pkey PRIMARY KEY (chara_id, index),
    CONSTRAINT chara_gear_set_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_gear_set_index_check CHECK (index BETWEEN 0 AND 2)
);
