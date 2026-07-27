-- One to four character slots.
--
-- Four is the retail maximum. The 0x3049 reply carries room for eight entries, so the packet does
-- not bound this and a larger value would be sent happily — the limit is the game's, not the
-- protocol's, which is exactly the kind of rule worth writing down as a constraint rather than
-- leaving to whoever next runs an UPDATE by hand.
alter table account add constraint account_slots_range check (slots between 1 and 4);
