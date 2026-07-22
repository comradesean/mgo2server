-- Ad-hoc capture harness for the 0x142/0x143 conflict test; not part of the schema.
-- Archives every 0x4310 host-settings blob push so consecutive hosts don't overwrite the
-- evidence. Drop with: DROP TRIGGER host_settings_blob_audit ON chara_host_settings;
--                      DROP FUNCTION audit_host_settings_blob; DROP TABLE blob_audit;
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

DROP TRIGGER IF EXISTS host_settings_blob_audit ON chara_host_settings;
CREATE TRIGGER host_settings_blob_audit
    AFTER INSERT OR UPDATE OF blob ON chara_host_settings
    FOR EACH ROW EXECUTE FUNCTION audit_host_settings_blob();

SELECT 'trigger installed' AS status;
