#!/bin/bash
# MS SQL Server .bak faylini vaqtinchalik konteynerda tiklaydi va tahlil qiladi.
#   ./scripts/mssql_bak.sh inspect <fayl.bak>   tiklash + hisobot (data/<fayl>_hisobot.txt)
#   ./scripts/mssql_bak.sh sql "<so'rov>"       tiklangan bazada so'rov bajarish
#   ./scripts/mssql_bak.sh profile <sxema.jadval>      ustunlar profili (to'ldirilganlik, noyob qiymatlar)
#   ./scripts/mssql_bak.sh load <sxema.jadval> [raw.nom]   jadvalni DWH ga ko'chirish
#   ./scripts/mssql_bak.sh down                 vaqtinchalik konteynerni o'chirish
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
NAME=dwh-mssql-tmp
DBNAME=src
PWFILE=.mssql_tmp_pw
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

pw() { cat "$PWFILE"; }
# -C: sertifikatga ishonish, -b: xatoda to'xtash, -W: bo'shliqlarni qisqartirish
q() { docker exec -i "$NAME" "$SQLCMD" -S localhost -U sa -P "$(pw)" -C -b -W "$@"; }

cmd="${1:-}"
case "$cmd" in
inspect)
    bak="${2:?Fayl kerak: ./scripts/mssql_bak.sh inspect <fayl.bak>}"
    [ -f "$bak" ] || { echo "Fayl topilmadi: $bak"; exit 1; }
    bakfile="$(basename "$bak")"
    report="data/${bakfile%.*}_hisobot.txt"

    docker rm -f "$NAME" >/dev/null 2>&1 || true
    echo "A1$(openssl rand -hex 12)z" > "$PWFILE"; chmod 600 "$PWFILE"
    echo ">> SQL Server konteyneri ishga tushmoqda ..."
    docker run -d --name "$NAME" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$(pw)" \
        -e MSSQL_PID=Developer -p 127.0.0.1:14330:1433 "$IMAGE" >/dev/null
    for i in $(seq 1 60); do
        q -Q "SELECT 1" >/dev/null 2>&1 && break
        [ "$i" = 60 ] && { echo "SQL Server ishga tushmadi:"; docker logs --tail 20 "$NAME"; exit 1; }
        sleep 2
    done

    # Fayl egasi/huquqi qanday bo'lsa ham SQL Server o'qiy olishi uchun ichkariga ko'chiramiz
    echo ">> Fayl konteynerga ko'chirilmoqda ..."
    docker exec -u 0 "$NAME" mkdir -p /bak
    docker cp "$bak" "$NAME:/bak/$bakfile"
    docker exec -u 0 "$NAME" chmod 644 "/bak/$bakfile"

    echo ">> Zaxira nusxa sarlavhasi:"
    q -Q "RESTORE HEADERONLY FROM DISK='/bak/$bakfile'" -s '|' -h -1 \
        | awk -F'|' 'NR==1 {print "   baza: " $10 "  server: " $9 "  versiya: " $26 "." $27 "." $28 "  sana: " $18}'

    # Fayllar ro'yxatidan MOVE bandlarini yig'amiz (mantiqiy nom | ... | tur)
    moves="$(q -Q "RESTORE FILELISTONLY FROM DISK='/bak/$bakfile'" -s '|' -h -1 \
        | awk -F'|' 'NF>3 && ($3=="D" || $3=="L" || $3=="S") {
              n++; ext = ($3=="L") ? "ldf" : ($3=="S" ? "fs" : (n==1 ? "mdf" : "ndf"));
              gsub(/\047/, "\047\047", $1);
              printf ", MOVE N\047%s\047 TO N\047/var/opt/mssql/data/src_%d.%s\047", $1, n, ext }')"
    [ -n "$moves" ] || { echo "Fayllar ro'yxatini o'qib bo'lmadi"; exit 1; }

    echo ">> Tiklanmoqda (hajmga qarab bir necha daqiqa) ..."
    q -Q "RESTORE DATABASE [$DBNAME] FROM DISK='/bak/$bakfile' WITH REPLACE, STATS=20 $moves" \
        | grep -E "percent|successfully|pages" || true
    docker exec -u 0 "$NAME" rm -f "/bak/$bakfile"

    echo ">> Hisobot tuzilmoqda ..."
    {
        echo "=== $bakfile: umumiy ==="
        q -d "$DBNAME" -Q "SET NOCOUNT ON;
            SELECT CAST(SUM(size)*8/1024 AS int) AS hajm_mb,
                   (SELECT COUNT(*) FROM sys.tables) AS jadvallar,
                   (SELECT COUNT(*) FROM sys.views) AS viewlar,
                   (SELECT COUNT(*) FROM sys.procedures) AS protseduralar
            FROM sys.database_files WHERE type = 0"
        echo; echo "=== Jadvallar (hajm bo'yicha) ==="
        q -d "$DBNAME" -Q "SET NOCOUNT ON;
            SELECT s.name + '.' + t.name AS jadval,
                   (SELECT SUM(p2.rows) FROM sys.partitions p2
                    WHERE p2.object_id = t.object_id AND p2.index_id IN (0,1)) AS qatorlar,
                   (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ustunlar,
                   CAST(SUM(a.total_pages)*8/1024.0 AS decimal(12,1)) AS hajm_mb,
                   CONVERT(varchar(10), t.modify_date, 120) AS ozgargan
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.partitions p ON p.object_id = t.object_id
            JOIN sys.allocation_units a ON a.container_id = p.partition_id
            GROUP BY s.name, t.name, t.object_id, t.modify_date
            ORDER BY SUM(a.total_pages) DESC"
        echo; echo "=== Ustunlar ==="
        q -d "$DBNAME" -Q "SET NOCOUNT ON;
            SELECT s.name + '.' + t.name AS jadval, c.name AS ustun,
                   ty.name + CASE WHEN ty.name IN ('varchar','nvarchar','char','nchar','varbinary')
                        THEN '(' + CASE WHEN c.max_length = -1 THEN 'max'
                             ELSE CAST(CASE WHEN ty.name LIKE 'n%' THEN c.max_length/2 ELSE c.max_length END AS varchar) END + ')'
                        WHEN ty.name IN ('decimal','numeric')
                        THEN '(' + CAST(c.precision AS varchar) + ',' + CAST(c.scale AS varchar) + ')'
                        ELSE '' END AS tur,
                   CASE WHEN c.is_nullable = 1 THEN '' ELSE 'NOT NULL' END AS nn,
                   CASE WHEN EXISTS (SELECT 1 FROM sys.index_columns ic
                        JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                        WHERE i.is_primary_key = 1 AND ic.object_id = c.object_id
                          AND ic.column_id = c.column_id) THEN 'PK' ELSE '' END AS pk
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.columns c ON c.object_id = t.object_id
            JOIN sys.types ty ON ty.user_type_id = c.user_type_id
            ORDER BY s.name, t.name, c.column_id"
        echo; echo "=== Tashqi kalitlar (bog'lanishlar) ==="
        q -d "$DBNAME" -Q "SET NOCOUNT ON;
            SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id)
                       + '.' + pc.name AS dan,
                   OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id)
                       + '.' + rc.name AS ga
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
            JOIN sys.columns pc ON pc.object_id = k.parent_object_id AND pc.column_id = k.parent_column_id
            JOIN sys.columns rc ON rc.object_id = k.referenced_object_id AND rc.column_id = k.referenced_column_id
            ORDER BY 1"
    } > "$report"

    echo; sed -n '1,45p' "$report"
    echo; echo ">> To'liq hisobot: $report ($(wc -l < "$report") qator)"
    echo ">> Konteyner ishlab turibdi. So'rov: ./scripts/mssql_bak.sh sql \"SELECT TOP 5 * FROM dbo.jadval\""
    echo ">> Tugatgach: ./scripts/mssql_bak.sh down"
    ;;
