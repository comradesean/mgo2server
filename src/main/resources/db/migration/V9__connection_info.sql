-- Peer-to-peer endpoints a character registers on entering a game lobby (command 0x4700), so a
-- joining player (command 0x4320) can be handed the host's address. Keyed by character rather
-- than game because the registration arrives before the game is created, and the public address
-- is observed from the socket rather than trusted from the payload.
CREATE TABLE IF NOT EXISTS public.chara_connection
(
    chara_id bigint NOT NULL,
    public_ip character varying(64) NOT NULL,
    public_port integer NOT NULL,
    private_ip character varying(64) NOT NULL,
    private_port integer NOT NULL,
    updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chara_connection_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_connection_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
