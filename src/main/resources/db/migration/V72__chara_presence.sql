-- Which lobby each character is in, right now. See dev/docs/PRESENCE.md for the full design.
--
-- The server has never known this. Production runs one process per lobby and ChannelRegistry is
-- deliberately per-instance, so no process can answer "where is this character" about anyone
-- outside itself. Three things are blocked on it, and one of them is not merely blank but WRONG:
-- 0x4582's wire 0x14 is a LOBBY ID that the client renders and then dials on "move to lobby", and
-- we hardcode 1 -- telling every client that every friend is in lobby 1.
--
-- CHARA_ID ALONE IS THE PRIMARY KEY, not (chara_id, lobby_id). A character is in exactly one lobby
-- at a time; making that the key lets the database enforce the invariant instead of relying on
-- every call site being careful, and it makes a lobby change one upsert rather than a
-- delete-then-insert with a window in the middle.
--
-- GAME MEMBERSHIP IS NOT DUPLICATED HERE. game_player already records which game a character is
-- in. This answers *which lobby*; the game comes from a join. Two tables both claiming to know the
-- current game is the kind of second source that goes stale and then gets believed.
--
-- THE RACE, because it is one clause and it is hard to diagnose afterwards: a lobby hop is two
-- processes racing -- the destination's insert against the origin's disconnect-delete, in either
-- order. So enter is an upsert and leave is CONDITIONAL on the deleting process owning the row
-- (`where chara_id = ? and lobby_id = :myLobby`). Without that clause a late disconnect erases the
-- presence the new lobby just wrote, and the player intermittently vanishes from every friend list.
--
-- CRASH RECOVERY is a boot-time `delete where lobby_id = :myLobby` rather than a TTL, because
-- nobody is connected to a process that has just started, so it is unconditionally correct. This
-- project has had a container crash-loop ~1300 times; a TTL-only design would have left every one
-- of those players "present" until the timer ran out. The heartbeat covers only a process that
-- dies and never comes back.

CREATE TABLE public.chara_presence
(
    chara_id  bigint      NOT NULL,
    lobby_id  bigint      NOT NULL,
    -- When they entered THIS lobby -- reset by the upsert on a hop, unlike last_seen.
    since     timestamptz NOT NULL DEFAULT now(),
    -- Touched by the heartbeat. Only the reaper reads it.
    last_seen timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chara_presence_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_presence_chara_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_presence_lobby_fkey FOREIGN KEY (lobby_id)
        REFERENCES public.lobby (id) ON DELETE CASCADE
);

-- The boot-time clear and the per-lobby population count both filter on lobby_id.
CREATE INDEX chara_presence_lobby_idx ON public.chara_presence (lobby_id);

-- The reaper scans by age across all lobbies.
CREATE INDEX chara_presence_last_seen_idx ON public.chara_presence (last_seen);

COMMENT ON TABLE public.chara_presence IS
    'Which lobby each character is connected to, one row per character. Written by ChannelRegistry '
    'on connect and disconnect, refreshed by GameServer''s scheduler, and cleared for its own '
    'lobby by each process at startup. Ephemeral: a row here is a claim about a live TCP '
    'connection, not durable state, and losing the table costs nothing but a reconnect.';

COMMENT ON COLUMN public.chara_presence.lobby_id IS
    'The lobby process holding the connection. Also the value 0x4582 wire 0x14 wants, which the '
    'client dials on "move to lobby".';
