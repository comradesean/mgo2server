-- Ad-hoc capture harness: archives a blob column on every write, so consecutive writers do not
-- overwrite the evidence while a payload is being decoded. Not part of the schema.
--
-- RETIRED FOR chara_host_settings AS OF V55. That column is gone -- the 0x4310 host-settings block
-- is fully decoded into typed columns, which is what this harness existed to make possible, and
-- V55 drops the trigger along with the column. The captured rows in blob_audit are KEPT: they are
-- the evidence the decode was built from, and discarding them because the conclusion is written
-- down would make that conclusion unverifiable.
--
-- To use it on the next blob, change the table and column in the trigger below. The function reads
-- NEW.blob by name, so a differently-named column needs it adjusted too.
--
-- Drop with: DROP TRIGGER <name> ON <table>;
--            DROP FUNCTION audit_host_settings_blob; DROP TABLE blob_audit;
CREATE TABLE IF NOT EXISTS blob_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    chara_id bigint NOT NULL,
    type smallint NOT NULL,
    blob bytea,
    captured_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_host_settings_blob() RETURNS trigger AS $$
BEGIN
    IF NEW.blob IS NOT NULL THEN
        INSERT INTO blob_audit (chara_id, type, blob) VALUES (NEW.chara_id, NEW.type, NEW.blob);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- No trigger is installed by default any more: the column this pointed at no longer exists.
-- Uncomment and edit for the next capture.
--
-- CREATE TRIGGER <name>_blob_audit
--     AFTER INSERT OR UPDATE OF blob ON <table>
--     FOR EACH ROW EXECUTE FUNCTION audit_host_settings_blob();

SELECT 'blob_audit table and function ready; no trigger installed' AS status;
