#!/usr/bin/env bash
# E2E de D3: fallo controlado en el observador para la PRÓXIMA petición de push.
#   fault.sh drop-push-response   Central procesa la intención (commit confirmado) y su
#                                 respuesta no llega al teléfono
#   fault.sh hold-push-request    la intención no llega a Central; el teléfono queda esperando
#   fault.sh clear | status
# Cada fallo se consume una sola vez; el observador lo registra en requests.log.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
file="$F03_RUN_DIR/requests.log.fault"
case "${1:-}" in
  drop-push-response | hold-push-request) printf '%s' "$1" > "$file"; echo "fallo preparado: $1" ;;
  clear) rm -f "$file"; echo "sin fallo preparado" ;;
  status) [ -f "$file" ] && echo "preparado: $(cat "$file")" || echo "sin fallo preparado" ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
