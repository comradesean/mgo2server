-- Seed for live testing against a real client.
--
-- Run against a migrated database:
--   docker compose exec -T postgres psql -U mgo2server -d mgo2server < dev/tools/seed.sql
--
-- IMPORTANT: the ip column is what the client is told to connect to next. It must be an address
-- the console (or RPCS3) can actually reach — the host's LAN address, not 127.0.0.1, unless the
-- emulator runs on the same machine. Edit the addresses below before running.

\set host_ip '192.168.1.200'

-- One lobby of each type. The gate is what the client reaches first; it hands back this list, and
-- the client then connects to the account lobby and finally a game lobby.
-- The client dials 15731 for the gate; the remaining ports are advertised in the lobby list.
-- Order matters, and it is by id, not by name: the client refers to a lobby by its index in the
-- list it was sent. Ordering by name was a bug -- see dev/docs/OBSERVED.md.
-- Idempotent, and with fixed ids.
--
-- The ids are not an implementation detail: compose passes MGO2SERVER_LOBBY_ID and
-- MGO2SERVER_LOBBY_SUBTYPE to each server, so every id below must keep matching the service that
-- claims it (gate 1, account 2, automatching 3, game 4, basic training 5, combat training 6). An earlier version of this file deleted and
-- reinserted without specifying ids, which let the serial advance on every run -- the rows looked
-- right, but games then failed to insert with a foreign key violation against a lobby id that no
-- longer existed.
--
-- Games reference lobbies, so they go first.
DELETE FROM public.game;
DELETE FROM public.lobby WHERE type IN (0, 1, 2, 3, 4, 5, 6, 7);

-- OVERRIDING SYSTEM VALUE because id is GENERATED ALWAYS; the whole point here is to choose it.
INSERT INTO public.lobby (id, type, subtype, name, ip, port)
OVERRIDING SYSTEM VALUE VALUES
    (1, 0, 0, 'Gate',    :'host_ip', 15731),
    (2, 1, 0, 'Account', :'host_ip', 15732),
    (3, 2, 2, 'Automatching', :'host_ip', 15740),
    (4, 2, 1, 'Game', :'host_ip', 15733),
    (5, 2, 7, 'Basic Training', :'host_ip', 15737),
    (6, 2, 8, 'Combat Training', :'host_ip', 15738);

-- Basic Training is 7 and Combat Training is 8, and the difference is not cosmetic. Both list
-- either way -- the sibling list at 0x89147C groups 7 and 8 and separates by lobby id, which is why
-- two subtype-7 rows both appeared on echo -- but the menu INSIDE a training lobby is gated row by
-- row by 0x884584(n), which matches the current lobby's own subtype exactly. A Combat Training
-- lobby seeded as 7 renders the basic-training menu: Solo/Novice only.
--
-- The port check is what constrains this table. It does not dial the lobby you pick: it connects
-- to the *ordinal-th* game lobby in the gate list, where the ordinal is a saved client setting
-- (group 25, id 0xFE, defaulting to 0) — see PROTOCOL.md, 0x4900. So whichever game lobby that
-- ordinal lands on must have a server listening on its ip and port, or login fails with "unable
-- to connect to lobby" before any of this is reached. Inserting a row ahead of the others moves
-- that target. Either give every game lobby its own instance (compose has one per row) or point
-- them all at a port that is actually up.


-- Keep the sequence ahead of the explicit ids so later inserts do not collide.
SELECT setval(pg_get_serial_sequence('public.lobby', 'id'),
              (SELECT max(id) FROM public.lobby), true);


-- A test account.
--
-- No session is set here. The client does not present a token: it derives a sixteen-byte value
-- from the one the login endpoint hands it, and the account stores that derived value, written by
-- AuthWebController when the player logs in. Seeding a session by hand is meaningless now -- the
-- column holds 32 hex characters, not the 8-character token this used to write.
--
-- The password is the MD5 the client sends, so log in with the password 'nomad'.
INSERT INTO public.account (username, password, slots, main_exp)
VALUES ('tester', md5('nomad'), 3, 0)
ON CONFLICT (username) DO NOTHING;

-- Something for the news screen, which is one of the first things the client asks for.
INSERT INTO public.news (important, title, body)
VALUES (true, 'mgo2server', 'Test server online.')
ON CONFLICT DO NOTHING;

SELECT id, type, name, ip, port FROM public.lobby ORDER BY id;
SELECT id, username, coalesce(session, '(no session until first login)') FROM public.account ORDER BY id;
