-- The raw 0x4310 host-settings blob for a game, stored so the game-details reply (0x4313) can
-- replay the fields it needs (per-mode timers/rounds/tickets, uniques) verbatim without the server
-- having to name and re-serialize every one. rule/map/flags are also broken out into their own
-- columns for the game list; this is the whole blob for the details reply.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS host_settings bytea;
