# F08-BKP (#35/#36): entorno propio del E2E de recuperación. Se carga con
# `source`, en una SHELL NUEVA, ANTES de `tool/f03_res_01/config.sh`.
#
# Los valores se asignan sin condición. Si la shell ya tiene otro valor para
# alguna de estas variables (por ejemplo, porque cargó antes la configuración
# de F03-RES-01, D4 o E-2), se aborta: `down.sh` podría borrar entonces el
# contenedor o el volumen conservados de otro ensayo. No contiene secretos.

_f08_set() {
  local name="$1" value="$2" current
  current="${!name-}"
  if [ -n "$current" ] && [ "$current" != "$value" ]; then
    echo "env.sh: $name ya tiene otro valor en esta shell; abra una shell nueva." >&2
    return 1
  fi
  export "$name=$value"
}

_f08_env() {
  _f08_set F03_PG_CONTAINER agro_c_f08e2e_pg &&
  _f08_set F03_PG_VOLUME agro_c_f08e2e_pgdata &&
  _f08_set F03_PG_PORT 55446 &&
  _f08_set F03_PG_DB agro_f08e2e &&
  _f08_set F03_API_PORT 3113 &&
  _f08_set F03_OBSERVER_PORT 3116 &&
  _f08_set F03_RUN_DIR /c/Users/MSI/AppData/Local/Temp/agro_f08bkp &&
  _f08_set F03_SHOTS_DIR /c/Users/MSI/AppData/Local/Temp/agro_f08bkp/capturas &&
  # Paquete aislado nuevo: nunca la app normal ni .f03res01/.f06d4/.f03e2b.
  _f08_set F03_APP_ID_SUFFIX .f08bkp &&
  _f08_set F03_APP_LABEL "Agrocuentas F08-BKP" &&
  # Almacenamiento privado del Backend del ensayo (adaptador de disco). La API
  # lo hereda de esta shell al arrancar con up.sh.
  _f08_set BACKUP_STORAGE_DIR /c/Users/MSI/AppData/Local/Temp/agro_f08bkp/backups &&
  # up.sh arranca la API con NODE_ENV=production, donde los respaldos están
  # cerrados por defecto. Se abren SÓLO en este entorno desechable y sintético,
  # como la admisión de Sync v1 en el arnés F03. Nunca en un despliegue.
  _f08_set BACKUP_PRODUCTION_ADMISSION enabled
}

if ! _f08_env; then
  unset -f _f08_set _f08_env
  return 1 2>/dev/null || exit 1
fi
unset -f _f08_set _f08_env
