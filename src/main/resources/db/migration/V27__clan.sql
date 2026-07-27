-- Clans.
--
-- The client keeps one clan record per character in its profile, and two commands fill it:
-- 0x4122 during the connect burst and 0x4b47 on demand. Both write clan id (profile+6816),
-- name (+6820, 16 bytes), membership state (+6837), a privilege mask (+6838) and an emblem
-- flag (+6872). This table is the server side of that record.
create table clan (
	id              bigint generated always as identity primary key,
	name            varchar(16) not null unique,
	description     varchar(128) not null default '',
	leader_chara_id bigint references chara (id) on delete set null,
	created_at      timestamptz not null default current_timestamp
);

-- One row per member. A character belongs to at most one clan, so chara_id is the key.
--
-- `state` is the client's own vocabulary, taken from the values it writes into profile+6837
-- itself: 0 affiliation pending (0xD58740), 1 member (0xD56B68), 2 leader (0xD56B84 and the
-- create path 0xD56E90), 99 not in a clan. 99 is never stored — it is the absence of a row.
-- Every reader in the client tests membership as `state - 1 <= 1`, i.e. 1 or 2.
create table clan_member (
	chara_id  bigint primary key references chara (id) on delete cascade,
	clan_id   bigint not null references clan (id) on delete cascade,
	state     smallint not null default 1,
	joined_at timestamptz not null default current_timestamp
);

create index clan_member_clan_idx on clan_member (clan_id);

comment on column clan_member.state is '0 pending, 1 member, 2 leader; 99 (no clan) is the absence of a row';
