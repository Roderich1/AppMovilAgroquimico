#!/usr/bin/env bash
# F03-RES-01 (#71): abre un origen HTTPS temporal (Cloudflare quick tunnel) hacia
# el Backend local. Certificado público de confianza: la app no necesita
# excepciones TLS. El origen se guarda en $F03_RUN_DIR/origin y no se publica.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
mkdir -p "$F03_RUN_DIR"
[ -f "$F03_RUN_DIR/tunnel.pid" ] && kill -0 "$(cat "$F03_RUN_DIR/tunnel.pid")" 2>/dev/null && {
  echo "El túnel ya está activo"; exit 0; }

# Observador: registra sólo método, ruta (UUID enmascarados) y estado de lo que
# entra por el túnel, en $F03_RUN_DIR/requests.log.
: > "$F03_RUN_DIR/requests.log"
nohup node "$here/observer.cjs" "$F03_OBSERVER_PORT" "$F03_API_PORT" "$F03_RUN_DIR/requests.log" \
  > "$F03_RUN_DIR/observer.out" 2>&1 &
echo $! > "$F03_RUN_DIR/observer.pid"
nohup "$F03_CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:${F03_OBSERVER_PORT}" \
  > "$F03_RUN_DIR/tunnel.log" 2>&1 &
echo $! > "$F03_RUN_DIR/tunnel.pid"
origin=""
for _ in $(seq 1 60); do
  origin=$(grep -o -E 'https://[a-z0-9-]+\.trycloudflare\.com' "$F03_RUN_DIR/tunnel.log" | head -1 || true)
  [ -n "$origin" ] && break
  sleep 1
done
[ -n "$origin" ] || { echo "No se obtuvo el origen HTTPS"; exit 1; }
printf '%s' "$origin" > "$F03_RUN_DIR/origin"
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$origin/api/v1/health" || true)
  [ "$code" = "200" ] && break
  sleep 2
done
echo "Origen HTTPS temporal activo (valor en \$F03_RUN_DIR/origin, no se publica): health HTTP ${code:-000}"
[ "${code:-000}" = "200" ]
