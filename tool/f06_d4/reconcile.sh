#!/usr/bin/env bash
# F06 (D4): reconciliación automatizada desde el host contra la API 3200.
# Rota las contraseñas de la base (sólo en esta shell), ejecuta dos veces
# test/f06_reconciliation_integration_test.dart (la segunda reenvía todo),
# vuelca Central en sólo lectura y lo compara con el oráculo escrito a mano.
# Exige una base sin aportaciones: cada corrida usa una base nueva.
# Uso: F06_BE_DIR=... F06_MOB_DIR=... reconcile.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
: "${F06_MOB_DIR:?Defina F06_MOB_DIR con la raíz de un worktree móvil}"

existing="$(f06_psql 'SELECT count(*) FROM "SyncV1Contribution"')"
[ "$existing" = 0 ] || { echo "la base $F06_DB_HOST ya tiene $existing aportaciones: use una base nueva"; exit 1; }

export AGRO_E2E_BASE_URL="http://127.0.0.1:${F06_API_PORT_HOST}"
export AGRO_E2E_WORKDIR="$F06_RUN_DIR/host_$(date -u +%Y%m%dT%H%M%SZ)"
echo "carpeta de la corrida: $AGRO_E2E_WORKDIR; base: $F06_DB_HOST"
export AGRO_E2E_F1_EMAIL="$F06_F1_EMAIL" AGRO_E2E_F2_EMAIL="$F06_F2_EMAIL"
export AGRO_E2E_F3_EMAIL="$F06_F3_EMAIL" AGRO_E2E_DIRECTIVA_EMAIL="$F06_DIRECTIVA_EMAIL"
for who in F1 F2 F3 DIRECTIVA; do export "AGRO_E2E_${who}_PASSWORD=$(f06_rand 18)"; done
F06_BE_DIR="$F06_BE_DIR" node "$here/rotate_passwords.cjs" \
  "$F06_F1_EMAIL=AGRO_E2E_F1_PASSWORD" "$F06_F2_EMAIL=AGRO_E2E_F2_PASSWORD" \
  "$F06_F3_EMAIL=AGRO_E2E_F3_PASSWORD" "$F06_DIRECTIVA_EMAIL=AGRO_E2E_DIRECTIVA_PASSWORD" |
  docker exec -i "$F06_PG_CONTAINER" psql -U postgres -d "$F06_DB_HOST" -q -v ON_ERROR_STOP=1 > /dev/null
echo "contraseñas rotadas en $F06_DB_HOST (valores no mostrados)"

cd "$F06_MOB_DIR"
for run in 1 2; do
  echo "== ejecución $run $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  flutter test test/f06_reconciliation_integration_test.dart --reporter expanded \
    > "$AGRO_E2E_WORKDIR.execution$run.log" 2>&1 && rc=0 || rc=$?
  grep -E "E2E F06|^  (F[123] |RAW|CANONICAL|informe)|All tests|Some tests|\[E\]|Exception|Expected|Actual|Which" \
    "$AGRO_E2E_WORKDIR.execution$run.log" | head -80
  [ "$rc" = 0 ] || { echo "ejecución $run falló (rc=$rc)"; exit "$rc"; }
done

bash "$here/central_dump.sh" > "$AGRO_E2E_WORKDIR/central_contributions.csv"
python -I "$here/oracle_check.py" docs/evidence --central "$AGRO_E2E_WORKDIR/central_contributions.csv"
echo "journal: $(f06_psql 'SELECT count(*) FROM "SyncV1OperationJournal"') operaciones;" \
  "liberaciones: $(f06_psql 'SELECT count(*) FROM "CollectiveRelease"');" \
  "asociaciones vigentes: $(f06_psql 'SELECT count(*) FROM "ProductCanonicalAssociation" WHERE "validTo" IS NULL')"
