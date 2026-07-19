-- What a character needs on connecting to a game lobby.

-- Experience is tracked per account rather than per character: the main character and the alts
-- each have their own pool, which is what the original modelled.
ALTER TABLE public.account ADD COLUMN IF NOT EXISTS main_exp integer NOT NULL DEFAULT 0;
ALTER TABLE public.account ADD COLUMN IF NOT EXISTS alt_exp integer NOT NULL DEFAULT 0;

-- Two sets of twelve preset chat messages, addressed by (type, index) rather than by id because
-- that is how the client sends them back.
CREATE TABLE IF NOT EXISTS public.chara_chat_macro
(
    chara_id bigint NOT NULL,
    type smallint NOT NULL,
    index smallint NOT NULL,
    text character varying(64) NOT NULL DEFAULT '',
    CONSTRAINT chara_chat_macro_pkey PRIMARY KEY (chara_id, type, index),
    CONSTRAINT chara_chat_macro_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_chat_macro_type_check CHECK (type BETWEEN 0 AND 1),
    CONSTRAINT chara_chat_macro_index_check CHECK (index BETWEEN 0 AND 11)
);
