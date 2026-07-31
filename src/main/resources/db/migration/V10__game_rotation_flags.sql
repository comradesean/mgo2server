-- Round-0 rotation flags for a game (the third byte of the [rule, map, flags] triple the host
-- pushes via 0x4310). rule and map already exist on game; this adds the flags the game-details
-- reply (0x4313) sends and that carry the per-round modifiers ("Normal" vs others). Meaning of the
-- bits is undocumented in every reference, so it is stored and replayed opaquely.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS flags integer NOT NULL DEFAULT 0;
