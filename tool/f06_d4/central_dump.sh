#!/usr/bin/env bash
# F06 (D4): volcado de SÓLO LECTURA de las aportaciones de Central en una base
# desechable, con los agricultores y campañas rotulados como en el dataset
# (F1–F3, C1–C2). Formato de F06_EXPECTED_CONTRIBUTIONS.csv.
# Uso: central_dump.sh [base]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
db="${1:-$F06_DB_HOST}"
echo "farmer,campaign,projection_type,product,base_unit,status,quantity_base"
f06_psql "SELECT CASE u.email WHEN '$F06_F1_EMAIL' THEN 'F1' WHEN '$F06_F2_EMAIL' THEN 'F2'
    WHEN '$F06_F3_EMAIL' THEN 'F3' ELSE 'OTRO' END,
  CASE c.name WHEN 'Campana Verano 2026' THEN 'C1' WHEN 'Campana Invierno 2026' THEN 'C2' ELSE 'OTRA' END,
  s.\"projectionType\", p.name, s.\"baseUnit\", s.status, COALESCE(s.\"quantityBase\"::text, '')
FROM \"SyncV1Contribution\" s
JOIN \"Member\" m ON m.id = s.\"memberId\" JOIN \"User\" u ON u.id = m.\"userId\"
JOIN \"AgriculturalCampaign\" c ON c.id = s.\"campaignId\" JOIN \"Product\" p ON p.id = s.\"productId\"
ORDER BY 1, 2, 3, 4" "$db"
