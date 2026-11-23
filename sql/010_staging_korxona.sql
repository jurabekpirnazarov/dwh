-- staging.korxona: raw.korxona_reyestr ning tozalangan nusxasi, har OKPO bitta qator.
-- Qoidalar: bo'sh joylar olib tashlanadi, bo'sh satr -> NULL, soxta sanalar -> NULL,
-- yaroqsiz INN/e-mail -> NULL, OKPO bo'yicha takrorlardan eng oxirgi yangilangani qoladi.

CREATE TABLE IF NOT EXISTS staging.korxona (
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
    csdp            text,
    ktf             integer,
    ptp             integer,
    priz            text,
    status          integer,
    pot             text,
    ustav_fondi     numeric(19,4),
    ustav_fondi_d   numeric(19,4),
    reg_organ       text,
    reg_raqam       text,
    reg_sana        date,
    izv_organ       text,
    izv_raqam       text,
    izv_sana        date,
    bezd_organ      text,
    bezd_sana       date,
    lik_organ       text,
    lik_raqam       text,
    lik_sana        date,
    du_i            timestamp,
    du_r            timestamp,
    du_b            timestamp,
    du_l            timestamp,
    oksm_1 text, namu_1 text, uf_1 numeric(19,4), uf_1d numeric(19,4), dol_1 numeric(19,4),
    oksm_2 text, namu_2 text, uf_2 numeric(19,4), uf_2d numeric(19,4), dol_2 numeric(19,4),
    oksm_3 text, namu_3 text, uf_3 numeric(19,4), uf_3d numeric(19,4), dol_3 numeric(19,4),
    oksm_4 text, namu_4 text, uf_4 numeric(19,4), uf_4d numeric(19,4), dol_4 numeric(19,4),
    oksm_5 text, namu_5 text, uf_5 numeric(19,4), uf_5d numeric(19,4), dol_5 numeric(19,4),
    _loaded_at      timestamptz NOT NULL DEFAULT now()
);

TRUNCATE staging.korxona;

-- Matnni tozalash: ketma-ket bo'shliqlar bitta, chetlari kesiladi, bo'sh -> NULL
CREATE OR REPLACE FUNCTION pg_temp.t(v anyelement) RETURNS text
LANGUAGE sql IMMUTABLE AS
$$ SELECT NULLIF(btrim(regexp_replace(v::text, '\s+', ' ', 'g')), '') $$;

-- Sana: 1900-01-01 va 1970-01-01 "bo'sh" o'rnida ishlatilgan, kelajak sanalar ham yaroqsiz
CREATE OR REPLACE FUNCTION pg_temp.d(v timestamp) RETURNS timestamp
LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN v::date IN (DATE '1900-01-01', DATE '1970-01-01')
                 OR v > now() + interval '1 day' THEN NULL ELSE v END $$;

INSERT INTO staging.korxona
SELECT okpo, inn, nomi, qisqa_nomi, soato, viloyat_kodi, tuman_kodi, manzil, kocha, telefon, email,
       opf, opf_yangi, skfs, oked, okonh, soogu, sektor, iqtisodiy_faoliyat, xodimlar_soni,
       csdp, ktf, ptp, priz, status, pot, ustav_fondi, ustav_fondi_d,
       reg_organ, reg_raqam, reg_sana, izv_organ, izv_raqam, izv_sana,
       bezd_organ, bezd_sana, lik_organ, lik_raqam, lik_sana, du_i, du_r, du_b, du_l,
       oksm_1, namu_1, uf_1, uf_1d, dol_1, oksm_2, namu_2, uf_2, uf_2d, dol_2,
       oksm_3, namu_3, uf_3, uf_3d, dol_3, oksm_4, namu_4, uf_4, uf_4d, dol_4,
       oksm_5, namu_5, uf_5, uf_5d, dol_5
