# REC-019 (#55): restaurar un respaldo de esquema antiguo y comprobar la migración

- **Fecha:** 2026-10-17. Sesión A de Claude Code.
- **Base:** Mobile `main` `cf3d510`. Flutter 3.47.2 en Windows 11.
- **Tipo de prueba:** host (`flutter test`, `sqflite_common_ffi`). **Sin dispositivo.**

## Por qué

El comentario de #55 del 2026-10-15 pidió, para `Verified`, «un test que restaure un `.db` de esquema antiguo y compruebe la migración».

El test «restaurar un respaldo de esquema antiguo dispara la migración» de `backup_service_test.dart` sólo llama a `validate()` sobre una base v3 de juguete (tablas con una sola columna `id`). No restaura ni migra. Se conserva tal cual.

`f04_restore_authorization_test.dart` ya restauraba una copia v7 (también sintetizada con `downgradeToV7`) por `GuardedRestore`, pero sólo comprobaba el acceso, el vínculo y la marca de base histórica.

## Prueba nueva: `test/rec_019_restore_legacy_schema_test.dart`

Base v7 **sintetizada**: un hogar con compra de 5 L y aplicación de 2 L, llevado al esquema v7 exacto con `downgradeToV7`, sin las tablas de v8/v9. No es una copia generada por una versión v7 de la app. Es equivalente porque las migraciones a v8 y v9 sólo crean tablas e insertan la marca, sin alterar las existentes (comprobado en la revisión de la sesión C). Se restaura un `.db` con `BackupService.restore` sobre una base actual con otros datos. No se usa el contenedor `.agrobackup` ni `GuardedRestore`: ese camino lo cubren `f04_restore_authorization_test` y las pruebas de F08.

Comprueba:
- `user_version` = `AppDatabase.schemaVersion` (9);
- `PRAGMA integrity_check` = `ok`;
- **las filas de cada tabla de la v7, idénticas** (`app_settings` sólo gana la marca);
- `install_origin` = `LEGACY_PRE_POLICY`;
- `owner_bindings` y `sync_outbox` existen y están vacías (restaurar no atribuye titular ni crea intenciones);
- el dominio actual lee los datos restaurados: el producto de la copia y existencias del titular 3000.

| Comando | Resultado |
|---|---|
| `flutter test test/rec_019_restore_legacy_schema_test.dart` | 1/1 |
| Mutación: la migración a v8 marca la base como nueva en vez de histórica (`installOriginLegacy` → `installOriginNew`) | Detectada: 1 fallo. Restaurado con `git checkout` |

## Lo que sigue sin cubrir en #55

Declarado; no se presenta como hecho:
- pruebas de los flujos de interfaz de exportar y restaurar;
- prueba propia de `InvoiceStorage`;
- el ciclo físico de `docs/46_BASELINE_FINAL_FREEZE.md` es documental.

Los requisitos (a) y (c) del comentario del 2026-10-15 se cubrieron en F08: `6c6a1a2` (#90) y `F08_MOBILE_RESTORE.md` §1.

## Revisiones

- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
