#!/usr/bin/env bash
# OE3 (2026-11-04): verificación en EMULADOR del «+» y de Sincronización sin botón
# flotante, a una escala de letra. Requiere la app de la DEMO (`.demo`) instalada
# desde esta rama, una intención pausada por versión y el emulador en primer plano.
#   fab_emulador_check.sh <escala> <carpeta>     p. ej. 1.3
set -uo pipefail
scale=${1:?escala}; out=${2:?carpeta}; mkdir -p "$out"
export ANDROID_SERIAL=${ANDROID_SERIAL:-emulator-5554}
export MSYS2_ARG_CONV_EXCL="/sdcard;/data/local;/dev/tty"
PKG=com.comunidad.agro.agroquimicos.demo
dump() { adb exec-out uiautomator dump /dev/tty 2>/dev/null | grep -o '<node[^>]*>'; }
center() { grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 | grep -o '[0-9]*' | tr '\n' ' ' | awk '{print int(($1+$3)/2), int(($2+$4)/2)}'; }
bounds() { grep -o 'bounds="[^"]*"' | head -1 | sed 's/bounds=//; s/"//g'; }
shot() { adb exec-out screencap -p > "$out/$1.png"; }
report() { echo "escala $scale · $*"; }

adb shell settings put system font_scale "$scale"
adb shell am force-stop "$PKG"; adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; sleep 6

# 1. Sincronización: sin «+» y «Reintentar con esta versión» pulsable.
node=$(dump | grep -E 'text="Enviar al sindicato"|content-desc="Enviar al sindicato' | head -1)
adb shell input tap $(echo "$node" | center); sleep 3
for _ in 1 2 3 4; do
  dump | grep -qE '(text|content-desc)="Reintentar con esta versión"' && break
  adb shell input swipe 540 1700 540 900 400; sleep 1
done
retry=$(dump | grep -E '(text|content-desc)="Reintentar con esta versión"' | head -1)
fab=$(dump | grep -c 'Registrar operaci')
report "Sincronización: «+» presentes=$fab; «Reintentar con esta versión» $( [ -n "$retry" ] && echo "en $(echo "$retry" | bounds)" || echo AUSENTE)"
shot "sincronizacion-$scale"
if [ -n "$retry" ]; then
  adb shell input tap $(echo "$retry" | center); sleep 2
  dialog=$(dump | grep -cE 'text="Reintentar"|content-desc="Reintentar"')
  sheet=$(dump | grep -cE 'text="Planificación"|content-desc="Planificación')
  report "toque en «Reintentar con esta versión»: confirmación=$dialog; menú de creación=$sheet"
  shot "sincronizacion-confirmacion-$scale"
  cancel=$(dump | grep -E 'text="Cancelar"|content-desc="Cancelar"' | head -1)
  [ -n "$cancel" ] && adb shell input tap $(echo "$cancel" | center); sleep 1
fi

# 2. Operaciones: «+» sin texto, tamaño, nombre accesible y menú.
tab=$(dump | grep -E 'content-desc="Operaciones' | head -1)
adb shell input tap $(echo "$tab" | center); sleep 3
plus=$(dump | grep 'Registrar operaci' | head -1)
names=$(dump | grep -c 'content-desc="Registrar operación"')
nuevo=$(dump | grep -cE 'text="Nuevo"|content-desc="Nuevo"')
report "Operaciones: «+» en $(echo "$plus" | bounds); text=\"$(echo "$plus" | grep -o 'text="[^"]*"' | head -1 | sed 's/text=//')\"; nodos con el nombre=$names; «Nuevo» visibles=$nuevo"
shot "operaciones-$scale"
# Último elemento desplazable frente al «+».
for _ in 1 2 3; do adb shell input swipe 540 1600 540 600 300; sleep 1; done
last=$(dump | grep -E 'content-desc="Más|text="Más' | head -1)
report "Operaciones desplazada al final: «Más» en $(echo "$last" | bounds); «+» en $(dump | grep 'Registrar operaci' | head -1 | bounds)"
shot "operaciones-final-$scale"
adb shell input tap $(echo "$plus" | center); sleep 2
opts=$(dump | grep -oE '(text|content-desc)="(Registrar operación|Planificación|Compra|Aplicación|Pago|Transferencia)"' | sed 's/.*="//; s/"//' | sort -u | tr '\n' ',')
report "menú del «+»: $opts"
shot "menu-$scale"
adb shell input keyevent KEYCODE_BACK; sleep 1
