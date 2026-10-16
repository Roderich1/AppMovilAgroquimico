# F08-BKP (#35/#36): entorno propio del E2E de recuperación. Se carga con
# `source` ANTES de `tool/f03_res_01/config.sh`, cuyos valores por defecto
# respeta. Reutiliza el arnés F03 con contenedor, volumen, puertos, carpeta y
# paquete propios: no toca F03-RES-01, D4, la repetición de E-2 ni la app
# normal. No contiene secretos.
export F03_PG_CONTAINER="${F03_PG_CONTAINER:-agro_c_f08e2e_pg}"
export F03_PG_VOLUME="${F03_PG_VOLUME:-agro_c_f08e2e_pgdata}"
export F03_PG_PORT="${F03_PG_PORT:-55446}"
export F03_PG_DB="${F03_PG_DB:-agro_f08e2e}"
export F03_API_PORT="${F03_API_PORT:-3113}"
export F03_OBSERVER_PORT="${F03_OBSERVER_PORT:-3116}"
export F03_RUN_DIR="${F03_RUN_DIR:-/c/Users/MSI/AppData/Local/Temp/agro_f08bkp}"
export F03_SHOTS_DIR="${F03_SHOTS_DIR:-$F03_RUN_DIR/capturas}"
# Paquete aislado nuevo: nunca la app normal ni .f03res01/.f06d4/.f03e2b.
export F03_APP_ID_SUFFIX="${F03_APP_ID_SUFFIX:-.f08bkp}"
export F03_APP_LABEL="${F03_APP_LABEL:-Agrocuentas F08-BKP}"
# Almacenamiento privado de respaldos del Backend del ensayo (adaptador de
# disco). La API lo hereda de esta shell al arrancar con up.sh.
export BACKUP_STORAGE_DIR="${BACKUP_STORAGE_DIR:-$F03_RUN_DIR/backups}"
