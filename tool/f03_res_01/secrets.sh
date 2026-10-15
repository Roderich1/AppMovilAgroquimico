# F03-RES-01 (#71): genera secretos efímeros SÓLO en variables de entorno de
# esta shell (`source secrets.sh`). No escribe archivos ni imprime valores.
# Para ver una contraseña al teclearla en el teléfono:  echo "$F03_FARMER_D_PASSWORD"
# (en la terminal del operador; no copiarla a evidencias ni a logs).

_f03_rand() { openssl rand -base64 "$1" | tr -d '\n/+='; }

export F03_PG_PASSWORD="${F03_PG_PASSWORD:-$(_f03_rand 24)}"
export F03_JWT_SECRET="${F03_JWT_SECRET:-$(_f03_rand 48)}"
export F03_JWT_REFRESH_SECRET="${F03_JWT_REFRESH_SECRET:-$(_f03_rand 48)}"
export F03_ADMIN_PASSWORD="${F03_ADMIN_PASSWORD:-$(_f03_rand 18)}"
export F03_FARMER_D_PASSWORD="${F03_FARMER_D_PASSWORD:-$(_f03_rand 18)}"
export F03_FARMER_E2_PASSWORD="${F03_FARMER_E2_PASSWORD:-$(_f03_rand 18)}"

echo "secretos efímeros definidos en esta shell (valores no mostrados)"
