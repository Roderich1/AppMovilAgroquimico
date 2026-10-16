# F08-BKP (#35/#36): entorno propio del E2E de recuperación. Se carga con
# `source`, en una SHELL NUEVA, ANTES de `tool/f03_res_01/config.sh`.
#
# Primero se validan TODAS las variables y sólo después se exporta alguna: si
# la shell ya tiene otro valor para cualquiera de ellas (por ejemplo, porque
# cargó antes la configuración de F03-RES-01, D4 o E-2), se aborta sin cambiar
# nada. Así ningún script del arnés F03 puede apuntar a un contenedor o volumen
# conservado de otro ensayo. No contiene secretos.

_f08_vars=(
  "F03_PG_CONTAINER=agro_c_f08e2e_pg"
  "F03_PG_VOLUME=agro_c_f08e2e_pgdata"
  "F03_PG_PORT=55446"
  "F03_PG_DB=agro_f08e2e"
  "F03_API_PORT=3113"
  "F03_OBSERVER_PORT=3116"
  "F03_RUN_DIR=/c/Users/MSI/AppData/Local/Temp/agro_f08bkp"
  "F03_SHOTS_DIR=/c/Users/MSI/AppData/Local/Temp/agro_f08bkp/capturas"
  # Paquete aislado nuevo: nunca la app normal ni .f03res01/.f06d4/.f03e2b.
  "F03_APP_ID_SUFFIX=.f08bkp"
  "F03_APP_LABEL=Agrocuentas F08-BKP"
  # Almacenamiento privado del Backend del ensayo (adaptador de disco). La
  # API lo hereda de esta shell al arrancar con up.sh.
  "BACKUP_STORAGE_DIR=/c/Users/MSI/AppData/Local/Temp/agro_f08bkp/backups"
  # up.sh arranca la API con NODE_ENV=production, donde los respaldos están
  # cerrados por defecto. Se abren SÓLO en este entorno desechable y
  # sintético, como la admisión de Sync v1 en el arnés F03. Nunca en un
  # despliegue.
  "BACKUP_PRODUCTION_ADMISSION=enabled"
)

_f08_conflict=""
for _f08_pair in "${_f08_vars[@]}"; do
  _f08_name="${_f08_pair%%=*}"
  _f08_value="${_f08_pair#*=}"
  _f08_current="${!_f08_name-}"
  if [ -n "$_f08_current" ] && [ "$_f08_current" != "$_f08_value" ]; then
    _f08_conflict="$_f08_name"
    break
  fi
done

if [ -n "$_f08_conflict" ]; then
  echo "env.sh: $_f08_conflict ya tiene otro valor en esta shell; no se cambió nada. Abra una shell nueva." >&2
  unset _f08_vars _f08_conflict _f08_pair _f08_name _f08_value _f08_current
  return 1 2>/dev/null || exit 1
fi

for _f08_pair in "${_f08_vars[@]}"; do
  export "${_f08_pair%%=*}=${_f08_pair#*=}"
done
unset _f08_vars _f08_conflict _f08_pair _f08_name _f08_value _f08_current
