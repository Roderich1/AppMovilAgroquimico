#!/usr/bin/env bash
# F08-BKP: cierre del entorno del ensayo F08. Úsese ESTE script, nunca
# `tool/f03_res_01/down.sh` directamente: en una shell sin env.sh aquél
# apuntaría al contenedor y al volumen conservados de F03-RES-01.
#
# Carga env.sh (que aborta si la shell trae otra configuración), comprueba que
# el contenedor y el volumen son los de F08 y sólo entonces delega en el
# down.sh de F03, que detiene túnel, observador y API y elimina SOLO ese
# contenedor y ese volumen. No borra el almacenamiento de respaldos ni las
# instantáneas: eso se hace a mano cuando ya no hagan falta (README §4).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/env.sh"
source "$here/../f03_res_01/config.sh"
if [ "$F03_PG_CONTAINER" != agro_c_f08e2e_pg ] || [ "$F03_PG_VOLUME" != agro_c_f08e2e_pgdata ]; then
  echo "down.sh (F08): contenedor o volumen inesperados ($F03_PG_CONTAINER / $F03_PG_VOLUME); no se borra nada." >&2
  exit 1
fi
exec "$here/../f03_res_01/down.sh"
