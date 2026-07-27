-- The clan notice: the 512-byte text field, distinct from the 128-byte comment.
--
-- Confirmed live 2026-07-27 by setting each from the client and watching the wire: 0x4b64 carried
-- "bench" in 128 bytes (Clan Comment, the `description` column) and 0x4b66 carried "watching you"
-- in 512 (Clan Notice, this column). That also identifies the 512-byte blob at T+0x700 in the
-- 0x4b21 profile block, which the ksy had as an unknown "long text block or packed table".
alter table clan add column notice varchar(512) not null default '';
