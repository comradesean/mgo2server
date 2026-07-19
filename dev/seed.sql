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
-- Names matter: the list is ordered by name so a lobby the client can enter comes before the
-- gate it just left.
INSERT INTO public.lobby (type, subtype, name, ip, port) VALUES
    (0, 0, 'Gate',    :'host_ip', 15731),
    (1, 0, 'Account', :'host_ip', 15732),
    (2, 1, 'Game',    :'host_ip', 15733)
ON CONFLICT DO NOTHING;

-- A test account. The session token is what the client presents on check-in; there is no web
-- login flow yet, so it is set here directly. It must be exactly 8 characters.
INSERT INTO public.account (username, password, session, slots, main_exp)
VALUES ('tester', 'unused', 'abcd1234', 3, 0)
ON CONFLICT (username) DO UPDATE SET session = EXCLUDED.session;

-- Something for the news screen, which is one of the first things the client asks for.
INSERT INTO public.news (important, title, body)
VALUES (true, 'nomad-ng', 'Test server online.')
ON CONFLICT DO NOTHING;

SELECT id, type, name, ip, port FROM public.lobby ORDER BY id;
SELECT id, username, session FROM public.account ORDER BY id;
