#!/bin/bash
# DWH ma'lumotlarini (PostgreSQL data papkasi) boshqa joyga/diskka ko'chiradi.
#   ./scripts/move_data.sh /mnt/disk2/dwh_pgdata
# Baza qisqa vaqtga to'xtaydi. Eski nusxa o'chirilmaydi: tekshirgach o'zingiz o'chirasiz.
set -euo pipefail
cd "$(dirname "$0")/.."

new="${1:?Yangi papka kerak: ./scripts/move_data.sh /yangi/yol}"
[[ "$new" == /* ]] || { echo "To'liq yo'l bering (/ bilan boshlansin): $new"; exit 1; }
[ -f .env ] || { echo ".env topilmadi"; exit 1; }

cid="$(docker compose ps -aq db)"
[ -n "$cid" ] || { echo "db konteyneri topilmadi, avval: docker compose up -d"; exit 1; }
# Hozirgi manba: nomli volume yoki papka
src="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}{{end}}' "$cid")"
[ -n "$src" ] || { echo "Hozirgi data joyini aniqlab bo'lmadi"; exit 1; }
[ "$src" != "$new" ] || { echo "Ma'lumotlar allaqachon shu yerda: $new"; exit 0; }

mkdir -p "$new" 2>/dev/null || { echo "Papka yaratib bo'lmadi: $new  (sudo mkdir -p $new && sudo chown \$USER $new)"; exit 1; }
[ -z "$(ls -A "$new")" ] || { echo "Papka bo'sh emas: $new"; exit 1; }

echo ">> Hozirgi joy: $src"
echo ">> Yangi joy:   $new  (bo'sh joy: $(df -h --output=avail "$new" | tail -1 | tr -d ' '))"
echo ">> Baza to'xtatilmoqda ..."
docker compose stop db >/dev/null

echo ">> Ko'chirilmoqda ..."
if ! docker run --rm -v "$src:/from:ro" -v "$new:/to" postgres:16 bash -c 'cp -a /from/. /to/'; then
    echo "Ko'chirish xato berdi, baza eski joyida qayta ishga tushirilmoqda"
    docker compose start db >/dev/null
    exit 1
fi

if grep -q '^DWH_DATA_DIR=' .env; then
    sed -i "s|^DWH_DATA_DIR=.*|DWH_DATA_DIR=$new|" .env
else
    printf '\nDWH_DATA_DIR=%s\n' "$new" >> .env
fi

echo ">> Baza yangi joydan ishga tushirilmoqda ..."
docker compose up -d --wait db >/dev/null
docker compose exec -T db psql -U "$(grep -E '^DWH_ADMIN_USER=' .env | cut -d= -f2 | grep . || echo dwh_admin)" \
    -d "$(grep -E '^DWH_DB=' .env | cut -d= -f2 | grep . || echo dwh)" -Atc \
    "SELECT 'OK  data: ' || current_setting('data_directory') || ', baza hajmi: ' || pg_size_pretty(pg_database_size(current_database()))"
echo ">> Ko'chirildi: $new"
echo ">> Eski nusxa joyida qoldi ($src). Hammasi joyida ekaniga ishonch hosil qilgach o'chiring:"
if [[ "$src" == /* ]]; then echo "     sudo rm -rf $src"; else echo "     docker volume rm $src"; fi