FROM (
    SELECT
        pg_temp.t(r.okpo)                                             AS okpo,
        CASE WHEN pg_temp.t(r.inn) ~ '^[0-9]{9}$' THEN pg_temp.t(r.inn) END AS inn,
        pg_temp.t(r.name)                                             AS nomi,
        pg_temp.t(r.name_s)                                           AS qisqa_nomi,
        pg_temp.t(r.soato)                                            AS soato,
        left(pg_temp.t(r.soato), 4)                                   AS viloyat_kodi,
        CASE WHEN length(pg_temp.t(r.soato)) >= 7 THEN left(pg_temp.t(r.soato), 7) END AS tuman_kodi,
        pg_temp.t(r.adres)                                            AS manzil,
        pg_temp.t(r.street)                                           AS kocha,
        pg_temp.t(r.phone)                                            AS telefon,
        CASE WHEN pg_temp.t(r.e_mail) ~* '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
             THEN lower(pg_temp.t(r.e_mail)) END                      AS email,
        pg_temp.t(r.opf)                                              AS opf,
        pg_temp.t(r.opf_n)                                            AS opf_yangi,
        pg_temp.t(r.skfs)                                             AS skfs,
        pg_temp.t(r.oked)                                             AS oked,
        pg_temp.t(r.okonh)                                            AS okonh,
        pg_temp.t(r.soogu)                                            AS soogu,
        pg_temp.t(r.sek)                                              AS sektor,
        pg_temp.t(r.iqtisodiy)                                        AS iqtisodiy_faoliyat,
        r.chisl::integer                                              AS xodimlar_soni,
        pg_temp.t(r.csdp)                                             AS csdp,
        r.ktf::integer                                                AS ktf,
        r.ptp::integer                                                AS ptp,
        pg_temp.t(r.priz)                                             AS priz,
        r.status::integer                                             AS status,
        pg_temp.t(r.pot)                                              AS pot,
        r.uf_sum::numeric(19,4)                                       AS ustav_fondi,
        r.uf_sumd::numeric(19,4)                                      AS ustav_fondi_d,
        pg_temp.t(r.reg_o)  AS reg_organ,  pg_temp.t(r.reg_nom) AS reg_raqam,
        pg_temp.d(r.reg_data::timestamp)::date                        AS reg_sana,
        pg_temp.t(r.izv_o)  AS izv_organ,  pg_temp.t(r.izv_nom) AS izv_raqam,
        pg_temp.d(r.izv_data::timestamp)::date                        AS izv_sana,
        pg_temp.t(r.bezd_o) AS bezd_organ,
        pg_temp.d(r.bezd_data::timestamp)::date                       AS bezd_sana,
        pg_temp.t(r.lik_o)  AS lik_organ,  pg_temp.t(r.lik_nom) AS lik_raqam,
        pg_temp.d(r.lik_data::timestamp)::date                        AS lik_sana,
        pg_temp.d(r.du_i::timestamp) AS du_i, pg_temp.d(r.du_r::timestamp) AS du_r,
        pg_temp.d(r.du_b::timestamp) AS du_b, pg_temp.d(r.du_l::timestamp) AS du_l,
        pg_temp.t(r.oksm_1) AS oksm_1, pg_temp.t(r.namu_1) AS namu_1,
        r.uf_1::numeric(19,4) AS uf_1, r.uf_1d::numeric(19,4) AS uf_1d, r.dol_1::numeric(19,4) AS dol_1,
        pg_temp.t(r.oksm_2) AS oksm_2, pg_temp.t(r.namu_2) AS namu_2,
        r.uf_2::numeric(19,4) AS uf_2, r.uf_2d::numeric(19,4) AS uf_2d, r.dol_2::numeric(19,4) AS dol_2,
        pg_temp.t(r.oksm_3) AS oksm_3, pg_temp.t(r.namu_3) AS namu_3,
        r.uf_3::numeric(19,4) AS uf_3, r.uf_3d::numeric(19,4) AS uf_3d, r.dol_3::numeric(19,4) AS dol_3,
        pg_temp.t(r.oksm_4) AS oksm_4, pg_temp.t(r.namu_4) AS namu_4,
        r.uf_4::numeric(19,4) AS uf_4, r.uf_4d::numeric(19,4) AS uf_4d, r.dol_4::numeric(19,4) AS dol_4,
        pg_temp.t(r.oksm_5) AS oksm_5, pg_temp.t(r.namu_5) AS namu_5,
        r.uf_5::numeric(19,4) AS uf_5, r.uf_5d::numeric(19,4) AS uf_5d, r.dol_5::numeric(19,4) AS dol_5,
        row_number() OVER (PARTITION BY pg_temp.t(r.okpo)
                           ORDER BY r.du_i DESC NULLS LAST, r.du_r DESC NULLS LAST) AS rn
    FROM raw.korxona_reyestr r
    WHERE pg_temp.t(r.okpo) IS NOT NULL
) x
WHERE rn = 1;

ANALYZE staging.korxona;
