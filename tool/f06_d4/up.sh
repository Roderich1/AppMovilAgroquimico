#!/usr/bin/env bash
# F06 (D4): levanta el entorno desechable de la reconciliación.
# - PostgreSQL propio (agro_f06d4_pg, volumen agro_f06d4_pgdata, 127.0.0.1:55434)
#   con dos bases: una para la reconciliación desde el host y otra para la ruta
#   física. Cada base nueva se migra y se siembra (seed del Backend + catálogo F06).
# - Dos API locales NODE_ENV=development con la política provisional sintética
#   (k=3): 3200 (host) y 3201 (teléfono). La admisión de producción de Sync v1
#   no interviene: no es production.
# Los secretos (contraseña de PostgreSQL de esta sesión, JWT, clave de huella)
# sólo viven en esta shell y en el entorno de cada proceso de la API.
# No usa ni toca agro_f03res01_pg. Requiere el Backend compilado en $F06_BE_DIR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
mkdir -p "$F06_RUN_DIR"
docker info > /dev/null 2>&1 || { echo "Docker no está activo"; exit 1; }

pg_password="$(f06_rand 24)"
if ! docker ps -a --format '{{.Names}}' | grep -qx "$F06_PG_CONTAINER"; then
  POSTGRES_PASSWORD="$pg_password" docker run -d --name "$F06_PG_CONTAINER" \
    -e POSTGRES_PASSWORD -p "127.0.0.1:${F06_PG_PORT}:5432" \
    -v "$F06_PG_VOLUME:/var/lib/postgresql/data" "$F06_PG_IMAGE" > /dev/null
  echo "contenedor creado: $F06_PG_CONTAINER (volumen $F06_PG_VOLUME)"
else
  docker start "$F06_PG_CONTAINER" > /dev/null
  echo "contenedor existente iniciado: $F06_PG_CONTAINER"
fi
for _ in $(seq 1 60); do
  docker exec "$F06_PG_CONTAINER" pg_isready -U postgres > /dev/null 2>&1 && break
  sleep 1
done
docker exec "$F06_PG_CONTAINER" pg_isready -U postgres > /dev/null
# Contraseña de esta sesión, fijada por el socket local del contenedor.
printf "ALTER USER postgres PASSWORD '%s';\n" "$pg_password" |
  docker exec -i "$F06_PG_CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 > /dev/null

url_for() { printf 'postgresql://postgres:%s@127.0.0.1:%s/%s?schema=public' "$pg_password" "$F06_PG_PORT" "$1"; }

for db in "$F06_DB_HOST" "$F06_DB_DEVICE"; do
  if [ "$(f06_psql "SELECT 1 FROM pg_database WHERE datname='$db'" postgres)" != 1 ]; then
    f06_psql "CREATE DATABASE $db" postgres > /dev/null
    fresh=1
  else
    fresh=0
  fi
  (
    cd "$F06_BE_DIR"
    DATABASE_URL="$(url_for "$db")" npx prisma migrate deploy > "$F06_RUN_DIR/migrate_$db.log" 2>&1 ||
      { tail -5 "$F06_RUN_DIR/migrate_$db.log"; exit 1; }
    echo "$db: migraciones aplicadas en esta llamada: $(grep -c -E '^Applying migration' "$F06_RUN_DIR/migrate_$db.log" || true)"
    if [ "$fresh" = 1 ]; then
      DATABASE_URL="$(url_for "$db")" node dist/prisma/seed.js > "$F06_RUN_DIR/seed_$db.log" 2>&1 || { echo "seed falló"; exit 1; }
      echo "$db: seed: $(tail -1 "$F06_RUN_DIR/seed_$db.log")"
      DATABASE_URL="$(url_for "$db")" F06_BE_DIR="$F06_BE_DIR" node "$here/seed_d4.cjs"
    fi
  )
done

# Clave de huella (32 bytes en base64). Git Bash convierte en ruta de Windows
# un valor de entorno que empieza por «/» al pasarlo a node.exe: se descarta.
fingerprint_key() {
  local key
  while key="$(openssl rand -base64 32 | tr -d '\r\n')"; [ "${key#/}" != "$key" ]; do :; done
  printf '%s' "$key"
}

start_api() { # puerto base
  local port="$1" db="$2" pidfile="$F06_RUN_DIR/api_$1.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2> /dev/null; then
    kill "$(cat "$pidfile")"; sleep 2
  fi
  (
    cd "$F06_BE_DIR"
    NODE_ENV=development PORT="$port" DATABASE_URL="$(url_for "$db")" \
      JWT_SECRET="$(f06_rand 48)" JWT_REFRESH_SECRET="$(f06_rand 48)" \
      JWT_EXPIRES_IN=15m JWT_REFRESH_EXPIRES_IN=7d COOKIE_SECURE=false \
      CORS_ORIGIN=http://127.0.0.1 \
      SYNC_V1_FINGERPRINT_KEY="$(fingerprint_key)" SYNC_V1_FINGERPRINT_KEY_VERSION=1 \
      COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic \
      nohup node dist/main.js > "$F06_RUN_DIR/api_$port.log" 2>&1 &
    echo $! > "$pidfile"
  )
  local code=000
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/api/v1/health" || true)
    [ "$code" = 200 ] && break
    sleep 1
  done
  echo "API $port ($db): health HTTP $code"
  [ "$code" = 200 ]
}
start_api "$F06_API_PORT_HOST" "$F06_DB_HOST"
start_api "$F06_API_PORT_DEVICE" "$F06_DB_DEVICE"
