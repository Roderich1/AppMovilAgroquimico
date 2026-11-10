#!/usr/bin/env bash
# F09 en el EMULADOR (Pixel_8, x86_64): operaciones sobre el paquete AISLADO
# `.f09` («AC F09») y NADA más. No desinstala, no borra datos y no toca otros
# sufijos (.voz, .uxpres, .demo, la app normal...). Antes de cada toque comprueba
# que `.f09` está en primer plano (o, sólo con `permiso`, que el diálogo del
# sistema es el de «AC F09»). Idempotente: repetir una orden no cambia nada más.
#
#   f09emu.sh estado                 emulador, paquete, primer plano, Central local y túnel (sin publicar el origen)
#   f09emu.sh compilar <sha>         APK `.f09` del HEAD exacto de $F09_MOB con el origen del túnel VIVO (no lo imprime)
#   f09emu.sh instalar <apk>         comprueba que la APK es `.f09` y hace `adb install -r` (conserva los datos)
#   f09emu.sh abrir                  abre `.f09` como el launcher y espera a que esté en primer plano
#   f09emu.sh primer-plano           paquete en primer plano; sale con 1 si no es `.f09`
#   f09emu.sh ui                     textos visibles de `.f09` con su centro (contraseñas omitidas)
#   f09emu.sh tocar <regex>          toca el primer elemento de `.f09` cuyo texto/descr. coincide
#   f09emu.sh permiso <regex>        toca en el diálogo de permisos SÓLO si es el de «AC F09»
#   f09emu.sh esperar <regex> [s]    espera (por defecto 20 s) a que aparezca el texto en `.f09`
#   f09emu.sh ir voz|compra|plan|aplicacion   Operaciones → Más → Registrar por voz → opción
#   f09emu.sh captura <nombre>       PNG en $F09_RUN/capturas (sólo con `.f09` en primer plano); imprime SHA-256
#   f09emu.sh microfono              permiso, appops, entradas de audio activas y AVD (sólo lectura)
#   f09emu.sh voz                    pantalla de voz sólo con la lista blanca (sin lo oído)
#   f09emu.sh base                   cuentas de la base de `.f09` (copia temporal por run-as, sólo lectura)
#   f09emu.sh sembrar [cuenta]       siembra local DEMO con el código F09 (app detenida; ver ENTORNO_EMULADOR_F09.md)
#   f09emu.sh red on|off             Wi‑Fi y datos del EMULADOR entero (afecta a todas las apps)
#
# Variables: F09_SERIAL (emulator-5554), F09_RUN (%TEMP%/agro_f09_emu), F09_MOB (este
# worktree), DEMO_BE (_wt/DEMO-BE), DEMO_MOB (_wt/DEMO-MOB), DEMO_PGPORT (15432),
# DEMO_DATE (2026-11-03, fecha de siembra del Central), F09_ACCOUNT (agricultor5).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
F09_MOB=${F09_MOB:-$(cd "$here/../.." && pwd)}
DEMO_BE=${DEMO_BE:-$ROOT/_wt/DEMO-BE}
DEMO_MOB=${DEMO_MOB:-$ROOT/_wt/DEMO-MOB}
DEMO_MOB_RUN=/c/Users/MSI/AppData/Local/Temp/agro_demo_mob
RUN=${F09_RUN:-/c/Users/MSI/AppData/Local/Temp/agro_f09_emu}
export ANDROID_SERIAL=${F09_SERIAL:-emulator-5554}
# F09_PKG / F09_LABEL: otra instalación aislada de la misma familia (p. ej.
# `.f09sm`, «AC F09 Small»). Por defecto, `.f09`.
PKG=${F09_PKG:-com.comunidad.agro.agroquimicos.f09}
LABEL=${F09_LABEL:-AC F09}
DB=agroquimicos_v2.db
AAPT2=${AAPT2:-/c/Users/MSI/AppData/Local/Android/Sdk/build-tools/37.0.0/aapt2.exe}
export MSYS2_ARG_CONV_EXCL="/sdcard;/data/local;/dev/tty"
export PYTHONIOENCODING=utf-8
adb() { MSYS_NO_PATHCONV=1 command adb "$@"; }
py() { python -I -X utf8 "$here/f09emu.py" "$@"; }
mkdir -p "$RUN"

