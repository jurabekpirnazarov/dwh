# DWH — ma'lumotlar ombori

PostgreSQL 16 asosidagi ma'lumotlar ombori. Server: `172.30.30.30` (`qamal`).

## Qatlamlar

| Sxema     | Vazifasi                                              |
|-----------|-------------------------------------------------------|
| `raw`     | Manbadan qanday kelgan bo'lsa shunday (hamma ustun matn) |
| `staging` | Tozalangan, turlari to'g'rilangan                     |
| `core`    | Birlashtirilgan model: fakt va o'lchov jadvallari     |
| `mart`    | Hisobot va dashboardlar uchun tayyor vitrinalar       |
| `meta`    | Yuklash jurnali (`meta.load_log`)                     |

## Foydalanuvchilar

| Rol          | Huquq                                         | Kim ishlatadi            |
|--------------|-----------------------------------------------|--------------------------|
| `dwh_admin`  | To'liq (superuser)                            | Faqat ma'mur             |
| `dwh_loader` | `raw`/`staging`/`core`/`mart` ga yozadi       | Yuklagich, ETL           |
| `dwh_reader` | Faqat `core`, `mart`, `features` ni o'qiydi   | BI, tahlilchilar         |
| shaxsiy      | Faqat ruxsat berilgan jadval/sxemalar         | Har bir odam o'z logini bilan |

## Serverda ishga tushirish

```bash
git clone https://github.com/jurabekpirnazarov/dwh.git
cd dwh
cp .env.example .env
# .env ichida uchta parolni to'ldiring: openssl rand -hex 24
docker compose up -d
docker compose ps
```

Sxemalar va rollar faqat birinchi ishga tushishda (bo'sh volume) yaratiladi.
Xotira sozlamalarini (`DWH_SHARED_BUFFERS` va b.) serverning RAM hajmiga qarab `.env` da o'zgartiring.

Ulanish: `psql -h 172.30.30.30 -p 5440 -U dwh_reader dwh`

## Foydalanuvchilar va jadval bo'yicha ruxsat

Har bir odamga alohida login ochiladi; yangi login hech narsani ko'rmaydi, ruxsat jadval yoki sxema bo'yicha beriladi.

```bash
./scripts/user.sh add ali                         # login + parol (bir marta ko'rsatiladi)
./scripts/user.sh grant ali mart.savdo core.hudud # faqat shu jadvallarni o'qiydi
./scripts/user.sh grant-schema ali features       # butun sxema, yangi jadvallar ham
./scripts/user.sh revoke ali mart.savdo
./scripts/user.sh full jurabek                    # ombor egasi: hammasini o'qiydi va yozadi
./scripts/user.sh disable ali                     # kirishni o'chirish
./scripts/user.sh list                            # kimda qanday huquq bor
```

Jadval `replace` rejimida qayta yuklanganda berilgan huquqlar saqlanib qoladi.

## Feature store

`features` sxemasi. Nomlash: `features.<obyekt>__<guruh>` (masalan `features.korxona__moliya`),
har jadvalda obyekt kaliti va `as_of_date` (belgi qaysi sanaga hisoblangan) ustuni bo'ladi.
Har jadval `meta.feature_catalog` ga yoziladi: obyekt, kalit, tavsif, manba, mas'ul, yangilanish davri.

Ishlab turgan bazaga qo'shish (yangi o'rnatishda avtomatik):

```bash
docker compose exec -T db psql -U dwh_admin -d dwh < init/02_features.sql
```

## Fayl yuklash

Faylni `data/` ga qo'ying (CSV, TSV, Excel, Parquet, JSON), so'ng:

```bash
docker compose run --rm loader aholi_2025.xlsx
docker compose run --rm loader savdo.csv --table savdo --mode append
```

- Jadval `raw.<fayl_nomi>` bo'lib yaratiladi; ko'p varaqli Excel'da har varaq alohida: `raw.<fayl>__<varaq>`.
- Ustun nomlari snake_case ga keltiriladi, `_source_file` va `_loaded_at` qo'shiladi.
- Standart rejim `replace` (jadval qayta yaratiladi), `--mode append` ustiga qo'shadi.
- Har yuklash `meta.load_log` ga yoziladi. Xato bo'lsa, eski jadval o'zgarmaydi.

## MS SQL Server `.bak` faylini tahlil qilish

Faylni vaqtinchalik SQL Server konteynerida tiklaydi va jadvallar, ustunlar, bog'lanishlar bo'yicha hisobot beradi
(kamida 2 GB bo'sh RAM va fayl hajmidan bir necha barobar bo'sh disk kerak):

```bash
./scripts/mssql_bak.sh inspect data/baza.bak        # hisobot: data/baza_hisobot.txt
./scripts/mssql_bak.sh sql "SELECT TOP 5 * FROM dbo.jadval"
./scripts/mssql_bak.sh profile dbo.jadval            # har ustun: to'ldirilganlik %, noyob qiymatlar, taqsimot
./scripts/mssql_bak.sh load dbo.jadval raw.nom      # jadvalni DWH ga ko'chirish (turlari saqlanadi)
./scripts/mssql_bak.sh down                         # tugatgach konteynerni o'chirish
```

## Ma'lumotlarni boshqa diskka ko'chirish

Standart holatda ma'lumotlar Docker volume'da (`/var/lib/docker`) turadi. Boshqa joyga ko'chirish:

```bash
./scripts/move_data.sh /mnt/disk2/dwh_pgdata
```

Baza qisqa vaqtga to'xtaydi, ma'lumotlar nusxalanadi, `.env` ga `DWH_DATA_DIR` yoziladi va baza yangi joydan ishga tushadi.
Eski nusxa o'chirilmaydi, tekshirgach o'zingiz o'chirasiz.

## Zaxira nusxa

```bash
docker compose exec -T db pg_dump -U dwh_admin -Fc dwh > dwh_$(date +%F).dump
```
