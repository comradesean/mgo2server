-- Accounts, characters and lobbies: the minimum needed for a client to log in and reach a lobby.

CREATE TABLE IF NOT EXISTS public.account
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    username character varying(32) NOT NULL,
    password character varying(255) NOT NULL,
    -- Issued by the web side when a player authenticates; the game client presents it back
    -- (encrypted) on the check-session packet. Null means no active session.
    session character varying(8),
    -- Character slots the account has paid for or been granted.
    slots smallint NOT NULL DEFAULT 3,
    main_chara_id bigint,
    current_chara_id bigint,
    created_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT account_pkey PRIMARY KEY (id),
    CONSTRAINT account_username_key UNIQUE (username),
    CONSTRAINT account_session_key UNIQUE (session)
);

CREATE TABLE IF NOT EXISTS public.chara
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    account_id bigint NOT NULL,
    name character varying(16) NOT NULL,
    -- Soft delete: the client keeps referring to characters after they are removed.
    active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chara_pkey PRIMARY KEY (id),
    CONSTRAINT chara_name_key UNIQUE (name),
    CONSTRAINT chara_account_id_fkey FOREIGN KEY (account_id)
        REFERENCES public.account (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS chara_account_id_idx ON public.chara (account_id);

ALTER TABLE public.account
    ADD CONSTRAINT account_main_chara_id_fkey FOREIGN KEY (main_chara_id)
        REFERENCES public.chara (id) ON DELETE SET NULL;

ALTER TABLE public.account
    ADD CONSTRAINT account_current_chara_id_fkey FOREIGN KEY (current_chara_id)
        REFERENCES public.chara (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.lobby
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    -- 0 gate, 1 account, 2 game. The client is handed this list and connects onward.
    type smallint NOT NULL,
    subtype smallint NOT NULL DEFAULT 0,
    name character varying(16) NOT NULL,
    ip character varying(15) NOT NULL,
    port integer NOT NULL,
    beginners_only boolean NOT NULL DEFAULT false,
    expansion_required boolean NOT NULL DEFAULT false,
    no_headshots boolean NOT NULL DEFAULT false,
    CONSTRAINT lobby_pkey PRIMARY KEY (id)
);
