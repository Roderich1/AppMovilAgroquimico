#!/usr/bin/env bash
# F08-BKP: estado del servidor del ensayo, sin identificadores completos ni
# hashes: copias por estado y, para cada copia AVAILABLE, si el archivo del
# almacenamiento privado coincide en tamaño y SHA-256 con sus metadatos.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/env.sh"
source "$here/../f03_res_01/config.sh"
echo "copias por estado:"
f03_psql 'SELECT status, count(*) FROM "BackupMetadata" GROUP BY status ORDER BY status'
echo "integridad de las copias disponibles:"
f03_psql "SELECT left(id::text, 8), \"storageKey\", \"sizeBytes\", sha256 FROM \"BackupMetadata\" WHERE status='AVAILABLE' ORDER BY \"createdAt\"" |
while IFS='|' read -r short key size digest; do
  short=$(echo "$short" | xargs); key=$(echo "$key" | xargs); size=$(echo "$size" | xargs); digest=$(echo "$digest" | xargs)
  file="$BACKUP_STORAGE_DIR/objects/$key"
  if [ -f "$file" ] && [ "$(stat -c %s "$file")" = "$size" ] && [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$digest" ]; then
    echo "  copia $short…: archivo íntegro ($size bytes)"
  else
    echo "  copia $short…: NO coincide"
  fi
done
echo "staging: $(ls "$BACKUP_STORAGE_DIR/staging" 2>/dev/null | wc -l) archivo(s)"
echo "filas Sync v1: journal=$(f03_psql 'SELECT count(*) FROM "SyncV1OperationJournal"') contribuciones=$(f03_psql 'SELECT count(*) FROM "SyncV1Contribution"')"
