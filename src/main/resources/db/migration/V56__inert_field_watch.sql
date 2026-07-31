-- A tripwire for the fields we believe the client never reads.
--
-- Several bytes of the host-settings block are established as parsed-and-never-read: either no
-- reader exists in the binary at all, or the only consumer is an accessor nothing calls. We echo
-- them because that is the honest thing to do with a value we cannot explain. But "this build never
-- reads it" is a claim about ONE build, and the plan is to serve later versions behind toggles --
-- so the moment a patched client starts using one of these, we want to know, not to find out from a
-- bug report months later.
--
-- The design choice worth stating: this records EVERY DISTINCT VALUE seen per field rather than
-- checking against a hardcoded baseline. A field that is genuinely fixed accumulates exactly one
-- row; a second row IS the alert. Nothing has to be kept up to date, and a baseline that drifts
-- silently -- which is what a hardcoded expectation becomes -- cannot happen.
--
-- It also already earned itself before being built. Live data shows unread_824 and unread_931
-- CO-VARYING: six stored rows carry the pair (0x02000000, 0x20) and five carry (0, 0). Two fields
-- with no reader moving in lockstep is not noise, and it was invisible while these bytes sat inside
-- a blob.

CREATE TABLE IF NOT EXISTS public.inert_field_watch (
	field text NOT NULL,
	value_hex text NOT NULL,
	first_seen timestamptz NOT NULL DEFAULT now(),
	last_seen timestamptz NOT NULL DEFAULT now(),
	observations bigint NOT NULL DEFAULT 1,
	PRIMARY KEY (field, value_hex)
);

COMMENT ON TABLE public.inert_field_watch IS
	'Distinct values observed for fields believed unread by the client. One row per field means the '
	'belief holds; a second row means a client sent something new and the field is doing something. '
	'Query: select field, count(*) from inert_field_watch group by 1 having count(*) > 1;';
COMMENT ON COLUMN public.inert_field_watch.value_hex IS
	'The raw bytes, big-endian hex, so a multi-byte field is comparable as one value.';
COMMENT ON COLUMN public.inert_field_watch.observations IS
	'How many times this exact value arrived. A rare second value is more interesting than a common '
	'one, so the count is what separates a real change from a one-off.';
