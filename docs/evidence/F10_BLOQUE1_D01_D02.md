# Bloque 1 de la revisión integral — D-01 (reanudación tras 422) y D-02 (reversión en propio)

- **Fecha real:** 2026-10-27 (America/La_Paz). Sesión A, por encargo de Roderich del 2026-10-26 («Autorizo un primer bloque acotado de correcciones», frente 1). Rama `fix/d01-version-mismatch-d02-reversion-propio` sobre `main` `a68285c`.
- **Trazabilidad:** RF-18 (sincronización, CU-11), RF-13 (reversiones, CU-05), RN-17; INT-02. Issues: MOB #37. Contratos: `F05_SYNC_V1_PUSH_ACK_CONTRACT.md` (fila 422) y `F05_SYNC_V1_RETRY_IDEMPOTENCY_MATRIX.md` (C25) del Backend; `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §1.2.
- **Procedencia:** pruebas de **host** (`flutter test`, Windows 11, Flutter 3.47.2) y lectura del contrato. Ninguna sesión con participantes. La comprobación en **emulador** de la integración de las cuatro ramas (`F10_BLOQUE1_INTEGRACION_EMULADOR.md`, misma fecha) no ejercita estos dos defectos (exigen un 422 de contrato y una base en propio con lotes de terceros): se cubren sólo en host.

## 1. Commits

| SHA | Qué |
|---|---|
| `90b7192` | D-01: `SyncOutboxStore.resumeVersionMismatch`, `SyncController.resumeVersionMismatch`, tarjeta «Envíos pausados por una versión distinta de la aplicación» → «Reintentar con esta versión» (con confirmación) en Sincronización; pruebas |
| `eb9775b` | D-02: `_reversePurchaseIn` recibe el contexto y aplica `_requireOwnerInPersonal` sobre dueños de lotes vivos y personas con cargo por asignación; pruebas |
| `b67d914` | Seguimientos de la revisión cruzada: controlador con cuenta distinta o sin acceso (devuelve 0, no toca filas); compra mezclada en propio; caso F04-BUG-02 |
| `77b78ee` | La prueba de widget de D-01 se apoya en los chips del resumen (no en el texto de la fila, que redacta otro PR) |

## 2. D-01

- **Contrato:** 422 `CONTRACT_VERSION_MISMATCH` → `KEEP_FOR_RECONCILIATION`; C25: «pausar versión; upgrade gobernado, no cambiar versión del pendiente; no automático; conservar ID/versión original».
- **Antes (`a68285c`):** `sync_worker.dart:164-167` bloquea cada ciclo si hay filas `VERSION_MISMATCH`; no existía ninguna transición de salida; el mensaje pedía actualizar la aplicación.
- **Ahora:** reanudación sólo por acción del titular con acceso verificado (`ensureAccess`, mismo ámbito del vínculo); filas → `PENDING` si `attempts = 0`, `OUTCOME_UNKNOWN` si ya se intentaron; `operation_id`, contenido, `contractVersion` y predecesores intactos; nada al arrancar, por temporizador ni por reconexión; un 422 repetido vuelve a pausar en el mismo ciclo. `sync_worker.dart` sin cambios.
- **Reproducción (host):** `flutter test test/sync_retry_worker_test.dart --plain-name "422 y reanudación"` sobre `lib/` de `a68285c` no compila (método inexistente); `flutter test test/f10_sync_version_mismatch_resume_test.dart` sobre `lib/` base falla con «Found 0 widgets with key version-mismatch» tras comprobar que la fila sigue en `VERSION_MISMATCH` y nada se envía (salidas literales `d01_before_*.txt` en el informe de sesión). Con la corrección: `sync_retry_worker_test` +37 verdes; `f10_sync_version_mismatch_resume_test` +4 verdes (un único push con el mismo `operationId` y `contractVersion == 1`; `core(acked) == core(paused)`; sin acceso o con otra cuenta devuelve 0 y no toca filas).

## 3. D-02

- **Decisión:** defecto (guarda ausente), coherente con las reversiones de aplicación y transferencia: evidencia F04-MODE-03, gate F04 criterio MODE-04 («en propio no se revierte actividad de terceros»), F04_RF13 §1.2 («la operación original no se reasigna»). La compensación sigue legítima y disponible en COMPARTIDA; en PROPIO nada se reasigna: se rechaza con «En inventario propio sólo se revierten compras asignadas al titular…».
- **Alcance real:** la transición a propio bloquea mientras un tercero tenga existencias o saldo, así que por la interfaz el estado casi no se alcanza; sí con bases anteriores a esa compuerta, restauradas o por uso directo del repositorio. Gravedad efectiva menor que P1; se mantiene por coherencia.
- **Reproducción (host):** prueba nueva en `test/personal_mode_flows_test.dart` sobre `a68285c`: la reversión en propio de la compra del vecino **se completa** («emitted (effectiveDate: …, personId: null)»). Con la corrección: +18 verdes (rechazo sin cambios en la base; reversión en compartido con abono al vecino; compra del titular sí se revierte en propio; compra mezclada rechazada; F04-BUG-02). Regresión verde: `rec_050_reversal_rules_test`, `f04_rf13_reversal_audit_test`, `f04_bug_02_reverse_purchase_after_transfer_test`, `f04_repository_guards_test`.

## 4. Suite completa y calidad

- `flutter test` en la rama (`b67d914`): **1 856 pasan, 3 omitidas, 0 fallos** (`01:38 +1856 ~3: All other tests passed!`). Tras `77b78ee`: archivos afectados `personal_mode_flows_test`, `f10_sync_version_mismatch_resume_test`, `sync_retry_worker_test` → `+61: All tests passed!`.
- `dart format` sin cambios; `flutter analyze` «No issues found!» antes de cada commit. Commits sin trailers.
- **Revisión cruzada** (otro agente de la misma sesión, sólo lectura del diff): LISTO; sus dos seguimientos están en `b67d914`. Observaciones no bloqueantes: `OUTCOME_UNKNOWN` vs `PENDING` para filas ya intentadas (se eligió el criterio conservador existente); bloqueo global del worker si otro vínculo tuviera filas pausadas (preexistente, no alcanzable por la interfaz).

## 5. Lo que no cambia y decisiones pendientes

Stock, FIFO, costos, asignaciones, pagos históricos, auditoría, worker, estados y códigos de la outbox, contrato F05/F06, esquema. Pendiente de Roderich: si las filas reanudadas con intentos deberían salir como `PENDING`; si la compra con asignaciones a terceros debiera ser la excepción permitida en propio (en ese caso se revierte `eb9775b` y se anota en #102/CU-05).
