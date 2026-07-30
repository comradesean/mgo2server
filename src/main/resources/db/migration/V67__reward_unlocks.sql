-- Colour reward unlocks, from the database instead of a hardcoded filler.
--
-- The gear payload in 0x4124 and 0x4133 ends with 32 bytes that are NOT a terminator, despite the
-- name they carried for a long time. [ELF] they are SIXTEEN {u8 item_id, u8 bit_index} pairs, read
-- by both parsers into the same table -- sixteen, not fifteen: the bound at 0xD3C8D4 is tested
-- before the increment at 0xD3C8DC, and 4 + 615 + 32 = 651 only balances at sixteen.
--
-- We filled all 32 bytes with 0xff. That works only by accident: item id 255 exceeds the parser's
-- 128-entry bound, so every pair is skipped rather than applied. Inert, not correct -- and the
-- existing comment in LoadoutWriter already said that anything granting colours per character has
-- to write real pairs here, in both packets.
--
-- This is the table that lets it. A row is "this character has unlocked colour <bit> of item
-- <item>", i.e. a reward, distinct from chara_gear.colours which is the base mask for an item the
-- character owns.
--
-- SIXTEEN IS A HARD WIRE LIMIT, not a policy choice: there are exactly sixteen slots in the
-- payload. The reader takes the oldest sixteen by unlocked_at so the selection is deterministic
-- and stable between packets -- 0x4124 and 0x4133 must agree, or the client's table depends on
-- which packet arrived last.
--
-- Unused slots keep the 0xff filler, which is the one thing about the old behaviour that was
-- right: it is provably skipped by the parser. So an account with no rows here is byte-identical
-- to what we sent before, and this migration changes nothing until a row exists.
--
-- Colour indices are 0..35 across the catalogue (VA 0x10506BC, 36-byte records, 1044 rows,
-- 71 item ids); the widest single item has 24. The bit_index range below is the wire's u8, not a
-- claim about which values are meaningful for a given item.

CREATE TABLE public.reward_unlock
(
    chara_id    bigint      NOT NULL REFERENCES public.chara (id) ON DELETE CASCADE,
    item_id     smallint    NOT NULL,
    bit_index   smallint    NOT NULL,
    unlocked_at timestamptz NOT NULL DEFAULT now(),
    -- Why it was granted, for an operator reading these later. Free text on purpose: the award
    -- system is ours, and pinning an enum now would be inventing policy we have not designed.
    reason      character varying(64) NOT NULL DEFAULT '',
    CONSTRAINT reward_unlock_pkey PRIMARY KEY (chara_id, item_id, bit_index),
    CONSTRAINT reward_unlock_item_range CHECK (item_id BETWEEN 0 AND 254),
    CONSTRAINT reward_unlock_bit_range CHECK (bit_index BETWEEN 0 AND 254)
);

COMMENT ON TABLE public.reward_unlock IS
    'Colour reward unlocks, written into the sixteen {item_id, bit_index} pairs at the end of the '
    '0x4124 / 0x4133 gear payload. Item 255 is excluded by the constraints because the client '
    'parser skips it -- 255 is the filler value for unused slots.';

CREATE INDEX reward_unlock_chara_idx ON public.reward_unlock (chara_id, unlocked_at);
