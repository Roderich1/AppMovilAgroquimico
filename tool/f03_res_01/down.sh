#!/usr/bin/env bash
# F03-RES-01 (#71): detiene túnel y Backend y elimina SOLO el contenedor y el
# volumen efímeros de este ensayo. No toca otros contenedores, volúmenes ni la app.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
for name in tunnel observer api; do
  pid_file="$F03_RUN_DIR/$name.pid"
  if [ -f "$pid_file" ]; then
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || taskkill //PID "$pid" //F > /dev/null 2>&1 || true
    rm -f "$pid_file"
    echo "$name detenido"
  fi
done
docker rm -f "$F03_PG_CONTAINER" > /dev/null 2>&1 && echo "contenedor $F03_PG_CONTAINER eliminado"
docker volume rm "$F03_PG_VOLUME" > /dev/null 2>&1 && echo "volumen $F03_PG_VOLUME eliminado"
rm -f "$F03_RUN_DIR"/{origin,migrate.log,seed.log,api.log,tunnel.log,observer.out,requests.log}
echo "restos: contenedor=$(docker ps -a --format '{{.Names}}' | grep -cx "$F03_PG_CONTAINER")," \
  "escucha en ${F03_API_PORT}=$(netstat -ano 2>/dev/null | grep -c ":${F03_API_PORT} .*LISTENING")," \
  "escucha en ${F03_OBSERVER_PORT}=$(netstat -ano 2>/dev/null | grep -c ":${F03_OBSERVER_PORT} .*LISTENING")"
