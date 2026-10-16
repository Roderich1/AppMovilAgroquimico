# F06-COLL-03 (#33) — Consumo total del titular publicado a Central

- **Fecha real:** 2026-10-16.
- **Rama:** `feat/f06-consumption-total`. Código en `c82f3fb`; dataset, oráculo y reconciliación en `0ef9e05` + `5e7ed78`; herramienta en `7be6aa0`.
- **Contrato:** [`F06_COLLECTIVE_PROJECTION_CONTRACT.md`](https://github.com/Roderich1/Agro_Sindicato_Backend-Web/blob/main/docs/architecture/F06_COLLECTIVE_PROJECTION_CONTRACT.md) §2, §3, §5 y §8.
- **Requisitos:** RF-13, RF-16, RF-24.
- **Revisión:** técnica automatizada (pruebas y mutaciones de abajo). No hay revisión del autor ni del tutor.

## Qué se implementó

| Pieza | Archivo | Comportamiento |
|---|---|---|
| Constructor puro | `lib/domain/sync/consumption_projection.dart` | Total por campaña vinculada × producto vinculado: suma exacta en `int` de 64 bits (sin `double`) de las aplicaciones `CONFIRMED` del **titular**, neta de reversiones. Por encima de `maxBaseQuantity`, el total se excluye por `overflow` y no se trunca. Familiares y terceros nunca se proyectan (RF-16). Lo que no está vinculado o tiene un vínculo inválido se excluye y se avisa |
| Publicación | `lib/data/sync/consumption_publisher.dart` | `preview()` es de sólo lectura. `publish(confirmada)` recalcula dentro de la misma transacción y la rechaza si la vista previa quedó desactualizada. Encola `PUBLISH`/`SUPERSEDE` **sólo** donde el total cambió, con el planner y la outbox de D3. Un total que se queda sin aplicaciones se corrige a 0. Un conflicto bloquea ese total hasta que el titular envía su total actual |
| Pantalla | `lib/presentation/screens/consumption_publish_screen.dart`, ruta `/sincronizacion/consumo` | Lista con cambios y exclusiones. Botón «Publicar consumo al sindicato» con diálogo de confirmación («Cada total sustituye al anterior; no se suma») |
| Envío | `SyncWorker` de D3, sin cambios | Mismo worker, mismo ACK y mismos reintentos |

**Envelope.** Sólo lleva los cuatro campos de la whitelist F06: `campaign_ref`, `product_ref`, `base_unit` y `quantity_base`. No viaja ninguna nota, persona, finca, costo ni foto.

**Reversión (RF-13).** Una reversión es siempre de la aplicación entera. `reverseApplication` hace cuatro cosas:

- marca `applications.status = 'REVERSED'` y `reversed_at`;
- cierra cada `application_consumptions` con `reversed_at`;
- inserta los movimientos compensatorios `APPLICATION_REVERSAL` en `inventory_movements`;
- revierte las cuentas.

El constructor lee el estado de la aplicación, no los movimientos. Una aplicación revertida no aporta a ningún total, y la publicación siguiente lo corrige con un `SUPERSEDE`.

## Pruebas (host)

| Suite | Casos | Resultado |
|---|---|---|
| `test/consumption_projection_test.dart` | 6: multiproducto, reversión, familiar, sin vínculo o con vínculo inválido, int64, ausencia | PASS |
| `test/collective_consumption_sync_test.dart` | 9: 3 totales y reversión; sólo lo que cambió, atómico y sin tocar el inventario; vista previa desactualizada; fallo atómico; compartido; envelope; worker y ACK; conflicto; sin titular | PASS |
| `test/consumption_publish_screen_test.dart` | 2: vista previa, confirmación y cancelación sin escribir; nada que publicar | PASS |
| `test/f06_dataset_test.dart` | 4: niveles SQLite y outbox de los tres agricultores del dataset frente al oráculo a mano; exclusiones | PASS |
| Suite completa (`flutter test`, `c82f3fb`) | 971 pasan | PASS |

**Mutaciones** (2026-10-16, reemplazo exacto y restauración byte a byte verificada): se detectaron las 13.

- **M1–M9** contra las suites de arriba:
  - M1: cuenta al familiar;
  - M2: cuenta las revertidas;
  - M3: sin control de desbordamiento;
  - M4: un vínculo inválido no excluye;
  - M5: nunca «sin cambios»;
  - M6: un total que se queda sin aplicaciones no pasa a 0;
  - M7: sin revalidar la vista previa;
  - M8: publica sin confirmación;
  - M9: el conflicto no bloquea.
- **X1–X4** contra `test/f06_dataset_test.dart`:
  - X1: cuenta al familiar;
  - X2: cuenta las revertidas;
  - X3: oráculo alterado;
  - X4: dataset sin una reversión.

## Contra Central

- **Reconciliación automatizada:**
  - SQLite → outbox → Central → agregado por celda, contra el Backend local desechable, 2026-10-16, en dos ejecuciones;
  - todas las celdas con diferencia 0, y el reenvío no cambia el agregado;
  - detalle en `Agro_Sindicato_Backend-Web/docs/evidence/F06_RECONCILIATION.md`;
  - artefactos de la corrida en [`F06_RUN_20261016/`](F06_RUN_20261016/).
- **Ruta física:** el agricultor 1 publica desde la copia aislada del POCO y su aporte coincide con su fila del CSV ([F06_D4_DEVICE](F06_D4_DEVICE.md)).

## Discrepancias con el issue (gana el contrato)

- **Denominación observada.** El issue pide enviar la «denominación observada». F06 §2 sólo admite `product_ref` (el producto central vinculado). La denominación local no viaja; las variantes (Belator/Bellator) se reconcilian en Central con una asociación canónica confirmada (CU-18, BE #21).
- **Unidades.** El issue pide conservar la unidad de cada línea sin sumar unidades incompatibles. Se suma por producto en su unidad base (`ML` o `G`). El vínculo exige unidades compatibles y nunca se suman ML con G.
- **Ruta del constructor.** El brief D4 sugería `lib/services/sync/consumption_projection_builder.dart` y comparar con `sync_contributions`. No se creó esa tabla: el estado publicado es la última intención efectiva de la outbox de D3 por destino. El constructor vive en `lib/domain/sync/`.

## Limitaciones

- No hay publicación automática: sólo la acción explícita del titular.
- El envío en segundo plano es el de D3.
- La ruta física cubre la publicación de un titular. Reversiones, familiar y reenvíos se miden en la reconciliación automatizada, no en el teléfono.
