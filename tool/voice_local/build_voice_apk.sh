#!/usr/bin/env bash
# APK de prueba de la voz local, en un paquete aislado (`.voz`, «AC VOZ»).
#
#   bash tool/voice_local/build_voice_apk.sh <x64|arm64> <carpeta-salida>
#
# Requiere antes `fetch_voice_models.sh` y `build_whisper_libs.sh`: el APK lleva
# los modelos dentro y no necesita conexión para el primer dictado. Es una
# compilación *profile* firmada con la clave de depuración: sirve para probar,
# no para distribuir. El sufijo y la etiqueta se aplican sólo durante la
# compilación y los archivos versionados se restauran al terminar.
set -euo pipefail

ABI=${1:?x64|arm64}; OUT=${2:?carpeta}
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
case "$ABI" in
  x64) PLATFORM=android-x64; SPLIT=x86_64 ;;
  arm64) PLATFORM=android-arm64; SPLIT=arm64-v8a ;;
  *) echo "ABI: x64 o arm64" >&2; exit 2 ;;
esac
[ -f android/app/voice-models/voice/manifest.json ] || { echo "faltan los modelos: fetch_voice_models.sh" >&2; exit 1; }
[ -f "android/app/src/main/jniLibs/$SPLIT/libagro_whisper.so" ] || echo "AVISO: sin libagro_whisper.so para $SPLIT; la segunda pasada quedará no disponible" >&2

gradle=android/app/build.gradle.kts; manifest=android/app/src/main/AndroidManifest.xml
# Se restaura desde una copia, no desde git: así no se pierde ningún cambio
# local sin commit de esos archivos.
BACKUP=$(mktemp -d)
cp "$gradle" "$BACKUP/gradle"; cp "$manifest" "$BACKUP/manifest"
restore() { cp "$BACKUP/gradle" "$gradle"; cp "$BACKUP/manifest" "$manifest"; rm -rf "$BACKUP"; }
trap restore EXIT
python -I - "$gradle" "$manifest" <<'PY'
import sys, pathlib
gradle, manifest = sys.argv[1:3]
g = pathlib.Path(gradle); s = g.read_text(encoding='utf-8'); nl = '\r\n' if '\r\n' in s else '\n'
anchor = '    buildTypes {' + nl
assert s.count(anchor) == 1
g.write_text(s.replace(anchor, anchor + f'        getByName("profile") {{{nl}            applicationIdSuffix = ".voz"{nl}        }}{nl}'), encoding='utf-8', newline='')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
assert t.count('android:label="agroquimicos"') == 1
m.write_text(t.replace('android:label="agroquimicos"', 'android:label="AC VOZ"'), encoding='utf-8', newline='')
PY
mkdir -p "$OUT"
# Origen HTTPS del Central (opcional): sólo hace falta para activar la
# instalación; el dictado no lo usa.
flutter build apk --profile --split-per-abi --target-platform "$PLATFORM" \
  ${AGRO_API_BASE_URL:+--dart-define=AGRO_API_BASE_URL="$AGRO_API_BASE_URL"} > "$OUT/build-$ABI.log" 2>&1 \
  || { tail -30 "$OUT/build-$ABI.log"; exit 1; }
restore; trap - EXIT
# El modelo de revisión empaquetado (fetch_voice_models.sh base|small|none).
# Con base el nombre no cambia; con otro, lo lleva para no confundirlas.
REVIEW=$(python -I -c "import json,sys; w=json.load(open(sys.argv[1],encoding='utf-8')).get('whisper'); print(w.get('variant') or w['name'].split('-')[1] if w else 'none')" android/app/voice-models/voice/manifest.json)
TAG=""; [ "$REVIEW" = base ] || TAG="-review-$REVIEW"
APK="$OUT/agrocuentas-voz-$(git rev-parse --short HEAD)-$SPLIT$TAG-profile.apk"
cp "build/app/outputs/flutter-apk/app-$SPLIT-profile.apk" "$APK"
echo "APK $APK"
echo "Revisión $REVIEW"
echo "Mobile $(git rev-parse HEAD)$( [ -n "$(git status --porcelain --untracked-files=no)" ] && echo ' + cambios sin commit')"
echo "SHA-256 $(sha256sum < "$APK" | awk '{print $1}') · $(stat -c %s "$APK") B"
