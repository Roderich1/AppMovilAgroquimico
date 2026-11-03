#!/usr/bin/env bash
# Instala la APK aislada .oe3 en el POCO y pulsa «Instalar» SÓLO en el diálogo del
# sistema «Instalar vía USB» de MIUI (que se niega solo a los 10 s). Patrón de
# tool/f12_est_07/device_run.sh.
set -uo pipefail
serial=${EST_SERIAL:-cc14247a}
RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
apk="$RUN/apk/agrocuentas.oe3-profile-arm64.apk"
[ -f "$apk" ] || { echo "falta la APK"; exit 1; }
adb -s "$serial" shell input keyevent KEYCODE_WAKEUP
adb -s "$serial" install -r "$(cygpath -w "$apk")" > "$RUN/install.log" 2>&1 &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  node=$(adb -s "$serial" exec-out uiautomator dump /dev/tty 2>/dev/null | grep -o '<node[^>]*>' \
    | grep -E 'package="com\.(miui\.securitycenter|android\.packageinstaller|google\.android\.packageinstaller)"' \
    | grep -m1 -E 'text="(Instalar|Install)"' || true)
  if [ -n "$node" ]; then
    set -- $(echo "$node" | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | grep -o '[0-9]*' | tr '\n' ' ')
    adb -s "$serial" shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
    echo "$(date -u +%FT%TZ) diálogo de instalación por USB confirmado"
  fi
  sleep 1
done
wait "$pid"; rc=$?
tail -1 "$RUN/install.log"
echo "SHA-256 de la APK $(sha256sum "$apk" | awk '{print $1}')"
exit $rc
