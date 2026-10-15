#!/usr/bin/env bash
# F03-RES-01 (#71): levanta PostgreSQL efímero + Backend local con cuentas
# sintéticas. No toca la base de desarrollo habitual ni el puerto 3000.
# Requiere: source config.sh && source secrets.sh en la misma shell, Docker activo
# y el Backend compilado en $F03_BE_DIR (npm ci, prisma generate, build, build:seed).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
: "${F03_PG_PASSWORD:?Ejecute antes: source secrets.sh}"

mkdir -p "$F03_RUN_DIR"
docker info > /dev/null 2>&1 || { echo "Docker no está activo"; exit 1; }
if docker ps -a --format '{{.Names}}' | grep -qx "$F03_PG_CONTAINER"; then
  echo "Ya existe $F03_PG_CONTAINER; ejecute down.sh antes"; exit 1
fi

# La contraseña pasa por el entorno, no por la línea de comandos.
POSTGRES_PASSWORD="$F03_PG_PASSWORD" docker run -d --name "$F03_PG_CONTAINER" \
  -e POSTGRES_PASSWORD -e POSTGRES_DB="$F03_PG_DB" \
  -p "127.0.0.1:${F03_PG_PORT}:5432" -v "$F03_PG_VOLUME:/var/lib/postgresql/data" \
  "$F03_PG_IMAGE" > /dev/null
for _ in $(seq 1 60); do
  docker exec "$F03_PG_CONTAINER" pg_isready -U postgres -d "$F03_PG_DB" > /dev/null 2>&1 && break
  sleep 1
done
docker exec "$F03_PG_CONTAINER" pg_isready -U postgres -d "$F03_PG_DB" > /dev/null
echo "PostgreSQL efímero listo en 127.0.0.1:${F03_PG_PORT} ($F03_PG_DB)"

export DATABASE_URL="postgresql://postgres:${F03_PG_PASSWORD}@127.0.0.1:${F03_PG_PORT}/${F03_PG_DB}?schema=public"
export F03_BE_DIR F03_ADMIN_EMAIL F03_FARMER_D_EMAIL F03_FARMER_E2_EMAIL
(
  cd "$F03_BE_DIR"
  npx prisma migrate deploy > "$F03_RUN_DIR/migrate.log" 2>&1 || { tail -5 "$F03_RUN_DIR/migrate.log"; exit 1; }
  echo "migraciones aplicadas: $(grep -c -E '^Applying migration' "$F03_RUN_DIR/migrate.log" || true)"
  node dist/prisma/seed.js > "$F03_RUN_DIR/seed.log" 2>&1 || { echo "seed falló"; exit 1; }
  echo "seed: $(tail -1 "$F03_RUN_DIR/seed.log")"
)
node "$here/rotate_passwords.cjs"

# Backend en segundo plano, con TTL por defecto (15m / 7d): no se acortan.
(
  cd "$F03_BE_DIR"
  NODE_ENV=production PORT="$F03_API_PORT" DATABASE_URL="$DATABASE_URL" \
    JWT_SECRET="$F03_JWT_SECRET" JWT_REFRESH_SECRET="$F03_JWT_REFRESH_SECRET" \
    JWT_EXPIRES_IN=15m JWT_REFRESH_EXPIRES_IN=7d COOKIE_SECURE=true \
    CORS_ORIGIN=http://127.0.0.1 \
    nohup node dist/main.js > "$F03_RUN_DIR/api.log" 2>&1 &
  echo $! > "$F03_RUN_DIR/api.pid"
)
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$(f03_api_local)/api/v1/health" || true)
  [ "$code" = "200" ] && break
  sleep 1
done
echo "Backend local: health HTTP ${code:-000} en $(f03_api_local)"
[ "${code:-000}" = "200" ]
