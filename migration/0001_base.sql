CREATE TABLE IF NOT EXISTS public.news
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    "time" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    important boolean NOT NULL DEFAULT false,
    title character varying(128) COLLATE pg_catalog."default" NOT NULL,
    body character varying(886) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT news_pkey PRIMARY KEY (id)
);
