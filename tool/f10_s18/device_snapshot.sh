#!/usr/bin/env bash
# F10 (#36, MOB #91-#93): como tool/f08_bkp/device_snapshot.sh, pero para la copia
# aislada .f10bkp del entorno de la sesión A (tool/f10_s18/env.sh, F10_COPY=bkp).
# Copia la base (con -wal/-shm) y las fotografías por run-as a
# $F03_RUN_DIR/snap_<etiqueta> y genera la instantánea con tool/f08_bkp/snapshot.py
# sin cambios. La app se detiene antes para que la copia sea consistente.
#   device_snapshot.sh <etiqueta>          p. ej. antes | despues
#   device_snapshot.sh compare <a> <b>     compara dos instantáneas
# Requiere: F10_COPY=bkp source tool/f10_s18/env.sh y tool/f03_res_01/config.sh.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${F03_APP_PACKAGE:?Cargue antes env.sh (F10_COPY=bkp) y config.sh}"
adb() { MSYS_NO_PATHCONV=1 command adb "$@"; }
in_app() { adb exec-out run-as "$F03_APP_PACKAGE" "$@"; }

if [ "${1:-}" = compare ]; then
  python -I -X utf8 "$here/../f08_bkp/snapshot.py" --compare "$F03_RUN_DIR/snap_${2:?}" "$F03_RUN_DIR/snap_${3:?}"
  exit $?
fi
label="${1:?etiqueta}"
case "$F03_APP_PACKAGE" in *.f10bkp) ;; *) echo "paquete inesperado: $F03_APP_PACKAGE"; exit 1 ;; esac
adb shell am force-stop "$F03_APP_PACKAGE"
out="$F03_RUN_DIR/snap_$label"
rm -rf "$out"
mkdir -p "$out/db" "$out/invoices"
for f in $(in_app ls -1 databases | tr -d '\r' | grep -E "^${F03_DEVICE_DB}(-wal|-shm|-journal)?$"); do
  in_app cat "databases/$f" > "$out/db/$f"
done
[ -s "$out/db/$F03_DEVICE_DB" ] || { echo "base de la app aislada ausente"; exit 1; }
for f in $(in_app ls -1 app_flutter/invoices 2>/dev/null | tr -d '\r'); do
  in_app cat "app_flutter/invoices/$f" > "$out/invoices/$f"
done
echo "instantánea $label:"
python -I -X utf8 "$here/../f08_bkp/snapshot.py" "$out"
