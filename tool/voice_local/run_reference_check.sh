#!/usr/bin/env bash
# Inferencia real del motor de voz local con audio de referencia, en el EMULADOR.
#
#   bash tool/voice_local/run_reference_check.sh <carpeta-wav> <carpeta-salida> [Clase#metodo]
#
# 1. Compila la app (profile, x86_64, paquete aislado `.voz`) y su APK de prueba
#    instrumentada, con el sufijo aplicado sólo durante la compilación.
# 2. Instala ambas con `adb install -r` (conserva los datos de `.voz`; no
#    desinstala nada ni toca otros paquetes).
# 3. Copia los WAV a los archivos externos de `.voz`, ejecuta
#    `LocalVoiceEngineReferenceTest` con `am instrument` y trae los resultados.
#
# Los tiempos describen el emulador de este PC, no un teléfono.
set -euo pipefail
WAV=${1:?carpeta-wav}; OUT=${2:?carpeta-salida}; ONLY=${3:-}
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export MSYS2_ARG_CONV_EXCL="/sdcard;/data/local;/dev/tty"
PKG=com.comunidad.agro.agroquimicos.voz
mkdir -p "$OUT"

gradle=android/app/build.gradle.kts; manifest=android/app/src/main/AndroidManifest.xml
BACKUP=$(mktemp -d)
cp "$gradle" "$BACKUP/gradle"; cp "$manifest" "$BACKUP/manifest"
ASSETS=android/app/src/androidTest/assets/ref
restore() { cp "$BACKUP/gradle" "$gradle"; cp "$BACKUP/manifest" "$manifest"; rm -rf "$BACKUP" "$(dirname "$ASSETS")"; }
trap restore EXIT
# El audio de referencia viaja como assets del APK de PRUEBA, no de la app.
mkdir -p "$ASSETS"; cp "$WAV"/*.wav "$ASSETS/"
python -I - "$gradle" "$manifest" <<'PY'
import sys, pathlib
gradle, manifest = sys.argv[1:3]
g = pathlib.Path(gradle); s = g.read_text(encoding='utf-8'); nl = '\r\n' if '\r\n' in s else '\n'
anchor = '    buildTypes {' + nl
assert s.count(anchor) == 1
s = s.replace(anchor, f'    testBuildType = "profile"{nl}' + anchor + f'        getByName("profile") {{{nl}            applicationIdSuffix = ".voz"{nl}        }}{nl}')
g.write_text(s, encoding='utf-8', newline='')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
m.write_text(t.replace('android:label="agroquimicos"', 'android:label="AC VOZ"'), encoding='utf-8', newline='')
PY
(cd android && ./gradlew -q :app:assembleProfile :app:assembleProfileAndroidTest \
  -Ptarget-platform=android-x64 -Psplit-per-abi=true) > "$OUT/gradle.log" 2>&1 \
  || { tail -40 "$OUT/gradle.log"; exit 1; }
restore; trap - EXIT

APP=$(ls build/app/outputs/apk/profile/*x86_64*profile.apk 2>/dev/null | head -1)
[ -n "$APP" ] || APP=$(ls build/app/outputs/apk/profile/*.apk | head -1)
TEST=$(ls build/app/outputs/apk/androidTest/profile/*.apk | head -1)
adb install -r "$(cygpath -w "$APP")" | tail -1
adb install -r -t "$(cygpath -w "$TEST")" | tail -1

EXT=/sdcard/Android/data/$PKG/files
# La carpeta externa la crea la propia app; una creada por el shell no le
# pertenece y no podría escribir en ella. Sólo contiene resultados de esto.
adb shell rm -rf "$EXT"
adb logcat -c 2>/dev/null || true
CLASS=com.comunidad.agro.agroquimicos.LocalVoiceEngineReferenceTest
adb shell am instrument -w -r -e class "$CLASS${ONLY:+#$ONLY}" \
  "$PKG.test/androidx.test.runner.AndroidJUnitRunner" > "$OUT/instrument.txt" 2>&1 || true
adb pull "$EXT/ref-results.jsonl" "$(cygpath -w "$OUT/ref-results.jsonl")" > /dev/null 2>&1 || true
adb logcat -d | grep -E 'AgroVoz|FATAL|UnsatisfiedLink|ANR in' > "$OUT/logcat.txt" || true
# El APK de prueba (con el audio de referencia) se desinstala: no queda audio.
adb uninstall "$PKG.test" > /dev/null 2>&1 || true
grep -E 'INSTRUMENTATION_STATUS: test=|INSTRUMENTATION_STATUS_CODE|^OK|FAILURES|Tests run' "$OUT/instrument.txt" | tail -12
echo "app $(sha256sum < "$APP" | awk '{print $1}') · Mobile $(git rev-parse --short HEAD)"
