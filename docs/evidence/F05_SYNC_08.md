# Evidencia F05-SYNC-08 — Vincular campañas y productos locales con el catálogo central

Issue [#72](https://github.com/Roderich1/AppMovilAgroquimico/issues/72). Endpoint consumido: `GET /api/v1/sync/v1/references` (BE #106, PR BE #109). El detalle está en [F05_MOBILE_SYNC](F05_MOBILE_SYNC.md). Ejecutado con Claude Code el 2026-10-15 sobre `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` (base `main` `3eecb2d`), en host y sin dispositivo.

**Estructura (migración v9).** `campaign_bindings` y `product_bindings` guardan:
- el ID local;
- el tenant;
- la referencia central UUID;
- el nombre central (y, para productos, la unidad central y `base_unit`);
- el estado `VALID` o `INVALID`, con su motivo;
- las fechas de vínculo y de revisión.

Un vínculo sólo se crea con el titular vinculado del mismo tenant.

| Criterio | Prueba | Resultado |
| --- | --- | --- |
| Elegir una referencia y confirmar guarda el vínculo, que sigue vigente tras reabrir | `central_reference_binding_test.dart` «un vínculo confirmado se guarda y sigue vigente tras reabrir la app»; `sync_screens_test.dart` «vincular: la elección es explícita…» | PASS |
| Nombres coincidentes no crean ningún vínculo sin confirmación | «nombres coincidentes no crean ningún vínculo sin confirmación»; en la pantalla, leer las referencias no vincula nada | PASS |
| L local con KG central se rechaza sin conversión | «L local con KG central se rechaza sin conversión»; «una unidad central sin equivalencia L/KG no se vincula»; la pantalla deshabilita la opción con su motivo | PASS |
| Sin vínculo vigente no se genera la publicación y se indica «requiere vinculación» | «sin vínculo vigente no se prepara ninguna publicación»; `declared_need_test.dart` «una campaña sin vínculo vigente pide vincular» | PASS |
| Referencia que desaparece o campaña que no admite aportes: el vínculo queda inválido y bloquea un valor nuevo sin borrar operaciones | «referencia desaparecida o campaña cerrada: el vínculo queda inválido, sin borrar nada, y bloquea un valor nuevo» (volcado igual); «un producto inactivo…» | PASS |
| Sin conexión o con reautenticación pendiente se informa el motivo, se conservan los vínculos y SQLite sigue disponible | `sync_screens_test.dart` «sin conexión se informa el motivo y los vínculos se conservan» | PASS |
| Una base v6 con datos migra sin alterar ni perder datos | `migration_test.dart` «v6 → v9…» | PASS |
| De la respuesta sólo se guardan la referencia, el nombre, la unidad y el estado | «sólo se guardan la referencia, el nombre, la unidad y el estado»; `sync_wire_test.dart` rechaza entera una respuesta con campos ajenos a la whitelist | PASS |

Además:
- **Correcciones bloqueadas:** un vínculo no se corrige ni se quita mientras sostenga una necesidad vigente o envíos sin asentar. Cambiar de campaña o de producto exige anular y declarar de nuevo (F06 §6).
- **Sin duplicados:** una referencia central no se vincula a dos registros locales.

Comandos: `flutter test test/central_reference_binding_test.dart test/migration_test.dart` y `flutter test` (947/947).

No incluye CU-18: la reconciliación de denominaciones es de la Directiva en F07-REC-01.
