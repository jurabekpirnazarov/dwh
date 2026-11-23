-- features.korxona__asosiy: korxona bo'yicha asosiy belgilar (bitta kesim sanasiga).
-- Kesim sanasi (as_of_date) = manbadagi eng oxirgi yangilanish sanasi.

CREATE TABLE IF NOT EXISTS features.korxona__asosiy (
    okpo                 text    NOT NULL,
    as_of_date           date    NOT NULL,
    yoshi_yil            numeric(6,1),     -- ro'yxatdan o'tganidan beri
    xodimlar_soni        integer,
    xodimlar_toifasi     text,             -- 1 | 2-5 | 6-25 | 26-100 | 100+
    ustav_fondi          numeric(19,4),
    tasischilar_soni     smallint NOT NULL,
    xorijiy_tasischi_bor boolean  NOT NULL,
    xorijiy_ulush        numeric(19,4),    -- xorijiy ta'sischilar ulushi yig'indisi
    faol                 boolean  NOT NULL,
    tugatilgan           boolean  NOT NULL,
    faoliyatsiz          boolean  NOT NULL,
    inn_bor              boolean  NOT NULL,
    email_bor            boolean  NOT NULL,
    sektor               text,
    viloyat_kodi         text,
    opf                  text,
    PRIMARY KEY (okpo, as_of_date)
);
COMMENT ON TABLE features.korxona__asosiy IS 'Korxona asosiy belgilari; kalit: okpo + as_of_date';

-- Shu kesim qayta hisoblansa, eskisi almashtiriladi; boshqa kesimlar (tarix) saqlanadi
DELETE FROM features.korxona__asosiy
WHERE as_of_date = (SELECT max(yangilangan)::date FROM core.korxona);

INSERT INTO features.korxona__asosiy
SELECT k.okpo,
       a.as_of,
       round(((a.as_of - k.reg_sana) / 365.25)::numeric, 1),
       k.xodimlar_soni,
       CASE WHEN k.xodimlar_soni IS NULL THEN NULL
            WHEN k.xodimlar_soni <= 1   THEN '1'
            WHEN k.xodimlar_soni <= 5   THEN '2-5'
            WHEN k.xodimlar_soni <= 25  THEN '6-25'
            WHEN k.xodimlar_soni <= 100 THEN '26-100'
            ELSE '100+' END,
       k.ustav_fondi,
       COALESCE(t.soni, 0),
       COALESCE(t.xorijiy_bor, false),
       t.xorijiy_ulush,
       k.holat = 'faol', k.holat = 'tugatilgan', k.holat = 'faoliyatsiz',
       k.inn IS NOT NULL, k.email IS NOT NULL,
       k.sektor, k.viloyat_kodi, k.opf
FROM core.korxona k
CROSS JOIN (SELECT max(yangilangan)::date AS as_of FROM core.korxona) a
LEFT JOIN (
    SELECT okpo,
           count(*)::smallint                     AS soni,
           COALESCE(bool_or(xorijiy), false)      AS xorijiy_bor,
           sum(ulush) FILTER (WHERE xorijiy)      AS xorijiy_ulush
    FROM core.korxona_tasischi GROUP BY okpo
) t USING (okpo)
WHERE a.as_of IS NOT NULL;

ANALYZE features.korxona__asosiy;

INSERT INTO meta.feature_catalog (feature_table, entity, entity_key, description, source, owner, refresh)
VALUES ('features.korxona__asosiy', 'korxona', 'okpo',
        'Korxona asosiy belgilari: yoshi, xodimlar, ustav fondi, ta''sischilar, holat',
        'core.korxona, core.korxona_tasischi', 'dwh', 'manba yangilanganda')
ON CONFLICT (feature_table) DO UPDATE
SET description = EXCLUDED.description, source = EXCLUDED.source, updated_at = now();
