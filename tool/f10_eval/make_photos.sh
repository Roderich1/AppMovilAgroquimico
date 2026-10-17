#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.4, DS-B): fotografías SINTÉTICAS de comprobante
# para los respaldos de R6. JPEG 1600×1200 válidos (~0,84 MB: ruido 50, calidad 4), deterministas (ruido de ffmpeg
# con semilla fija por foto), sin contenido personal.
#   make_photos.sh <carpeta-destino-vacía> <cantidad>
# Escribe dsv_photo_001.jpg … y un manifiesto SHA256SUMS.
set -euo pipefail
out="${1:?Carpeta destino}"
n="${2:?Cantidad de fotos}"
mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || { echo "La carpeta destino no está vacía: $out"; exit 1; }
for i in $(seq 1 "$n"); do
  name=$(printf 'dsv_photo_%03d.jpg' "$i")
  ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=0x6b8e23:s=1600x1200:d=1" \
    -vf "noise=alls=50:allf=u:all_seed=$((20261016 + i))" \
    -frames:v 1 -q:v 4 -map_metadata -1 "$out/$name"
done
(cd "$out" && sha256sum dsv_photo_*.jpg > SHA256SUMS)
echo "fotos: $n en $out ($(du -sb "$out" | awk '{print $1}') bytes con el manifiesto)"
