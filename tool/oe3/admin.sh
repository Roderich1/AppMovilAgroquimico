#!/usr/bin/env bash
# OE3: acciones del Administrador sintético sobre el Agricultor, por la API REAL a
# través del túnel (patrón de tool/f03_res_01/revoke.sh). La contraseña del
# Administrador es nueva y de un solo uso, vive sólo en este proceso y nunca se imprime.
#   admin.sh deactivate   PATCH users/{agricultor}/deactivate
#   admin.sh activate     PATCH users/{agricultor} {"isActive":true}
#   admin.sh create-farmer-b   POST users: segundo Agricultor (correo en $RUN/farmerB_email)
#   admin.sh post <ruta> [json]   POST /api/v1/<ruta> como Administrador (sólo el código HTTP)
# Sólo muestra códigos HTTP.
set -euo pipefail
ROOT=/c/Users/MSI/Documents/ProyectoDeGrado/ProyectoAgro
here="$ROOT/_wt/OE3-DEV-MOB/tool/f03_res_01"
BE=${EST_BE:-$ROOT/_wt/F12-EST-08/Back}
RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
ids=$(cygpath -w "$RUN/ids.json")
get() { node -e "process.stdout.write(String(require(process.argv[1])[process.argv[2]]))" "$ids" "$1"; }
origin=$(cat "$RUN/origin"); db=$(get database); admin=$(get adminEmail); farmer=$(get farmerEmail)
action=${1:?deactivate|activate}
password=$(openssl rand -base64 18 | tr -d '\r\n/+=')
hash=$(PASSWORD="$password" node -e 'process.stdout.write(require(process.argv[1]).hashSync(process.env.PASSWORD, 10))' "$(cygpath -m "$BE/node_modules/bcrypt")")
updated=$(printf "UPDATE \"User\" SET \"passwordHash\" = '%s' WHERE email = '%s';\n" "$hash" "$admin" | docker exec -i agro_oe3_pg psql -U postgres -d "$db" -At)
[ "$updated" = "UPDATE 1" ] || { echo "no se pudo asignar la contraseña"; exit 1; }
user_id=$(printf "SELECT id FROM \"User\" WHERE email = '%s';\n" "$farmer" | docker exec -i agro_oe3_pg psql -U postgres -d "$db" -At)
response=$(EMAIL="$admin" PASSWORD="$password" node -e \
  'process.stdout.write(JSON.stringify({email:process.env.EMAIL,password:process.env.PASSWORD,refreshTransport:"BODY"}))' \
  | curl -s -H 'Content-Type: application/json' --data-binary @- "$origin/api/v1/auth/v2/login")
password=
ACCESS=$(node "$here/json.cjs" get accessToken <<< "$response")
REFRESH=$(node "$here/json.cjs" get refreshToken <<< "$response")
response=
[ -n "$ACCESS" ] || { echo "login del Administrador falló"; exit 1; }
auth_config() { printf 'header = "Authorization: Bearer %s"\n' "$ACCESS"; }
case "$action" in
  deactivate)
    code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -K - "$origin/api/v1/users/$user_id/deactivate" <<< "$(auth_config)") ;;
  activate)
    code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H 'Content-Type: application/json' --data '{"isActive":true}' \
      -K - "$origin/api/v1/users/$user_id" <<< "$(auth_config)") ;;
  create-farmer-b)
    # P-05: segundo Agricultor sintético del mismo sindicato. Su contraseña inicial
    # es aleatoria y se descarta: se entra con `OE3_FARMER=B oe3.sh credential`.
    emailB="farmerB-oe3-$(openssl rand -hex 4 | tr -d '\r\n')@example.test"
    # La petición la hace node: el token y la contraseña viajan sólo por el entorno.
    code=$(EMAIL="$emailB" PASSWORD="$(openssl rand -base64 18 | tr -d '\r\n/+=')" TOKEN="$ACCESS" URL="$origin/api/v1/users" node -e \
      'fetch(process.env.URL,{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${process.env.TOKEN}`},
        body:JSON.stringify({name:"Beatriz Sintetica",email:process.env.EMAIL,password:process.env.PASSWORD,role:"AGRICULTOR"})})
        .then((r)=>process.stdout.write(String(r.status)),()=>process.stdout.write("error"))')
    [ "$code" = 201 ] && echo "$emailB" > "$RUN/farmerB_email" ;;
  post)
    # C16/C18/C19: POST /api/v1/<ruta> con cuerpo JSON opcional (p. ej. cerrar una
    # campaña o desactivar un producto del sindicato). Sólo se muestra el código.
    code=$(TOKEN="$ACCESS" URL="$origin/api/v1/${2:?ruta}" BODY="${3:-{\}}" node -e \
      'fetch(process.env.URL,{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${process.env.TOKEN}`},body:process.env.BODY})
        .then((r)=>process.stdout.write(String(r.status)),()=>process.stdout.write("error"))')
    action="POST $2" ;;
  *) echo "acción desconocida"; exit 2 ;;
esac
case "$action" in "POST "*) echo "$(date -u +%FT%TZ) $action: HTTP $code" ;; *) echo "$(date -u +%FT%TZ) $action del Agricultor: HTTP $code" ;; esac
lcode=$(REFRESH="$REFRESH" node -e 'process.stdout.write(JSON.stringify({refreshToken:process.env.REFRESH}))' \
  | curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$origin/api/v1/auth/v2/logout")
ACCESS=; REFRESH=
echo "logout de la sesión del Administrador: HTTP $lcode"
