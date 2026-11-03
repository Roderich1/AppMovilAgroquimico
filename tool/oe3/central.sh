#!/usr/bin/env bash
# OE3: estado del Agricultor sintético en el Central desechable (agro_oe3_pg). Sólo
# conteos y estados; nunca hashes, tokens ni correos.
#   central.sh auth        registros de cliente y sesiones del Member del Agricultor
#   central.sh sql <consulta>   consulta de sólo lectura (usar :'member' para el Member)
set -euo pipefail
RUN=/c/Users/MSI/AppData/Local/Temp/agro_oe3
ids=$(cygpath -w "$RUN/ids.json")
db=$(node -e "process.stdout.write(require(process.argv[1]).database)" "$ids")
member=$(node -e "process.stdout.write(require(process.argv[1]).farmerMember)" "$ids")
q() { docker exec -i agro_oe3_pg psql -U postgres -d "$db" -At -F ' | ' -v member="$member" -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only = on;" -f - | sed 1d; }
case "${1:?orden}" in
  auth)
    q <<'SQL'
SELECT 'ClientRegistration ' || status || ' revocado=' || ("revokedAt" IS NOT NULL)::text || ' n=' || count(*)
  FROM "ClientRegistration" WHERE "memberId" = :'member' GROUP BY status, ("revokedAt" IS NOT NULL) ORDER BY 1;
SELECT 'AuthSession ' || status || ' n=' || count(*) FROM "AuthSession" WHERE "memberId" = :'member' GROUP BY status ORDER BY 1;
SQL
    ;;
  sql) shift; printf '%s\n' "$*" | q ;;
esac
