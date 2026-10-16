# F06 (D4): entorno desechable de la reconciliación. Se carga con `source`.
# No contiene secretos: cada script genera los suyos y sólo viven en su proceso
# (las API los guardan en su propio entorno). Es otro contenedor, otro volumen y
# otro puerto que F03-RES-01: no toca agro_f03res01_pg ni sus datos.

: "${F06_BE_DIR:?Defina F06_BE_DIR con la ruta a Back/ de un worktree del Backend}"

F06_PG_IMAGE=postgres:16-alpine
F06_PG_CONTAINER=agro_f06d4_pg
F06_PG_VOLUME=agro_f06d4_pgdata
F06_PG_PORT=55434
F06_DB_HOST="${F06_DB_HOST:-agro_f06d4}" # reconciliación automatizada desde el host (una base nueva por corrida)
F06_DB_DEVICE=agro_f06d4_poco  # ruta física: agricultor 1 en el teléfono
F06_API_PORT_HOST=3200
F06_API_PORT_DEVICE=3201
F06_RUN_DIR="${F06_RUN_DIR:-${TMPDIR:-/tmp}/agro_f06d4}"

# Cuentas sintéticas del seed del Backend; sus contraseñas se rotan en cada uso.
F06_F1_EMAIL=juan.perez@agro.local
F06_F2_EMAIL=maria.choque@agro.local
F06_F3_EMAIL=pedro.mamani@agro.local
F06_DIRECTIVA_EMAIL=directiva@agro.local

# Copia aislada para la ruta física (nunca la app normal ni la de F03-RES-01).
F06_APP_ID_SUFFIX=.f06d4
F06_APP_PACKAGE="com.comunidad.agro.agroquimicos${F06_APP_ID_SUFFIX}"
F06_APP_LABEL="Agrocuentas F06-D4"
F06_DEVICE_DB=agroquimicos_v2.db

f06_rand() { openssl rand -base64 "$1" | tr -d '\r\n/+='; }
# Consulta de sólo lectura dentro del contenedor (socket local, sin contraseña).
f06_psql() {
  docker exec "$F06_PG_CONTAINER" psql -U postgres -d "${2:-$F06_DB_HOST}" -At -F ',' -c "$1"
}
