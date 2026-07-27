-- Character names are unique regardless of case.
--
-- The unique index was case-sensitive, so "sean" was accepted while "Sean" existed. Two names that
-- differ only in case are indistinguishable on every screen that shows one, and the client already
-- has the error for this: -260, "Desired PC name is already in use. Unable to register PC."
--
-- Only active characters hold a name. A deleted character keeps its row but releases the name into
-- old_name, so the index has to ignore them or a deleted name could never be reused.
create unique index chara_name_lower_idx on chara (lower(name)) where active;