sql)
    [ -s "$PWFILE" ] || { echo "Avval: ./scripts/mssql_bak.sh inspect <fayl.bak>"; exit 1; }
    q -d "$DBNAME" -Q "${2:?SQL matnini bering}"
    ;;
profile)
    [ -s "$PWFILE" ] || { echo "Avval: ./scripts/mssql_bak.sh inspect <fayl.bak>"; exit 1; }
    tbl="${2:?Jadval kerak: ./scripts/mssql_bak.sh profile dbo.jadval}"
    [[ "$tbl" =~ ^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$ ]] || { echo "Jadval nomi sxema.jadval bo'lsin: $tbl"; exit 1; }
    out="data/$(echo "$tbl" | tr '.' '_')_profil.txt"
    echo ">> Har bir ustun tekshirilmoqda (katta jadvalda bir necha daqiqa) ..."
    docker cp scripts/mssql_profile.sql "$NAME:/tmp/profile.sql"
    q -d "$DBNAME" -s "|" -v tbl="$tbl" -i /tmp/profile.sql > "$out" || { cat "$out"; exit 1; }
    cat "$out"
    echo; echo ">> Saqlandi: $out"
    ;;
load)
    [ -s "$PWFILE" ] || { echo "Avval: ./scripts/mssql_bak.sh inspect <fayl.bak>"; exit 1; }
    tbl="${2:?Jadval kerak: ./scripts/mssql_bak.sh load dbo.jadval [raw.nom]}"
    # SQL Server konteynerini DWH tarmog'iga ulaymiz, yuklagich uni nomi bilan topadi
    net="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
        "$(docker compose ps -q db)" | awk '{print $1}')"
    docker network connect "$net" "$NAME" 2>/dev/null || true
    echo ">> $tbl -> DWH ko'chirilmoqda ..."
    docker compose run --rm --build -e MSSQL_PASSWORD="$(pw)" -e MSSQL_HOST="$NAME" \
        -e MSSQL_DB="$DBNAME" --entrypoint python loader /app/mssql_to_pg.py "$tbl" ${3:+--target "$3"}
    ;;
down)
    docker rm -f -v "$NAME" >/dev/null 2>&1 || true
    [ -f "$PWFILE" ] && : > "$PWFILE"
    echo "Vaqtinchalik SQL Server o'chirildi"
    ;;
*)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1
    ;;
esac
