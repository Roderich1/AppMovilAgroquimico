-- Ronda 2 del rediseño, sesión C (P1a). SÓLO LECTURA: no modifica nada.
--
-- Lista los asientos de pago o adelanto de cuenta personal registrados a
-- quien es o era titular (clase «propia» del criterio Q-3 de
-- docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md §7):
--   * todos los PAYMENT/ADVANCE de la persona titular vigente (vínculo sin
--     ended_at), también los anteriores a su vínculo;
--   * los de quien era titular el día del asiento: día(bound_at) <= día <
--     día(ended_at); lo anterior al primer vínculo es del primer titular.
--
-- Desde el 2026-11-12 el repositorio rechaza registrar asientos así
-- (decisión del autor que revisa el criterio Q-2/C-12). Los que ya existen
-- se conservan y se muestran como registro («pagos y ajustes registrados»),
-- nunca como cobro. Esta consulta sólo los identifica.
--
-- Origen: la app no guarda desde qué pantalla se registró un pago
-- (reference_type = 'PAYMENT' o 'ADVANCE', reference_id NULL, notes NULL
-- desde la interfaz). Entre E-15 (2026-10-27) y el 2026-11-12 la única
-- entrada que registraba un pago a la persona titular era el menú
-- «Registrar pago» de la tarjeta «Consumo y costos propios» de Cuentas
-- (criterio Q-2), además de «Registrar adelanto» hasta el 2026-10-30.
-- Antes de E-15, un pago al titular se registraba desde su tarjeta como a
-- cualquier persona.
--
-- Días locales: SQLite usa la zona del sistema con 'localtime'; la app usa
-- la del teléfono, que es la misma en el dispositivo.
--
-- Uso (copia de la base, nunca la base en uso):
--   sqlite3 -readonly agroquimicos.db < tool/rediseno/asientos_pago_titular.sql
SELECT
  t.id AS asiento_id,
  t.person_id,
  p.name AS persona,
  t.type AS tipo,
  t.transaction_date AS fecha_utc,
  date(t.transaction_date, 'localtime') AS dia_local,
  t.campaign_id,
  c.name AS campana_de_registro,
  -t.amount_bob_minor_signed AS importe_centavos,
  t.reference_type,
  t.reference_id,
  t.notes,
  (
    SELECT COALESCE(SUM(a.amount_bob_minor), 0)
    FROM payment_allocations a
    WHERE a.payment_transaction_id = t.id
  ) AS imputado_centavos,
  (
    SELECT group_concat(a.charge_transaction_id || ':' || a.amount_bob_minor, ' ')
    FROM payment_allocations a
    WHERE a.payment_transaction_id = t.id
  ) AS imputaciones_cargo_importe,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM owner_bindings v
      WHERE v.ended_at IS NULL AND v.person_id = t.person_id
    ) THEN 'titular vigente'
    ELSE 'era titular ese día'
  END AS motivo
FROM account_transactions t
JOIN persons p ON p.id = t.person_id
LEFT JOIN campaigns c ON c.id = t.campaign_id
WHERE t.type IN ('PAYMENT', 'ADVANCE')
  AND (
    EXISTS (
      SELECT 1 FROM owner_bindings v
      WHERE v.ended_at IS NULL AND v.person_id = t.person_id
    )
    OR EXISTS (
      SELECT 1 FROM owner_bindings b
      WHERE b.person_id = t.person_id
        AND (
          NOT EXISTS (
            SELECT 1 FROM owner_bindings o
            WHERE o.bound_at < b.bound_at
               OR (o.bound_at = b.bound_at AND o.id < b.id)
          )
          OR date(t.transaction_date, 'localtime')
             >= date(b.bound_at, 'localtime')
        )
        AND (
          b.ended_at IS NULL
          OR date(t.transaction_date, 'localtime')
             < date(b.ended_at, 'localtime')
        )
    )
  )
ORDER BY t.transaction_date, t.id
