# F10 — La lista de Sincronización refleja el ACK tras «Liberar» (MOB #36)

**Origen:** Live. **Fecha real:** 2026-10-16 (America/La_Paz). **Gate relacionado:** Roderich1/Agro_Sindicato_Backend-Web#41 (GATE-F08), **Pending**.

**Trazabilidad:** RF-18 y CU-15.

**Alcance:** pruebas de host (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.** El defecto se observó en el POCO durante el turno 2 de A (`F08_MOBILE_RESTORE.md` §5). Su corrección en el teléfono forma parte del turno pedido a A.

## Commits

| Commit | Contenido |
|---|---|
| `4f203c7` | Base: `main` Mobile |
| `d930a3f` | Regresión `test/f10_sync_release_refresh_test.dart`, **en rojo sobre `4f203c7`** |
| `8ca87c5` | Corrección en `sync_status_screen.dart` y README del arnés F08 |

## 1. Defecto

`SyncController.releaseRestored()` libera las intenciones y lanza el envío con `unawaited(kick())`. `SyncStatusScreen` relee la lista justo al volver de liberar, antes del ACK, y no vuelve a leerla. El resumen sí se actualiza, porque observa el controlador. Por eso, en el POCO, el resumen decía «Sincronizado: 2» mientras la fila seguía «Pendiente (sin confirmar)» hasta salir y volver a entrar.

`DeclaredNeedsScreen` ya resolvía el mismo caso con un `ref.listen`, que relee la lista cuando el controlador publica un resumen nuevo.

## 2. Regresión

Recorrido sobre la base del fixture F05, con el MockClient de Central:
1. Necesidad de 30 L declarada. `markSending` y `recordRetry(OUTCOME_UNKNOWN, NETWORK)` reproducen el intento sin red del ensayo.
2. `SyncOutboxStore.pauseAfterRestore`, lo que hace `GuardedRestore`, la deja en `RESTORE_PAUSED`. Comprobado: **la fila completa de `sync_outbox` es idéntica salvo `status` y `updated_at`**. Eso incluye la operación, la cantidad, la versión, los intentos y la causalidad.
3. Abrir la pantalla no envía nada.
4. «Liberar», con su confirmación y el acceso verificado del titular, produce **un único push con el mismo `operationId`**. La base queda `ACKED` con la misma operación y cantidad.
5. **La fila muestra «Sincronizado · creada…» sin salir de la pantalla** y ya no aparece «Pendiente (sin confirmar)».

**Rojo sobre `4f203c7`**, con `flutter test test/f10_sync_release_refresh_test.dart`, el 2026-10-16. Los pasos 1 a 4 pasan; falla el 5:

```
Expected: exactly one matching candidate
  Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Sincronizado · creada: …
OUTCOME_UNKNOWN → RESTORE_PAUSED → Liberar: un único envío con la misma operación y la fila muestra el ACK sin salir de la pantalla [E]
```

## 3. Corrección

`SyncStatusScreen.build` registra el mismo `ref.listen` que `DeclaredNeedsScreen`: relee las filas cuando cambia el resumen del controlador, que es lo último que publica cada ciclo. Así se refleja el ciclo de «Liberar» y también el del temporizador o el de una reconexión.

**No cambia:**
- la verificación del acceso;
- la regla de que abrir la app no envía (F05 §11, F06 §8);
- el refresh de credenciales de F03;
- qué se libera.

**README del arnés** (`tool/f08_bkp/README.md`):
- **§1.4:** con acceso verificado, la necesidad declarada sin red queda OUTCOME_UNKNOWN, no PENDING. Para que no salga al volver la red hay que detener la app sin red.
- **§2.10:** lo enviable (PENDING u OUTCOME_UNKNOWN) pasa a RESTORE_PAUSED con la misma operación, cantidad y causalidad. `compare` ya lo admitía y sólo acepta cambios en `status` y `updated_at`.
- **§3:** se reenvía el mismo `operationId` y la fila debe mostrar «Sincronizado» sin salir de la pantalla.

## 4. Resultados

| Comando, sobre `8ca87c5` | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test test/f10_sync_release_refresh_test.dart test/sync_screens_test.dart test/remote_backup_client_test.dart` | 37/37 |
| `flutter test`, suite completa | **1031 pasan, 2 omitidas, 0 fallos** |

## 5. Límites

Es una prueba de widget con el reloj de la prueba y un cliente HTTP simulado. En el teléfono, la comprobación es el paso §3.4 del README en el turno de A.
