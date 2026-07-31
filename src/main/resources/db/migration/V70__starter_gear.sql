-- The starter gear set: what a character owns on creation, and what every character owns now.
--
-- Until now creation granted the ENTIRE catalogue in EVERY colour -- "select distinct item_id from
-- gear_item" with colours defaulting to 0xFFFFFFFF. V44 built the structure for a real starter set
-- and deliberately did not use it, saying so in its own header: "Restricting a character to a
-- starter set is now a DELETE, not a code change. Do that deliberately, as policy." This is that
-- policy, chosen by the operator.
--
-- OPERATOR POLICY, NOT PROTOCOL. Nothing in the binary says which items a character should begin
-- with -- the client renders whatever the two gear writers agree on. These 28 items and their
-- colours are a choice and can be edited freely; the table exists so that editing them is an
-- UPDATE rather than a rebuild.
--
-- THE MASKS ARE NOT ARBITRARY, AND NOT UNIFORM. A colour bit indexes a PER-ITEM SLOT, not a global
-- colour id [ELF, catalogue at 0x10506BC], so the same five colours produce different masks
-- depending on how many slots the item has and which names they carry:
--
--     Black, Olive Drab, Coyote Brown, Khaki, Sage Green
--       on a 21-slot camo item  -> 0x15C000   (slots 14,15,16,18,20)
--       on a 10-slot solid item -> 0x000057   (slots  0, 1, 2, 4, 6)
--       on an 8-slot item       -> 0x00002F   (slots  0, 1, 2, 3, 5 -- it skips Green)
--
-- Reading any of these against a single global colour list would name the wrong colours.
--
-- The gloves (47, 49) get 0x000001: hands have exactly one colour slot carrying the null name, so
-- there is no colour choice to grant.
--
-- Id 22 is granted because "Lower Body -> None" is that id. The category has no None entry and no
-- second item, so the client force-equips 22 and draws one unlabelled row -- but its camouflage IS
-- selectable on its own screen, which is what the colours here are for.
--
-- The other None entries (28, 46, 68, 86, 102) are deliberately NOT granted. They are hardcoded
-- always-available at 0x92735C-0x927384, so a row for them would be a no-op in both directions.

CREATE TABLE public.starter_gear
(
    -- No FK to gear_item: its key is `ordinal`, and item_id is deliberately not unique there
    -- (0x86 appears twice, preserved because dropping it would change 0x4124's known-good length).
    item_id smallint NOT NULL PRIMARY KEY,
    colours bigint  NOT NULL,
    CONSTRAINT starter_gear_colours_range CHECK (colours BETWEEN 0 AND 4294967295)
);

COMMENT ON TABLE public.starter_gear IS
    'What a new character owns. Operator policy -- nothing in the client requires any particular '
    'set. Read by CharacterService.create; edit freely, no rebuild needed.';

INSERT INTO public.starter_gear (item_id, colours) VALUES
    ( 11,  1425408),
    ( 12,       87),
    ( 13,       87),
    ( 22,  1425408),
    ( 30,  1425408),
    ( 32,  1425408),
    ( 34,  1425408),
    ( 37,  1425408),
    ( 38,       87),
    ( 47,        1),
    ( 49,        1),
    ( 57,  1425408),
    ( 61,  1425408),
    ( 69,  1425408),
    ( 70,  1425408),
    ( 72,  1425408),
    ( 73,  1425408),
    ( 77,  1425408),
    ( 87,  1425408),
    ( 88,  1425408),
    ( 91,  1425408),
    ( 92,  1425408),
    ( 95,  1425408),
    (103,       33),
    (104,       87),
    (105,       47),
    (106,       17),
    (111,       47);

-- Every existing character is brought to the same set, so old and new characters match.
DELETE FROM public.chara_gear;
INSERT INTO public.chara_gear (chara_id, item_id, colours)
SELECT c.id, s.item_id, s.colours FROM public.chara c CROSS JOIN public.starter_gear s;
