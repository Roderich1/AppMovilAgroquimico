#!/usr/bin/env bash
# F03-RES-01 (#71): compila la app AISLADA (applicationId con sufijo) apuntando al
# origen HTTPS temporal, en un worktree Mobile desacoplado y limpio. El cambio de
# sufijo y etiqueta es temporal y se revierte al terminar; no se commitea.
#   build_isolated_apk.sh <worktree-mobile> [origen-https]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
wt="${1:?Ruta del worktree Mobile desacoplado}"
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
g.write_text(s.replace(anchor, anchor + f'        getByName("debug") {{\n            applicationIdSuffix = "{suffix}"\n        }}\n'), encoding='utf-8')
m = pathlib.Path(manifest); t = m.read_text(encoding='utf-8')
assert t.count('android:label="agroquimicos"') == 1, 'label no encontrado'
m.write_text(t.replace('android:label="agroquimicos"', f'android:label="{label}"'), encoding='utf-8')
PY
flutter build apk --debug --dart-define=AGRO_API_BASE_URL="$origin" > "$F03_RUN_DIR/apk_build.log" 2>&1 \
  || { tail -20 "$F03_RUN_DIR/apk_build.log"; exit 1; }
apk=build/app/outputs/flutter-apk/app-debug.apk
mkdir -p "$F03_RUN_DIR"
cp "$apk" "$F03_RUN_DIR/agrocuentas-f03res01-debug.apk"
echo "APK aislada: paquete $F03_APP_PACKAGE, Mobile $sha"
echo "SHA-256: $(sha256sum "$F03_RUN_DIR/agrocuentas-f03res01-debug.apk" | awk '{print $1}')"
git checkout -q -- "$gradle" "$manifest"; trap - EXIT
[ -z "$(git status --porcelain)" ] && echo "worktree Mobile limpio tras la compilación"
