#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.5-§1.7): R4 (sincronización por acción explícita) y R6
# (respaldos) en N1, en la copia aislada `.f10eval`. Como series_n0.sh: vídeo por repetición,
# inicio y fin con frames.py y una fila de CSV crudo; un error queda en su fila.
#   series_n1.sh r4 <primera> <última>     una intención nueva por repetición, ≥ 60 s entre toques
#   series_n1.sh r6up <tamaño> <primera> <última>    subidas (rep 0 = calentamiento del tamaño)
#   series_n1.sh r6down <tamaño> <primera> <última>  descargas hasta «verificada con SHA-256»; se cancela
# Requiere: entorno cargado, ANDROID_SERIAL del POCO y show_touches=1.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f03="$here/../f03_res_01"
serie="${1:?r4|r6up|r6down}"; shift
: "${F03_APP_PACKAGE:?cargue el entorno}" "${ANDROID_SERIAL:?fije ANDROID_SERIAL}"
py() { python -I -X utf8 "$here/$1" "${@:2}"; }
component="$F03_APP_PACKAGE/com.comunidad.agro.agroquimicos.MainActivity"
log_lines() { wc -l < "$F03_RUN_DIR/requests.log"; }

net_on_wait() {
  bash "$f03/device.sh" net on > /dev/null 2>&1
  for _ in $(seq 1 40); do
    MSYS_NO_PATHCONV=1 adb shell ping -c 1 -W 1 1.1.1.1 > /dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

analyse() {  # $1 vídeo, $2 x,y del toque, $3 región final
  py frames.py "$1" --start touch --tap "$2" --end-roi "$3" --frames-dir "$(dirname "$1")/../frames" || true
}

row_from() {  # JSON de frames.py -> inicio,fin,duración,cuadro_inicio,cuadro_fin,cuadros
  JSON="$1" python -I -X utf8 -c '
import json, os
try:
    r = json.loads(os.environ["JSON"])
except Exception:
    r = {}
print(",".join(str(r.get(k, "")) for k in ("start_s", "end_s", "duration_ms", "start_frame", "end_frame", "frames")))'
}

case "$serie" in
  r4)
    first="${1:?}"; last="${2:?}"
    out="$F03_RUN_DIR/series/r4"; mkdir -p "$out/video" "$out/frames"
    csv="$F03_RUN_DIR/series/r4.csv"
    [ -f "$csv" ] || echo "serie,rep,calentamiento,hora_utc,inicio_s,fin_s,duracion_ms,cuadro_inicio,cuadro_fin,cuadros,operacion,estado_previo,peticiones,estado_final,journal,error,video_sha256" > "$csv"
    for rep in $(seq "$first" "$last"); do
      err=""
      # 1. Sin red, una intención nueva (necesidad de DSV-001 con otra cantidad).
      bash "$f03/device.sh" net off > /dev/null 2>&1; sleep 2
      qty=$((20 + rep))
      py ui.py need "$qty" > /dev/null
      op=$(bash "$f03/device.sh" db outbox 2>/dev/null | tail -1 | sed -n -E 's/.*op=([0-9a-f]{8}).*/\1/p')
      before=$(bash "$f03/device.sh" db outbox 2>/dev/null | tail -1 | sed -n -E 's/.* (PENDING|OUTCOME_UNKNOWN|SENDING|ACKED) .*/\1/p')
      # 2. Se detiene la app (sin acceso verificado en memoria) y vuelve la red.
      adb shell am force-stop "$F03_APP_PACKAGE"
      net_on_wait || err="sin red tras activar"
      # 3. Se abre Sincronización.
      adb shell am start -n "$component" > /dev/null; sleep 5
      py ui.py open-sync > /dev/null
      xy=$(py ui.py find "^Sincronizar ahora$")
      n0=$(log_lines)
      log=$(bash "$here/record_tap.sh" "r4_$(printf '%02d' "$rep")" ${xy% *} ${xy#* } 20 "$out/video")
      sleep 2
      reqs=$(tail -n +$((n0 + 1)) "$F03_RUN_DIR/requests.log" | awk '{print $1" "$2" "$3" "$4}' | tr '\n' ';')
      after=$(bash "$f03/device.sh" db outbox 2>/dev/null | grep "op=$op" | sed -n -E 's/.* (PENDING|OUTCOME_UNKNOWN|SENDING|ACKED|AUTH_PAUSED) .*/\1/p')
      journal=$(bash "$f03/check.sh" sync D 2>/dev/null | grep -c "journal $op" || true)
      [ "$after" = "ACKED" ] || err="${err:+$err; }estado final $after"
      [ "$journal" = "1" ] || err="${err:+$err; }journal $journal"
      json=$(analyse "$out/video/r4_$(printf '%02d' "$rep").mp4" "${xy/ /,}" "0,380,1080,900")
      when=$(echo "$log" | sed -n -E 's/^toque_utc=(.*)/\1/p'); sha=$(echo "$log" | sed -n -E 's/.*sha256=([0-9a-f]+).*/\1/p')
      echo "r4,$rep,no,$when,$(row_from "$json"),$op,$before,$reqs,$after,$journal,$err,$sha" >> "$csv"
      echo "r4 rep $rep op=$op $before -> $after journal=$journal $(row_from "$json") ${err:+ERROR: $err}"
      # ≥ 60 s entre toques (límite de 20/min y espaciado del protocolo).
      sleep 45
    done
    ;;
  *)
    echo "serie desconocida: $serie"; exit 2 ;;
esac
