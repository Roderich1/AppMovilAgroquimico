# #18 (F10) y comprobación focalizada de F08 contra el Backend integrado: entorno
# propio de la sesión A. Se carga con `source`, en una SHELL NUEVA, ANTES de
# `tool/f03_res_01/config.sh`, con F10_COPY=a|b|c para elegir la copia aislada
# de #18, o F10_COPY=bkp para la de la comprobación de restauración (.f10bkp).
#
# Como tool/f08_bkp/env.sh: primero se validan TODAS las variables y sólo después
# se exporta alguna. Si la shell ya tiene otro valor (otro ensayo cargado), se
# aborta sin cambiar nada. Así ningún script del arnés F03 apunta a un contenedor,
# volumen o paquete conservado de otro ensayo (.f03res01, .f06d4, .f03e2b,
# .f08bkp). No contiene secretos.

case "${F10_COPY:-}" in
  a | b | c)
    _f10_suffix=".f10s18${F10_COPY}"
    _f10_label="Agrocuentas F10-S18-$(printf '%s' "$F10_COPY" | tr 'abc' 'ABC')"
    ;;
  # Restauración (#36, #91-#93): paquete propio, para no reemplazar los datos
  # conservados del turno 2 en .f08bkp.
  bkp)
    _f10_suffix=".f10bkp"
    _f10_label="Agrocuentas F10-BKP"
    ;;
  *)
    echo "env.sh: defina F10_COPY=a, b, c o bkp (copia aislada .f10s18a/b/c o .f10bkp); no se cambió nada." >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

_f10_vars=(
  "F03_PG_CONTAINER=agro_a_f10int_pg"
  "F03_PG_VOLUME=agro_a_f10int_pgdata"
  "F03_PG_PORT=55447"
  "F03_PG_DB=agro_f10int"
  "F03_API_PORT=3116"
  "F03_OBSERVER_PORT=3117"
  "F03_RUN_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10int"
  "F03_SHOTS_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10int/capturas"
  # Copias aisladas nuevas: nunca la app normal ni las de otros ensayos.
  "F03_APP_ID_SUFFIX=${_f10_suffix}"
  "F03_APP_LABEL=${_f10_label}"
  # Respaldos (F08) del entorno desechable y sintético; cerrados en producción
  # salvo esta admisión explícita, que nunca se usa en un despliegue.
  "BACKUP_STORAGE_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10int/backups"
  "BACKUP_PRODUCTION_ADMISSION=enabled"
)

_f10_conflict=""
for _f10_pair in "${_f10_vars[@]}"; do
  _f10_name="${_f10_pair%%=*}"
  _f10_value="${_f10_pair#*=}"
  _f10_current="${!_f10_name-}"
  if [ -n "$_f10_current" ] && [ "$_f10_current" != "$_f10_value" ]; then
    _f10_conflict="$_f10_name"
    break
  fi
done

if [ -n "$_f10_conflict" ]; then
  echo "env.sh: $_f10_conflict ya tiene otro valor en esta shell; no se cambió nada. Abra una shell nueva." >&2
  unset _f10_vars _f10_conflict _f10_pair _f10_name _f10_value _f10_current _f10_suffix _f10_label
  return 1 2>/dev/null || exit 1
fi

for _f10_pair in "${_f10_vars[@]}"; do
  export "${_f10_pair%%=*}=${_f10_pair#*=}"
done
unset _f10_vars _f10_conflict _f10_pair _f10_name _f10_value _f10_current _f10_suffix _f10_label
