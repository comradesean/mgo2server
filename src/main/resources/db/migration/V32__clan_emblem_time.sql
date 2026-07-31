-- When the clan's emblem was last put on display.
--
-- Emblem Edit warns that a spam filter may block re-displaying for a fixed time, and the client has
-- the string for it ("You must wait another %d hours %d minutes before you can put this emblem on
-- display", lobby 17247) — so it formats a remaining duration, which means it computes one from a
-- timestamp. The only candidate the server sends is 0x4b21's T+0x48, read as a u32 and stored with
-- `std` as a 64-bit word (0xD5899C), the same shape the client uses for other timestamps. We have
-- been sending zero there, i.e. 1970, so any cooldown has always already expired.
alter table clan add column emblem_at timestamptz;
