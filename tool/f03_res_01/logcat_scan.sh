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
echo "contraseñas del ensayo: $secret_hits (las de credential.sh son de un solo uso y no se conservan: ver la línea siguiente)"
echo "nombres de campos sensibles (refresh_token, accessToken, password): $(count 'refresh_?token|accessToken|password')"
echo "FATAL/Unhandled: $(count 'FATAL|Unhandled Exception')"
# Ampliación del 2026-10-16 (addendum de #71): el refresh token de Auth V2 es opaco
# (base64url), no un JWT; y los nombres de campo se buscan sin distinguir mayúsculas.
opaque='[A-Za-z0-9_-]{43,}'
fields='authorization|bearer|password|passwd|refresh_?token|access_?token|set-cookie|client_?id'
echo "valores opacos de 43+ caracteres (refresh tokens): $(count "$opaque")"
echo "campos sensibles sin distinguir mayúsculas: $(grep -c -i -E "$fields" <<< "$log" || true)"
# Registro propio de la app aislada (app_flutter/agrocuentas.log): mismos conteos.
own=$(MSYS_NO_PATHCONV=1 adb exec-out run-as "$F03_APP_PACKAGE" cat app_flutter/agrocuentas.log 2>/dev/null || true)
echo "registro propio: líneas=$(grep -c . <<< "$own" || true)" \
  "JWT=$(grep -c -E 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' <<< "$own" || true)" \
  "UUID=$(grep -c -E '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<< "$own" || true)" \
  "refresh/token/password=$(grep -c -i -E 'refresh_?token|accessToken|password' <<< "$own" || true)" \
  "opacos43=$(grep -c -E "$opaque" <<< "$own" || true)" \
  "campos=$(grep -c -i -E "$fields" <<< "$own" || true)"
