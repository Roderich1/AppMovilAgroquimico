#!/usr/bin/env bash
# Validación de servidor (sin teléfono, sin túnel): una sesión EXISTENTE recibe
# 401 en su refresh después de E-1 (desactivación) y de E-2 (revocación del
# registro de cliente al que está ligada). Sólo imprime códigos y conteos.
# No sustituye el ensayo en dispositivo: no comprueba la reacción de la app.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./config.sh
api="$(f03_api_local)"
J() { node json.cjs "$@"; }
cfg() { printf 'header = "Authorization: Bearer %s"\n' "$1"; }

login() { # $1 email, $2 contraseña -> ACCESS, REFRESH (globales)
  local body r
  body=$(EMAIL="$1" PASSWORD="$2" node -e \
    'process.stdout.write(JSON.stringify({email:process.env.EMAIL,password:process.env.PASSWORD,refreshTransport:"BODY"}))')
  r=$(curl -s -H 'Content-Type: application/json' --data-binary @- \
    "$api/api/v1/auth/v2/login" <<< "$body")
  ACCESS=$(J get accessToken <<< "$r")
  REFRESH=$(J get refreshToken <<< "$r")
}

do_refresh() { # usa y rota REFRESH (global); deja el código en CODE
  local body out json next
  body=$(REFRESH="$REFRESH" node -e \
    'process.stdout.write(JSON.stringify({refreshToken:process.env.REFRESH}))')
  out=$(curl -s -w '\n%{http_code}' -H 'Content-Type: application/json' \
    --data-binary @- "$api/api/v1/auth/v2/refresh" <<< "$body")
  CODE="${out##*$'\n'}"
  json="${out%$'\n'*}"
  next=$(J get refreshToken <<< "$json")
  if [ -n "$next" ]; then REFRESH="$next"; fi
}

echo "== E-1: sesión existente de la cuenta D"
login "$F03_FARMER_D_EMAIL" "$F03_FARMER_D_PASSWORD"
do_refresh; echo "refresh previo de la sesión existente: HTTP $CODE"
D_REFRESH="$REFRESH"
login "$F03_ADMIN_EMAIL" "$F03_ADMIN_PASSWORD"; ADMIN_ACCESS="$ACCESS"
uid=$(f03_psql "SELECT id FROM \"User\" WHERE email='$F03_FARMER_D_EMAIL'")
code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -K - \
  "$api/api/v1/users/$uid/deactivate" <<< "$(cfg "$ADMIN_ACCESS")")
echo "E-1 desactivación: HTTP $code"
REFRESH="$D_REFRESH"; do_refresh
echo "refresh de la MISMA sesión existente tras E-1: HTTP $CODE"
./check.sh state D

echo "== E-2: sesión existente de E2 ligada a un registro de cliente"
login "$F03_FARMER_E2_EMAIL" "$F03_FARMER_E2_PASSWORD"
E2_ACCESS="$ACCESS"
cid=$(node -e 'process.stdout.write(require("crypto").randomUUID())')
reg=$(curl -s -H 'Content-Type: application/json' --data "{\"clientId\":\"$cid\"}" \
  -K - "$api/api/v1/auth/clients" <<< "$(cfg "$E2_ACCESS")")
rid=$(J get registrationId <<< "$reg")
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  --data "{\"registrationId\":\"$rid\"}" -K - \
  "$api/api/v1/auth/v2/session/client" <<< "$(cfg "$E2_ACCESS")")
echo "sesión ligada al registro: HTTP $code"
do_refresh; echo "refresh previo de la sesión ligada: HTTP $CODE"
LINKED_REFRESH="$REFRESH"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -K - \
  "$api/api/v1/auth/clients/$rid/revoke" <<< "$(cfg "$E2_ACCESS")")
echo "E-2 revocación del registro: HTTP $code"
REFRESH="$LINKED_REFRESH"; do_refresh
echo "refresh de la MISMA sesión ligada tras E-2: HTTP $CODE"
./check.sh state E2
unset ACCESS REFRESH D_REFRESH LINKED_REFRESH ADMIN_ACCESS E2_ACCESS
