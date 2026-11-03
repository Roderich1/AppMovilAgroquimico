#!/usr/bin/env bash
# Teclea el PIN del holder SÓLO si el campo enfocado del POCO es de contraseña
# (guarda añadida el 2026-11-01 tras un incidente: un PIN cayó en un campo de texto
# visible). Nunca imprime el contenido de la pantalla.
set -u
RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
focused=$(adb -s ${EST_SERIAL:-cc14247a} exec-out uiautomator dump /dev/tty 2>/dev/null | grep -o '<node[^>]*>' | grep 'class="android.widget.EditText"' | grep 'focused="true"' | head -1)
echo "$focused" | grep -q 'password="true"' || { echo "ABORTADO: el campo enfocado no es de contraseña; no se teclea el PIN"; exit 3; }
rm -f "$RUN/pin/typed"; touch "$RUN/pin/type"
for _ in $(seq 1 20); do [ -f "$RUN/pin/typed" ] && break; sleep 0.5; done
[ -f "$RUN/pin/typed" ] && echo "PIN tecleado por el guardián en un campo de contraseña" || { echo "el guardián no tecleó"; exit 1; }
