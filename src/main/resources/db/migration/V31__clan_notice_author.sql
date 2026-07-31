-- Who last set the clan notice, and when.
--
-- 0x4b21 carries them immediately after the 512-byte notice: a u32 timestamp at T+0x904 and a
-- 16-byte name at T+0x908, which the Clan Affiliation screen renders as the notice's date and
-- author. T+0x904 was briefly taken for the clan's founding date — it is the field the screen
-- shows a date in, but the date it shows is the notice's.
alter table clan add column notice_at timestamptz;
alter table clan add column notice_writer_chara_id bigint references chara (id) on delete set null;
