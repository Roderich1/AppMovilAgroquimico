#!/usr/bin/env bash
# F03-RES-01 (#71) y E2E de D3: contraseñas de un solo uso, sin archivos.
#   credential.sh type <ADMIN|D|E2|S>        asigna a la cuenta una contraseña nueva y la
#                                            teclea en el campo enfocado del teléfono
#   credential.sh run <ADMIN|D|E2|S> <cmd>   asigna una contraseña nueva y ejecuta <cmd> con
#                                            F03_<cuenta>_PASSWORD sólo en su entorno
# La contraseña vive sólo en este proceso: no se imprime ni se escribe. Cada uso la
# reemplaza, así que la anterior deja de servir. No cierra ni toca sesiones existentes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"

mode="${1:-}"; who="${2:-}"
case "$who" in
  ADMIN) email="$F03_ADMIN_EMAIL"; var=F03_ADMIN_PASSWORD ;;
  D) email="$F03_FARMER_D_EMAIL"; var=F03_FARMER_D_PASSWORD ;;
  E2) email="$F03_FARMER_E2_EMAIL"; var=F03_FARMER_E2_PASSWORD ;;
  S) email="$F03_FARMER_S_EMAIL"; var=F03_FARMER_S_PASSWORD ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac

# El openssl de Git Bash termina en CRLF: un \r no se puede teclear en Android.
password=$(openssl rand -base64 18 | tr -d '\r\n/+=')
bcrypt_dir="$(cygpath -m "$F03_BE_DIR")/node_modules/bcrypt"
hash=$(PASSWORD="$password" node -e \
  'process.stdout.write(require(process.argv[1]).hashSync(process.env.PASSWORD, 12))' "$bcrypt_dir")
# El hash viaja por stdin; sólo contiene [./$A-Za-z0-9].
updated=$(printf "UPDATE \"User\" SET \"passwordHash\" = '%s' WHERE email = '%s';\n" "$hash" "$email" \
  | docker exec -i "$F03_PG_CONTAINER" psql -U postgres -d "$F03_PG_DB" -At)
[ "$updated" = "UPDATE 1" ] || { echo "no se pudo asignar la contraseña de $who"; exit 1; }

case "$mode" in
  type)
    adb shell input text "$password"
    echo "contraseña nueva de $who tecleada en el teléfono (no se muestra)"
    ;;
  run)
    shift 2
    export "$var=$password"
    "$@"
    ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
