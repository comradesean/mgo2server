-- Match-state tracking, fed by the in-match host commands.
--
-- blob: the raw 0x4310 host-settings push, saved per (character, lobby subtype) so 0x4304 can
-- pre-fill the Create Game screen next session. Stored raw because the client's own serializer is
-- the only authority on its layout; the read side re-maps it into the 0x4305 reply shape.
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS blob bytea;

-- Per-player latency, reported by the host via 0x4398 and served back in the 0x4313 player list.
ALTER TABLE public.game_player ADD COLUMN IF NOT EXISTS ping integer NOT NULL DEFAULT 0;

-- Round membership snapshot, taken when the host starts a round (0x43ca): only players flagged
-- here are accepted as stat targets in the host's end-of-round 0x4390 reports. Players who join
-- mid-round keep the default false until the next round starts.
ALTER TABLE public.game_player ADD COLUMN IF NOT EXISTS played_last_round boolean NOT NULL DEFAULT false;
