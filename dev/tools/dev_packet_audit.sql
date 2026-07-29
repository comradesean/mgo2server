-- Capture harness for raw payloads. Analysis evidence, never served to a client.
--
-- THE HOST-SETTINGS CAPTURE IS NOW IN THE SERVER, not in this file, and is gated by
-- MGO2SERVER_CAPTURE_PACKETS. It used to be a trigger on
-- chara_host_settings.blob; V55 dropped that column when the block was decoded into typed columns,
-- which took the trigger with it. GameService.archiveHostSettings writes every raw 0x4310 push to
-- dev_packet_audit instead, and V57 owns the table.
--
-- Capturing in the server is better placed than a trigger was: a trigger only ever saw what we
-- CHOSE to store, while the server sees exactly what the client sent, including bytes we do not
-- model. That difference is the whole point of an evidence trail.
--
-- It pairs with inert_field_watch:
--
--   inert_field_watch  -- the SUMMARY. Distinct values per watched field; a second row is an alert.
--   dev_packet_audit         -- the EVIDENCE. Whole payloads with timestamps.
--
-- This file remains for capturing a DIFFERENT blob column, if one ever needs the same treatment.
-- Edit the table and column below; the function reads NEW.blob by name, so a differently-named
-- column needs it adjusted too.

CREATE OR REPLACE FUNCTION audit_host_settings_blob() RETURNS trigger AS $$
BEGIN
    IF NEW.blob IS NOT NULL THEN
        INSERT INTO dev_packet_audit (chara_id, type, blob) VALUES (NEW.chara_id, NEW.type, NEW.blob);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- No trigger is installed: the host-settings capture lives in the server now. Uncomment and edit
-- for the next blob that needs archiving.
--
-- CREATE TRIGGER <name>_dev_packet_audit
--     AFTER INSERT OR UPDATE OF blob ON <table>
--     FOR EACH ROW EXECUTE FUNCTION audit_host_settings_blob();

SELECT 'dev_packet_audit function ready; host-settings capture runs in the server' AS status;
