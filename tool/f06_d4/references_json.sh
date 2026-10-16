#!/usr/bin/env bash
# F06 (D4): referencias centrales del dataset (campañas y productos F06) con el
# formato de GET /api/v1/sync/v1/references, leídas en sólo lectura de una base
# desechable. Sirven para sembrar la base del teléfono sin usar su identidad.
# Uso: references_json.sh [base]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/config.sh"
db="${1:-$F06_DB_DEVICE}"
f06_psql "SELECT json_build_object('contractVersion', 1,
  'campaigns', (SELECT json_agg(json_build_object('campaign_ref', c.id, 'name', c.name, 'status', c.status,
      'start_date', to_char(c.\"startDate\" AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'),
      'end_date', NULL, 'accepts_contributions', c.status = 'ABIERTA' AND c.\"isActive\") ORDER BY c.name)
    FROM \"AgriculturalCampaign\" c JOIN \"Tenant\" t ON t.id = c.\"tenantId\"
    WHERE t.slug = 'default' AND c.name IN ('Campana Verano 2026', 'Campana Invierno 2026')),
  'products', (SELECT json_agg(json_build_object('product_ref', p.id, 'name', p.name, 'unit', p.unit,
      'base_unit', CASE upper(p.unit) WHEN 'L' THEN 'ML' WHEN 'KG' THEN 'G' END,
      'is_active', p.\"isActive\", 'linkable', upper(p.unit) IN ('L', 'KG')) ORDER BY p.name)
    FROM \"Product\" p JOIN \"Tenant\" t ON t.id = p.\"tenantId\"
    WHERE t.slug = 'default' AND p.name IN ('Belator', 'Bellator', 'Glifosato F06', 'Urea F06', 'Mancozeb F06')))" "$db"
