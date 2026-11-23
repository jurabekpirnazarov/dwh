#!/bin/bash
# sql/ papkasidagi modellarni tartib bilan bajaradi: raw -> staging -> core -> features.
#   ./scripts/build.sh            hammasi
#   ./scripts/build.sh 020        nomi shu bilan boshlanadigan fayl(lar)
# Har fayl bitta tranzaksiyada: xato bo'lsa o'sha jadval eski holicha qoladi.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; [ -f .env ] && . ./.env; set +a
ADMIN="${DWH_ADMIN_USER:-dwh_admin}"
DB="${DWH_DB:-dwh}"

shopt -s nullglob
files=(sql/${1:-}*.sql)
[ ${#files[@]} -gt 0 ] || { echo "Mos SQL fayl topilmadi: sql/${1:-}*.sql"; exit 1; }

for f in "${files[@]}"; do
    printf '>> %-45s' "$f"
    t0=$SECONDS
    # dwh_loader nomidan: jadvallar egasi loader bo'ladi, reader huquqlari avtomatik beriladi
    docker compose exec -T db psql -q -v ON_ERROR_STOP=1 -1 -U "$ADMIN" -d "$DB" \
        -c "SET ROLE dwh_loader" -c "SET client_min_messages = warning" -f - < "$f"
    echo "OK ($((SECONDS - t0))s)"
done

echo
docker compose exec -T db psql -q -U "$ADMIN" -d "$DB" -c "
SELECT n.nspname || '.' || c.relname AS jadval,
       to_char((xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM %I.%I',
               n.nspname, c.relname), false, true, '')))[1]::text::bigint, 'FM999G999G999G990') AS qatorlar,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS hajm
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname IN ('raw', 'staging', 'core', 'mart', 'features')
ORDER BY array_position(ARRAY['raw','staging','core','mart','features'], n.nspname::text), c.relname"
