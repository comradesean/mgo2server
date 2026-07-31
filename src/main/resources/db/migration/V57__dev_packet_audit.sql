-- Remove the raw-payload capture table.
--
-- It began as blob_audit, an ad-hoc harness fed by a trigger on chara_host_settings.blob, and it
-- did its job: the 352-byte host-settings block is fully decoded into typed columns. V55 dropped
-- the column the trigger hung off, and rather than re-point it, the honest answer is that a
-- single-purpose tool whose purpose is served should go.
--
-- Widening it to capture every packet would be a DIFFERENT tool with different tradeoffs -- an
-- allow-list so pings do not drown it, a retention cap so it cannot fill a disk, and capture ahead
-- of validation so malformed payloads are kept. That is worth building when something needs it, not
-- worth keeping half of in the meantime.
--
-- THE CAPTURES SURVIVE, in dev/proto/samples/4310/. All 214 payloads, with the queries that
-- re-derive what was established from them: the 352-byte length, the training-lobby correlation in
-- struct +824/+931, and the Common Settings bits that cannot be rebuilt from their booleans.
-- Discarding evidence because the conclusion is written down is how a finding becomes unverifiable;
-- discarding the machinery once the evidence is safe is just tidying.
--
-- The inert-field tripwire (V56) stays. It is the cheap half -- distinct values per watched field,
-- a second row is an alert -- and it is the one that keeps working when a patched client appears.

DROP TABLE IF EXISTS public.blob_audit;
DROP TABLE IF EXISTS public.dev_packet_audit;
DROP FUNCTION IF EXISTS public.audit_host_settings_blob();
