-- The hub entry's flags byte (0x4902 wire offset 0x07), per lobby.
--
-- We have never sent this byte as anything but zero, and not on purpose: HubGameController packs
-- the subtype into the TOP byte of a u32 attribute word, so wire 0x04 gets the subtype and 0x05,
-- 0x06 and 0x07 fall out as zero. 0x07 is the flags byte.
--
-- That is why a lobby with beginners_only set shows no "newbie" icon and admits anyone. The gate
-- list's restriction bits (0x2003 offset 0x2d) ARE being sent -- a live capture on 2026-07-28
-- shows JOHNNY's entry ending `3d77 0000 0008 01` -- and the client ignored them for both the icon
-- and the entry gate. The menus come from the hub list, not the gate list; LOBBIES.md says so in
-- as many words and the code did not follow it.
--
-- WHICH BIT means "beginners" is NOT known, so this column is a raw byte to sweep rather than a
-- boolean to trust. What is known, from the parser at 0xD47E18 (0xD47F40..0xD47FEC): the byte is
-- expanded one bit per struct field AND REVERSED -- wire bit 0 becomes internal 0x80, wire bit 1
-- becomes 0x40, down to wire bit 7 (tested as the sign) becoming internal 0x01. So a guess made at
-- the wrong end of the byte would look like a clean negative result. Sweep it.
ALTER TABLE public.lobby
    ADD COLUMN IF NOT EXISTS hub_flags smallint NOT NULL DEFAULT 0;

ALTER TABLE public.lobby
    ADD CONSTRAINT lobby_hub_flags_range CHECK (hub_flags BETWEEN 0 AND 255);
