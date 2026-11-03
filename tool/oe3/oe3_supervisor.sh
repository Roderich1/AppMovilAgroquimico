#!/usr/bin/env bash
# OE3 (cierre técnico, 2026-11-03), adaptado de F12-EST-07-MOB (#164): Central PROPIO y DESECHABLE para el ensayo Android contra el
# Backend real, con datos SINTÉTICOS. No toca pilotos, EXP, UX, AV ni sus paquetes.
#   contenedor agro_oe3_pg (sin volumen; trust sólo en 127.0.0.1:55495)
#   API 127.0.0.1:3320 · observador 3321 · carpeta %TEMP%/agro_oe3
# Mantiene en MEMORIA (nunca en archivos) los secretos JWT y de huella y la contraseña de
# un solo uso de la Directiva sintética; así un reinicio de la API para cambiar la política
# no invalida la sesión del teléfono. El modo se cambia escribiendo en $RUN/mode:
#   provisional  COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic (perfil FARMER permitido)
#   pending      sin modo: la política está pendiente (409 POLICY_PENDING real)
# Al arrancar: siembra (control-sintetico.cjs del Backend), API en modo provisional y dos
# estimaciones reales con el trabajador (invierno: estimada; verano: datos insuficientes).
set -uo pipefail
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
BE=${EST_BE:-$ROOT/_wt/F12-EST-08/Back}
RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
PG=agro_oe3_pg; PORT=55495; API=3320
mkdir -p "$RUN"
rnd() { openssl rand -base64 "$1" | tr -d '\r\n/+='; }
stamp() { date -u +%FT%TZ; }
log() { echo "$(stamp) $*" >> "$RUN/supervisor.log"; }
listener() { netstat -ano | awk -v p=":$1" '$2 ~ p"$" && $4 == "LISTENING" {print $5; exit}'; }
export PG_ADMIN_URL="postgresql://postgres@127.0.0.1:${PORT}/postgres"

docker run -d --rm --name "$PG" -e POSTGRES_HOST_AUTH_METHOD=trust -p "127.0.0.1:$PORT:5432" postgres:16.13 > /dev/null || { log "no se pudo crear $PG"; exit 1; }
for _ in $(seq 1 60); do docker exec "$PG" pg_isready -U postgres > /dev/null 2>&1 && break; sleep 1; done
sleep 2
export WALK_PASSWORD=$(rnd 18)
( cd "$BE" && node ../docs/evidence/f12_est_07/control-sintetico.cjs seed "$RUN/ids.json" ) >> "$RUN/supervisor.log" 2>&1 || { log "siembra fallida"; exit 1; }
DB=$(node -e "process.stdout.write(require(process.argv[1]).database)" "$(cygpath -w "$RUN/ids.json")")
DATABASE_URL="postgresql://postgres@127.0.0.1:${PORT}/${DB}?schema=public"
log "PostgreSQL $PG y base sintética sembrada"

JWT=$(rnd 48); JWTR=$(rnd 48); FP=$(openssl rand -base64 32 | tr -d '\r\n')
start_api() {
  local mode=$1 extra=()
  [ "$mode" = provisional ] && extra=(COLLECTIVE_DISCLOSURE_MODE=provisional-synthetic)
  ( cd "$BE" && env NODE_ENV=development PORT=$API DATABASE_URL="$DATABASE_URL" JWT_SECRET="$JWT" JWT_REFRESH_SECRET="$JWTR" \
      JWT_EXPIRES_IN=15m JWT_REFRESH_EXPIRES_IN=7d COOKIE_SECURE=false CORS_ORIGIN=http://127.0.0.1 \
      SYNC_V1_FINGERPRINT_KEY="$FP" SYNC_V1_FINGERPRINT_KEY_VERSION=1 SYNC_V1_PRODUCTION_ADMISSION=enabled \
      BACKUP_PRODUCTION_ADMISSION=disabled ESTIMATION_WORKER_INTERVAL_MS=1000 "${extra[@]}" \
      node dist/main.js >> "$RUN/api.log" 2>&1 ) &
  for _ in $(seq 1 90); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API/api/v1/health")" = 200 ] && break; sleep 1
  done
  log "API en modo $mode: health $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API/api/v1/health")"
}
stop_api() {
  local pid; pid=$(listener "$API")
  [ -n "$pid" ] && taskkill //PID "$pid" //F > /dev/null 2>&1
  for _ in $(seq 1 30); do [ -z "$(listener "$API")" ] && break; sleep 1; done
  log "API detenida"
}

echo provisional > "$RUN/mode"
start_api provisional
# Dos estimaciones con el trabajador real, pedidas por la Directiva sintética.
node - "$(cygpath -w "$RUN/ids.json")" "http://127.0.0.1:$API/api/v1" >> "$RUN/supervisor.log" 2>&1 <<'JS'
const [ids, api] = [require(process.argv[2]), process.argv[3]];
const { randomUUID } = require('node:crypto');
(async () => {
  const login = await fetch(`${api}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: ids.directorEmail, password: process.env.WALK_PASSWORD }) });
  if (!login.ok) throw new Error(`login Directiva ${login.status}`);
  const { accessToken } = await login.json();
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` };
  for (const target of [ids.t1, ids.t2]) {
    const job = await (await fetch(`${api}/estimation/jobs`, { method: 'POST', headers,
      body: JSON.stringify({ contract_version: 1, request_id: randomUUID(), target_campaign_ref: target }) })).json();
    let status = job.status;
    for (let i = 0; i < 60 && !['COMPLETED', 'STOPPED'].includes(status); i++) {
      await new Promise((r) => setTimeout(r, 1000));
      status = (await (await fetch(`${api}/estimation/jobs/${job.job_ref}`, { headers })).json()).status;
    }
    console.log(new Date().toISOString(), 'estimación', target === ids.t1 ? 'invierno' : 'verano', status);
  }
})().catch((e) => { console.error('estimaciones:', e.message); process.exit(1); });
JS
WALK_PASSWORD=
log "listo"
current=provisional
while [ -f "$RUN/mode" ]; do
  want=$(cat "$RUN/mode" 2>/dev/null || echo "$current")
  if [ "$want" != "$current" ]; then stop_api; start_api "$want"; current=$want; fi
  sleep 2
done
stop_api
docker stop "$PG" > /dev/null 2>&1
JWT=; JWTR=; FP=
log "supervisor terminado: API y contenedor detenidos"
