#!/usr/bin/env bash
# F06 (D4): detiene las API y el contenedor. CONSERVA el contenedor, el volumen
# y los datos (no hay `down`: nada se borra).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
for port in "$F06_API_PORT_HOST" "$F06_API_PORT_DEVICE"; do
  pidfile="$F06_RUN_DIR/api_$port.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2> /dev/null; then
    kill "$(cat "$pidfile")" && echo "API $port detenida"
  fi
done
docker stop "$F06_PG_CONTAINER" > /dev/null && echo "contenedor $F06_PG_CONTAINER detenido (volumen $F06_PG_VOLUME conservado)"
