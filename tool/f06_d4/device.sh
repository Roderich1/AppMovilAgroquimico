#!/usr/bin/env bash
# F06 (D4): ruta física del agricultor 1 en la copia aislada `.f06d4` del teléfono.
# Reutiliza los scripts de F03-RES-01 con el paquete, los puertos y la carpeta de
# D4 (la app normal y la copia .f03res01 no se tocan).
#   device.sh tunnel | tunnel-stop   túnel HTTPS temporal hacia la API 3201 (sólo en la sesión)
#   device.sh apk <worktree-limpio>  APK aislada con el origen del túnel
#   device.sh seed                   siembra en el host la base del agricultor 1 con la
#                                    referencia de instalación de la copia y la copia al teléfono
#   device.sh password               contraseña nueva de un solo uso para el agricultor 1
#                                    (base del teléfono), tecleada en el campo enfocado
#   device.sh logcat-start | logcat-scan   buffer ampliado y escaneo sólo con conteos
#   device.sh central                aportaciones de Central del agricultor 1 frente al oráculo
#   device.sh <otro>                 lo resuelve tool/f03_res_01/device.sh (ui, tap, shot, db, ...)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
f03="$here/../f03_res_01"
export F03_BE_DIR="$F06_BE_DIR" F03_CLOUDFLARED="${F06_CLOUDFLARED:-unused}"
export F03_RUN_DIR="$F06_RUN_DIR/device" F03_APP_ID_SUFFIX="$F06_APP_ID_SUFFIX" F03_APP_LABEL="$F06_APP_LABEL"
export F03_API_PORT="$F06_API_PORT_DEVICE" F03_OBSERVER_PORT=3202
mkdir -p "$F03_RUN_DIR"
pkg="$F06_APP_PACKAGE"
adb() { MSYS_NO_PATHCONV=1 command adb "$@"; }
in_app() { adb exec-out run-as "$pkg" "$@"; }

# Patrones del escaneo (addendum de #71): JWT, UUID, valores opacos base64url de
# 43 o más caracteres (refresh tokens) y nombres de campos sensibles sin
# distinguir mayúsculas. Sólo se imprimen conteos.
scan() { # etiqueta, texto por stdin
  local text; text="$(cat)"
  printf '%s: líneas=%s JWT=%s UUID=%s opacos43=%s campos=%s FATAL=%s\n' "$1" \
    "$(grep -c . <<< "$text" || true)" \
    "$(grep -c -E 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' <<< "$text" || true)" \
    "$(grep -c -E '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' <<< "$text" || true)" \
    "$(grep -c -E '[A-Za-z0-9_-]{43,}' <<< "$text" || true)" \
    "$(grep -c -i -E 'authorization|bearer|password|passwd|refresh_?token|access_?token|set-cookie|client_?id' <<< "$text" || true)" \
    "$(grep -c -E 'FATAL|Unhandled Exception' <<< "$text" || true)"
}

case "${1:-}" in
  tunnel) bash "$f03/tunnel.sh" ;;
  tunnel-stop)
    for p in tunnel observer; do
      f="$F03_RUN_DIR/$p.pid"
      [ -f "$f" ] && kill "$(cat "$f")" 2> /dev/null && echo "$p detenido" || true
      rm -f "$f"
    done
    rm -f "$F03_RUN_DIR/origin"
    ;;
  apk) bash "$f03/build_isolated_apk.sh" "${2:?worktree Mobile limpio}" ;;
  seed)
    adb shell pm list packages | tr -d '\r' | grep -qx "package:$pkg" || { echo "copia aislada no instalada"; exit 1; }
    adb shell am force-stop "$pkg"
    client_id="$(in_app cat no_backup/client_id | tr -d '\r\n')"
    [[ "$client_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] ||
      { echo "la copia aún no creó su identidad de instalación: ábrala una vez"; exit 1; }
    ids="$(f06_psql "SELECT m.id || ' ' || m.\"tenantId\" FROM \"Member\" m JOIN \"User\" u ON u.id = m.\"userId\" WHERE u.email = '$F06_F1_EMAIL'" "$F06_DB_DEVICE")"
    bash "$here/references_json.sh" "$F06_DB_DEVICE" > "$F03_RUN_DIR/references.json"
    out="$F03_RUN_DIR/seed_$(date -u +%Y%m%dT%H%M%SZ).db"
    (
      cd "$here/../.."
      AGRO_F06_DEVICE_DB_OUT="$out" AGRO_F06_REFS_JSON="$F03_RUN_DIR/references.json" \
        AGRO_F06_CLIENT_ID="$client_id" AGRO_F06_MEMBER_ID="${ids% *}" AGRO_F06_TENANT_ID="${ids#* }" \
        flutter test tool/f06_d4/seed_device_db_test.dart --reporter expanded 2>&1 |
        grep -E '^  |All tests|Some tests|\[E\]|Exception'
    )
    [ -s "$out" ] || { echo "no se generó la base"; exit 1; }
    for suffix in -wal -shm -journal; do in_app rm -f "databases/$F06_DEVICE_DB$suffix"; done
    adb exec-in run-as "$pkg" sh -c "cat > databases/$F06_DEVICE_DB" < "$out"
    local_sha="$(sha256sum "$out" | cut -d' ' -f1)"
    device_sha="$(in_app cat "databases/$F06_DEVICE_DB" | sha256sum | cut -d' ' -f1)"
    echo "base sembrada: SHA-256 host=$local_sha teléfono=$device_sha $([ "$local_sha" = "$device_sha" ] && echo IGUALES || echo DISTINTOS)"
    [ "$local_sha" = "$device_sha" ]
    ;;
  password)
    password="$(f06_rand 18)"
    export F06_DEVICE_F1_PASSWORD="$password"
    F06_BE_DIR="$F06_BE_DIR" node "$here/rotate_passwords.cjs" "$F06_F1_EMAIL=F06_DEVICE_F1_PASSWORD" |
      docker exec -i "$F06_PG_CONTAINER" psql -U postgres -d "$F06_DB_DEVICE" -q -v ON_ERROR_STOP=1 > /dev/null
    adb shell input text "$password"
    echo "contraseña nueva del agricultor 1 tecleada en el teléfono (no se muestra; la anterior deja de servir)"
    ;;
  logcat-start)
    before="$(adb logcat -g 2> /dev/null | tr -d '\r' | head -1)"
    adb logcat -G 16M
    echo "buffer de logcat ampliado a 16M (antes: $before)"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$F03_RUN_DIR/logcat_since"
    ;;
  logcat-scan)
    uid="$(adb shell pm list packages -U "$pkg" | grep -o -E 'uid:[0-9]+' | head -1 | cut -d: -f2)"
    adb logcat -d --uid="$uid" | scan "logcat (uid de la copia)"
    in_app cat app_flutter/agrocuentas.log 2> /dev/null | scan "registro propio"
    ;;
  central)
    bash "$here/central_dump.sh" "$F06_DB_DEVICE" > "$F03_RUN_DIR/central_contributions.csv"
    cd "$here/../.."
    python -I "$here/oracle_check.py" docs/evidence --central "$F03_RUN_DIR/central_contributions.csv" --only F1
    ;;
  *) bash "$f03/device.sh" "$@" ;;
esac
