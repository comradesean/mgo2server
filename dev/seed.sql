-- Seed for live testing against a real client.
--
-- Run against a migrated database:
--   docker compose exec -T postgres psql -U nomad -d nomad < dev/seed.sql
--
-- IMPORTANT: the ip column is what the client is told to connect to next. It must be an address
-- the console (or RPCS3) can actually reach — the host's LAN address, not 127.0.0.1, unless the
-- emulator runs on the same machine. Edit the addresses below before running.

\set host_ip '192.168.1.100'

-- One lobby of each type. The gate is what the client reaches first; it hands back this list, and
-- the client then connects to the account lobby and finally a game lobby.
-- The client dials 15731 for the gate; the remaining ports are advertised in the lobby list.
-- Order matters, and it is by id, not by name: the client refers to a lobby by its index in the
-- list it was sent. Ordering by name was a bug -- see dev/OBSERVED.md.
INSERT INTO public.lobby (type, subtype, name, ip, port) VALUES
    (0, 0, 'Gate',    :'host_ip', 15731),
    (1, 0, 'Account', :'host_ip', 15732),
    (2, 1, 'Game',    :'host_ip', 15733)
ON CONFLICT DO NOTHING;

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
VALUES (true, 'nomad-ng', 'Test server online.')
ON CONFLICT DO NOTHING;

SELECT id, type, name, ip, port FROM public.lobby ORDER BY id;
SELECT id, username, coalesce(session, '(no session until first login)') FROM public.account ORDER BY id;
