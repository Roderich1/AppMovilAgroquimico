#!/usr/bin/env bash
# Evaluación F10: conteos de negocio de la copia aislada (sólo lectura) para comprobar
# persistencia y efectos duplicados entre bloques (protocolo v1.0 §1.7, paso 5).
# Copia temporal por run-as; la copia se borra al terminar. Respeta ANDROID_SERIAL.
#   eval_counts.sh            (requiere tool/f03_res_01/config.sh cargado)
set -euo pipefail
: "${F03_APP_PACKAGE:?cargue config.sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
MSYS_NO_PATHCONV=1 adb exec-out run-as "$F03_APP_PACKAGE" cat databases/agroquimicos_v2.db > "$tmp/db"
if MSYS_NO_PATHCONV=1 adb exec-out run-as "$F03_APP_PACKAGE" ls databases/agroquimicos_v2.db-journal > /dev/null 2>&1; then
  MSYS_NO_PATHCONV=1 adb exec-out run-as "$F03_APP_PACKAGE" cat databases/agroquimicos_v2.db-journal > "$tmp/db-journal"
fi
python -I -X utf8 - "$tmp/db" <<'PY'
import sqlite3, sys, pathlib
db = sqlite3.connect(pathlib.Path(sys.argv[1]).resolve().as_uri(), uri=True)
q = lambda s: db.execute(s).fetchone()[0]
print("conteos: compras=%d líneas_compra=%d aplicaciones=%d líneas_aplicación=%d movimientos=%d fotos=%d outbox=%d acked=%d necesidades=%d integridad=%s" % (
    q("SELECT count(*) FROM purchases"), q("SELECT count(*) FROM purchase_items"),
    q("SELECT count(*) FROM applications"), q("SELECT count(*) FROM application_items"),
    q("SELECT count(*) FROM inventory_movements"),
    q("SELECT count(*) FROM purchases WHERE invoice_image_path IS NOT NULL"),
    q("SELECT count(*) FROM sync_outbox"), q("SELECT count(*) FROM sync_outbox WHERE status='ACKED'"),
    q("SELECT count(*) FROM declared_needs"), q("PRAGMA integrity_check")))
PY
