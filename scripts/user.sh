#!/bin/bash
# DWH foydalanuvchilari va ularning jadval darajasidagi huquqlarini boshqarish.
# Repo ildizidan ishga tushiring: ./scripts/user.sh <buyruq> ...
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat <<'EOF'
Foydalanish:
  ./scripts/user.sh add <user>                       yangi foydalanuvchi (parol bir marta ko'rsatiladi)
  ./scripts/user.sh passwd <user>                    parolni yangilash
  ./scripts/user.sh grant <user> <sxema.jadval>...   jadval(lar)ni o'qish huquqi
  ./scripts/user.sh grant-schema <user> <sxema>      butun sxemani o'qish (kelajakdagi jadvallar bilan)
  ./scripts/user.sh revoke <user> <sxema.jadval>...  jadval huquqini olib tashlash
  ./scripts/user.sh revoke-schema <user> <sxema>     sxema huquqini olib tashlash
  ./scripts/user.sh full <user>                      hamma sxemani o'qish + yozish (ombor egasi uchun)
  ./scripts/user.sh disable <user>                   kirishni o'chirish (huquqlar saqlanadi)
  ./scripts/user.sh enable <user>                    kirishni qayta yoqish
  ./scripts/user.sh list                             foydalanuvchilar va huquqlari
EOF
    exit 1
}

set -a; [ -f .env ] && . ./.env; set +a
ADMIN="${DWH_ADMIN_USER:-dwh_admin}"
DB="${DWH_DB:-dwh}"

sql() { docker compose exec -T db psql -v ON_ERROR_STOP=1 -q -U "$ADMIN" -d "$DB" "$@"; }

check_name() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || { echo "Noto'g'ri nom: '$1' (kichik lotin harf, raqam, _)"; exit 1; }
}
check_user() {
    check_name "$1"
    case "$1" in dwh_admin|dwh_loader|dwh_reader|postgres) echo "'$1' xizmat roli, o'zgartirib bo'lmaydi"; exit 1;; esac
}
split_table() {  # sxema.jadval -> S va T
    [[ "$1" == *.* ]] || { echo "Jadval 'sxema.jadval' ko'rinishida bo'lsin: $1"; exit 1; }
    S="${1%%.*}"; T="${1#*.}"; check_name "$S"; check_name "$T"
}
new_password() { openssl rand -hex 16; }
show_login() {
    echo "  foydalanuvchi: $1"
    echo "  parol:         $2"
    echo "  ulanish:       psql -h <server> -p ${DWH_PORT:-5440} -U $1 $DB"
}

cmd="${1:-}"; [ -n "$cmd" ] || usage; shift

case "$cmd" in
add)
    [ $# -eq 1 ] || usage; check_user "$1"; pw="$(new_password)"
    sql -v u="$1" -v pw="$pw" <<'SQL'
CREATE ROLE :"u" LOGIN PASSWORD :'pw';
SQL
    echo "Yaratildi (hozircha hech qaysi jadvalga huquqi yo'q):"; show_login "$1" "$pw"
    ;;
passwd)
    [ $# -eq 1 ] || usage; check_user "$1"; pw="$(new_password)"
    sql -v u="$1" -v pw="$pw" <<'SQL'
ALTER ROLE :"u" PASSWORD :'pw';
SQL
    echo "Parol yangilandi:"; show_login "$1" "$pw"
    ;;
grant|revoke)
    [ $# -ge 2 ] || usage; u="$1"; check_user "$u"; shift
    for ft in "$@"; do
        split_table "$ft"
        if [ "$cmd" = grant ]; then
            sql -v u="$u" -v s="$S" -v t="$T" <<'SQL'
GRANT USAGE ON SCHEMA :"s" TO :"u";
GRANT SELECT ON :"s".:"t" TO :"u";
SQL
            echo "OK  $u -> $ft (o'qish)"
        else
            sql -v u="$u" -v s="$S" -v t="$T" <<'SQL'
REVOKE ALL ON :"s".:"t" FROM :"u";
SQL
            echo "OK  $u -x $ft"
        fi
    done
    ;;
grant-schema)
    [ $# -eq 2 ] || usage; check_user "$1"; check_name "$2"
    sql -v u="$1" -v s="$2" <<'SQL'
GRANT USAGE ON SCHEMA :"s" TO :"u";
GRANT SELECT ON ALL TABLES IN SCHEMA :"s" TO :"u";
ALTER DEFAULT PRIVILEGES FOR ROLE dwh_loader IN SCHEMA :"s" GRANT SELECT ON TABLES TO :"u";
ALTER DEFAULT PRIVILEGES IN SCHEMA :"s" GRANT SELECT ON TABLES TO :"u";
SQL
    echo "OK  $1 -> $2.* (o'qish, yangi jadvallar ham)"
    ;;
revoke-schema)
    [ $# -eq 2 ] || usage; check_user "$1"; check_name "$2"
    sql -v u="$1" -v s="$2" <<'SQL'
ALTER DEFAULT PRIVILEGES FOR ROLE dwh_loader IN SCHEMA :"s" REVOKE SELECT ON TABLES FROM :"u";
ALTER DEFAULT PRIVILEGES IN SCHEMA :"s" REVOKE SELECT ON TABLES FROM :"u";
REVOKE ALL ON ALL TABLES IN SCHEMA :"s" FROM :"u";
REVOKE ALL ON SCHEMA :"s" FROM :"u";
SQL
    echo "OK  $1 -x $2.*"
    ;;
full)
    [ $# -eq 1 ] || usage; check_user "$1"
    sql -v u="$1" <<'SQL'
GRANT pg_read_all_data, dwh_loader TO :"u";
SQL
    echo "OK  $1: hamma sxemani o'qiydi, dwh_loader sifatida yozadi"
    ;;
disable|enable)
    [ $# -eq 1 ] || usage; check_user "$1"
    if [ "$cmd" = disable ]; then opt=NOLOGIN; else opt=LOGIN; fi
    sql -v u="$1" <<SQL
ALTER ROLE :"u" $opt;
SQL
    echo "OK  $1: $opt"
    ;;
list)
    sql <<'SQL'
\pset footer off
\echo '== Foydalanuvchilar =='
SELECT r.rolname AS foydalanuvchi,
       CASE WHEN r.rolcanlogin THEN 'ha' ELSE 'yo''q' END AS kirish,
       COALESCE((SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
                 FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
                 WHERE m.member = r.oid), '') AS rollar
FROM pg_roles r
WHERE r.rolname !~ '^pg_' AND NOT r.rolsuper
ORDER BY 1;
\echo '== Jadval huquqlari =='
SELECT grantee AS foydalanuvchi, table_schema || '.' || table_name AS jadval,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS huquq
FROM information_schema.role_table_grants
WHERE grantee !~ '^pg_' AND grantee NOT IN ('PUBLIC', 'dwh_loader')
  AND grantee <> grantor
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
GROUP BY 1, 2 ORDER BY 1, 2;
SQL
    ;;
*) usage ;;
esac
