#!/usr/bin/env bash
# Guarda un PIN sintético de 6 dígitos SOLO en la memoria de este proceso y lo
# teclea en el POCO cuando aparece el archivo de señal $DIR/type. Nunca lo
# imprime ni lo escribe en disco. $DIR/quit termina el proceso (y el PIN muere
# con él). Bloque 2, E-12 (A, 2026-10-28); adaptado para OE3 (2026-11-03).
set -u
export ANDROID_SERIAL=${EST_SERIAL:-cc14247a}
DIR=${1:?directorio de señales}
mkdir -p "$DIR"; rm -f "$DIR/type" "$DIR/quit" "$DIR/typed"
gen() {
  while :; do
    p=$(od -An -N6 -tu1 /dev/urandom | awk '{for(i=1;i<=NF;i++) printf "%d", $i%10}')
    [ ${#p} -eq 6 ] || continue
    asc=1; desc=1; same=1
    for i in 1 2 3 4 5; do
      a=${p:i-1:1}; b=${p:i:1}
      [ $((b - a)) -eq 1 ] || asc=0
      [ $((a - b)) -eq 1 ] || desc=0
      [ "$a" = "$b" ] || same=0
    done
    [ $asc -eq 0 ] && [ $desc -eq 0 ] && [ $same -eq 0 ] && { echo "$p"; return; }
  done
}
PIN=$(gen)
echo "PIN sintético generado en memoria (no se muestra)"
n=0
while :; do
  if [ -f "$DIR/quit" ]; then PIN=; rm -f "$DIR/quit"; echo "fin: PIN descartado"; exit 0; fi
  if [ -f "$DIR/type" ]; then
    rm -f "$DIR/type"
    adb shell input text "$PIN" > /dev/null 2>&1
    n=$((n + 1)); echo "$n" > "$DIR/typed"
    echo "PIN tecleado ($n)"
  fi
  sleep 0.5
done
