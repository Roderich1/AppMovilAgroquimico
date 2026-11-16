#!/usr/bin/env bash
# DEMO de Agrocuentas (OE3, 2026-11-03): la app en el EMULADOR Android (Pixel_8,
# x86_64) con un paquete AISLADO `.demo` («AC DEMO») conectado al Central DEMO
# (Backend repo: tool/demo/demo.sh). Nunca toca la app normal ni otros sufijos.
#
#   demo-mobile.sh tunnel | untunnel     túnel HTTPS temporal (cloudflared) → observador 3331 → API 3330
#   demo-mobile.sh build <sha>           APK profile x86_64 del HEAD exacto con el origen del túnel
#   demo-mobile.sh install | uninstall   sólo .demo (adb install -r conserva los datos)
#   demo-mobile.sh pull-db <dir>         copia de la base de la app (app detenida)
#   demo-mobile.sh push-db <archivo>     devuelve la base sembrada (app detenida; quita -wal/-shm)
#   demo-mobile.sh seed-local            pull-db + referencias + tool/demo/seed_demo_mobile.dart + push-db
#   demo-mobile.sh net on|off            datos y Wi‑Fi del emulador (desconexión REAL del emulador)
#   demo-mobile.sh <ui|start|stop|tap|tapxy|key|text|shot>   tool/f03_res_01/device.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOB="$(cd "$here/../.." && pwd)"
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
DEMO_BE=${DEMO_BE:-$ROOT/_wt/DEMO-BE}
RUN=${DEMO_MOB_RUN:-/c/Users/MSI/AppData/Local/Temp/agro_demo_mob}
export ANDROID_SERIAL=${DEMO_SERIAL:-emulator-5554}
SUFFIX=.demo; LABEL="AC DEMO"; PKG=com.comunidad.agro.agroquimicos$SUFFIX
export F03_BE_DIR=$DEMO_BE/Back F03_CLOUDFLARED=$ROOT/_wt/tools/cloudflared-2026.10.0/cloudflared-windows-amd64.exe
export F03_API_PORT=3330 F03_OBSERVER_PORT=3331 F03_RUN_DIR=$RUN F03_PG_CONTAINER=agro_demo_pg
export F03_APP_ID_SUFFIX=$SUFFIX F03_APP_LABEL="$LABEL" F03_SHOTS_DIR=$RUN/capturas
# Rutas del dispositivo sin convertir (Git Bash); las del PC sí se convierten.
export MSYS2_ARG_CONV_EXCL="/sdcard;/data/local;/dev/tty"
mkdir -p "$RUN"
dev="$MOB/tool/f03_res_01/device.sh"
# Rutas del dispositivo sin conversión de Git Bash (sólo en adb).
adb() { MSYS_NO_PATHCONV=1 command adb "$@"; }
DB=agroquimicos_v2.db
cmd=${1:?orden}; shift || true
case "$cmd" in
  tunnel) bash "$MOB/tool/f03_res_01/tunnel.sh" ;;
  untunnel)
    for f in tunnel observer; do
      [ -f "$RUN/$f.pid" ] && kill "$(cat "$RUN/$f.pid")" 2>/dev/null || true; rm -f "$RUN/$f.pid"
    done
    echo "túnel y observador cerrados" ;;
  build)
    sha=${1:?sha}; origin=$(cat "$RUN/origin" 2>/dev/null || true)
    [ -n "$origin" ] || { echo "sin origen HTTPS: primero 'demo-mobile.sh tunnel'"; exit 1; }
    cd "$MOB"
    [ "$(git rev-parse HEAD)" = "$sha" ] || { echo "$MOB no está en $sha"; exit 1; }
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "hay cambios en archivos versionados"; exit 1; }
    gradle=android/app/build.gradle.kts; manifest=android/app/src/main/AndroidManifest.xml
    trap 'git checkout -q -- "$gradle" "$manifest"' EXIT
    mkdir -p "$RUN/apk"
    python -I - "$gradle" "$manifest" "$SUFFIX" "$LABEL" <<'PY'
