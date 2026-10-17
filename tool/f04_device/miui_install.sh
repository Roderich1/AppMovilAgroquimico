#!/usr/bin/env bash
# Herramientas de la sesión física F03/F04/#97 del 2026-10-17 (sesión A). Sólo copias aisladas; no imprimen secretos.
# Instala una APK aislada aceptando el diálogo de MIUI («Instalar» en 10 s).
#   miui_install.sh <apk> <log>
set -uo pipefail
# Sólo adb: rutas del teléfono sin la conversión de Git Bash.
export MSYS_NO_PATHCONV=1
apk="$1"; log="$2"
( adb install -r "$apk" > "$log" 2>&1 ) &
pid=$!
for _ in $(seq 1 25); do
  sleep 1
  kill -0 "$pid" 2>/dev/null || break
  adb shell uiautomator dump /sdcard/agro_ui.xml > /dev/null 2>&1 || continue
  xml=$(adb exec-out cat /sdcard/agro_ui.xml 2>/dev/null)
  b=$(printf '%s' "$xml" | grep -o 'text="Instalar"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 \
      | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
  if [ -n "$b" ]; then
    read -r x1 y1 x2 y2 < <(printf '%s' "$b" | tr '[],' '   ')
    adb shell input tap $(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 ))
  fi
done
wait "$pid"
adb shell rm -f /sdcard/agro_ui.xml > /dev/null 2>&1
cat "$log"
