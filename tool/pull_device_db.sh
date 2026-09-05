#!/usr/bin/env bash
# Copia la base de datos del dispositivo a build/ui_audit/device_pull.db para
# poder inspeccionarla desde el equipo de desarrollo.
#
# HERRAMIENTA DE DESARROLLO. No toca el codigo de produccion ni el dispositivo:
# solo lee. Se usa para verificar en el Pixel 8 lo que la aplicacion escribio
# realmente, que es el criterio de cierre de los UIBUG contables.
#
#   bash tool/pull_device_db.sh [destino.db]
#
# Requiere la app instalada en modo DEPURACION: `run-as` solo funciona sobre
# paquetes depurables.
set -euo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

PKG=com.comunidad.agro.agroquimicos
DB_NAME=agroquimicos_v2.db
OUT="${1:-build/ui_audit/device_pull.db}"
ADB="${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB=adb

mkdir -p "$(dirname "$OUT")"

# `run-as` puede LEER el sandbox pero no ESCRIBIR en /data/local/tmp, asi que se
# usa `exec-out cat`, que no toca el dispositivo y conserva los bytes tal cual.
"$ADB" exec-out run-as "$PKG" cat "databases/$DB_NAME" > "$OUT" 2>/dev/null || {
  echo "No se pudo leer la base (¿app instalada en debug?)" >&2
  exit 1
}
[ -s "$OUT" ] || { echo "La base copiada esta vacia" >&2; exit 1; }

# Los diarios pertenecen a la base del dispositivo: sin ellos la copia local
# puede no ver las ultimas escrituras, asi que se traen tambien si existen.
for suffix in wal shm journal; do
  if "$ADB" shell run-as "$PKG" test -f "databases/$DB_NAME-$suffix" 2>/dev/null; then
    "$ADB" exec-out run-as "$PKG" cat "databases/$DB_NAME-$suffix" \
      > "$OUT-$suffix" 2>/dev/null || rm -f "$OUT-$suffix"
  else
    rm -f "$OUT-$suffix"
  fi
done

echo "$OUT"
