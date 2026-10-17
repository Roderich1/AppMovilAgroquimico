# F10 — Mensajes de autorización observados en la tanda física de #18

**Origen:** Live. **Fecha real:** 2026-10-16 (America/La_Paz). Pruebas de **host** (Windows 11, Flutter 3.47.2): **no es una prueba DEVICE**. La comprobación en el teléfono la decide la sesión A, que es quien usa adb, cuando no esté midiendo sobre la base congelada.

**Trazabilidad:** RF-18, RNF-07, INT-08 y RN-18; BE #18 (F05-SYNC-06).

**Base:** Mobile `main` `dff6802`.

## 1. Observaciones de origen

Fuente: `docs/evidence/F05_SYNC_06_DEVICE_F10.md`, «Límites y observaciones», tanda 1 de #18 ejecutada por la sesión A en el POCO.

| Caso | Lo observado | Defecto comprobado |
|---|---|---|
| C38 | Al volver a autenticar con **otra cuenta** (R en lugar de S), la app cerró esa sesión sin vincularla (logout 204, 0 push). Comportamiento correcto. | La pantalla sólo decía «Se requiere volver a autenticar…» y **no explicaba que la cuenta no es la del titular** |
| C40 y C22 | Tras un `push 403`, la fila queda `AUTH_PAUSED` y «Verificar acceso en línea» no la reanuda: hace falta «Sincronizar ahora». Esto es por diseño (plan F05-SYNC-06, observación 2) | **Ninguna pantalla indicaba esa acción explícita**. El mensaje decía «Los envíos quedan pausados; nada se borró.» |
| C23 | Registro del dispositivo revocado: `session/client` 404 y el mensaje «La vinculación de este dispositivo no fue aceptada. Se necesita revisión…». La intención siguió `AUTH_PAUSED`, sin pérdida | El mensaje **no decía que los datos se conservan ni cuál es el camino** |

## 2. Ruta bloqueada: C23 (documentada, no se cambia)

Un `ClientRegistration` revocado **no vuelve a vincularse** en esa instalación, por diseño (#71, E-2). Volver a autenticar da `session/client` 404 o 401.

El único camino para enviar lo pausado:
1. Exportar una copia de seguridad en el teléfono. La copia lleva la outbox con sus filas `AUTH_PAUSED`.
2. Activar una **instalación nueva**, que recibe un registro nuevo, con la cuenta del titular.
3. Restaurar la copia. `pauseAfterRestore` pasa `AUTH_PAUSED` a `RESTORE_PAUSED`.
4. El titular verificado **libera** las filas con el mismo `operationId`.

Cada tramo está probado por separado:
- el ensayo F08/F10 en el POCO cubre la restauración en una instalación limpia y la liberación (`F08_MOBILE_RESTORE.md` §5 y `F10_RESTORE_DEVICE.md`);
- `pauseAfterRestore` incluye `AUTH_PAUSED` en el código.

**El recorrido completo partiendo de C23 no se ejecutó en el teléfono.** El mensaje describe ese camino sin afirmar que se haya ensayado.

## 3. Cambio

Commits: `754aedb` (pruebas, rojo) y `e452916` (corrección).

**Ninguna regla cambia:**
- no hay refresh automático;
- no hay cambio de titular;
- verificar el acceso no reanuda nada;
- `ensureAccess`, `releaseRestored`, `resumeAfterVerification` y el worker quedan igual.

**Cambios:**

| Archivo | Cambio |
|---|---|
| `remote_session_coordinator.dart` | Nuevo `RemoteSessionProblem.otherAccount`. `_validateLogin` comprueba **primero la identidad** (cuenta, Member y tenant frente a la sesión almacenada) y después el rol y el estado, así que una cuenta de Directiva distinta también se informa como otra cuenta. Mensaje: «Esa cuenta no es la vinculada a este teléfono. Los datos de este teléfono son de su titular y sólo se envían con la cuenta del titular: ingrese con esa cuenta. No se envió nada ni cambió el titular.» Un contexto inactivo conserva el mensaje general. Mensaje de `registrationRejected` con la conservación de los datos y el camino de §2 |
| `sync_providers.dart` | `SyncBlocker.forbidden`: «… No se reanudan solos: cuando el sindicato lo autorice, verifique el acceso con la cuenta del titular y pulse «Sincronizar ahora».» |
| `sync_status_screen.dart` | Tarjeta «Envíos pausados por autorización» cuando hay filas `AUTH_PAUSED`. Es sólo texto: la acción sigue siendo el botón «Sincronizar ahora» |

## 4. Pruebas

**Rojo sobre `754aedb`:** las pruebas nuevas más el valor del enum sin uso. 8 fallos con `flutter test test/f10_mensajes_autorizacion_test.dart test/remote_session_coordinator_test.dart`:
- otra cuenta, otro Member, otro tenant y otra cuenta que no es agricultor: el problema era `contextMismatch`;
- los mensajes de otra cuenta, del registro rechazado y del 403;
- la tarjeta de Sincronización (`Found 0 widgets with text containing Envíos pausados por`).

**Verde sobre `e452916`:**

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/f10_mensajes_autorizacion_test.dart test/remote_session_coordinator_test.dart test/remote_session_screen_test.dart test/sync_screens_test.dart` | 79/79 |
| `flutter test`, suite completa | **1073 pasan, 2 omitidas, 0 fallos** |

**La prueba de pantalla comprueba además** que abrir Sincronización con el acceso verificado **no envía nada** y deja la fila en `AUTH_PAUSED`. Sólo «Sincronizar ahora» la reanuda, con un único push del **mismo** `operationId`, hasta `ACKED`.

## 5. Límites

- Sólo host. No se repitió C38, C40 ni C23 en el teléfono con estos mensajes.
- El camino de C23 descrito en el mensaje no se ejecutó completo (§2).
- Este PR no debe integrarse mientras la sesión A mide sobre la base congelada: A decide cuándo.
