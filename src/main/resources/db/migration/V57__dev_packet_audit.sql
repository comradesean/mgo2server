-- The raw-payload capture table, named for what it is, and kept fed.
--
-- It began as blob_audit, created by dev/tools/blob_audit.sql and fed by a trigger on
-- chara_host_settings.blob. V55 dropped that column when the host-settings block was decoded into
-- typed columns, which took the trigger with it -- so the capture stopped, and on a fresh
-- deployment the table would not have existed at all.
--
-- Renamed because "blob_audit" says what it stores rather than what it is FOR, and with the blob it
-- was named after now gone the name actively misleads: a reader would go looking for a matching
-- blob column. "dev_packet_audit" says the two things that matter -- DEV tooling, archiving
-- PACKETS.
--
-- EXISTING ROWS ARE PRESERVED. They are the captures the host-settings decode was built from, and
-- 214 of them are what proved the two no-reader fields track training lobbies. Discarding evidence
-- because the conclusion is written down is how a finding becomes unverifiable.
--
-- The capture now runs in the server rather than in a trigger, gated by MGO2SERVER_CAPTURE_PACKETS.
-- That is better placed than the trigger was: a trigger only ever saw what we CHOSE to store, while
-- the server sees exactly what the client sent, including bytes we do not model.
--
-- It complements the inert-field tripwire rather than duplicating it:
--
--   inert_field_watch  -- the SUMMARY. Distinct values per field; a second row is an alert.
--   dev_packet_audit   -- the EVIDENCE. Whole payloads with timestamps.

ALTER TABLE IF EXISTS public.blob_audit RENAME TO dev_packet_audit;

CREATE TABLE IF NOT EXISTS public.dev_packet_audit (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	chara_id bigint NOT NULL,
	type smallint NOT NULL,
	blob bytea,
	captured_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dev_packet_audit_captured_at_idx ON public.dev_packet_audit (captured_at);

-- The column keeps the name "blob": it holds a raw payload, which is what a blob honestly is here.
COMMENT ON TABLE public.dev_packet_audit IS
	'DEV TOOLING. Raw protocol payloads as received, one row per push, for offline decoding. Never '
	'served to a client. Written when MGO2SERVER_CAPTURE_PACKETS is on. Grows unbounded by design -- '
	'consecutive senders must not overwrite each other -- so prune with: delete from '
	'dev_packet_audit where captured_at < now() - interval ''90 days'';';
