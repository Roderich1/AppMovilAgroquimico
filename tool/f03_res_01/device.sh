#!/usr/bin/env bash
# F03-RES-01 (#71) y E2E de D3: operaciones sobre el teléfono por ADB. Sólo actúa
# sobre la app AISLADA ($F03_APP_PACKAGE); la app normal sólo se lista.
#   device.sh info               modelo, Android, API, zona horaria y radios
#   device.sh net off|on|state   modo avión (todas las radios)
#   device.sh packages           paquetes agro instalados y fechas de la app normal
#   device.sh stop | start       force-stop (y comprobación sin proceso) / abrir como el launcher
#   device.sh ui                 textos y botones visibles, con su centro (para navegar)
#   device.sh tap <regex>        toca el primer elemento cuyo texto o descripción coincide
#   device.sh tapxy <x> <y> | key <BACK|ENTER|...> | text <texto sin secretos>
#   device.sh shot <nombre>      captura sin barra de estado en $F03_SHOTS_DIR; imprime su SHA-256
#   device.sh secure             slot activo, guard y huellas (12 hex) de la identidad de
#                                instalación y del almacén cifrado; nunca valores
#   device.sh db <consulta>      copia temporal de SQLite (run-as) y consulta de sólo lectura
#                                con device_db.py; la copia se borra al terminar
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
pkg="$F03_APP_PACKAGE"
# Rutas del teléfono (/sdcard, ...) sin la conversión de rutas de Git Bash.
adb() { MSYS_NO_PATHCONV=1 command adb "$@"; }
export PYTHONIOENCODING=utf-8
sha12() { sha256sum | cut -c1-12; }
in_app() { adb exec-out run-as "$pkg" "$@"; }

ui_dump() {
  adb shell uiautomator dump /sdcard/f03_ui.xml > /dev/null 2>&1
  adb exec-out cat /sdcard/f03_ui.xml
  adb shell rm -f /sdcard/f03_ui.xml
}

case "${1:-}" in
  info)
    for prop in ro.product.marketname ro.product.model ro.build.version.release ro.build.version.sdk \
      ro.build.version.incremental persist.sys.timezone; do
      echo "$prop=$(adb shell getprop "$prop" | tr -d '\r')"
    done
    "$0" net state
    ;;
  net)
    case "${2:-}" in
      off) adb shell cmd connectivity airplane-mode enable ;;
      on) adb shell cmd connectivity airplane-mode disable ;;
      state) ;;
      *) echo "net off|on|state"; exit 2 ;;
    esac
    echo "modo avión=$(adb shell settings get global airplane_mode_on | tr -d '\r')" \
      "wifi=$(adb shell settings get global wifi_on | tr -d '\r')" \
      "datos=$(adb shell settings get global mobile_data | tr -d '\r')"
    ;;
  packages)
    adb shell pm list packages | tr -d '\r' | grep -E 'com\.comunidad\.agro\.agroquimicos' || true
    adb shell dumpsys package com.comunidad.agro.agroquimicos | tr -d '\r' \
      | grep -m2 -E 'firstInstallTime|lastUpdateTime' | sed 's/^ */app normal: /'
    ;;
  stop)
    adb shell am force-stop "$pkg"
    echo "force-stop; proceso vivo: $(adb shell pidof "$pkg" | tr -d '\r' | grep -c . || true)"
    ;;
  start)
    adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    echo "abierta como desde el launcher"
    ;;
  ui)
    ui_dump | python -I -X utf8 "$here/device_db.py" --ui
    ;;
  tap)
    xy=$(ui_dump | python -I -X utf8 "$here/device_db.py" --find "${2:?regex}")
    [ -n "$xy" ] || { echo "no encontrado: $2"; exit 1; }
    adb shell input tap $xy
    echo "tocado: $2 ($xy)"
    ;;
  tapxy) adb shell input tap "${2:?x}" "${3:?y}" ;;
  key) adb shell input keyevent "KEYCODE_${2:?tecla}" ;;
  text) adb shell input text "$(printf '%s' "${2:?texto}" | sed 's/ /%s/g')" ;;
  shot)
    mkdir -p "$F03_SHOTS_DIR"
    out="$F03_SHOTS_DIR/${2:?nombre}.png"
    adb exec-out screencap -p > "$out.raw"
    python -c 'import sys; from PIL import Image; i=Image.open(sys.argv[1]); i.crop((0,110,i.width,i.height)).save(sys.argv[2])' \
      "$out.raw" "$out"
    rm -f "$out.raw"
    echo "$(sha256sum "$out" | cut -d' ' -f1)  $(basename "$out")"
    ;;
  secure)
    files=$(in_app ls -1 shared_prefs 2>/dev/null | tr -d '\r')
    if grep -qx 'AgrocuentasSessionPointer.xml' <<< "$files"; then
      prefs=$(in_app cat shared_prefs/AgrocuentasSessionPointer.xml)
      slot=$(grep -o -E 'name="activeSlot">[^<]*' <<< "$prefs" | sed 's/.*>//' || true)
      guard=$(grep -o -E 'name="refreshQuarantined" value="[a-z]+"' <<< "$prefs" | sed 's/.*value="//;s/"//' || true)
      echo "puntero: slot activo=${slot:-ninguno} guard en cuarentena=${guard:-false}"
    else
      echo "puntero: ausente"
    fi
    id_file=$(in_app find no_backup -name client_id 2>/dev/null | tr -d '\r' | head -1)
    echo "identidad de instalación=$([ -n "$id_file" ] && in_app cat "$id_file" | sha12 || echo ausente)"
    # Sesión cifrada A/B: huella del texto cifrado de cada slot (nunca se descifra).
    if grep -qx 'agrocuentas_secure_session_v1.xml' <<< "$files"; then
      store=$(in_app cat shared_prefs/agrocuentas_secure_session_v1.xml)
      for s in a b; do
        value=$(grep -o -E "_session_${s}\">[^<]*" <<< "$store" | sed 's/.*">//' || true)
        echo "sesión cifrada slot $s=$([ -n "$value" ] && printf '%s' "$value" | sha12 || echo ausente)"
      done
      echo "sesión cifrada modificada: $(in_app ls -l shared_prefs/agrocuentas_secure_session_v1.xml | awk '{print $6, $7}')"
    else
      echo "sesión cifrada: ausente"
    fi
    ;;
  db)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    for f in $(in_app ls -1 databases | tr -d '\r' | grep -E "^${F03_DEVICE_DB}(-wal|-shm|-journal)?$"); do
      in_app cat "databases/$f" > "$tmp/$f"
    done
    [ -s "$tmp/$F03_DEVICE_DB" ] || { echo "base de la app aislada ausente"; exit 1; }
    python -I -X utf8 "$here/device_db.py" "$tmp/$F03_DEVICE_DB" "${2:?consulta}"
    ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
