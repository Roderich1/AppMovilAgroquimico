# Evidencia F05-SYNC-02 — Outbox SQLite atómica

Issue [#30](https://github.com/Roderich1/AppMovilAgroquimico/issues/30). El detalle está en [F05_MOBILE_SYNC](F05_MOBILE_SYNC.md). Ejecutado con Claude Code el 2026-10-15 sobre `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` (base `main` `3eecb2d`), en host y sin dispositivo.

La outbox es `sync_outbox` (migración v9). La escriben `DeclaredNeedStore` y `SyncOutboxStore.applyPlan` dentro de la **misma** `transaction` que la necesidad declarada y su versión, bajo la compuerta de activación y la exclusión de restauración. Estados: `PENDING`, `SENDING`, `OUTCOME_UNKNOWN`, `ACKED`, `CONFLICT`, `REJECTED`, `FAILED`, `AUTH_PAUSED`, `OWNER_PAUSED`, `RESTORE_PAUSED`, `VERSION_MISMATCH` y `DISCARDED`.

| Criterio | Prueba | Resultado |
| --- | --- | --- |
| Sin conectividad, la operación y su entrada `pending` se guardan en la misma transacción y sobreviven a cerrar y reabrir | `declared_need_test.dart` «declarar sin conexión…»; `outbox_repository_test.dart` «la necesidad y su intención persisten tras cerrar y reabrir» | PASS |
| Una excepción dentro de la transacción no deja efectos parciales | `outbox_repository_test.dart` «una excepción dentro de la transacción…». Trigger temporal que aborta el insert de `declared_needs` (después de la intención) o de `declared_need_versions` (después de ambas); no queda ninguna fila. | PASS |
| La misma operación lógica no crea una segunda entrada ni otro efecto | `outbox_repository_test.dart` «una misma intención no se registra dos veces» (`UNIQUE`); coalescencia de lo no enviado (`declared_need_test.dart` «modificar conserva la versión anterior…») | PASS |
| Una base v6 con datos migra sin alterar ni perder datos | `migration_test.dart` «v6 → v9…» (también v7 y v8) | PASS |
| Con notas, relaciones o adjuntos privados, la carga sólo lleva los campos autorizados | `outbox_repository_test.dart` «la outbox sólo lleva la whitelist…» (columnas); `need_sync_payload_test.dart` (envelope) | PASS |

Además: una intención enviada no se modifica y ninguna se borra (trigger), y un ACK aceptado es definitivo (`outbox_repository_test.dart` «una intención enviada no se modifica ni se borra»).

Comandos: `flutter test test/outbox_repository_test.dart test/migration_test.dart` y `flutter test` (947/947).
