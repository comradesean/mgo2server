-- The lobby subtype a round was played in, recorded on the report itself.
--
-- round_report.game_id has no foreign key and games are deleted on teardown, so joining a report
-- back to its lobby through `game` finds nothing the moment the host leaves. Every training total
-- derived that way read zero. The reporting server knows its own subtype from configuration, so
-- it is stamped at insert time instead.
--
-- Existing rows keep 0: their games are already gone and the value cannot be recovered. 0 is not a
-- real game-lobby subtype, so those rows are simply excluded from per-subtype totals rather than
-- being miscounted as training.
ALTER TABLE round_report ADD COLUMN lobby_subtype smallint NOT NULL DEFAULT 0;

COMMENT ON COLUMN round_report.lobby_subtype IS
    'Lobby subtype the round was played in, stamped at insert; 0 for rows predating V19.';
