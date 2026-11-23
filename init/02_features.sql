-- Feature store qatlami. Idempotent: yangi o'rnatishda avtomatik bajariladi,
-- ishlab turgan bazaga esa qo'lda qo'llanadi:
--   docker compose exec -T db psql -U dwh_admin -d dwh < init/02_features.sql

CREATE SCHEMA IF NOT EXISTS features;
COMMENT ON SCHEMA features IS 'Feature store: ML va skoring uchun tayyor belgilar';

GRANT USAGE, CREATE ON SCHEMA features TO dwh_loader;
GRANT USAGE ON SCHEMA features TO dwh_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA features TO dwh_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE dwh_loader IN SCHEMA features
    GRANT SELECT ON TABLES TO dwh_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA features
    GRANT SELECT ON TABLES TO dwh_reader;

-- Katalog: har bir feature jadvali nima, kimniki, qayerdan hisoblanadi.
-- Jadval nomlash: features.<obyekt>__<guruh>, masalan features.korxona__moliya.
-- Har jadvalda obyekt kaliti (entity_key) va as_of_date (qaysi sanaga) ustuni bo'ladi.
CREATE TABLE IF NOT EXISTS meta.feature_catalog (
    feature_table text PRIMARY KEY,              -- features.korxona__moliya
    entity        text        NOT NULL,          -- korxona, hudud, shaxs ...
    entity_key    text        NOT NULL,          -- kalit ustun(lar): inn
    description   text        NOT NULL,
    source        text,                          -- qaysi core/mart jadvallaridan
    owner         text,                          -- mas'ul
    refresh       text,                          -- kunlik, oylik ...
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON meta.feature_catalog TO dwh_loader;
GRANT USAGE ON SCHEMA meta TO dwh_reader;
GRANT SELECT ON meta.feature_catalog TO dwh_reader;
