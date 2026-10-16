# F03-RES-01 (#71): configuración del entorno controlado. Se carga con `source`.
# No contiene secretos. Los secretos efímeros los genera `secrets.sh` sólo en
# variables de entorno de la shell actual.

: "${F03_BE_DIR:?Defina F03_BE_DIR con la ruta a Back/ de un worktree del Backend}"
: "${F03_CLOUDFLARED:?Defina F03_CLOUDFLARED con la ruta al cloudflared verificado}"

F03_PG_IMAGE=postgres:16-alpine
F03_PG_CONTAINER=agro_f03res01_pg
F03_PG_VOLUME=agro_f03res01_pgdata
F03_PG_PORT=55432
F03_PG_DB=agro_f03res01
F03_API_PORT=3100
F03_OBSERVER_PORT=3101 # proxy que registra método, ruta y estado; el túnel apunta aquí
F03_RUN_DIR="${F03_RUN_DIR:-${TMPDIR:-/tmp}/agro_f03res01}"

# Cuentas sintéticas del seed del Backend. Sus contraseñas se rotan al levantar
# el entorno; la del seed (pública en el repositorio) deja de servir.
F03_ADMIN_EMAIL=admin@agro.local
F03_FARMER_D_EMAIL=juan.perez@agro.local    # caso D y luego E-1
F03_FARMER_E2_EMAIL=maria.choque@agro.local # caso E-2
F03_FARMER_S_EMAIL=pedro.mamani@agro.local # E2E de D3 (sincronización)

# Aplicación aislada: nunca la app normal.
F03_APP_ID_SUFFIX=.f03res01
F03_APP_PACKAGE="com.comunidad.agro.agroquimicos${F03_APP_ID_SUFFIX}"
F03_APP_LABEL="Agrocuentas F03-RES-01"
F03_DEVICE_DB=agroquimicos_v2.db
F03_SHOTS_DIR="${F03_SHOTS_DIR:-$F03_RUN_DIR/capturas}" # fuera de cualquier worktree

f03_api_local() { printf 'http://127.0.0.1:%s' "$F03_API_PORT"; }
f03_origin() { cat "$F03_RUN_DIR/origin" 2>/dev/null; }
f03_psql() {
  docker exec "$F03_PG_CONTAINER" psql -U postgres -d "$F03_PG_DB" -At -F ' | ' -c "$1"
}
