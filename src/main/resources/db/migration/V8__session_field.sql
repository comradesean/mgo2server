-- The account no longer stores a fragment of the login token. The client never sends the token
-- back: it derives a sixteen-byte value from it at login and presents that on check-session, so
-- the server stores the same derived value and matches it with a plain lookup. Sixteen bytes as
-- hex is 32 characters. See nomad.common.crypto.SessionField.
--
-- Existing sessions cannot be converted -- the stored eight characters are a prefix of a token
-- that was never kept in full -- so they are cleared. Clients simply log in again.
ALTER TABLE account ALTER COLUMN session TYPE character varying(32);

UPDATE account SET session = NULL;
