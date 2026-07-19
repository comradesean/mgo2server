-- Character appearance, and the bookkeeping a soft delete needs.

-- Deleting a character renames it to free the name up, so the original is kept for support and
-- for restoring a character if a player asks.
ALTER TABLE public.chara ADD COLUMN IF NOT EXISTS old_name character varying(16);

CREATE TABLE IF NOT EXISTS public.chara_appearance
(
    chara_id bigint NOT NULL,

    gender smallint NOT NULL DEFAULT 0,
    face smallint NOT NULL DEFAULT 0,
    face_paint smallint NOT NULL DEFAULT 0,
    voice smallint NOT NULL DEFAULT 0,
    pitch smallint NOT NULL DEFAULT 0,

    upper smallint NOT NULL DEFAULT 0,
    upper_color smallint NOT NULL DEFAULT 0,
    lower smallint NOT NULL DEFAULT 0,
    lower_color smallint NOT NULL DEFAULT 0,

    head smallint NOT NULL DEFAULT 0,
    head_color smallint NOT NULL DEFAULT 0,
    chest smallint NOT NULL DEFAULT 0,
    chest_color smallint NOT NULL DEFAULT 0,
    hands smallint NOT NULL DEFAULT 0,
    hands_color smallint NOT NULL DEFAULT 0,
    waist smallint NOT NULL DEFAULT 0,
    waist_color smallint NOT NULL DEFAULT 0,
    feet smallint NOT NULL DEFAULT 0,
    feet_color smallint NOT NULL DEFAULT 0,

    accessory1 smallint NOT NULL DEFAULT 0,
    accessory1_color smallint NOT NULL DEFAULT 0,
    accessory2 smallint NOT NULL DEFAULT 0,
    accessory2_color smallint NOT NULL DEFAULT 0,

    CONSTRAINT chara_appearance_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_appearance_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
