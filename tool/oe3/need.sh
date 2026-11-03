#!/usr/bin/env bash
# OE3: en la pantalla «Necesidad declarada» del paquete .oe3, cambia la cantidad de
# la necesidad de <producto> (o la anula) y muestra las peticiones nuevas del
# observador y el estado de la intención en la outbox.
#   need.sh <producto> <litros>     «Cambiar cantidad…» o «Declarar de nuevo…»
#   need.sh <producto> anular       «Anular»
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/oe3.sh"; RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
product=${1:?producto}; value=${2:?litros|anular}
y=$(bash "$T" ui | grep -A1 -E "^\[[0-9]+,[0-9]+\] +$product · " | grep "Opciones de la necesidad" | sed -E 's/^\[([0-9]+),([0-9]+)\].*/\2/' | head -1)
[ -n "$y" ] || { echo "no está la necesidad de $product"; exit 1; }
bash "$T" tapxy 904 "$y"; sleep 2
n0=$(wc -l < "$RUN/requests.log")
if [ "$value" = anular ]; then
  bash "$T" tap '^Anular$' > /dev/null; sleep 2
  bash "$T" tap '^Anular$' > /dev/null
else
  bash "$T" tap '^(Cambiar cantidad|Declarar de nuevo)' > /dev/null; sleep 2
  adb shell input keyevent KEYCODE_MOVE_END
  for _ in 1 2 3 4 5 6; do adb shell input keyevent KEYCODE_DEL; done
  adb shell input text "$value"; sleep 1
  adb shell input keyevent KEYCODE_ENTER; sleep 1
  bash "$T" tap '^Continuar$' > /dev/null; sleep 2
  bash "$T" ui | grep -q "Declarar al sindicato: $value L" || { echo "la confirmación no muestra $value L"; exit 1; }
  bash "$T" tap '^Declarar$' > /dev/null
fi
echo "$(date -u +%T) confirmado"
sleep "${NEED_WAIT:-6}"
tail -n +$((n0 + 1)) "$RUN/requests.log"
bash "$here/appdb.sh" "SELECT substr(operation_id,1,8), action, coalesce(quantity_base,'-'), status, attempts, coalesce(last_code,'-'), coalesce(next_attempt_at,'-') FROM sync_outbox ORDER BY id DESC LIMIT 1"
bash "$T" ui | grep -E "$product · " | head -1
