#!/usr/bin/env bash
# F12-EST-07-MOB (#164): pruebas de integración en el teléfono físico.
# App AISLADA con sufijo temporal .est164 (se revierte y se desinstala al final);
# no toca ninguna otra instalación. Respuestas del servidor simuladas.
#   bash tool/f12_est_07/device_run.sh <worktree-mobile> <serial-adb> <carpeta-de-salida>
set -uo pipefail
wt="$1"; serial="$2"; out="$3"
mkdir -p "$out"
export MSYS_NO_PATHCONV=1
pkg=com.comunidad.agro.agroquimicos.est164
cd "$wt"
[ -z "$(git status --porcelain)" ] || { echo "El worktree no está limpio"; exit 1; }
sha=$(git rev-parse HEAD)
gradle=android/app/build.gradle.kts
stay=$(adb -s "$serial" shell settings get global stay_on_while_plugged_in | tr -d '\r')
restore() {
  git checkout -q -- "$gradle"
  adb -s "$serial" uninstall "$pkg" >/dev/null 2>&1 || true
  adb -s "$serial" shell settings put global stay_on_while_plugged_in "$stay"
}
trap restore EXIT
python -I - "$gradle" <<'PY'
import sys, pathlib
g = pathlib.Path(sys.argv[1]); s = g.read_text(encoding='utf-8')
anchor = '    buildTypes {\n'
if '\r\n' in s: anchor = anchor.replace('\n', '\r\n')
assert s.count(anchor) == 1, 'buildTypes no encontrado'
nl = '\r\n' if '\r\n' in s else '\n'
g.write_text(s.replace(anchor, anchor + f'        getByName("debug") {{{nl}            applicationIdSuffix = ".est164"{nl}        }}{nl}'), encoding='utf-8', newline='')
PY
{
  echo "mobile_sha=$sha"
  echo "dispositivo=$(adb -s "$serial" shell getprop ro.product.manufacturer | tr -d '\r') $(adb -s "$serial" shell getprop ro.product.model | tr -d '\r'), Android $(adb -s "$serial" shell getprop ro.build.version.release | tr -d '\r')"
  echo "paquete=$pkg (sufijo temporal, desinstalado al terminar)"
  echo "inicio=$(date -u +%FT%TZ)"
} > "$out/version.txt"
adb -s "$serial" shell settings put global stay_on_while_plugged_in 3
adb -s "$serial" shell input keyevent KEYCODE_WAKEUP
sleep 1
adb -s "$serial" shell input swipe 540 2000 540 700
flutter test integration_test/f12_est_07_estimation_device_test.dart -d "$serial" > "$out/flutter-test.log" 2>&1 &
pid=$!
taken=""
# MIUI pide confirmar la instalación por USB («Instalar vía USB») y la niega sola a los
# 10 s: se pulsa «Instalar» SÓLO en ese diálogo del sistema mientras se instala .est164.
confirm_install() {
  local node
  node=$(adb -s "$serial" exec-out uiautomator dump /dev/tty 2>/dev/null | grep -o '<node[^>]*>'     | grep -E 'package="com\.(miui\.securitycenter|android\.packageinstaller|google\.android\.packageinstaller)"'     | grep -m1 -E 'text="(Instalar|Install)"' || true)
  [ -n "$node" ] || return 0
  local b; b=$(echo "$node" | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | grep -o '[0-9]*' | tr '
' ' ')
  set -- $b
  adb -s "$serial" shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
  echo "$(date -u +%FT%TZ) diálogo de instalación por USB confirmado" >> "$out/version.txt"
}
while kill -0 "$pid" 2>/dev/null; do
  grep -q "Installing build" "$out/flutter-test.log" 2>/dev/null && ! grep -q "CAPTURA:\|+1:" "$out/flutter-test.log" 2>/dev/null && confirm_install
  for name in $(grep -o 'CAPTURA:[0-9a-z-]*' "$out/flutter-test.log" 2>/dev/null | cut -d: -f2); do
    case " $taken " in *" $name "*) continue ;; esac
    sleep 1
    adb -s "$serial" exec-out screencap -p > "$out/$name.png"
    taken="$taken $name"
  done
  sleep 1
done
wait "$pid"; status=$?
echo "fin=$(date -u +%FT%TZ)" >> "$out/version.txt"
echo "exit=$status" >> "$out/version.txt"
grep -E "All tests passed|Some tests failed|\+[0-9]+.*: |RESPALDO:" "$out/flutter-test.log" | tail -12
exit $status
