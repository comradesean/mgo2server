-- A diagnostic override for the player count a lobby reports in the gate list (0x2003 wire 0x29).
--
-- The real count is derived from game_player and is the honest number. This exists because the
-- count is the ONLY per-lobby value that varies in a sub-list row -- the row is name plus count and
-- nothing else (0x8FFE44's lobby call site passes literal zero for its remaining fields) -- so if
-- the client marks a lobby visually at all on this build, a count threshold is one of the few
-- remaining ways it could be doing it. Faking one is how you find out.
--
-- NULL means "use the real count", which is what every lobby does. Set it, watch the list, unset
-- it. It is not policy and nothing should depend on it; if it is still here with rows set to
-- non-NULL after the question is answered, that is a bug.
ALTER TABLE public.lobby
    ADD COLUMN IF NOT EXISTS player_count_override integer;

ALTER TABLE public.lobby
    ADD CONSTRAINT lobby_player_count_override_range
        CHECK (player_count_override IS NULL OR player_count_override BETWEEN 0 AND 65535);
