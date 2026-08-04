-- Five gameplay options in 0x4120 were driven by the wrong bits. All five are read by the live
-- client on every login, so each one is a player-visible defect rather than a mapping nicety.
-- Established 2026-08-04 by walking the client's own option-screen accessor bank
-- (0x9066F0-0x906894, one function per nibble), its defaults/clamp run (0x9472B4-0x947D44) and
-- the 88-arm ONLINE GAME OPTIONS row switch at 0x9AD0F4. See dev/proto/outbound/mgo2_cmd_4120_s2c.ksy.
--
-- 1. "Now" (the weapon Recall Mode swaps to) lives in wire byte 0x10's HIGH nibble, which we never
--    sent. Its accessor is 0x90681C, read at 0x9C9E74 on the mode==1 branch.
-- 2. Wire byte 0x11's high nibble is NOT "Now" - it is the single weapon Toggle Mode equips and
--    unequips (accessor 0x906834, read at 0x9C9094 on the mode==0 fall-through). The existing
--    weapon_switch_now column has been holding that value all along, so it is renamed rather than
--    dropped: the data is correct, only the name was wrong.
-- 3. First Person View Memory is wire byte 0x12's LOW NIBBLE compared against 1, not bit 1. We
--    wrote 0b10, which the client's own validator (0x947AF8) rewrites to 1 = Disabled. Renamed to
--    say what the wire says: 0 = Enabled (the client's default), 1 = Disabled.
-- 4. Wire byte 0x0D bits 0-1 are Voice Chat Audio Output Device, which we pinned to 1
--    (USB/Bluetooth Device) on every login and never read back.
-- 5. Wire byte 0x0D bits 2-3 are Codec Audio Output Device, which we always sent as 0 and never
--    read back.
--
-- Every default below is the client's own, read from the defaults run: 0x9474B8 and 0x9474D0
-- (both li r4,0) for the two output devices, 0x947448 (li r4,0) for the toggle weapon.

ALTER TABLE public.chara_settings RENAME COLUMN weapon_switch_now TO weapon_switch_toggle;

ALTER TABLE public.chara_settings ADD COLUMN weapon_switch_now smallint NOT NULL DEFAULT 0;

-- Bit 2 of wire byte 0x03 SET means "Camera direction", not "Player direction" - the value we send
-- was always right, the name inverted it. The client's default is 4, i.e. the bit set, which is why
-- this column defaults to true.
ALTER TABLE public.chara_settings RENAME COLUMN first_view_player_direction TO first_view_camera_direction;

ALTER TABLE public.chara_settings RENAME COLUMN first_view_memory TO first_view_memory_disabled;

ALTER TABLE public.chara_settings ADD COLUMN voice_chat_output_device smallint NOT NULL DEFAULT 0;

ALTER TABLE public.chara_settings ADD COLUMN codec_output_device smallint NOT NULL DEFAULT 0;

-- Deliberately NOT constrained: voice_chat_volume and headset_volume are the only two sliders the
-- client does not coerce away from zero. Its validator clamps the recognition level with both
-- "== 0 -> 5" and "greater than 10 -> 5" (0x947A64, 0x947A8C), but clamps these two with only
-- "greater than 10 -> 5" (0x947AB4, 0x947ADC). Zero is therefore a state the game itself permits -
-- silence - and rejecting it here would be us inventing policy the client does not have.
