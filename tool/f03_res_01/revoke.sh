#!/usr/bin/env bash
# F03-RES-01 (#71): acciones remotas reales del caso E, por HTTPS.
#   revoke.sh e1      E-1: el Administrador desactiva la cuenta D (PATCH users/{id}/deactivate)
#   revoke.sh e2      E-2: la propia cuenta E2 revoca sus registros de cliente ACTIVE
#                     (POST auth/clients/{id}/revoke). Irreversible para esa instalación.
# Sólo muestra códigos HTTP y conteos. Cierra las sesiones de curl que abre.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
origin="$(f03_origin)"; [ -n "$origin" ] || { echo "sin túnel"; exit 1; }

login() { # $1 email, $2 contraseña -> exporta ACCESS y REFRESH
  local body response
  body=$(EMAIL="$1" PASSWORD="$2" node -e \
    'process.stdout.write(JSON.stringify({email:process.env.EMAIL,password:process.env.PASSWORD,refreshTransport:"BODY"}))')
  response=$(curl -s -H 'Content-Type: application/json' --data-binary @- \
    "$origin/api/v1/auth/v2/login" <<< "$body")
  ACCESS=$(node "$here/json.cjs" get accessToken <<< "$response")
  REFRESH=$(node "$here/json.cjs" get refreshToken <<< "$response")
  [ -n "$ACCESS" ] || { echo "login de la sesión auxiliar falló"; exit 1; }
}
# La cabecera viaja como configuración de curl por stdin, no en los argumentos.
auth_config() { printf 'header = "Authorization: Bearer %s"\n' "$ACCESS"; }
logout() {
  REFRESH="$REFRESH" node -e 'process.stdout.write(JSON.stringify({refreshToken:process.env.REFRESH}))' \
    | curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
      --data-binary @- "$origin/api/v1/auth/v2/logout" > "$F03_RUN_DIR/.logout_code"
  echo "logout de la sesión auxiliar: HTTP $(cat "$F03_RUN_DIR/.logout_code")"
  rm -f "$F03_RUN_DIR/.logout_code"
}

case "${1:-}" in
  e1)
    : "${F03_ADMIN_PASSWORD:?Ejecute antes: source secrets.sh}"
    user_id=$(f03_psql "SELECT id FROM \"User\" WHERE email='$F03_FARMER_D_EMAIL'")
    login "$F03_ADMIN_EMAIL" "$F03_ADMIN_PASSWORD"
    code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
      -K - "$origin/api/v1/users/$user_id/deactivate" <<< "$(auth_config)")
    echo "E-1 desactivación de la cuenta D: HTTP $code"
    logout
    ;;
  e2)
    : "${F03_FARMER_E2_PASSWORD:?Ejecute antes: source secrets.sh}"
    login "$F03_FARMER_E2_EMAIL" "$F03_FARMER_E2_PASSWORD"
    list=$(curl -s -K - "$origin/api/v1/auth/clients" <<< "$(auth_config)")
    revoked=0
    while read -r id status; do
      [ "$status" = "ACTIVE" ] || continue
      code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -K - \
        "$origin/api/v1/auth/clients/$id/revoke" <<< "$(auth_config)")
      echo "E-2 revocación de un registro de cliente: HTTP $code"
      revoked=$((revoked + 1))
    done < <(node "$here/json.cjs" ids <<< "$list")
    echo "registros ACTIVE revocados: $revoked"
    logout
    ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac
