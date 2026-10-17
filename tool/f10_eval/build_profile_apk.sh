#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §0.5): compila la app AISLADA en modo PROFILE
# (el modo debug no sirve para medir tiempos) apuntando al origen HTTPS temporal,
# en un worktree Mobile limpio. Como tool/f03_res_01/build_isolated_apk.sh, el
# cambio de sufijo y etiqueta es temporal y se revierte al terminar; no se
# commitea. El tipo `profile` lo crea el plugin de Flutter con initWith(debug):
# hereda la firma local de depuración, así que la APK sólo sirve para este
# ensayo y no es distribuible.
#   build_profile_apk.sh <worktree-mobile> [origen-https]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../f03_res_01/config.sh"
wt="${1:?Ruta del worktree Mobile limpio}"
origin="${2:-$(f03_origin)}"
[ -n "$origin" ] || { echo "sin origen HTTPS"; exit 1; }
cd "$wt"
[ -z "$(git status --porcelain)" ] || { echo "El worktree no está limpio"; exit 1; }
sha=$(git rev-parse HEAD)

gradle=android/app/build.gradle.kts
manifest=android/app/src/main/AndroidManifest.xml
trap 'git checkout -q -- "$gradle" "$manifest"' EXIT
python -I - "$gradle" "$manifest" "$F03_APP_ID_SUFFIX" "$F03_APP_LABEL" <<'PY'
import sys, pathlib
gradle, manifest, suffix, label = sys.argv[1:5]
g = pathlib.Path(gradle); s = g.read_text(encoding='utf-8')
anchor = '    buildTypes {\n'
assert s.count(anchor) == 1, 'buildTypes no encontrado'
g.write_text(s.replace(anchor, anchor + f'        getByName("profile") {{\n            applicationIdSuffix = "{suffix}"\n        }}\n'), encoding='utf-8', newline='\n')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
assert t.count('android:label="agroquimicos"') == 1, 'label no encontrado'
m.write_text(t.replace('android:label="agroquimicos"', f'android:label="{label}"'), encoding='utf-8', newline='\n')
PY
mkdir -p "$F03_RUN_DIR"
flutter build apk --profile --dart-define=AGRO_API_BASE_URL="$origin" > "$F03_RUN_DIR/apk_build_profile.log" 2>&1 \
  || { tail -20 "$F03_RUN_DIR/apk_build_profile.log"; exit 1; }
apk=build/app/outputs/flutter-apk/app-profile.apk
out="$F03_RUN_DIR/agrocuentas${F03_APP_ID_SUFFIX//./-}-profile.apk" # .f10eval → agrocuentas-f10eval-profile.apk
cp "$apk" "$out"
echo "APK aislada (profile): paquete $F03_APP_PACKAGE, Mobile $sha"
echo "SHA-256: $(sha256sum "$out" | awk '{print $1}')"
git checkout -q -- "$gradle" "$manifest"; trap - EXIT
[ -z "$(git status --porcelain)" ] && echo "worktree Mobile limpio tras la compilación"
