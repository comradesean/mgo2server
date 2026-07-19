-- Per-character gameplay and interface settings, plus the bits of a character the personal-info
-- response needs.
--
-- Defaults reproduce the settings blob the original hands a character that has never saved any,
-- so a fresh character behaves identically.

ALTER TABLE public.chara ADD COLUMN IF NOT EXISTS comment character varying(128) NOT NULL DEFAULT '';
ALTER TABLE public.chara ADD COLUMN IF NOT EXISTS rank smallint NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.chara_settings
(
    chara_id bigint NOT NULL,
    online_status_mode smallint NOT NULL DEFAULT 0,
    normal_view_speed smallint NOT NULL DEFAULT 5,
    shoulder_view_speed smallint NOT NULL DEFAULT 5,
    first_view_speed smallint NOT NULL DEFAULT 5,
    view_change_speed smallint NOT NULL DEFAULT 5,
    hud_display_size smallint NOT NULL DEFAULT 0,
    weapon_switch_mode smallint NOT NULL DEFAULT 2,
    weapon_switch_a smallint NOT NULL DEFAULT 0,
    weapon_switch_b smallint NOT NULL DEFAULT 1,
    weapon_switch_c smallint NOT NULL DEFAULT 2,
    weapon_switch_now smallint NOT NULL DEFAULT 0,
    weapon_switch_before smallint NOT NULL DEFAULT 1,
    item_switch_mode smallint NOT NULL DEFAULT 2,
    codec1a smallint NOT NULL DEFAULT 1,
    codec1b smallint NOT NULL DEFAULT 3,
    codec1c smallint NOT NULL DEFAULT 4,
    codec1d smallint NOT NULL DEFAULT 2,
    codec2a smallint NOT NULL DEFAULT 10,
    codec2b smallint NOT NULL DEFAULT 12,
    codec2c smallint NOT NULL DEFAULT 13,
    codec2d smallint NOT NULL DEFAULT 11,
    codec3a smallint NOT NULL DEFAULT 14,
    codec3b smallint NOT NULL DEFAULT 16,
    codec3c smallint NOT NULL DEFAULT 17,
    codec3d smallint NOT NULL DEFAULT 15,
    codec4a smallint NOT NULL DEFAULT 5,
    codec4b smallint NOT NULL DEFAULT 7,
    codec4c smallint NOT NULL DEFAULT 8,
    codec4d smallint NOT NULL DEFAULT 6,
    voice_chat_recognition_level smallint NOT NULL DEFAULT 5,
    voice_chat_volume smallint NOT NULL DEFAULT 5,
    headset_volume smallint NOT NULL DEFAULT 5,
    bgm_volume smallint NOT NULL DEFAULT 10,
    email_friends_only boolean NOT NULL DEFAULT false,
    receive_notices boolean NOT NULL DEFAULT true,
    receive_invites boolean NOT NULL DEFAULT true,
    normal_view_vertical_invert boolean NOT NULL DEFAULT false,
    normal_view_horizontal_invert boolean NOT NULL DEFAULT false,
    shoulder_view_vertical_invert boolean NOT NULL DEFAULT false,
    shoulder_view_horizontal_invert boolean NOT NULL DEFAULT false,
    first_view_vertical_invert boolean NOT NULL DEFAULT false,
    first_view_horizontal_invert boolean NOT NULL DEFAULT false,
    first_view_player_direction boolean NOT NULL DEFAULT true,
    first_view_memory boolean NOT NULL DEFAULT false,
    radar_lock_north boolean NOT NULL DEFAULT false,
    radar_floor_hide boolean NOT NULL DEFAULT false,
    hud_hide_name_tags boolean NOT NULL DEFAULT false,
    lock_on_enabled boolean NOT NULL DEFAULT false,
    codec1_name character varying(64) NOT NULL DEFAULT '',
    codec2_name character varying(64) NOT NULL DEFAULT '',
    codec3_name character varying(64) NOT NULL DEFAULT '',
    codec4_name character varying(64) NOT NULL DEFAULT '',
    CONSTRAINT chara_settings_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_settings_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);

-- The four skills a character has equipped, with the level of each.
CREATE TABLE IF NOT EXISTS public.chara_equipped_skills
(
    chara_id bigint NOT NULL,
    skill1 smallint NOT NULL DEFAULT 0,
    skill2 smallint NOT NULL DEFAULT 0,
    skill3 smallint NOT NULL DEFAULT 0,
    skill4 smallint NOT NULL DEFAULT 0,
    level1 smallint NOT NULL DEFAULT 0,
    level2 smallint NOT NULL DEFAULT 0,
    level3 smallint NOT NULL DEFAULT 0,
    level4 smallint NOT NULL DEFAULT 0,
    CONSTRAINT chara_equipped_skills_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_equipped_skills_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
