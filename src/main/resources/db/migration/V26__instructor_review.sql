-- Every instructor review a student submits, whether or not they recognised the instructor.
--
-- 0x43c8 carries two answers: a star rating (always given) and the recognition decision (given
-- only when the client shows the "Save current instructor ... as the instructor for your personal
-- data?" prompt, n002a string 3099). Before this table the rating was only retained when the
-- relationship was written, so a review without recognition vanished. It is also the raw material
-- for the Instructor Score the ranking screens display (lobby strings 18258, 18630).
create table instructor_review (
	id                  bigint generated always as identity primary key,
	instructor_chara_id bigint not null references chara (id) on delete cascade,
	student_chara_id    bigint not null references chara (id) on delete cascade,
	rating              smallint not null,
	recognised          boolean not null,
	answer_byte         smallint not null,
	reviewed_at         timestamptz not null default current_timestamp
);

create index instructor_review_instructor_idx on instructor_review (instructor_chara_id, reviewed_at desc);

-- The raw second field of 0x43c8, kept per review because its encoding is not settled: 0x21 has
-- been seen when the recognition prompt never appeared and 0x01 when it appeared and was answered
-- yes. Storing it means the answer for "no" can be read off real data instead of re-tested.
comment on column instructor_review.answer_byte is '0x43c8 wire byte 0x04, verbatim';
