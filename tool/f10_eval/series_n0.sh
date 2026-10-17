#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.5-§1.7): series R1, R2 y R3 sin red (N0) en la copia
# aislada `.f10eval`. Cada repetición graba la pantalla (record_tap.sh), calcula inicio y
# fin con frames.py y añade una fila al CSV crudo. Nada se descarta: un error queda en la
# fila con su causa. Las preparaciones (abrir pantallas, rellenar el formulario) no se miden.
#   series_n0.sh r1 <primera-rep> <última-rep>   (rep 0 = calentamiento, anotado aparte)
#   series_n0.sh r2 <primera-rep> <última-rep>    (serie R2-a: toque instantáneo; ver r2b)
#   series_n0.sh r2b <primera-rep> <última-rep>   (R2-b: toque sostenido y contacto visible)
#   series_n0.sh r3 <primera-rep> <última-rep>
# Requiere: source del entorno (env.sh + config.sh), ANDROID_SERIAL del POCO, modo avión
# activo y pointer_location=1 (show_touches no aparece en la grabación de este MIUI). Escribe en $F03_RUN_DIR/series/ (fuera de cualquier worktree).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
serie="${1:?r1|r2|r2b|r3}"; first="${2:?primera}"; last="${3:?última}"
: "${F03_APP_PACKAGE:?cargue el entorno}" "${ANDROID_SERIAL:?fije ANDROID_SERIAL}"
out="$F03_RUN_DIR/series/$serie"; mkdir -p "$out/video" "$out/frames"
csv="$F03_RUN_DIR/series/${serie}.csv"
[ -f "$csv" ] || echo "serie,rep,calentamiento,hora_utc,inicio_s,fin_s,duracion_ms,cuadro_inicio,cuadro_fin,cuadros,total_time_ms,comprobacion,error,video_sha256" > "$csv"
[ "$(adb shell settings get global airplane_mode_on | tr -d '\r')" = "1" ] || { echo "N0 exige modo avión"; exit 1; }
component="$F03_APP_PACKAGE/com.comunidad.agro.agroquimicos.MainActivity"
py() { python -I -X utf8 "$here/$1" "${@:2}"; }

counts() { bash "$here/eval_counts.sh" | sed -E 's/.*compras=([0-9]+) líneas_compra=([0-9]+).*/\1 \2/'; }

for rep in $(seq "$first" "$last"); do
  name="${serie}_$(printf '%02d' "$rep")"
  warm=$([ "$rep" = 0 ] && echo si || echo no)
  total=""; check=""; err=""
  case "$serie" in
    r1)
      adb shell am force-stop "$F03_APP_PACKAGE"
      adb shell input keyevent KEYCODE_HOME; sleep 3
      log=$(bash "$here/record_tap.sh" "$name" launch "$component" 8 "$out/video")
      total=$(echo "$log" | sed -n -E 's/.*TotalTime: ([0-9]+).*/\1/p')
      roi="0,700,1080,1350"; mode=(--start launch)
      ;;
    r2|r2b)
      read -r p0 l0 < <(counts)
      py ui.py purchase-form "Proveedor DSV 1" DSV-002 10 50 DSV-003 5 40 > /dev/null
      xy=$(py ui.py find "^Confirmar$")
      log=$(bash "$here/record_tap.sh" "$name" ${xy% *} ${xy#* } 6 "$out/video")
      roi="0,760,1080,760"; mode=(--start touch --tap "${xy/ /,}" --start-roi 760,94,320,35)
      sleep 1
      read -r p1 l1 < <(counts)
      check="compras ${p0}->${p1} lineas ${l0}->${l1}"
      [ $((p1 - p0)) = 1 ] && [ $((l1 - l0)) = 2 ] || err="persistencia: $check"
      ;;
    r3)
      adb shell input tap 540 2113; sleep 2   # pestaña Inventario
      xy=$(py ui.py find "^DSV-001 Producto sintético Físico")
      log=$(bash "$here/record_tap.sh" "$name" ${xy% *} ${xy#* } 5 "$out/video")
      roi="0,300,1080,1750"; mode=(--start touch --tap "${xy/ /,}" --start-roi 760,94,320,35)
      seen=$(py ui.py find "Distribución por persona")
      [ -n "$seen" ] && check="detalle DSV-001 visible" || err="no se abrió el detalle"
      adb shell input keyevent KEYCODE_BACK; sleep 1.5
      ;;
  esac
  when=$(echo "$log" | sed -n -E 's/^(toque|orden)_utc=(.*)/\2/p')
  sha=$(echo "$log" | sed -n -E 's/.*sha256=([0-9a-f]+).*/\1/p')
  json=$(py frames.py "$out/video/$name.mp4" "${mode[@]}" --end-roi "$roi" --frames-dir "$out/frames" || true)
  row=$(JSON="$json" python -I -X utf8 -c '
import json, os
try:
    r = json.loads(os.environ["JSON"])
except Exception:
    r = {"error": "análisis fallido"}
print(",".join(str(r.get(k, "")) for k in ("start_s", "end_s", "duration_ms", "start_frame", "end_frame", "frames")) + "," + r.get("error", ""))')
  ferr="${row##*,}"; row="${row%,*}"
  [ -n "$ferr" ] && err="${err:+$err; }$ferr"
  echo "$serie,$rep,$warm,$when,$row,$total,$check,$err,$sha" >> "$csv"
  echo "$serie rep $rep: ${row} total=${total:-} ${check} ${err:+ERROR: $err}"
done