installed() { adb shell pm list packages "$PKG" | tr -d '\r' | grep -qx "package:$PKG"; }
need_installed() { installed || { echo "ABORTADO: $PKG no está instalado"; exit 1; }; }
foreground() {
  adb shell dumpsys window | tr -d '\r' | grep -m1 -E 'mCurrentFocus=' \
    | sed -E 's/.* u[0-9]+ ([^/ }]+).*/\1/'
}
guard() {
  local fg; fg=$(foreground)
  [ "$fg" = "$PKG" ] || { echo "ABORTADO: en primer plano está '${fg:-nada}', no $PKG"; exit 1; }
}
# Volcado de la interfaz directo a la salida (sin archivo en /sdcard).
# MIUI (POCO) imprime antes una traza de ThemeCompatibilityLoader: sólo el XML.
ui_dump() { adb exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\r' | grep -o '<?xml.*</hierarchy>'; }
has() { ui_dump | py has "$PKG" "$1"; }
wait_for() {
  local rx=$1 secs=${2:-20}
  for _ in $(seq 1 "$secs"); do
    guard
    has "$rx" && return 0
    sleep 1
  done
  echo "no apareció: $rx (${secs} s)"; return 1
}
tap() {
  guard
  local xy; xy=$(ui_dump | py find "$PKG" "$1") || { echo "no encontrado en $PKG: $1"; return 1; }
  guard
  adb shell input tap $xy
  echo "tocado: $1 ($xy)"
}

cmd=${1:-}; shift || true
case "$cmd" in
  estado)
    echo "dispositivo $ANDROID_SERIAL: $(adb get-state 2>/dev/null || echo ausente) · $(adb shell getprop ro.product.model | tr -d '\r') · API $(adb shell getprop ro.build.version.sdk | tr -d '\r') · TZ $(adb shell getprop persist.sys.timezone | tr -d '\r')"
    if installed; then
      echo "$PKG instalado: $(adb shell dumpsys package "$PKG" | tr -d '\r' | grep -m2 -E 'versionCode|lastUpdateTime' | sed 's/^ *//' | tr '\n' ' ')"
    else
      echo "$PKG NO instalado"
    fi
    echo "primer plano: $(foreground)"
    echo "Central local (API 3330): health HTTP $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3330/api/v1/health || echo 000)"
    tp=$(cat "$DEMO_MOB_RUN/tunnel.pid" 2>/dev/null || true)
    if [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null; then
      code=$(curl -s -o /dev/null -w '%{http_code}' "$(cat "$DEMO_MOB_RUN/origin")/api/v1/health" || echo 000)
      echo "túnel DEMO: proceso vivo; origen HTTPS (no se muestra) health HTTP $code"
    else
      echo "túnel DEMO: NO activo (el archivo origin, si existe, es de una sesión anterior y no sirve)"
    fi
    echo "red del emulador: wifi=$(adb shell settings get global wifi_on | tr -d '\r') datos=$(adb shell settings get global mobile_data | tr -d '\r') avión=$(adb shell settings get global airplane_mode_on | tr -d '\r')"
    ;;
  compilar)
    # APK `.f09` x86_64 profile del HEAD exacto de $F09_MOB, con el origen del túnel
    # DEMO VIVO (se comprueba antes) y la evidencia de dictado activada. El origen
    # se lee del archivo y no se imprime. Gradle y el manifiesto se restauran.
    sha=${1:?sha}
    tp=$(cat "$DEMO_MOB_RUN/tunnel.pid" 2>/dev/null || true)
    { [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null; } || { echo "ABORTADO: el túnel DEMO no está activo (lo abre Roderich)"; exit 1; }
    origin=$(cat "$DEMO_MOB_RUN/origin")
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$origin/api/v1/health")" = 200 ] || { echo "ABORTADO: el origen no responde 200"; exit 1; }
    cd "$F09_MOB"
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "$sha")" ] || { echo "ABORTADO: $F09_MOB no está en $sha"; exit 1; }
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "ABORTADO: cambios sin commit en archivos versionados"; exit 1; }
    [ -f android/app/voice-models/voice/manifest.json ] || { echo "ABORTADO: faltan los modelos (tool/voice_local/fetch_voice_models.sh)"; exit 1; }
    [ -f android/app/src/main/jniLibs/x86_64/libagro_whisper.so ] || echo "AVISO: sin libagro_whisper.so x86_64; la segunda pasada quedará no disponible"
    short=$(git rev-parse --short HEAD)
    gradle=android/app/build.gradle.kts; manifest=android/app/src/main/AndroidManifest.xml
    backup=$(mktemp -d); cp "$gradle" "$backup/gradle"; cp "$manifest" "$backup/manifest"
    trap 'cp "$backup/gradle" "$gradle"; cp "$backup/manifest" "$manifest"; rm -rf "$backup"' EXIT
    python -I - "$gradle" "$manifest" <<'PY'
