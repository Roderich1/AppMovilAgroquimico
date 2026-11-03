#!/usr/bin/env bash
# F12-EST-07-MOB (#164): control del ensayo Android contra el Backend REAL (Central propio
# y desechable de est164_supervisor.sh, datos sintéticos). Paquete AISLADO .est164 en el
# POCO (cc14247a); nunca toca la app normal ni otras copias.
#   est164.sh tunnel|untunnel     quick tunnel de cloudflared → observador 3301 → API 3300
#   est164.sh mode provisional|pending   el supervisor reinicia la API con esa política
#   est164.sh hide|show           la campaña de invierno pasa al sindicato B o vuelve (404 real)
#   est164.sh build <sha>         APK profile arm64 del HEAD exacto con el origen del túnel
#   est164.sh install|uninstall   sólo .est164
#   est164.sh credential          contraseña de UN solo uso del Agricultor sintético, tecleada
#                                 SÓLO si el campo enfocado es de contraseña; no se muestra
#   est164.sh db <consulta>       copia temporal de la base de la app (device.sh db)
#   est164.sh requests            peticiones vistas por el observador (método, ruta, estado)
#   est164.sh <ui|start|stop|tap|tapxy|key|text|shot|net> …   device.sh
set -euo pipefail
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
MOB=${EST_MOB:-$ROOT/_wt/F12-EST-07-MOB}
BE=${EST_BE:-$ROOT/_wt/F12-EST-07/Back}
RUN=/c/Users/MSI/AppData/Local/Temp/agro_f12_est164
export ANDROID_SERIAL=${EST_SERIAL:-cc14247a}
SUFFIX=.est164; LABEL="AC EST164"; PKG=com.comunidad.agro.agroquimicos$SUFFIX
export F03_BE_DIR=$BE F03_CLOUDFLARED=$ROOT/_wt/tools/cloudflared-2026.10.0/cloudflared-windows-amd64.exe
export F03_API_PORT=3300 F03_OBSERVER_PORT=3301 F03_RUN_DIR=$RUN F03_PG_CONTAINER=agro_f12_est164_pg
export F03_APP_ID_SUFFIX=$SUFFIX F03_APP_LABEL="$LABEL" F03_SHOTS_DIR=$RUN/capturas
dev="$MOB/tool/f03_res_01/device.sh"
foreground() { adb shell dumpsys activity activities 2>/dev/null | grep -m1 -E "topResumedActivity|mResumedActivity" | tr -d '\r'; }
require_foreground() {
  foreground | grep -q "$PKG/" || { echo "ABORTADO: el primer plano no es $PKG"; exit 3; }
}
cmd=${1:?orden}; shift || true
case "$cmd" in ui|tap|tapxy|key|text|shot|credential) require_foreground ;; esac
case "$cmd" in
  tunnel) bash "$MOB/tool/f03_res_01/tunnel.sh" ;;
  untunnel)
    for f in tunnel observer; do
      [ -f "$RUN/$f.pid" ] && kill "$(cat "$RUN/$f.pid")" 2>/dev/null || true; rm -f "$RUN/$f.pid"
    done
    echo "túnel y observador cerrados" ;;
  mode)
    m=${1:?provisional|pending}; echo "$m" > "$RUN/mode"
    for _ in $(seq 1 90); do grep -q "API en modo $m" "$RUN/supervisor.log" 2>/dev/null && [ "$(tail -1 "$RUN/supervisor.log" | grep -c "modo $m: health 200")" = 1 ] && break; sleep 1; done
    tail -1 "$RUN/supervisor.log" ;;
  hide|show)
    ( cd "$BE" && PG_ADMIN_URL="postgresql://postgres@127.0.0.1:55499/postgres" node ../docs/evidence/f12_est_07/control-sintetico.cjs "$cmd-target" "$RUN/ids.json" )
    echo "campaña de invierno: $cmd" ;;
  build)
    sha=${1:?sha}; origin=$(cat "$RUN/origin" 2>/dev/null || true)
    [ -n "$origin" ] || { echo "sin origen HTTPS: primero 'est164.sh tunnel'"; exit 1; }
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
    flutter build apk --profile --target-platform android-arm64 --dart-define=AGRO_API_BASE_URL="$origin" \
      > "$RUN/apk/build.log" 2>&1 || { tail -20 "$RUN/apk/build.log"; exit 1; }
    cp build/app/outputs/flutter-apk/app-profile.apk "$RUN/apk/agrocuentas$SUFFIX-profile-arm64.apk"
    git checkout -q -- "$gradle" "$manifest"; trap - EXIT
    echo "APK $PKG · Mobile $(git rev-parse HEAD) · SHA-256 $(sha256sum "$RUN/apk/agrocuentas$SUFFIX-profile-arm64.apk" | awk '{print $1}')"
    [ -z "$(git status --porcelain --untracked-files=no)" ] && echo "archivos versionados intactos" ;;
  install)
    apk="$RUN/apk/agrocuentas$SUFFIX-profile-arm64.apk"; [ -f "$apk" ] || { echo "falta la APK"; exit 1; }
    adb install -r "$(cygpath -w "$apk")" | tail -1
    echo "instalado $PKG; SHA-256 de la APK $(sha256sum "$apk" | awk '{print $1}')" ;;
  uninstall) adb uninstall "$PKG" && echo "desinstalado $PKG (sólo ese paquete)" ;;
  credential)
    focused=$(adb exec-out uiautomator dump /dev/tty 2>/dev/null | grep -o '<node[^>]*>' | grep 'class="android.widget.EditText"' | grep 'focused="true"' | head -1)
    echo "$focused" | grep -q 'password="true"' || { echo "ABORTADO: el campo enfocado no es de contraseña"; exit 3; }
    email=$(node -e "process.stdout.write(require(process.argv[1]).farmerEmail)" "$(cygpath -w "$RUN/ids.json")")
    password=$(openssl rand -base64 18 | tr -d '\r\n/+=')
    hash=$(PASSWORD="$password" node -e 'process.stdout.write(require(process.argv[1]).hashSync(process.env.PASSWORD, 10))' "$(cygpath -m "$BE/node_modules/bcrypt")")
    db=$(node -e "process.stdout.write(require(process.argv[1]).database)" "$(cygpath -w "$RUN/ids.json")")
    updated=$(printf "UPDATE \"User\" SET \"passwordHash\" = '%s' WHERE email = '%s';\n" "$hash" "$email" | docker exec -i agro_f12_est164_pg psql -U postgres -d "$db" -At)
    [ "$updated" = "UPDATE 1" ] || { password=; echo "no se pudo asignar la contraseña"; exit 1; }
    MSYS_NO_PATHCONV=1 adb shell input text "$password"; password=
    echo "contraseña de un solo uso del Agricultor sintético tecleada (no se muestra ni se guarda)" ;;
  email) node -e "process.stdout.write(require(process.argv[1]).farmerEmail)" "$(cygpath -w "$RUN/ids.json")" ;;
  requests) cat "$RUN/requests.log" ;;
  *) exec bash "$dev" "$cmd" "$@" ;;
esac
