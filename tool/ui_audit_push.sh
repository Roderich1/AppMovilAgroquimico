#!/usr/bin/env bash
# RESET -> SEED -> AUDIT: deja el emulador siempre en el mismo estado.
#
# HERRAMIENTA DE DESARROLLO. No toca el codigo de produccion: solo genera el
# archivo SQLite de auditoria y lo copia dentro del sandbox de la aplicacion.
#
#   bash tool/ui_audit_push.sh            # regenera el dataset y lo instala
#   bash tool/ui_audit_push.sh --no-seed  # reinstala el dataset ya generado
#   bash tool/ui_audit_push.sh --apk      # ademas reinstala el APK de depuracion
#
# Requiere un emulador/dispositivo con la app instalada en modo DEPURACION:
# `run-as` solo funciona sobre paquetes depurables.
set -euo pipefail

# Git Bash (MSYS) reescribe los argumentos que parecen rutas POSIX y convertiria
# /data/local/tmp en una ruta de Windows antes de que adb los reciba.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

PKG=com.comunidad.agro.agroquimicos
DB_NAME=agroquimicos_v2.db
OUT_DIR=build/ui_audit
ADB="${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB=adb

SEED=1
APK=0
for arg in "$@"; do
  case "$arg" in
    --no-seed) SEED=0 ;;
    --apk) APK=1 ;;
    *) echo "Argumento desconocido: $arg" >&2; exit 2 ;;
  esac
done

if [ "$SEED" = 1 ]; then
  echo "==> Generando dataset determinista"
  flutter test tool/seed_ui_audit.dart
fi

[ -f "$OUT_DIR/$DB_NAME" ] || { echo "Falta $OUT_DIR/$DB_NAME (ejecute sin --no-seed)" >&2; exit 1; }

if [ "$APK" = 1 ]; then
  echo "==> Instalando APK de depuracion"
  "$ADB" install -r build/app/outputs/flutter-apk/app-debug.apk
fi

echo "==> Deteniendo la aplicacion"
"$ADB" shell am force-stop "$PKG"

echo "==> Preparando directorios del sandbox"
"$ADB" shell run-as "$PKG" mkdir -p databases app_flutter/invoices

echo "==> Copiando la base de datos"
"$ADB" push "$OUT_DIR/$DB_NAME" "/data/local/tmp/$DB_NAME" >/dev/null
"$ADB" shell run-as "$PKG" cp "/data/local/tmp/$DB_NAME" "databases/$DB_NAME"
# Los diarios de la base anterior pertenecen a otro archivo: la corromperian.
"$ADB" shell run-as "$PKG" rm -f "databases/$DB_NAME-wal" "databases/$DB_NAME-shm"

echo "==> Copiando la fotografia de factura de prueba"
"$ADB" push "$OUT_DIR/invoice_ui_audit.png" /data/local/tmp/invoice_ui_audit.png >/dev/null
"$ADB" shell run-as "$PKG" cp /data/local/tmp/invoice_ui_audit.png app_flutter/invoices/invoice_ui_audit.png

echo "==> Limpiando archivos temporales del dispositivo"
"$ADB" shell rm -f "/data/local/tmp/$DB_NAME" /data/local/tmp/invoice_ui_audit.png

echo "==> Arrancando la aplicacion"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "LISTO."