import sys, pathlib
gradle, manifest, suffix, label = sys.argv[1:5]
g = pathlib.Path(gradle); s = g.read_text(encoding='utf-8'); nl = '\r\n' if '\r\n' in s else '\n'
anchor = '    buildTypes {' + nl
assert s.count(anchor) == 1, 'buildTypes no encontrado'
g.write_text(s.replace(anchor, anchor + f'        getByName("profile") {{{nl}            applicationIdSuffix = "{suffix}"{nl}        }}{nl}'), encoding='utf-8', newline='')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
assert t.count('android:label="agroquimicos"') == 1, 'label no encontrado'
m.write_text(t.replace('android:label="agroquimicos"', f'android:label="{label}"'), encoding='utf-8', newline='')
PY
    flutter build apk --profile --target-platform android-x64 --dart-define=AGRO_API_BASE_URL="$origin" \
      > "$RUN/apk/build.log" 2>&1 || { tail -20 "$RUN/apk/build.log"; exit 1; }
    cp build/app/outputs/flutter-apk/app-profile.apk "$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk"
    git checkout -q -- "$gradle" "$manifest"; trap - EXIT
    echo "APK $PKG · Mobile $(git rev-parse HEAD) · SHA-256 $(sha256sum "$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk" | awk '{print $1}')"
    git diff --quiet --ignore-cr-at-eol && echo "archivos versionados intactos" ;;
  install)
    apk="$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk"; [ -f "$apk" ] || { echo "falta la APK"; exit 1; }
    adb install -r "$(cygpath -w "$apk")" | tail -1
    echo "instalado $PKG; SHA-256 $(sha256sum "$apk" | awk '{print $1}')" ;;
  uninstall) adb uninstall "$PKG" && echo "desinstalado $PKG (sólo ese paquete)" ;;
  pull-db)
    out=${1:?carpeta}; mkdir -p "$out"; adb shell am force-stop "$PKG"
    for f in $(adb exec-out run-as "$PKG" ls -1 databases | tr -d '\r' | grep -E "^${DB}(-wal|-shm|-journal)?$"); do
      adb exec-out run-as "$PKG" cat "databases/$f" > "$out/$f"
    done
    python -I -X utf8 - "$out/$DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1]); db.execute('PRAGMA wal_checkpoint(TRUNCATE)'); db.close()
PY
    rm -f "$out/$DB-wal" "$out/$DB-shm"
    echo "base copiada en $out/$DB (sha256 $(sha256sum "$out/$DB" | cut -c1-16))" ;;
  push-db)
    src=${1:?archivo}; adb shell am force-stop "$PKG"
    adb push "$(cygpath -w "$src")" "/data/local/tmp/$DB" > /dev/null
    adb shell chmod 644 "/data/local/tmp/$DB"
    adb shell run-as "$PKG" cp "/data/local/tmp/$DB" "databases/$DB"
    adb shell run-as "$PKG" rm -f "databases/$DB-wal" "databases/$DB-shm" "databases/$DB-journal"
    adb shell rm -f "/data/local/tmp/$DB"
    echo "base devuelta a $PKG (sha256 $(sha256sum "$src" | cut -c1-16))" ;;
  seed-local)
    day=${DEMO_DATE:-$(TZ=America/La_Paz date +%F)}
    work="$RUN/seed"; rm -rf "$work"; mkdir -p "$work"
    bash "$0" pull-db "$work"
    bash "$DEMO_BE/tool/demo/demo.sh" references agricultor1 "$work/references.json"
    ( cd "$MOB" && DEMO_DB="$(cygpath -w "$work/$DB")" DEMO_REFERENCES="$(cygpath -w "$work/references.json")" DEMO_DATE="$day" \
        flutter test tool/demo/seed_demo_mobile.dart 2>&1 | tee "$work/seed.log" | grep -E "DEMO_SUMMARY|All tests passed|Some tests failed|Expected|Actual|reason" )
    grep -q "All tests passed" "$work/seed.log" || { echo "siembra local fallida: la base del teléfono no se tocó"; exit 1; }
    bash "$0" push-db "$work/$DB" ;;
  net)
    case "${1:?on|off}" in
      off) adb shell svc wifi disable; adb shell svc data disable ;;
      on) adb shell svc wifi enable; adb shell svc data enable ;;
    esac
    sleep 2; echo "emulador: wifi=$(adb shell settings get global wifi_on | tr -d '\r') datos=$(adb shell settings get global mobile_data | tr -d '\r')" ;;
  *) exec bash "$dev" "$cmd" "$@" ;;
esac
