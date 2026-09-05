#!/usr/bin/env bash
# Captura una pantalla del emulador en artifacts/ui-audit/fixed/regression/.
#
# HERRAMIENTA DE DESARROLLO. Solo lee del dispositivo.
#
#   bash tool/audit_shot.sh <nombre>            # captura
#   bash tool/audit_shot.sh <nombre> <x> <y>    # toca y luego captura
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

ADB="${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB=adb
OUT=artifacts/ui-audit/fixed/regression
mkdir -p "$OUT"

NAME=$1
if [ $# -ge 3 ]; then
  "$ADB" shell input tap "$2" "$3"
  sleep 3
fi
"$ADB" exec-out screencap -p > "$OUT/$NAME.png"
echo "$OUT/$NAME.png"