import sys, pathlib
gradle, manifest = sys.argv[1:3]
g = pathlib.Path(gradle); s = g.read_text(encoding='utf-8'); nl = '\r\n' if '\r\n' in s else '\n'
anchor = '    buildTypes {' + nl
assert s.count(anchor) == 1, 'buildTypes no encontrado'
g.write_text(s.replace(anchor, anchor + f'        getByName("profile") {{{nl}            applicationIdSuffix = ".f09"{nl}        }}{nl}'), encoding='utf-8', newline='')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
assert t.count('android:label="agroquimicos"') == 1, 'label no encontrado'
m.write_text(t.replace('android:label="agroquimicos"', 'android:label="AC F09"'), encoding='utf-8', newline='')
PY
    mkdir -p "$RUN/apk"
    flutter build apk --profile --split-per-abi --target-platform android-x64 \
      --dart-define=AGRO_API_BASE_URL="$origin" --dart-define=AGRO_VOICE_EVIDENCE=true \
      --dart-define=AGRO_APP_COMMIT="$short" > "$RUN/apk/build-$short.log" 2>&1 \
      || { tail -20 "$RUN/apk/build-$short.log"; exit 1; }
    apk="$RUN/apk/agrocuentas-f09-$short-x86_64-profile-origen.apk"
    cp build/app/outputs/flutter-apk/app-x86_64-profile.apk "$apk"
    echo "APK $apk · Mobile $(git rev-parse HEAD) · SHA-256 $(sha256sum "$apk" | awk '{print $1}')"
    ;;
  instalar)
    apk=${1:?apk}; [ -f "$apk" ] || { echo "no existe $apk"; exit 1; }
    badging=$("$AAPT2" dump badging "$(cygpath -w "$apk")" 2>/dev/null | tr -d '\r')
    name=$(grep -m1 -o -E "^package: name='[^']+'" <<< "$badging" | sed "s/.*name='//;s/'//")
    label=$(grep -m1 -o -E "^application-label:'[^']*'" <<< "$badging" | sed "s/application-label:'//;s/'//")
    [ "$name" = "$PKG" ] || { echo "ABORTADO: la APK es '$name', no $PKG"; exit 1; }
    [ "$label" = "$LABEL" ] || echo "AVISO: etiqueta '$label' (se esperaba '$LABEL')"
    adb install -r "$(cygpath -w "$apk")" | tr -d '\r' | tail -1
    echo "instalado $PKG (datos conservados); APK SHA-256 $(sha256sum "$apk" | awk '{print $1}')"
    ;;
  abrir)
    need_installed
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    for _ in $(seq 1 20); do [ "$(foreground)" = "$PKG" ] && { echo "$PKG en primer plano"; exit 0; }; sleep 1; done
    echo "ABORTADO: $PKG no llegó al primer plano (está '$(foreground)')"; exit 1
    ;;
  primer-plano) fg=$(foreground); echo "$fg"; [ "$fg" = "$PKG" ] ;;
  ui) guard; ui_dump | py ui "$PKG" ;;
  voz) guard; ui_dump | py estado "$PKG" ;;
  tocar) tap "${1:?regex}" ;;
  permiso)
    rx=${1:?regex}
    focus=$(adb shell dumpsys window | tr -d '\r' | grep -m1 -E 'mCurrentFocus=')
    grep -q -E 'permissioncontroller' <<< "$focus" || { echo "ABORTADO: no hay diálogo de permisos en primer plano"; exit 1; }
    dump=$(ui_dump)
    py has permisos "$LABEL" <<< "$dump" || { echo "ABORTADO: el diálogo de permisos no es de «$LABEL»"; exit 1; }
    xy=$(py find permisos "$rx" <<< "$dump") || { echo "no encontrado en el diálogo: $rx"; exit 1; }
    adb shell input tap $xy; echo "tocado en el diálogo de «$LABEL»: $rx ($xy)"
    ;;
  esperar) wait_for "${1:?regex}" "${2:-20}" && echo "visible: $1" ;;
  ir)
    dest=${1:?voz|compra|plan|aplicacion}
    case "$dest" in
      voz) target='' ;;
      compra) target='Compra por voz' ;;
      plan) target='^Planificaci.n por voz' ;;
      aplicacion) target='^Aplicaci.n por voz' ;;
      *) echo "destino: voz|compra|plan|aplicacion"; exit 2 ;;
    esac
    guard
    if ! has 'Dictar una compra, un plan o una aplicaci.n|Productos, cantidades, precios y proveedor'; then
      # Las pestañas leen «Operaciones / Pestaña 2 de 5»; los argumentos no ASCII no llegan bien a
      # Python desde Git Bash: se usan '.' en su lugar (verificación del 2026-11-08).
      if ! has '^M.s$'; then tap '^Operaciones'; wait_for '^M.s$' 10; fi
      tap '^M.s$'; sleep 2
      # «Registrar por voz» queda bajo el pliegue en «Más»: se desliza (con guarda).
      for _ in 1 2 3; do has 'Registrar por voz' && break; guard; adb shell input swipe 540 1700 540 700 400; sleep 1; done
      wait_for 'Registrar por voz' 5
    fi
    if ! has 'Productos, cantidades, precios y proveedor'; then
      tap 'Registrar por voz'; wait_for 'Compra por voz' 10
    fi
    [ "$dest" = voz ] && { echo "en «Registrar por voz»"; exit 0; }
    tap "$target"
    # El título del borrador repite el de la opción: se espera a que la lista
    # de opciones (su subtítulo) desaparezca.
    for _ in $(seq 1 10); do
      guard
      has 'Productos, cantidades, precios y proveedor' || { echo "en «$target»"; exit 0; }
      sleep 1
    done
    echo "la pantalla «$target» no se abrió"; exit 1
    ;;
  captura)
    guard
    # Privacidad: una captura de una pantalla de voz puede mostrar lo oído o lo
    # transcrito; para esas pantallas se usa `estado` (lista blanca).
    if has 'Hablar. Abre el micr|Terminar. El micr|Reconocedor:|Lo .ltimo que se oy|Completar por voz|Ocultar el panel de voz|Grabando|Procesando tu voz|Revisa los campos marcados|Deshacer .ltimo dictado'; then
      echo "ABORTADO: captura bloqueada en una pantalla de voz (use «voz»)"; exit 1
    fi
    mkdir -p "$RUN/capturas"; out="$RUN/capturas/${1:?nombre}.png"
    adb exec-out screencap -p > "$out"
    echo "$(sha256sum "$out" | awk '{print $1}')  $out"
    ;;
  microfono)
    need_installed
    uid=$(adb shell dumpsys package "$PKG" | tr -d '\r' | grep -m1 -o -E '(userId|appId)=[0-9]+' | cut -d= -f2 || true)
    echo "permiso RECORD_AUDIO: $(adb shell dumpsys package "$PKG" | tr -d '\r' | grep -m1 -o -E 'android.permission.RECORD_AUDIO: granted=[a-z]+' || echo 'no concedido ni solicitado')"
    echo "appops: $(adb shell appops get "$PKG" RECORD_AUDIO | tr -d '\r' | tr '\n' ' ')"
    echo "entradas de audio abiertas (audio_policy): $(adb shell dumpsys media.audio_policy | tr -d '\r' | grep -m1 -E '^ *Inputs \(' | sed 's/^ *//')"
    echo "grabaciones activas de uid $uid: $(adb shell dumpsys audio | tr -d '\r' | sed -n '/RecordActivityMonitor/,/Events log/p' | grep -c -E "uid:? ?$uid\b" || true)"
    echo "proceso vivo: $(adb shell pidof "$PKG" | tr -d '\r' | grep -c . || true)"
    echo "AVD: $(grep -E '^hw.audioInput' /c/Users/MSI/.android/avd/Pixel_8.avd/config.ini 2>/dev/null || echo 'config.ini no leído') (la entrada del host la activa sólo Roderich)"
    ;;
  base)
    need_installed
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    for f in $(adb exec-out run-as "$PKG" ls -1 databases 2>/dev/null | tr -d '\r' | grep -E "^${DB}(-wal|-shm|-journal)?$"); do
      adb exec-out run-as "$PKG" cat "databases/$f" > "$tmp/$f"
    done
    [ -s "$tmp/$DB" ] || { echo "base de $PKG ausente (¿no se ha abierto nunca?)"; exit 1; }
    py db "$tmp/$DB"
    ;;
  sembrar)
    account=${1:-${F09_ACCOUNT:-agricultor5}}
    case "$account" in agricultor2|agricultor6) echo "ABORTADO: $account lo usan «AC UX»/«AC VOZ»"; exit 1 ;; esac
    need_installed
    day=${DEMO_DATE:-2026-11-03}
    work="$RUN/seed"; rm -rf "$work"; mkdir -p "$work"
    adb shell am force-stop "$PKG"
    for f in $(adb exec-out run-as "$PKG" ls -1 databases | tr -d '\r' | grep -E "^${DB}(-wal|-shm|-journal)?$"); do
      adb exec-out run-as "$PKG" cat "databases/$f" > "$work/$f"
    done
    python -I -X utf8 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("PRAGMA wal_checkpoint(TRUNCATE)"); c.close()' "$work/$DB"
    rm -f "$work/$DB-wal" "$work/$DB-shm"
    cp "$work/$DB" "$work/$DB.antes"
    DEMO_PGPORT=${DEMO_PGPORT:-15432} bash "$DEMO_BE/tool/demo/demo.sh" references "$account" "$work/references.json"
    # El código de la siembra es el de la DEMO, pero se ejecuta con el código F09
    # (esquema v14): la base de `.f09` no se abre nunca con el esquema v13.
    seed_src="$DEMO_MOB/tool/demo/seed_demo_mobile.dart"
    mkdir -p "$F09_MOB/build/f09_emu"; cp "$seed_src" "$F09_MOB/build/f09_emu/seed_demo_mobile.dart"
    echo "siembra: $seed_src (DEMO-MOB $(git -C "$DEMO_MOB" rev-parse --short HEAD), sha256 $(sha256sum "$seed_src" | cut -c1-16)) con F09 $(git -C "$F09_MOB" rev-parse --short HEAD)"
    ( cd "$F09_MOB" && DEMO_DB="$(cygpath -w "$work/$DB")" DEMO_REFERENCES="$(cygpath -w "$work/references.json")" DEMO_DATE="$day" \
        flutter test build/f09_emu/seed_demo_mobile.dart 2>&1 | tee "$work/seed.log" | grep -E "DEMO_SUMMARY|All tests passed|Some tests failed|Expected|Actual|reason" ) || true
    grep -q "All tests passed" "$work/seed.log" || { echo "siembra local fallida: la base de $PKG no se tocó"; exit 1; }
    adb push "$(cygpath -w "$work/$DB")" "/data/local/tmp/f09_$DB" > /dev/null
    adb shell chmod 644 "/data/local/tmp/f09_$DB"
    adb shell run-as "$PKG" cp "/data/local/tmp/f09_$DB" "databases/$DB"
    adb shell run-as "$PKG" rm -f "databases/$DB-wal" "databases/$DB-shm" "databases/$DB-journal"
    adb shell rm -f "/data/local/tmp/f09_$DB"
    echo "base sembrada devuelta a $PKG (sha256 $(sha256sum "$work/$DB" | cut -c1-16)); copia previa en $work/$DB.antes"
    ;;
  red)
    case "${1:?on|off}" in
      off) adb shell svc wifi disable; adb shell svc data disable ;;
      on) adb shell svc wifi enable; adb shell svc data enable ;;
      *) echo "red on|off"; exit 2 ;;
    esac
    sleep 2
    echo "emulador: wifi=$(adb shell settings get global wifi_on | tr -d '\r') datos=$(adb shell settings get global mobile_data | tr -d '\r')"
    ;;
  *) sed -n '2,26p' "$0"; exit 2 ;;
esac
