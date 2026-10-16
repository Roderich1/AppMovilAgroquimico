# F06-COLL-02 (#32) — Armonización de aplicaciones multiproducto

- **Fecha real:** 2026-10-16.
- **Rama:** `feat/f06-consumption-total` (`c82f3fb`, `0ef9e05`).
- **Requisitos:** RF-13, RF-24.
- **Revisión:** técnica automatizada. No hay revisión del autor ni del tutor.

## Nota de diseño

El contrato F06 **no proyecta aplicaciones**: proyecta totales por campaña × producto × unidad base (§2). La armonización entre Mobile y Central consiste en que una aplicación con N productos aporte a N totales. Cada línea suma a su producto y ninguna se fusiona con otra.

## Criterios del issue

| Criterio | Resolución | Evidencia | Resultado |
|---|---|---|---|
| Cada línea conserva producto, cantidad, unidad, parcela y fecha, sin fusiones | **Gana el contrato.** F06 §2 y §5 excluyen parcelas, fechas y detalle de aplicaciones. Cada línea aporta su cantidad al total de su producto, en su unidad base; ninguna se pierde ni se fusiona con otro producto | `consumption_projection_test.dart` «una aplicación con tres productos aporta exactamente a tres totales»; `collective_consumption_sync_test.dart` «MOB #32: una aplicación con 3 productos da 3 totales…» | PASS (alcance del contrato) |
| Un fallo en una línea no deja un consumo parcial | La publicación encola todos los totales en una transacción, o ninguno | «si falla un total, no se encola ninguno» | PASS |
| Notas, relaciones y adjuntos privados quedan fuera | El envelope sólo lleva los 4 campos F06 | «el envelope lleva sólo los cuatro campos de F06» | PASS |
| Central agrega por campaña y producto lo confirmado en Mobile, separado de la necesidad declarada | Reconciliación con dataset controlado (aplicaciones A1 y A4 multiproducto; A13 multiproducto revertida); `CONSUMPTION_TOTAL` y `DECLARED_NEED` en celdas distintas; diferencia 0 | `F06_RECONCILIATION.md` (Backend); [`F06_RUN_20261016/`](F06_RUN_20261016/) | PASS |

**Discrepancia anotada.** El issue pedía `test/application_sync_contract_test.dart`. La cobertura está en las suites citadas, porque no existe un contrato de aplicaciones que probar.
