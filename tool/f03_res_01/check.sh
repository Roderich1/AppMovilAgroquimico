#!/usr/bin/env bash
# F03-RES-01 (#71): comprobaciones sin valores sensibles.
#   check.sh health            health local y por HTTPS
#   check.sh login <D|E2>      login V2 BODY de la cuenta por HTTPS; muestra HTTP y claves
#                              de la respuesta, y cierra esa sesión de curl (logout)
#   check.sh state <D|E2>      estado en PostgreSQL de la cuenta: usuario, sesiones,
#                              refresh tokens y registros de cliente (sólo conteos)
#   check.sh requests [desde]  peticiones que entraron por el túnel, agrupadas por
#                              método, ruta y estado; [desde] = marca devuelta por `mark`
#   check.sh mark              imprime el número de líneas actual del registro (marca)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"

account() {
  case "$1" in
    D) email="$F03_FARMER_D_EMAIL"; password="${F03_FARMER_D_PASSWORD:-}" ;;
    E2) email="$F03_FARMER_E2_EMAIL"; password="${F03_FARMER_E2_PASSWORD:-}" ;;
    *) echo "cuenta desconocida: $1"; exit 2 ;;
  esac
}

case "${1:-}" in
  health)
    echo "local: $(curl -s -o /dev/null -w '%{http_code}' "$(f03_api_local)/api/v1/health")"
    origin="$(f03_origin)"
    [ -n "$origin" ] && echo "https: $(curl -s -o /dev/null -w '%{http_code}' "$origin/api/v1/health")" \
      || echo "https: sin túnel"
    ;;
  login)
    account "${2:-}"
    : "${password:?Ejecute antes: source secrets.sh}"
    origin="$(f03_origin)"; [ -n "$origin" ] || { echo "sin túnel"; exit 1; }
    body=$(EMAIL="$email" PASSWORD="$password" node -e \
      'process.stdout.write(JSON.stringify({email:process.env.EMAIL,password:process.env.PASSWORD,refreshTransport:"BODY"}))')
    response=$(curl -s -w '\n%{http_code}' -H 'Content-Type: application/json' \
      --data-binary @- "$origin/api/v1/auth/v2/login" <<< "$body")
    code="${response##*$'\n'}"; json="${response%$'\n'*}"
    echo "login V2 BODY: HTTP $code; claves: $(node "$here/json.cjs" keys <<< "$json")"
    refresh=$(node "$here/json.cjs" get refreshToken <<< "$json")
    if [ -n "$refresh" ]; then
      out=$(REFRESH="$refresh" node -e 'process.stdout.write(JSON.stringify({refreshToken:process.env.REFRESH}))' \
        | curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
          --data-binary @- "$origin/api/v1/auth/v2/logout")
      echo "logout de la sesión de comprobación: HTTP $out"
    fi
    ;;
  state)
    account "${2:-}"
    f03_psql "SELECT 'usuario activo='||u.\"isActive\"||', member activo='||m.\"isActive\"||', rol='||m.role
      FROM \"User\" u JOIN \"Member\" m ON m.\"userId\"=u.id WHERE u.email='$email'"
    f03_psql "SELECT 'sesiones '||s.status||'='||count(*) FROM \"AuthSession\" s
      JOIN \"Member\" m ON m.id=s.\"memberId\" JOIN \"User\" u ON u.id=m.\"userId\"
      WHERE u.email='$email' GROUP BY s.status ORDER BY s.status"
    f03_psql "SELECT 'refresh tokens: total='||count(*)||', consumidos='||count(r.\"consumedAt\")||
      ', revocados='||count(r.\"revokedAt\") FROM \"RefreshToken\" r JOIN \"User\" u ON u.id=r.\"userId\"
      WHERE u.email='$email'"
    f03_psql "SELECT 'registros de cliente '||c.status||'='||count(*) FROM \"ClientRegistration\" c
      JOIN \"Member\" m ON m.id=c.\"memberId\" JOIN \"User\" u ON u.id=m.\"userId\"
      WHERE u.email='$email' GROUP BY c.status ORDER BY c.status"
    ;;
  mark)
    wc -l < "$F03_RUN_DIR/requests.log" | tr -d ' '
    ;;
  requests)
    from="${2:-0}"
    tail -n +"$((from + 1))" "$F03_RUN_DIR/requests.log" | awk '{print $2, $3, $4}' | sort | uniq -c
    ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
