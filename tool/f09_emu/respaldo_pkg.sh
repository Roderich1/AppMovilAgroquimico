#!/usr/bin/env bash
# COPIA PARA INSPECCIÓN de una instalación de Agrocuentas en el teléfono.
# Sólo lectura: no detiene la app, no instala y no escribe nada en el teléfono.
#
#   F09_SERIAL=<serie> bash tool/f09_emu/respaldo_pkg.sh <paquete> <carpeta-salida>
#
# NO es un respaldo recuperable de la aplicación:
#   - lo cifrado por flutter_secure_storage (shared_prefs/FlutterSecure*) sólo
#     lo descifra ESTA instalación con su clave del Keystore de Android: tras
#     desinstalar, o en otra instalación, no sirve (vínculo, sesión, PIN);
#   - restaurar estos archivos NO está probado;
#   - el respaldo recuperable previsto es el de la propia app (F08).
# Sirve para comparar conteos e integridad antes y después de actualizar.
#
# Incluye: databases/ (agroquimicos_v2.db y su diario -journal o -wal/-shm si
# existen), shared_prefs/ (ajustes y valores cifrados), app_flutter/ (registro
# de la app: líneas de códigos y números, sin lo dictado) y files/.
# Excluye: no_backup/ (modelos de voz copiados del APK, cientos de MB), cache/
# y code_cache/ (regenerables).
#
# Consistencia: la base usa diario de reversión (o WAL). Se hacen dos pasadas
# seguidas y sólo se acepta la copia si la base y su diario son idénticos byte
# a byte en ambas (si no, hay escrituras en curso: se reintenta hasta 3 veces y
# se aborta). Después se comprueba la integridad sobre una copia de trabajo
# aparte (abrirla puede aplicar el diario; el .tar no se modifica). Conviene
# hacerlo con la app en una pantalla sin borrador ni operación en curso.
#
# Salida en <carpeta-salida>: estado.txt, datos.tar (+ .sha256),
# contenido.txt, consistencia.txt y resumen.txt (conteos e integridad).
set -euo pipefail
export MSYS_NO_PATHCONV=1
PKG=${1:?paquete}; OUT=${2:?carpeta}
SER=${F09_SERIAL:?F09_SERIAL}
A="adb -s $SER"
HERE="$(cd "$(dirname "$0")" && pwd)"
DIRS="databases shared_prefs app_flutter files"
mkdir -p "$OUT"; cd "$OUT"
$A shell pm path "$PKG" >/dev/null || { echo "no instalado: $PKG"; exit 1; }

pass() { # $1 = archivo .tar
  $A exec-out run-as "$PKG" tar -cf - $DIRS 2>/dev/null > "$1"
}
db_hashes() { # $1 = archivo .tar → sha256 de cada archivo de databases/
  local tmp; tmp=$(mktemp -d)
  tar -xf "$1" -C "$tmp" databases 2>/dev/null || true
  ( cd "$tmp" && find databases -type f | sort | xargs -r sha256sum )
  rm -rf "$tmp"
}

ok=no
for intento in 1 2 3; do
  pass p1.tar; pass p2.tar
  h1=$(db_hashes p1.tar); h2=$(db_hashes p2.tar)
  if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then ok=si; break; fi
  sleep 2
done
[ "$ok" = si ] || { rm -f p1.tar p2.tar; echo "ABORTADO: la base cambió entre pasadas (escrituras en curso)"; exit 3; }
mv p1.tar datos.tar; rm -f p2.tar
{
  echo "pasadas coincidentes en el intento $intento"
  echo "$h1"
} > consistencia.txt

{
  echo "fecha $(date '+%F %T %z')"
  $A shell dumpsys package "$PKG" | grep -E "versionCode|versionName|firstInstallTime|lastUpdateTime|pkgFlags" | sed 's/^ *//' | sort -u
  apk=$($A shell pm path "$PKG" | tr -d '\r' | sed -n 's/^package://p' | head -1)
  echo "apk_sha256 $($A shell sha256sum "$apk" | awk '{print $1}')"
  echo "proceso $($A shell pidof "$PKG" | tr -d '\r')"
  echo "foco $($A shell dumpsys window | tr -d '\r' | grep -m1 mCurrentFocus | sed 's/^ *//')"
  $A shell df -h /data | tail -1 | awk '{print "data_libre " $4}'
  echo "no_backup_voz:"; $A shell run-as "$PKG" ls -1 no_backup/voice 2>/dev/null | sed 's/^/  /'
} > estado.txt

tar -tf datos.tar > contenido.txt
rm -rf trabajo; mkdir trabajo; tar -xf datos.tar -C trabajo databases
DB=trabajo/databases/agroquimicos_v2.db
python -I -X utf8 - "$(cygpath -w "$DB")" >> estado.txt <<'PY'
import os, sys
db = sys.argv[1]
MAGIC = bytes.fromhex("d9d505f920a163d7")  # cabecera de un diario de reversión vivo
for suffix in ("-journal", "-wal"):
    f = db + suffix
    if not os.path.exists(f):
        print(f"diario{suffix}: ausente")
        continue
    size = os.path.getsize(f)
    head = open(f, "rb").read(8)
    if suffix == "-journal":
        state = "ACTIVO (transacción sin terminar)" if head == MAGIC else "inerte (cabecera vacía)"
    else:
        state = "presente"
    print(f"diario{suffix}: {size} B, {state}")
PY
python -I -X utf8 "$(cygpath -w "$HERE/snapshot.py")" "$(cygpath -w "$DB")" > resumen.txt
rm -rf trabajo
sha256sum datos.tar > datos.tar.sha256
echo "copia para inspección en $OUT: $(stat -c %s datos.tar) B, $(wc -l < contenido.txt) entradas, intento $intento"
head -1 resumen.txt
