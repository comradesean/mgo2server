-- Bring blob_audit into the schema, and keep capturing raw host-settings pushes.
--
-- The table was created by dev/tools/blob_audit.sql and fed by a trigger on
-- chara_host_settings.blob. V55 dropped that column, which took the trigger with it -- so the
-- capture stopped, and on a fresh deployment the table would not exist at all.
--
-- The capability is worth keeping and the trigger cannot come back, because there is no longer a
-- blob column to hang it on. The capture moves into the server instead, at the point the raw 0x4310
-- payload actually arrives. That is strictly better placed: a trigger only ever saw what we chose to
-- store, while this sees exactly what the client sent, including any bytes we do not yet model.
--
-- It complements inert_field_watch rather than duplicating it:
--
--   inert_field_watch  -- the SUMMARY. Distinct values per field; a second row is an alert.
--   blob_audit         -- the EVIDENCE. Whole payloads with timestamps, so any future question can
--                         be answered against real bytes instead of re-deriving from a conclusion.
--
-- The existing rows are kept. They are the captures the host-settings decode was built from, and
-- 214 of them are what proved the two no-reader fields track training lobbies.

CREATE TABLE IF NOT EXISTS public.blob_audit (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	chara_id bigint NOT NULL,
	type smallint NOT NULL,
	blob bytea,
	captured_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS blob_audit_captured_at_idx ON public.blob_audit (captured_at);

COMMENT ON TABLE public.blob_audit IS
	'Raw 0x4310 host-settings payloads as received, one row per push. Analysis evidence, never '
	'served to a client. Grows unbounded by design -- consecutive hosts must not overwrite each '
	'other. Prune with: delete from blob_audit where captured_at < now() - interval ''90 days'';';
