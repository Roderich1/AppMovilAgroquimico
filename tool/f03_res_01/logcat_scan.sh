#!/usr/bin/env bash
# F03-RES-01 (#71): revisa EN MEMORIA el logcat del proceso de la app aislada y
# sólo imprime conteos. No guarda ni muestra el logcat.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
uid=$(adb shell pm list packages -U "$F03_APP_PACKAGE" | grep -o -E 'uid:[0-9]+' | head -1 | cut -d: -f2)
[ -n "$uid" ] || { echo "app aislada no instalada"; exit 1; }
log=$(adb logcat -d --uid="$uid")
count() { grep -c -E "$1" <<< "$log" || true; }
secret_hits=0
for value in "${F03_FARMER_D_PASSWORD:-}" "${F03_FARMER_E2_PASSWORD:-}"; do
  [ -n "$value" ] && secret_hits=$((secret_hits + $(grep -c -F -f <(printf '%s\n' "$value") <<< "$log" || true)))
done
echo "líneas revisadas: $(wc -l <<< "$log")"
echo "JWT: $(count 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}')"
echo "UUID completos: $(count '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')"
echo "contraseñas del ensayo: $secret_hits"
echo "FATAL/Unhandled: $(count 'FATAL|Unhandled Exception')"
