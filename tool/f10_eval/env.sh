# Evaluación F10 (protocolo v1.0, §0.4 y §1.7): entorno propio de la sesión A para
# medir rendimiento Mobile y compatibilidad. Se carga con `source`, en una SHELL
# NUEVA, ANTES de `tool/f03_res_01/config.sh`.
#
# Como tool/f10_s18/env.sh: primero se validan TODAS las variables y sólo después
# se exporta alguna; si la shell ya tiene otro valor (otro ensayo cargado), se
# aborta sin cambiar nada. Ningún script del arnés F03 apunta así a un
# contenedor, volumen o paquete conservado de otro ensayo. No contiene secretos.

_f10e_vars=(
  "F03_PG_CONTAINER=agro_a_f10eval_pg"
  "F03_PG_VOLUME=agro_a_f10eval_pgdata"
  "F03_PG_PORT=55448"
  "F03_PG_DB=agro_f10eval"
  "F03_API_PORT=3118"
  "F03_OBSERVER_PORT=3119"
  "F03_RUN_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10eval"
  "F03_SHOTS_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10eval/capturas"
  # Copia aislada nueva, sólo para la evaluación: nunca la app normal ni las de
  # otros ensayos (.f03res01, .f06d4, .f03e2b, .f08bkp, .f10s18a/b/c, .f10bkp).
  "F03_APP_ID_SUFFIX=.f10eval"
  "F03_APP_LABEL=Agrocuentas F10-EVAL"
  # Respaldos (F08) del entorno desechable y sintético; cerrados en producción
  # salvo esta admisión explícita, que nunca se usa en un despliegue.
  "BACKUP_STORAGE_DIR=/c/Users/MSI/AppData/Local/Temp/agro_a_f10eval/backups"
  "BACKUP_PRODUCTION_ADMISSION=enabled"
  # Protocolo v1.0 §0.4: 15 copias activas para conservar las de R6 sin borrar
  # ninguna (de fábrica, 5). No es un control de seguridad ni cambia el tiempo.
  "BACKUP_MAX_ACTIVE_PER_MEMBER=15"
)

_f10e_conflict=""
for _f10e_pair in "${_f10e_vars[@]}"; do
  _f10e_name="${_f10e_pair%%=*}"
  _f10e_value="${_f10e_pair#*=}"
  _f10e_current="${!_f10e_name-}"
  if [ -n "$_f10e_current" ] && [ "$_f10e_current" != "$_f10e_value" ]; then
    _f10e_conflict="$_f10e_name"
    break
  fi
done

if [ -n "$_f10e_conflict" ]; then
  echo "env.sh: $_f10e_conflict ya tiene otro valor en esta shell; no se cambió nada. Abra una shell nueva." >&2
  unset _f10e_vars _f10e_conflict _f10e_pair _f10e_name _f10e_value _f10e_current
  return 1 2>/dev/null || exit 1
fi

for _f10e_pair in "${_f10e_vars[@]}"; do
  export "${_f10e_pair%%=*}=${_f10e_pair#*=}"
done
unset _f10e_vars _f10e_conflict _f10e_pair _f10e_name _f10e_value _f10e_current
