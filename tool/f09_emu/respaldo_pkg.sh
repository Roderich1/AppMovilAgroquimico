#!/usr/bin/env bash
# Respaldo y estado de una instalación de Agrocuentas en el POCO, SOLO LECTURA.
#
#   F09_SERIAL=cc14247a bash respaldo_pkg.sh <paquete> <carpeta-salida>
#
# Guarda en <carpeta-salida>:
#   estado.txt     versión, fechas de instalación, firmante, SHA-256 del APK
#                  instalado, espacio libre, proceso vivo y primer plano
#   datos.tar      databases/, shared_prefs/ y app_flutter/ (sin no_backup/,
#                  que sólo tiene los modelos de voz copiados del APK)
#   resumen.txt    conteos, integridad y existencias de la base copiada
#
# No detiene la app, no instala y no escribe nada en el teléfono. Requiere un
# APK debuggable (las profile lo son) para run-as. Con la app abierta, la base
# se copia junto con su -wal: conviene hacerlo en una pantalla sin borrador.
# Límite: lo que flutter_secure_storage cifra con el Keystore de Android sólo es
# legible por ESA instalación; el respaldo no sirve tras desinstalar.
set -euo pipefail
export MSYS_NO_PATHCONV=1
PKG=${1:?paquete}; OUT=${2:?carpeta}
SER=${F09_SERIAL:?F09_SERIAL}
A="adb -s $SER"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"; cd "$OUT"
$A shell pm path "$PKG" >/dev/null || { echo "no instalado: $PKG"; exit 1; }
{
  echo "fecha $(date '+%F %T %z')"
  $A shell dumpsys package "$PKG" | grep -E "versionCode|versionName|firstInstallTime|lastUpdateTime|pkgFlags" | sed 's/^ *//' | sort -u
  apk=$($A shell pm path "$PKG" | tr -d '\r' | sed -n 's/^package://p' | head -1)
  echo "apk_sha256 $($A shell sha256sum "$apk" | awk '{print $1}')"
  echo "proceso $($A shell pidof "$PKG" | tr -d '\r')"
  echo "primer_plano $($A shell dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity' | head -1 | sed 's/^ *//')"
  $A shell df -h /data | tail -1 | awk '{print "data_libre " $4}'
  echo "no_backup_voz:"; $A shell run-as "$PKG" ls -1 no_backup/voice 2>/dev/null | sed 's/^/  /'
} > estado.txt
$A exec-out run-as "$PKG" tar -cf - databases shared_prefs app_flutter 2>/dev/null > datos.tar
tar -tf datos.tar > contenido.txt
rm -rf db; mkdir db; tar -xf datos.tar -C db databases
python -I -X utf8 "$(cygpath -w "$HERE/snapshot.py")" "$(cygpath -w db/databases/agroquimicos_v2.db)" > resumen.txt
sha256sum datos.tar > datos.tar.sha256
echo "respaldo en $OUT: $(stat -c %s datos.tar) B, $(wc -l < contenido.txt) entradas"
head -1 resumen.txt
