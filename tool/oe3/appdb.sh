#!/usr/bin/env bash
# OE3: consulta de sólo lectura sobre una COPIA temporal de la base de la app aislada
# .oe3 (run-as; la APK profile es depurable). La copia se borra al terminar.
#   appdb.sh "<consulta SQL>"     imprime filas separadas por « | »
#   appdb.sh --dump               SHA-256 del volcado ordenado de todas las tablas
set -euo pipefail
PKG=com.comunidad.agro.agroquimicos.oe3; DB=agroquimicos_v2.db
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in $(MSYS_NO_PATHCONV=1 adb exec-out run-as "$PKG" ls -1 databases | tr -d '\r' | grep -E "^${DB}(-wal|-shm|-journal)?$"); do
  MSYS_NO_PATHCONV=1 adb exec-out run-as "$PKG" cat "databases/$f" > "$tmp/$f"
done
[ -s "$tmp/$DB" ] || { echo "base ausente"; exit 1; }
python -I -X utf8 - "$tmp/$DB" "${1:?consulta}" <<'PY'
import sys, sqlite3, hashlib
db = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
if sys.argv[2] == '--dump':
    h = hashlib.sha256(); total = 0
    for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
        rows = sorted(repr(r) for r in db.execute(f'SELECT * FROM "{t}"'))
        total += len(rows); h.update(t.encode()); [h.update(r.encode()) for r in rows]
    print(f'tablas+filas SHA-256 {h.hexdigest()} filas={total}')
else:
    for row in db.execute(sys.argv[2]):
        print(' | '.join('' if v is None else str(v) for v in row))
PY
