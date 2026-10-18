#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.6): graba la pantalla, inyecta un toque y trae el vídeo.
#   record_tap.sh <nombre> <x> <y> <segundos-de-grabación> [<carpeta-destino>]
#   record_tap.sh <nombre> launch <componente> <segundos> [<carpeta>]   (R1: am start -W)
# El toque se ve en el vídeo con pointer_location=1 (lo activa y restaura el operador).
# Imprime la hora UTC del toque o de la orden y, en R1, el TotalTime de am start.
# Respeta ANDROID_SERIAL. No toca ningún paquete distinto del indicado.
set -euo pipefail
name="${1:?nombre}"; a="${2:?x|launch}"; b="${3:?y|componente}"; dur="${4:?segundos}"
out="${5:-${F03_RUN_DIR:?}/video}"
mkdir -p "$out"
remote="/sdcard/f10eval_rec/$name.mp4"
MSYS_NO_PATHCONV=1 adb shell mkdir -p /sdcard/f10eval_rec
# El codificador del POCO falla a 1080x2400 (err=-38): 720x1600, misma proporción. Otro
# equipo fija su tamaño con F10_REC_SIZE (HONOR 720x1612: tamaño nativo, serie 2).
MSYS_NO_PATHCONV=1 adb shell screenrecord --size "${F10_REC_SIZE:-720x1600}" --bit-rate 12000000 --time-limit "$dur" "$remote" &
rec=$!
sleep 1.5
if [ "$a" = "launch" ]; then
  echo "orden_utc=$(date -u +%FT%T.%3NZ)"
  MSYS_NO_PATHCONV=1 adb shell am start -W -n "$b" | tr -d '\r' | grep -E "TotalTime|WaitTime|Status" | tr '\n' ' '
  echo
else
  echo "toque_utc=$(date -u +%FT%T.%3NZ)"
  # Toque sostenido TAP_HOLD_MS (80 ms por defecto): con pointer_location=1 el contacto se ve
  # en el vídeo desde el primer cuadro (en este MIUI show_touches no aparece en la grabación).
  adb shell input swipe "$a" "$b" "$a" "$b" "${TAP_HOLD_MS:-80}"
fi
wait "$rec" || true
sleep 0.5
MSYS_NO_PATHCONV=1 adb pull "$remote" "$(cygpath -m "$out")/$name.mp4" > /dev/null
MSYS_NO_PATHCONV=1 adb shell rm "$remote"
echo "video=$out/$name.mp4 sha256=$(sha256sum "$out/$name.mp4" | cut -c1-16)"
