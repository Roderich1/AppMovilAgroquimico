#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.5-§1.7): R4 (sincronización por acción explícita) y R6
# (respaldos) en N1, en la copia aislada `.f10eval`. Como series_n0.sh: vídeo por repetición,
# inicio y fin con frames.py y una fila de CSV crudo; un error queda en su fila.
#   series_n1.sh r4 <primera> <última>     una intención nueva por repetición, ≥ 60 s entre toques
#   series_n1.sh r6up <tamaño> <primera> <última>    subidas (rep 0 = calentamiento del tamaño)
#   series_n1.sh r6down <tamaño> <primera> <última>  descargas hasta «verificada con SHA-256»; se cancela
# Requiere: entorno cargado, ANDROID_SERIAL del POCO y pointer_location=1 (contacto visible).
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

copies() {  # copias AVAILABLE de la cuenta D en el servidor
  docker exec "$F03_PG_CONTAINER" psql -U postgres -d "$F03_PG_DB" -At -c "SELECT count(*) FROM \"BackupMetadata\" b JOIN \"Member\" m ON m.id = b.\"memberId\" JOIN \"User\" u ON u.id = m.\"userId\" WHERE u.email = '$F03_FARMER_D_EMAIL' AND b.status = 'AVAILABLE'"
}

analyse() {  # $1 vídeo, $2 x,y del toque, $3 región final
  py frames.py "$1" --start touch --tap "$2" --start-roi 760,94,320,35 --end-roi "$3" --frames-dir "$(dirname "$1")/../frames" || true
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
      echo "r4,$rep,$([ "$rep" = 0 ] && echo si || echo no),$when,$(row_from "$json"),$op,$before,$reqs,$after,$journal,$err,$sha" >> "$csv"
      echo "r4 rep $rep op=$op $before -> $after journal=$journal $(row_from "$json") ${err:+ERROR: $err}"
      # ≥ 60 s entre toques (límite de 20/min y espaciado del protocolo).
      sleep 45
    done
    ;;
  r6up|r6down)
    size="${1:?S1|S2|S3}"; first="${2:?}"; last="${3:?}"
    case "$size" in S1) limit=40 ;; S2) limit=120 ;; S3) limit=180 ;; *) echo "tamaño $size"; exit 2 ;; esac
    out="$F03_RUN_DIR/series/r6"; mkdir -p "$out/video" "$out/frames"
    csv="$F03_RUN_DIR/series/r6.csv"
    [ -f "$csv" ] || echo "serie,tamano,sentido,rep,calentamiento,hora_utc,inicio_s,fin_s,duracion_ms,cuadro_inicio,cuadro_fin,cuadros,peticiones,bytes_servidor,error,video_sha256" > "$csv"
    for rep in $(seq "$first" "$last"); do
      err=""; warm=$([ "$rep" = 0 ] && echo si || echo no)
      name="r6_${size}_${serie#r6}_$(printf '%02d' "$rep")"
      n0=$(log_lines)
      if [ "$serie" = r6up ]; then
        before_n=$(copies)
        open=$(py ui.py find "^Subir respaldo$"); adb shell input tap $open; sleep 1.5
        xy=$(py ui.py find "^Subir$")
        [ -n "$xy" ] || { echo "no apareció el diálogo de subida"; exit 1; }
        log=$(bash "$here/record_tap.sh" "$name" ${xy% *} ${xy#* } "$limit" "$out/video")
        roi="0,700,1080,800"   # fila nueva de la lista (el aviso temporal queda debajo)
        row_seen=$(py ui.py find "^Copia del .* SHA-256")
        after_n=$(copies)
        [ -n "$row_seen" ] || err="sin la copia en la lista al terminar la grabación"
        [ "$after_n" = $((before_n + 1)) ] || err="${err:+$err; }copias AVAILABLE ${before_n}->${after_n}"
      else
        row=$(py ui.py find "^Restaurar$"); [ -n "$row" ] || { echo "no hay copias"; exit 1; }
        log=$(bash "$here/record_tap.sh" "$name" ${row% *} ${row#* } "$limit" "$out/video")
        roi="0,850,1080,900"   # diálogo «¿Restaurar esta copia?» con la verificación SHA-256
        verified=$(py ui.py find "verificada con SHA-256")
        cancel=$(py ui.py find "^Cancelar$")
        [ -n "$verified" ] || err="sin «verificada con SHA-256» al terminar la grabación"
        [ -n "$cancel" ] && adb shell input tap $cancel
      fi
      sleep 2
      reqs=$(tail -n +$((n0 + 1)) "$F03_RUN_DIR/requests.log" | awk '{print $1" "$2" "$3" "$4}' | tr '\n' ';')
      # Bytes que midió el servidor de la copia AVAILABLE más reciente de la cuenta D.
      bytes=$(docker exec "$F03_PG_CONTAINER" psql -U postgres -d "$F03_PG_DB" -At -c "SELECT b.\"sizeBytes\" FROM \"BackupMetadata\" b JOIN \"Member\" m ON m.id = b.\"memberId\" JOIN \"User\" u ON u.id = m.\"userId\" WHERE u.email = '$F03_FARMER_D_EMAIL' AND b.status = 'AVAILABLE' ORDER BY b.\"createdAt\" DESC LIMIT 1" 2>/dev/null || true)
      [ -n "${xy:-}" ] && json=$(py frames.py "$out/video/$name.mp4" --start touch --tap "${xy/ /,}" --start-roi 760,94,320,35 --end-roi "$roi" --frames-dir "$out/frames" || true)
      [ -z "${xy:-}" ] && json=$(py frames.py "$out/video/$name.mp4" --start touch --tap "${row/ /,}" --start-roi 760,94,320,35 --end-roi "$roi" --frames-dir "$out/frames" || true)
      when=$(echo "$log" | sed -n -E 's/^toque_utc=(.*)/\1/p'); sha=$(echo "$log" | sed -n -E 's/.*sha256=([0-9a-f]+).*/\1/p')
      echo "r6,$size,${serie#r6},$rep,$warm,$when,$(row_from "$json"),$reqs,$bytes,$err,$sha" >> "$csv"
      echo "$name: $(row_from "$json") ${err:+ERROR: $err}"
      xy=""; row=""
      sleep 15
    done
    ;;
  *)
    echo "serie desconocida: $serie"; exit 2 ;;
esac
