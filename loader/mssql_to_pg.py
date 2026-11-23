"""MS SQL Server jadvalini DWH (PostgreSQL) ga ko'chiradi, turlarini saqlagan holda.

    python mssql_to_pg.py dbo.baza --target raw.baza

Ulanish: MSSQL_HOST, MSSQL_PORT, MSSQL_USER, MSSQL_PASSWORD, MSSQL_DB va DWH_DSN.
Ustun nomlari kichik harfga o'tadi, _source va _loaded_at qo'shiladi,
natija meta.load_log ga yoziladi.
"""
import argparse
import csv
import io
import os
import re
import sys
import time

import psycopg2
import pymssql

CHUNK = 50_000

TYPE_MAP = {
    "int": "integer", "bigint": "bigint", "smallint": "smallint", "tinyint": "smallint",
    "bit": "boolean", "float": "double precision", "real": "real",
    "money": "numeric(19,4)", "smallmoney": "numeric(10,4)",
    "date": "date", "time": "time", "datetime": "timestamp", "datetime2": "timestamp",
    "smalldatetime": "timestamp", "datetimeoffset": "timestamptz",
    "uniqueidentifier": "uuid",
    "binary": "bytea", "varbinary": "bytea", "image": "bytea", "timestamp": "bytea",
}


def clean_name(name) -> str:
    s = re.sub(r"[^0-9a-zA-Z_]+", "_", str(name).strip().lower()).strip("_") or "col"
    if s[0].isdigit():
        s = "_" + s
    return s[:63]


def pg_type(t, precision, scale):
    if t in ("decimal", "numeric"):
        return f"numeric({precision},{scale})"
    return TYPE_MAP.get(t, "text")


def cell(v):
    """Qiymatni COPY CSV uchun matnga aylantiradi (None -> bo'sh, ya'ni NULL)."""
    if v is None:
        return None
    if isinstance(v, bool):
        return "t" if v else "f"
    if isinstance(v, (bytes, bytearray)):
        return "\\x" + bytes(v).hex()
    if isinstance(v, str):
        return v.replace("\x00", "")
    return str(v)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("source", help="manba jadval: sxema.jadval (masalan dbo.baza)")
    p.add_argument("--target", help="maqsad: sxema.jadval (standart: raw.<jadval>)")
    a = p.parse_args()

    if "." not in a.source:
        sys.exit("Manba 'sxema.jadval' ko'rinishida bo'lsin")
    s_schema, s_table = a.source.split(".", 1)
    t_schema, t_table = (a.target or f"raw.{clean_name(s_table)}").split(".", 1)
    t_schema, t_table = clean_name(t_schema), clean_name(t_table)
    target = f'"{t_schema}"."{t_table}"'
    src_label = f"mssql:{os.environ.get('MSSQL_DB', 'src')}.{a.source}"

    ms = pymssql.connect(
        server=os.environ.get("MSSQL_HOST", "dwh-mssql-tmp"),
        port=int(os.environ.get("MSSQL_PORT", "1433")),
        user=os.environ.get("MSSQL_USER", "sa"),
        password=os.environ["MSSQL_PASSWORD"],
        database=os.environ.get("MSSQL_DB", "src"), charset="UTF-8")
    pg = psycopg2.connect(os.environ["DWH_DSN"].replace("+psycopg2", ""))
    pg.autocommit = True

    mc = ms.cursor()
    mc.execute(
        "SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE "
        "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s "
        "ORDER BY ORDINAL_POSITION", (s_schema, s_table))
    cols = mc.fetchall()
    if not cols:
        sys.exit(f"Manba jadval topilmadi: {a.source}")

    names, seen = [], {}
    for c in cols:
        n = clean_name(c[0])
        seen[n] = seen.get(n, 0) + 1
        names.append(n if seen[n] == 1 else f"{n}_{seen[n]}")
    ddl_cols = [f'"{n}" {pg_type(c[1], c[2], c[3])}' for n, c in zip(names, cols)]
    ddl_cols += ['"_source" text', '"_loaded_at" timestamptz DEFAULT now()']

    with pg.cursor() as c:
        c.execute("INSERT INTO meta.load_log (source, target_table) VALUES (%s, %s) RETURNING id",
                  (src_label, f"{t_schema}.{t_table}"))
        log_id = c.fetchone()[0]

    total, t0 = 0, time.time()
    try:
        pg.autocommit = False  # bitta tranzaksiya: xato bo'lsa eski jadval qoladi
        with pg.cursor() as c:
            # Qayta yaratilganda berilgan huquqlar yo'qolmasin
            c.execute(
                "SELECT g.rolname, a.privilege_type "
                "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, "
                "     aclexplode(c.relacl) a JOIN pg_roles g ON g.oid = a.grantee "
                "WHERE n.nspname = %s AND c.relname = %s AND a.grantee <> c.relowner",
                (t_schema, t_table))
            grants = c.fetchall()
            c.execute(f"DROP TABLE IF EXISTS {target}")
            c.execute(f"CREATE TABLE {target} ({', '.join(ddl_cols)})")

            src_cols = ", ".join("[" + col[0].replace("]", "]]") + "]" for col in cols)
            mc.execute(f"SELECT {src_cols} FROM [{s_schema}].[{s_table}]")
            copy_sql = (f"COPY {target} ({', '.join(chr(34) + n + chr(34) for n in names)}, "
                        f"\"_source\") FROM STDIN WITH (FORMAT csv)")
            while True:
                rows = mc.fetchmany(CHUNK)
                if not rows:
                    break
                buf = io.StringIO()
                w = csv.writer(buf, quoting=csv.QUOTE_NOTNULL)
                for r in rows:
                    # QUOTE_NOTNULL: None -> NULL, bo'sh satr bo'sh satr bo'lib qoladi
                    w.writerow([cell(v) for v in r] + [src_label])
                buf.seek(0)
                c.copy_expert(copy_sql, buf)
                total += len(rows)
                print(f"  {total:>12,} qator  ({time.time() - t0:.0f}s)", flush=True)
            for role, priv in grants:
                c.execute(f'GRANT {priv} ON {target} TO "{role}"')
        pg.commit()
        pg.autocommit = True
        with pg.cursor() as c:
            c.execute(f"ANALYZE {target}")
            c.execute("UPDATE meta.load_log SET status='ok', rows_loaded=%s, finished_at=now() "
                      "WHERE id=%s", (total, log_id))
        print(f"OK  {t_schema}.{t_table}: {total:,} qator, {time.time() - t0:.0f}s")
    except Exception as e:
        pg.rollback()
        pg.autocommit = True
        with pg.cursor() as c:
            c.execute("UPDATE meta.load_log SET status='error', error=%s, finished_at=now() "
                      "WHERE id=%s", (str(e)[:2000], log_id))
        sys.exit(f"XATO {t_schema}.{t_table}: {e}")


if __name__ == "__main__":
    main()
