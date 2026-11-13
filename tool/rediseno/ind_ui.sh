#!/usr/bin/env bash
# Manejo del emulador para «AC IND» (.ind). Cada orden comprueba antes que
# .ind esté en primer plano: nunca toca otra app (.demo, .et1…).
# No usar con un campo de contraseña o PIN a la vista: uiautomator expone el
# texto de los campos.
#
#   ind_ui.sh shot <archivo.png>      captura de pantalla
#   ind_ui.sh tap "<texto o desc>"    toca el primer nodo cuyo text/content-desc lo contiene
#   ind_ui.sh has "<texto>"           0 si está en pantalla
#   ind_ui.sh type "<texto>"          teclea (espacios → %s)
#   ind_ui.sh key <código>            tecla (4 = Atrás)
#   ind_ui.sh xy <x> <y>              toca coordenadas
set -uo pipefail
export MSYS_NO_PATHCONV=1
SERIAL=${IND_SERIAL:-emulator-5556}; PKG=com.comunidad.agro.agroquimicos.ind
a() { adb -s "$SERIAL" "$@"; }
guard() {
  local fg; fg=$(a shell dumpsys window | tr -d '\r' | grep -m1 -E 'mCurrentFocus=' | sed -E 's/.* u[0-9]+ ([^/ }]+).*/\1/')
  [ "$fg" = "$PKG" ] || { echo "ABORTADO: en primer plano está '${fg:-nada}', no $PKG"; exit 1; }
}
dump() { a exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\r' | grep -o '<?xml.*</hierarchy>'; }
find_xy() {
  python -I -X utf8 -c '
import sys, re, html
xml, needle = sys.stdin.read(), sys.argv[1]
for node in re.findall(r"<node [^>]*>", xml):
    t = html.unescape(re.search(r" text=\"([^\"]*)\"", node).group(1))
    d = html.unescape(re.search(r" content-desc=\"([^\"]*)\"", node).group(1))
    if needle in t or needle in d:
        x1, y1, x2, y2 = map(int, re.search(r"bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", node).groups())
        print((x1 + x2) // 2, (y1 + y2) // 2); sys.exit(0)
sys.exit(1)' "$1"
}
cmd=${1:-}; shift || true
case "$cmd" in
  shot) guard; a exec-out screencap -p > "${1:?archivo}" ;;
  tap) guard; xy=$(dump | find_xy "$1") || { echo "no encontrado: $1"; exit 1; }; guard; a shell input tap $xy; echo "tocado: $1 ($xy)" ;;
  has) guard; dump | find_xy "$1" > /dev/null ;;
  type) guard; a shell input text "${1// /%s}" ;;
  key) guard; a shell input keyevent "${1:?código}" ;;
  xy) guard; a shell input tap "${1:?x}" "${2:?y}" ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac
