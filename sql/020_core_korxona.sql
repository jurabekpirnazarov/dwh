-- core.korxona: har subyekt bitta qator (ta'sischilar alohida jadvalda).
-- core.korxona_tasischi: har ta'sischi bitta qator.

CREATE TABLE IF NOT EXISTS core.korxona (
    okpo            text PRIMARY KEY,
    inn             text,
    nomi            text,
    qisqa_nomi      text,
    soato           text,
    viloyat_kodi    text,
    tuman_kodi      text,
    manzil          text,
    kocha           text,
    telefon         text,
    email           text,
    opf             text,
    opf_yangi       text,
    skfs            text,
    oked            text,
    okonh           text,
    soogu           text,
    sektor          text,
    iqtisodiy_faoliyat text,
    xodimlar_soni   integer,
    ustav_fondi     numeric(19,4),
    ustav_fondi_d   numeric(19,4),
    holat           text NOT NULL,
    reg_organ       text,
    reg_raqam       text,
    reg_sana        date,
    bezd_sana       date,
    lik_sana        date,
    csdp            text,
    ktf             integer,
    ptp             integer,
    priz            text,
    status          integer,
    pot             text,
    yangilangan     timestamp,
    _loaded_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE core.korxona IS 'Korxona va tashkilotlar reyestri: har OKPO bitta qator';
COMMENT ON COLUMN core.korxona.holat IS
    'TAXMINIY: lik_sana bor -> tugatilgan; bezd_sana bor -> faoliyatsiz; aks holda faol. Ma''lumot egasi bilan tasdiqlash kerak';
COMMENT ON COLUMN core.korxona.viloyat_kodi IS 'SOATO ning birinchi 4 xonasi';
COMMENT ON COLUMN core.korxona.tuman_kodi IS 'SOATO ning birinchi 7 xonasi';
COMMENT ON COLUMN core.korxona.sektor IS 'OKED bo''limi (A-U), manbadagi sek ustuni';

TRUNCATE core.korxona CASCADE;
INSERT INTO core.korxona
SELECT okpo, inn, nomi, qisqa_nomi, soato, viloyat_kodi, tuman_kodi, manzil, kocha, telefon, email,
       opf, opf_yangi, skfs, oked, okonh, soogu, sektor, iqtisodiy_faoliyat, xodimlar_soni,
       ustav_fondi, ustav_fondi_d,
       CASE WHEN lik_sana  IS NOT NULL THEN 'tugatilgan'
            WHEN bezd_sana IS NOT NULL THEN 'faoliyatsiz'
            ELSE 'faol' END,
       reg_organ, reg_raqam, reg_sana, bezd_sana, lik_sana,
       csdp, ktf, ptp, priz, status, pot,
       GREATEST(du_i, du_r, du_b, du_l)
FROM staging.korxona;

CREATE INDEX IF NOT EXISTS korxona_inn_idx     ON core.korxona (inn);
CREATE INDEX IF NOT EXISTS korxona_viloyat_idx ON core.korxona (viloyat_kodi);
CREATE INDEX IF NOT EXISTS korxona_oked_idx    ON core.korxona (oked);
ANALYZE core.korxona;


CREATE TABLE IF NOT EXISTS core.korxona_tasischi (
    okpo          text     NOT NULL REFERENCES core.korxona (okpo) ON DELETE CASCADE,
    tartib        smallint NOT NULL,          -- manbadagi o'rni: 1..5
    davlat_kodi   text,                       -- OKSM (860 = O'zbekiston)
    nomi          text,
    ustav_fondi   numeric(19,4),
    ustav_fondi_d numeric(19,4),
    ulush         numeric(19,4),
    xorijiy       boolean,                    -- davlat kodi 860 emas
    PRIMARY KEY (okpo, tartib)
);
COMMENT ON TABLE core.korxona_tasischi IS 'Korxona ta''sischilari (manbada 5 tagacha)';

TRUNCATE core.korxona_tasischi;
INSERT INTO core.korxona_tasischi
SELECT s.okpo, v.tartib, v.oksm, v.namu, v.uf, v.ufd, v.dol,
       CASE WHEN v.oksm IS NOT NULL THEN v.oksm <> '860' END
FROM staging.korxona s
CROSS JOIN LATERAL (VALUES
    (1::smallint, s.oksm_1, s.namu_1, s.uf_1, s.uf_1d, s.dol_1),
    (2::smallint, s.oksm_2, s.namu_2, s.uf_2, s.uf_2d, s.dol_2),
    (3::smallint, s.oksm_3, s.namu_3, s.uf_3, s.uf_3d, s.dol_3),
    (4::smallint, s.oksm_4, s.namu_4, s.uf_4, s.uf_4d, s.dol_4),
    (5::smallint, s.oksm_5, s.namu_5, s.uf_5, s.uf_5d, s.dol_5)
) AS v (tartib, oksm, namu, uf, ufd, dol)
-- Bo'sh o'rinlar tashlanadi (manbada ko'pincha faqat 0 turadi)
WHERE v.namu IS NOT NULL OR v.oksm IS NOT NULL
   OR COALESCE(v.uf, 0) > 0 OR COALESCE(v.dol, 0) > 0;

CREATE INDEX IF NOT EXISTS korxona_tasischi_nomi_idx ON core.korxona_tasischi (nomi);
ANALYZE core.korxona_tasischi;
