#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.2 §1.4, DS-B): deja la copia aislada `.f10eval` con la
# composición de un tamaño de R6 (S1 = 1 foto, S2 = 12, S3 = 62). Fixture, no un flujo
# medido: con la app DETENIDA extrae la base, asocia las fotos con attach_photos.py, copia
# al paquete sólo las fotos que faltan y devuelve la base, comprobando SHA-256 en los dos
# extremos. Nunca borra filas ni fotos.
#   prepare_r6.sh <S1|S2|S3> <carpeta-de-fotos>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
size="${1:?S1|S2|S3}"; photos="${2:?carpeta de fotos}"
: "${F03_APP_PACKAGE:?cargue el entorno}" "${ANDROID_SERIAL:?fije ANDROID_SERIAL}"
case "$size" in S1) n=1 ;; S2) n=12 ;; S3) n=62 ;; *) echo "tamaño $size"; exit 2 ;; esac
pkg="$F03_APP_PACKAGE"
work="$F03_RUN_DIR/r6prep/$size"; mkdir -p "$work"
ra() { MSYS_NO_PATHCONV=1 adb "$@"; }

ra shell am force-stop "$pkg"
journal=$(ra exec-out run-as "$pkg" sh -c 'od -v -A n -t x1 -N 32 databases/agroquimicos_v2.db-journal 2>/dev/null' | tr -d ' \r\n' || true)
case "$journal" in ""|*[!0]*) [ -z "$journal" ] || { echo "journal no vacío: la base podría estar a mitad de una transacción"; exit 1; } ;; esac
ra exec-out run-as "$pkg" cat databases/agroquimicos_v2.db > "$work/agroquimicos_v2.db"
echo "extraída: $(sha256sum "$work/agroquimicos_v2.db" | cut -c1-16) / dispositivo: $(ra exec-out run-as "$pkg" sha256sum databases/agroquimicos_v2.db | cut -c1-16)"

list=()
for i in $(seq 1 "$n"); do list+=("$photos/$(printf 'dsv_photo_%03d.jpg' "$i")"); done
python -I -X utf8 "$here/attach_photos.py" "$work/agroquimicos_v2.db" "$n" "$pkg" "${list[@]}"

ra shell run-as "$pkg" mkdir -p app_flutter/invoices
present=$(ra exec-out run-as "$pkg" ls -1 app_flutter/invoices 2>/dev/null | tr -d '\r' || true)
copied=0
for f in "${list[@]}"; do
  name=$(basename "$f")
  echo "$present" | grep -qx "$name" && continue
  ra push "$(cygpath -m "$f")" "/data/local/tmp/$name" > /dev/null
  ra shell run-as "$pkg" cp "/data/local/tmp/$name" "app_flutter/invoices/$name"
  ra shell rm "/data/local/tmp/$name"
  want=$(sha256sum "$f" | cut -c1-64); got=$(ra exec-out run-as "$pkg" sha256sum "app_flutter/invoices/$name" | cut -c1-64)
  [ "$want" = "$got" ] || { echo "SHA distinto en $name"; exit 1; }
  copied=$((copied + 1))
done
echo "fotos copiadas ahora: $copied; en el paquete: $(ra exec-out run-as "$pkg" ls -1 app_flutter/invoices | grep -c dsv_photo_)"

ra push "$(cygpath -m "$work/agroquimicos_v2.db")" /data/local/tmp/f10eval_r6.db > /dev/null
ra shell run-as "$pkg" cp /data/local/tmp/f10eval_r6.db databases/agroquimicos_v2.db
ra shell rm /data/local/tmp/f10eval_r6.db
host=$(sha256sum "$work/agroquimicos_v2.db" | cut -c1-64); dev=$(ra exec-out run-as "$pkg" sha256sum databases/agroquimicos_v2.db | cut -c1-64)
[ "$host" = "$dev" ] || { echo "SHA de la base distinto tras devolverla"; exit 1; }
echo "base devuelta: $host"
bash "$here/eval_counts.sh"
