-- Hosted games, and the settings a character hosts them with.
--
-- The original keeps these as opaque JSON blobs re-parsed on every list request. They are typed
-- columns here: the fields are a fixed set defined by the client, and the game list has to derive
-- bitfields from them on every request, which is far easier to get right and to test against
-- columns than against free-form JSON.

CREATE TABLE IF NOT EXISTS public.chara_host_settings
(
    chara_id bigint NOT NULL,
    -- Matches the lobby subtype, so a character can keep different settings per lobby flavour.
    type smallint NOT NULL DEFAULT 0,

    name character varying(16) NOT NULL DEFAULT '',
    password character varying(16),
    comment character varying(128) NOT NULL DEFAULT '',
    stance smallint NOT NULL DEFAULT 0,
    max_players smallint NOT NULL DEFAULT 16,
    briefing_time smallint NOT NULL DEFAULT 0,

    dedicated boolean NOT NULL DEFAULT false,
    non_stat boolean NOT NULL DEFAULT false,
    friendly_fire boolean NOT NULL DEFAULT false,
    auto_aim boolean NOT NULL DEFAULT false,
    uniques_enabled boolean NOT NULL DEFAULT false,
    enemy_nametags boolean NOT NULL DEFAULT false,
    silent_mode boolean NOT NULL DEFAULT false,
    auto_assign boolean NOT NULL DEFAULT false,
    teams_switch boolean NOT NULL DEFAULT false,
    ghosts boolean NOT NULL DEFAULT false,
    voice_chat boolean NOT NULL DEFAULT false,

    level_limit_enabled boolean NOT NULL DEFAULT false,
    level_limit_base integer NOT NULL DEFAULT 0,
    level_limit_tolerance smallint NOT NULL DEFAULT 0,

    team_kill_kick smallint NOT NULL DEFAULT 0,
    idle_kick smallint NOT NULL DEFAULT 0,

    CONSTRAINT chara_host_settings_pkey PRIMARY KEY (chara_id, type),
    CONSTRAINT chara_host_settings_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.game
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    lobby_id bigint NOT NULL,
    host_chara_id bigint NOT NULL,

    name character varying(16) NOT NULL,
    password character varying(16),
    comment character varying(128) NOT NULL DEFAULT '',
    stance smallint NOT NULL DEFAULT 0,
    max_players smallint NOT NULL DEFAULT 16,

    -- Index into the game's rotation, and the rule/map that entry resolves to.
    current_game smallint NOT NULL DEFAULT 0,
    rule smallint NOT NULL DEFAULT 0,
    map smallint NOT NULL DEFAULT 0,

    briefing_time smallint NOT NULL DEFAULT 0,
    dedicated boolean NOT NULL DEFAULT false,
    non_stat boolean NOT NULL DEFAULT false,
    friendly_fire boolean NOT NULL DEFAULT false,
    auto_aim boolean NOT NULL DEFAULT false,
    uniques_enabled boolean NOT NULL DEFAULT false,
    enemy_nametags boolean NOT NULL DEFAULT false,
    silent_mode boolean NOT NULL DEFAULT false,
    auto_assign boolean NOT NULL DEFAULT false,
    teams_switch boolean NOT NULL DEFAULT false,
    ghosts boolean NOT NULL DEFAULT false,
    voice_chat boolean NOT NULL DEFAULT false,
    level_limit_enabled boolean NOT NULL DEFAULT false,
    level_limit_base integer NOT NULL DEFAULT 0,
    level_limit_tolerance smallint NOT NULL DEFAULT 0,
    team_kill_kick smallint NOT NULL DEFAULT 0,
    idle_kick smallint NOT NULL DEFAULT 0,

    ping integer NOT NULL DEFAULT 0,
    host_score integer NOT NULL DEFAULT 0,
    host_votes integer NOT NULL DEFAULT 0,
    last_update timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT game_pkey PRIMARY KEY (id),
    CONSTRAINT game_lobby_id_fkey FOREIGN KEY (lobby_id)
        REFERENCES public.lobby (id) ON DELETE CASCADE,
    CONSTRAINT game_host_chara_id_fkey FOREIGN KEY (host_chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS game_lobby_id_idx ON public.game (lobby_id);

CREATE TABLE IF NOT EXISTS public.game_player
(
    game_id bigint NOT NULL,
    chara_id bigint NOT NULL,
    team smallint NOT NULL DEFAULT 0,
    joined_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT game_player_pkey PRIMARY KEY (game_id, chara_id),
    CONSTRAINT game_player_game_id_fkey FOREIGN KEY (game_id)
        REFERENCES public.game (id) ON DELETE CASCADE,
    CONSTRAINT game_player_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
