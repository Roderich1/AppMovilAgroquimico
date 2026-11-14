#!/usr/bin/env bash
# Entorno AISLADO del modo individual (2026-11-13, derivado de rdm_env.sh): Central propia con datos
# exclusivamente SINTÉTICOS y la app «AC IND» (.ind) en el emulador. Deriva de
# _wt/ET2-BE/tool/etapa2/et2.sh, con contenedor, puertos y paquete propios.
# No toca la DEMO oficial (3330/5190, .demo), el entorno ET2 (15434/3350, .et1)
# ni ninguna otra app instalada. Los secretos sólo viven en variables del
# proceso de la API; no se imprimen ni se escriben en archivos.
#
#   ind_env.sh up            PostgreSQL 15438 (contenedor agro_ind_pg), API 3390
#   ind_env.sh seed          siembra «rica» por la API real (idempotente)
#   ind_env.sh verify        resumen de la siembra
#   ind_env.sh credential <rol>   teclea la contraseña de un solo uso en el campo enfocado del emulador
#   ind_env.sh tunnel | untunnel  origen HTTPS temporal → observador 3391 → compuerta 3392 → API 3390
#   ind_env.sh build-app     APK «AC IND» (.ind) profile x64 desde este worktree, con el origen del túnel
#   ind_env.sh install-app   adb install -r (conserva los datos de .ind)
#   ind_env.sh status | down
set -uo pipefail
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOB=$(cd "$here/../.." && pwd)
# Back CONGELADO propio (worktree detached _wt/RDM-BE): 5b394f2 (contrato de
# convocatorias 2 + P-C) hasta la noche del 2026-11-12; desde entonces 49ed870
# (P-A, contrato 3, migración 20261112180000_e2_pa_responsible_substitution),
# que corresponde a la rama F integrada en el rediseño (91f2e73). Desde el 2026-11-12 ya no se usa _wt/ET2-BE, que cambia
# con el trabajo de otra sesión. Sólo se ejecuta su dist.
BE=$ROOT/_wt/RDM-BE/Back
CENTRAL=$ROOT/_wt/DEMO-BE/tool/demo/demo-central.cjs
RICA=$ROOT/_wt/RDM-BE/tool/demo-rica/demo-rica.cjs
GATE_JS=$ROOT/_wt/RDM-BE/tool/etapa1/api_gate.cjs
TUNNEL=$ROOT/_wt/RICA-MOB/tool/f03_res_01/tunnel.sh
CLOUDFLARED=$ROOT/_wt/tools/cloudflared-2026.10.0/cloudflared-windows-amd64.exe
RUN=${IND_RUN:-/c/Users/MSI/AppData/Local/Temp/agro_ind}; mkdir -p "$RUN" "$RUN/photos" "$RUN/backups"
PG=agro_ind_pg; VOLUME=agro_ind_pgdata; PGPORT=15438; API=3390; OBS=3391; GATE=3392
SERIAL=${IND_SERIAL:-emulator-5556}; SUFFIX=.ind; LABEL="AC IND"; PKG=com.comunidad.agro.agroquimicos$SUFFIX
export DEMO_PG_ADMIN_URL="postgresql://postgres@127.0.0.1:${PGPORT}/postgres"
export DEMO_API="http://127.0.0.1:${API}/api/v1"
export DEMO_SEED="agrocuentas-individual-1"
stamp() { date -u +%FT%TZ; }
log() { echo "$(stamp) $*" | tee -a "$RUN/supervisor.log"; }
listener() { netstat -ano | awk -v p=":$1" '$2 ~ p"$" && $4 == "LISTENING" {print $5; exit}'; }
health() { curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API/api/v1/health"; }
rica() { ( cd "$BE" && node "$RICA" "$@" ); }
case "${1:-}" in
  up)
    if [ -z "$(docker ps -q --filter name="^${PG}$")" ]; then
      docker start "$PG" > /dev/null 2>&1 || docker run -d --name "$PG" -e POSTGRES_HOST_AUTH_METHOD=trust \
        -v "$VOLUME:/var/lib/postgresql/data" -p "127.0.0.1:$PGPORT:5432" postgres:16.13 > /dev/null || { log "no se pudo crear $PG"; exit 1; }
    fi
    for _ in $(seq 1 60); do docker exec "$PG" pg_isready -U postgres > /dev/null 2>&1 && break; sleep 1; done
    sleep 2
    ( cd "$BE" && node "$CENTRAL" bootstrap ) >> "$RUN/supervisor.log" 2>&1 || { log "bootstrap fallido"; tail -5 "$RUN/supervisor.log"; exit 1; }
    if [ -z "$(listener $API)" ]; then
      rnd() { openssl rand -base64 "$1" | tr -d '\r\n/+='; }
      JWT=$(rnd 48); JWTR=$(rnd 48); FP=$(rnd 48)
      ( cd "$BE" && env NODE_ENV=development PORT=$API \
          DATABASE_URL="postgresql://postgres@127.0.0.1:${PGPORT}/agro_demo?schema=public" \
          JWT_SECRET="$JWT" JWT_REFRESH_SECRET="$JWTR" JWT_EXPIRES_IN=15m JWT_REFRESH_EXPIRES_IN=7d \
          COOKIE_SECURE=false CORS_ORIGIN=http://127.0.0.1:5998 \
          SYNC_V1_FINGERPRINT_KEY="$FP" SYNC_V1_FINGERPRINT_KEY_VERSION=1 SYNC_V1_PRODUCTION_ADMISSION=enabled \
          COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic COLLECTIVE_SEALING=enabled \
          BACKUP_STORAGE_DIR="$(cygpath -w "$RUN/backups")" BACKUP_PRODUCTION_ADMISSION=disabled \
          PRODUCT_PHOTO_STORAGE_DIR="$(cygpath -w "$RUN/photos")" \
          ESTIMATION_WORKER_INTERVAL_MS=1000 \
          node dist/main.js >> "$RUN/api.log" 2>&1 ) &
      JWT=; JWTR=; FP=
    fi
    for _ in $(seq 1 90); do [ "$(health)" = 200 ] && break; sleep 1; done
    log "API $API: health $(health)"; log "listo" ;;
  seed) rica seed ;;
  verify) rica verify ;;
  credential) rica credential-adb "${2:?rol}" "$SERIAL" ;;
  tunnel)
    # Túnel → observador $OBS → compuerta $GATE (sólo /api/v1/) → API $API. Nada más se expone.
    if [ -z "$(listener $GATE)" ]; then
      ET1_GATE_PHOTO_FAIL_FILE="$(cygpath -w "$RUN/gate.photo-fail")" \
        nohup node "$(cygpath -w "$GATE_JS")" "$GATE" "$API" > "$RUN/gate.out" 2>&1 &
      echo $! > "$RUN/gate.pid"; sleep 1
    fi
    [ -n "$(listener $GATE)" ] || { echo "la compuerta $GATE no arrancó: no se abre el túnel"; exit 1; }
    F03_BE_DIR=$BE F03_CLOUDFLARED=$CLOUDFLARED F03_API_PORT=$GATE F03_OBSERVER_PORT=$OBS F03_RUN_DIR=$RUN \
      F03_PG_CONTAINER=$PG bash "$TUNNEL" ;;
  untunnel)
    for f in tunnel observer gate; do [ -f "$RUN/$f.pid" ] && kill "$(cat "$RUN/$f.pid")" 2>/dev/null; rm -f "$RUN/$f.pid"; done
    rm -f "$RUN/origin"; echo "túnel y observador cerrados" ;;
  build-app)
    origin=${IND_ORIGIN:-$(cat "$RUN/origin" 2>/dev/null || true)}; [ -n "$origin" ] || { echo "sin origen HTTPS: primero ind_env.sh tunnel"; exit 1; }
    cd "$MOB"
    gradle=android/app/build.gradle.kts; manifest=android/app/src/main/AndroidManifest.xml
    [ -z "$(git status --porcelain -- "$gradle" "$manifest")" ] || { echo "ABORTADO: $gradle o $manifest tienen cambios"; exit 1; }
    # Estado del árbol ANTES del parche temporal de gradle y manifiesto.
    short=$(git rev-parse --short HEAD); dirty=$([ -n "$(git status --porcelain --untracked-files=no)" ] && echo "+cambios" || true)
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
      --dart-define=AGRO_APP_COMMIT="$short$dirty" > "$RUN/apk/build.log" 2>&1 || { tail -20 "$RUN/apk/build.log"; exit 1; }
    cp build/app/outputs/flutter-apk/app-profile.apk "$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk"
    git checkout -q -- "$gradle" "$manifest"; trap - EXIT
    echo "APK $PKG · Mobile $(git rev-parse HEAD)$dirty · SHA-256 $(sha256sum "$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk" | awk '{print $1}')" ;;
  install-app)
    apk="$RUN/apk/agrocuentas$SUFFIX-profile-x64.apk"; [ -f "$apk" ] || { echo "falta la APK: 'ind_env.sh build-app'"; exit 1; }
    out=$(MSYS_NO_PATHCONV=1 adb -s "$SERIAL" install -r "$(cygpath -w "$apk")" 2>&1 | tr -d '')
    echo "$out" | tail -1
    echo "$out" | grep -qx "Success" && echo "instalado $PKG en $SERIAL" || { echo "NO instalado"; exit 1; } ;;
  status)
    echo "contenedor: $(docker ps --filter name="^${PG}$" --format '{{.Status}}' | head -1)"
    echo "API $API: $(health)"
    origin=$(cat "$RUN/origin" 2>/dev/null || true)
    [ -n "$origin" ] && echo "túnel: $(curl -s -o /dev/null -w '%{http_code}' "$origin/api/v1/health") (origen en $RUN/origin, no se publica)" || echo "túnel: cerrado"
    MSYS_NO_PATHCONV=1 adb -s "$SERIAL" shell pm list packages 2>/dev/null | grep -q "$PKG" && echo "app $PKG instalada en $SERIAL" || echo "app $PKG no instalada" ;;
  down)
    bash "$0" untunnel
    pid=$(listener $API); [ -n "$pid" ] && taskkill //PID "$pid" //F > /dev/null 2>&1
    docker stop "$PG" > /dev/null 2>&1; log "entorno IND detenido (volumen $VOLUME conservado)" ;;
  *) sed -n 2,17p "$0"; exit 2 ;;
esac
