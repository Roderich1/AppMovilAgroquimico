#!/usr/bin/env bash
# E2E de D3 y #18 (F10): fallo controlado en el observador para las PRÓXIMAS peticiones de push.
#   fault.sh drop-push-response   Central procesa la intención (commit confirmado) y su
#                                 respuesta no llega al teléfono
#   fault.sh hold-push-request    la intención no llega a Central; el teléfono queda esperando
#   fault.sh ack-incomplete | ack-contradictory | ack-other-operation
#                                 se reenvía a Central y el teléfono recibe un 200 con su ACK
#                                 alterado (sin hora, otra disposition u otro operationId)
#   fault.sh status-500-after     se reenvía a Central y el teléfono recibe un 500 genérico
#   fault.sh status-500-before    no llega a Central; el teléfono recibe un 500 genérico
#   fault.sh <modo> <modo> ...    una línea por petición, en orden
#   fault.sh clear | status
# Cada línea se consume una sola vez; el observador lo registra en requests.log.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
file="$F03_RUN_DIR/requests.log.fault"
modes='drop-push-response|hold-push-request|ack-incomplete|ack-contradictory|ack-other-operation|status-500-after|status-500-before'
case "${1:-}" in
  clear) rm -f "$file"; echo "sin fallo preparado" ;;
  status) [ -f "$file" ] && echo "preparado: $(tr '\n' ' ' < "$file")" || echo "sin fallo preparado" ;;
  "") sed -n '2,13p' "$0"; exit 2 ;;
  *)
    for mode in "$@"; do
      [[ "$mode" =~ ^($modes)$ ]] || { echo "modo desconocido: $mode"; exit 2; }
    done
    printf '%s\n' "$@" > "$file"
    echo "fallo preparado: $*"
    ;;
esac
