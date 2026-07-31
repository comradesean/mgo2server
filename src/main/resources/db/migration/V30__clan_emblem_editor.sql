-- Who may set the clan's emblem.
--
-- 0x4b62 assigns it ("Assign Emblem Editing Rights", lobby string 17062) and the id is reported in
-- 0x4b21 at T+0x6FC, where the client compares it against its own character id to decide whether to
-- offer "set as the clan's emblem". Null means nobody is assigned, and the leader is used instead —
-- they can commit an emblem regardless, since the client's own gate is membership state 2.
alter table clan add column emblem_editor_chara_id bigint references chara (id) on delete set null;
