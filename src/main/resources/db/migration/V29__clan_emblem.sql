-- The clan emblem: 768 opaque bytes the client uploads and downloads verbatim.
--
-- 0x4b50 carries {u8 mode, byte[768]} and is the upload (sender 0xD5804C, reached from the emblem
-- screen via task kind 25). On success the client also copies the same 768 bytes into its own
-- profile+6873 and sets the emblem flag at profile+6872 to the mode. 0x4b49 and 0x4b4b hand the
-- block back — the first into profile+6873 at login, the second as the display fetch.
--
-- Nothing in the client decodes the 768 bytes: both readers NUL-terminate at +768 into a 769-byte
-- buffer and never look inside. So the structure is unknown and the bytes are stored as-is; do not
-- guess a stride.
alter table clan add column emblem bytea;

-- The mode byte from 0x4b50, which becomes the client's emblem flag (profile+6872). 3 is "put on
-- display" and is the only value the client post-processes; 2 and 4 also occur and their meaning
-- is unknown. Null while the clan has no emblem, which is what keeps the flag != 3 and stops the
-- client fetching one that does not exist.
alter table clan add column emblem_mode smallint;
