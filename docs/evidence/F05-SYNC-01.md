# Evidencia F05-SYNC-01 — IDs globales sólo donde la sincronización los requiere

Issue [#29](https://github.com/Roderich1/AppMovilAgroquimico/issues/29). El detalle está en [F05_MOBILE_SYNC](F05_MOBILE_SYNC.md). Ejecutado con Claude Code el 2026-10-15 sobre `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` (base `main` `3eecb2d`), en host y sin dispositivo.

**Decisión.** Según el contrato F05 §15 («no globalizar todos los IDs SQLite ni equiparar Person con Member»), lo único que cruza al sindicato es la **intención** de una proyección. Por eso el identificador global es su `operation_id`, en `sync_outbox`. Ninguna tabla operativa recibe un UUID ni cambia de clave. Las entidades locales que una intención menciona viajan como referencias centrales vinculadas (`campaign_ref`, `product_ref`), no como IDs locales.

| Criterio | Prueba | Resultado |
| --- | --- | --- |
| Un registro sincronizable confirmado queda con un UUID no nulo y único | `outbox_repository_test.dart` «una misma intención no se registra dos veces»; `declared_need_test.dart` «declarar sin conexión…» (UUID v4, `UNIQUE`) | PASS |
| Reintento o reapertura antes del ACK reutilizan el mismo ID | `sync_retry_worker_test.dart` «timeout/error de red/500: …el reintento envía exactamente lo mismo» y «cierre forzado durante el envío…» | PASS |
| Una base anterior migra sin perder datos, con claves y relaciones intactas | `migration_test.dart` «v8/v7/v6 → v9 conserva todas las filas…». Ninguna fila existente es una intención: no hay nada que numerar | PASS |
| Una tabla que no se sincroniza no incorpora identificador global | `migration_test.dart`: las columnas de cada tabla existente son idénticas antes y después | PASS |
| Dos instalaciones no colisionan aunque coincida la clave local | `sync_global_ids_test.dart`: UUID v4 de `Random.secure`, 10 000 sin repetidos y fuentes distintas; nunca deriva del entero de SQLite | PASS |

Comandos: `flutter test test/sync_global_ids_test.dart test/migration_test.dart test/schema_equivalence_test.dart` y `flutter test` (947/947).

Documentación actualizada: `docs/14_OFFLINE_AND_SYNC.md` y `docs/10_DATA_MODEL.md`.
