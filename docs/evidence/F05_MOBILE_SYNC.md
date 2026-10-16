# Evidencia F05 Mobile — vinculación, necesidad declarada, outbox y worker Sync v1

Issues: [#29](https://github.com/Roderich1/AppMovilAgroquimico/issues/29) (F05-SYNC-01), [#30](https://github.com/Roderich1/AppMovilAgroquimico/issues/30) (F05-SYNC-02), [#31](https://github.com/Roderich1/AppMovilAgroquimico/issues/31) (F05-SYNC-03), [#72](https://github.com/Roderich1/AppMovilAgroquimico/issues/72) (F05-SYNC-08) y [#34](https://github.com/Roderich1/AppMovilAgroquimico/issues/34) (F06-COLL-04, sólo la parte local).

Contratos aplicados (Backend): `docs/architecture/F05_SYNC_V1_PUSH_ACK_CONTRACT.md`, `F05_SYNC_V1_RETRY_IDEMPOTENCY_MATRIX.md`, `F06_COLLECTIVE_PROJECTION_CONTRACT.md` y `F06_COLLECTIVE_PROJECTION_FIELD_MATRIX.md`. La matriz F06 se leyó completa antes de construir el productor: 8 filas ALLOW (`campaign_ref`, `product_ref`, `base_unit` y `quantity_base` para cada tipo) y 118 DENY.

Ejecución con Claude Code el 2026-10-15 (America/La_Paz), en host Windows 11, Flutter 3.47.2 y Dart 3.13.2. **Sin dispositivo:** el E2E en el POCO queda `NOT_MEASURED` (§6). Esto no es un PASS de GATE-F05 (BE #19), que sigue Pending.

## 1. Identidad

| Elemento | Valor |
| --- | --- |
| Base | `main` `3eecb2d7d8405e88c6550f7bb70f9095b55b4283` |
| Rama | `feat/f05-outbox-sync-v1` (worktree `_wt/F05-MOB`) |
| Commit de implementación | `30c04b63a43dbd610414d81e58b2e5ad556a3dbe` |
| Backend de referencia | PR BE #109 (`feat/f05-sync-v1-push`, código `db87004`), sin fusionar |
| Datos | Sintéticos; ningún token real, contraseña ni clave en pruebas ni registros |

## 2. Diseño

### Migración v9

Sólo crea tablas vacías. Ninguna tabla existente recibe columnas ni un identificador global (F05 §15).

| Tabla | Para qué | Reglas |
| --- | --- | --- |
| `campaign_bindings`, `product_bindings` | Vínculo explícito con `campaign_ref`/`product_ref` del tenant del titular | Exige confirmación. Una referencia central por registro local y viceversa. Misma dimensión. Estado `VALID`/`INVALID` con motivo. Sólo guarda referencia, nombre, unidad y estado |
| `sync_outbox` | Una fila por intención: `operation_id` UUID v4, `owner_binding_id NOT NULL`, tipo, acción, los cuatro campos F06, causalidad, estado e intentos | Sin borrado. Una intención enviada es inmutable (trigger). Un ACK aceptado es definitivo |
| `declared_needs`, `declared_need_versions` | Necesidad vigente por titular, campaña y producto, y su historial | Historial inmutable; cero es válido; sin borrado |

### Productor (necesidad declarada)

- **Una sola transacción** para la necesidad, su versión y la intención (`DeclaredNeedStore`, bajo la compuerta de activación y la exclusión de restauración).
- **Campaña derivada de la fecha de referencia** (#34): debe ser exactamente una y estar vinculada. Si no lo está, no se asigna en silencio.
- **Cantidad** en L o KG convertida a ML o G con aritmética entera (`parseBaseQuantity`). Un cuarto decimal distinto de cero se rechaza, no se redondea.
- **Planificación causal** (`planIntention`), con las reglas del Backend:
  - el primer valor es PUBLISH sin antecesor;
  - después de un valor, SUPERSEDE o CANCEL contra él;
  - después de una retirada, sólo PUBLISH.
- **Coalescencia segura:** sólo una intención que nunca salió (`PENDING` con `attempts = 0`) se reescribe o se descarta. Cualquier otra genera una nueva con antecesor.
- **Tras un rechazo,** la sucesora que nunca salió pasa a apoyarse en el antecesor real.

### Worker

`SyncWorker` (#31):

- **Orden causal:** como máximo una intención en vuelo por contribución, y la sucesora sólo tras el ACK de su antecesora.
- **Antes de enviar,** registra `SENDING` y `attempts + 1`. Tras un cierre forzado, `SENDING` pasa a `OUTCOME_UNKNOWN` y se reenvía igual.
- **Validación estricta del ACK** (§7): siete claves, el mismo `operationId`, disposition coherente, código del outcome, hora para la aceptación y referencia para el conflicto. Sólo un ACK válido de aceptación marca «sincronizado».

| Respuesta | Estado local |
| --- | --- |
| ACK APPLIED / ALREADY_APPLIED | `ACKED`, con la hora del servidor |
| ACK RETRYABLE, 429/503 cerrados | `PENDING`, con backoff y el mismo envelope |
| 500, timeout, red, ACK incoherente, error sin cuerpo cerrado | `OUTCOME_UNKNOWN`, con backoff y el mismo envelope |
| ACK CONFLICT | `CONFLICT` visible, con su referencia. Decide el propietario |
| ACK REJECTED | `REJECTED` con su código; sin reintento |
| 400 / 413 / 415 con cuerpo cerrado | `FAILED` terminal; sin reintento |
| 401 | Vuelve a `PENDING` y se descarta el token. Espera que el agricultor verifique el acceso; no hay bucle |
| 403 | Toda la cola del titular pasa a `AUTH_PAUSED`; nada se borra |
| 422 | `VERSION_MISMATCH`, y el worker no envía nada más |

- **Backoff** con jitter completo: base 2 s, ×2, tope 15 min, mínimo 1 s y `max(backoff, Retry-After)` (segundos o fecha HTTP). Presupuesto de 20 intentos por ciclo.
- **Disparadores:** al iniciar, tras encolar, «Sincronizar ahora» y cada minuto en primer plano. Sin trabajo en segundo plano.

### Credencial, titular y restauración

- **Access token:** sólo en memoria (`SyncAccessHolder`, vida local de 10 min). Lo entrega `RemoteSessionCoordinator` tras confirmar el commit y liberar la guarda de una verificación explícita (refresh o reautenticación). El worker nunca rota el refresh por su cuenta, y sin acceso vigente no hace ninguna llamada de red.
- **Titular:** sólo se envían filas del vínculo activo y con la sesión del mismo Member y tenant. Las de otro vínculo pasan a `OWNER_PAUSED`. `changeOwner` usa ahora la outbox real y queda bloqueado con cualquier intención no rechazada, fallida ni descartada.
- **Restauración:** dentro de la sustitución exclusiva, toda intención por enviar pasa a `RESTORE_PAUSED`. El titular la libera desde Sincronización; las que ya habían salido vuelven como `OUTCOME_UNKNOWN`. Restaurar no publica ni reasigna nada.

### Pantallas

- **Vincular con el sindicato** (Sincronización, Necesidad declarada): una elección y una confirmación por registro. La unidad incompatible se ofrece deshabilitada, con su motivo.
- **Necesidad declarada** (Planificación): fecha, campaña, producto y cantidad, con la confirmación «Declarar al sindicato: X L de … para …». Permite editar, anular, ver el historial y resolver un conflicto.
- **Sincronización** (Inicio): estados, último ACK, «Sincronizar ahora» y «Liberar» lo restaurado.
- **Indicador en el shell:** sólo aparece si hay algo pendiente o que atender.

## 3. Resultados

| Sobre | Comando | Resultado |
| --- | --- | --- |
| `30c04b6` | `dart format --output=none --set-exit-if-changed lib test` | 169 archivos, 0 cambios |
| `30c04b6` | `flutter analyze` | sin issues |
| `30c04b6` | `flutter test` | **947/947** |

Pruebas nuevas o ampliadas (todas dentro de las 947):

| Archivo | Qué cubre |
| --- | --- |
| `test/sync_global_ids_test.dart` | UUID v4: versión, variante, 10 000 sin repetidos y fuentes distintas |
| `test/migration_test.dart` (ampliado) | v8, v7 y v6 → v9 con datos: todas las filas iguales, tablas nuevas vacías y ninguna columna añadida a las existentes. `owner_binding_id NOT NULL` |
| `test/outbox_repository_test.dart` | Atomicidad con falla forzada (trigger temporal que aborta después del primer insert): no queda ni la necesidad ni la intención. Además: persistencia tras reabrir, sin duplicados, whitelist, inmutabilidad (trigger) y edición concurrente con el worker |
| `test/declared_need_test.dart` | Declarar sin red sin cambiar el inventario (volcado completo), cero explícito, historial, SUPERSEDE encadenado, retirada, campaña indeterminable, vinculación requerida, compuerta |
| `test/need_sync_payload_test.dart` | Envelope de seis claves; payload con la whitelist exacta; CANCEL sin cantidad; nada privado ni contextual |
| `test/sync_intention_planner_test.dart` | Conversión exacta sin `double` (incluso por encima de 2^53) y reglas de planificación causal |
| `test/sync_wire_test.dart` | ACK, errores, `GET {ack, contribution}`, Retry-After y referencias con la whitelist cerrada |
| `test/sync_retry_worker_test.dart` | Una prueba por cada respuesta de la tabla, más: orden causal, cierre forzado, sin acceso, otra cuenta, restauración, vínculo cerrado, cambio de titular, reencolada no reescrita, edición tras un rechazo, caducidad del token y backoff |
| `test/sync_simulated_central_test.dart` | Recorrido completo contra un **Central simulado** (§6) |
| `test/central_reference_binding_test.dart` | Criterios de #72 |
| `test/sync_screens_test.dart` | Las tres pantallas: confirmación explícita, cancelar, sin productos vinculados, vincular con unidad incompatible deshabilitada, sin conexión y estados |
| `test/remote_session_coordinator_test.dart` (ampliado) | El token se entrega sólo tras commit y guarda liberada; nunca ante desajuste de contexto, clear fallido o red |
| `test/f04_restore_authorization_test.dart` (ampliado) | Restauración real: lo aceptado sigue ACKED, lo enviado sin respuesta queda RESTORE_PAUSED y liberarlo conserva el contenido |

Defectos encontrados por las pruebas y corregidos antes del commit (conservados):

- **Cabecera de Vincular.** La etiqueta larga «Actualizar referencias» dejaba al título y al subtítulo sin ancho a 420 px: el contenido empezaba a 2 604 px. La etiqueta pasa a «Actualizar».
- **`setState` de flecha.** Tres asignaban un `Future` y el contrato del proyecto (`set_state_contract_test`) los rechazó.
- **Pruebas F04 con v8 fijada.** Afirmaban la versión 8 y el conjunto exacto de triggers. Ahora usan la versión vigente y el conjunto exacto con los triggers v9. **No es un debilitamiento:** el conjunto sigue siendo exacto.
- **`downgradeToV7` de los fixtures.** No quitaba lo de v9, así que una «v7» de prueba conservaba la outbox. Ahora es fiel (`dropSyncSchemaV9`, `downgradeToV8`).

### Mutaciones

Cada mutación es un reemplazo exacto en `lib/`. Se ejecutaron las suites indicadas y se restauró el archivo byte a byte, comprobando su SHA-256. Las mutaciones se aplicaron sobre el árbol previo al commit; las pruebas tenían entonces los nombres `f05_*`, equivalentes a los actuales.

| Mutación | Resultado |
| --- | --- |
| M01 reescribir una intención ya enviada | detectada |
| M02 enviar sin registrar el intento antes | detectada |
| M03 sin la comprobación de antecesor | **sobrevive: mutante equivalente.** La regla «primera sin asentar por contribución, en orden de id» ya impide enviar la sucesora |
| M03b sin la regla «una por contribución» | **sobrevive: equivalente.** La comprobación de antecesor la cubre |
| M03c sin ninguna de las dos guardas | detectada |
| M04 sin reapoyar la sucesora tras un rechazo | detectada |
| M05 aceptar un ACK de otra intención | detectada |
| M06 un 403 pausa sólo una intención | detectada |
| M07 restaurar sin pausar la cola | detectada |
| M08 otra cuenta publica lo del titular | detectada |
| M09 CANCEL con cantidad | detectada |
| M10 redondear una fracción de ML/G | detectada |
| M11 vincular dimensiones distintas | detectada |
| M12 cambiar de titular ignorando la cola | detectada |
| M13 campaña cerrada sigue vigente | detectada |
| M14 entregar el token antes del commit | detectada |
| M15 un 401 conserva el token | detectada |
| M16 una intención rechazada como antecesora | **sobrevivió en la primera tanda.** Faltaba la prueba «tras un rechazo, la siguiente edición no se apoya en la intención rechazada». Se añadió y la mutación queda detectada |
| M17 un 422 no detiene el worker | detectada |
| M18 sin el trigger de inmutabilidad | detectada |
| M19 declarar sin la compuerta de activación | detectada |
| M20 un conflicto resuelto sigue bloqueando | detectada |
| M21 RESTORE_PAUSED enviable en el worker | **sobrevive: enmascarada.** `markSending` sólo admite estados enviables en SQL y no envía nada |
| M21b RESTORE_PAUSED enviable en ambas guardas | detectada |

## 4. Discrepancias con el brief D3 (gana el contrato o el issue más específico)

| Brief | Se aplicó | Por qué |
| --- | --- | --- |
| `GET /api/v1/sync/v1/refs` | `/api/v1/sync/v1/references` | Es la ruta del Backend (PR BE #109) |
| Columna `central_ref` en `campaigns`/`products` | Tablas de vínculo con tenant, estado, motivo y fecha | #72 pide estado y fecha del vínculo; el tenant evita usar referencias de otro tenant |
| `declared_needs` sin historial y con campaña elegida | Historial inmutable y campaña derivada de la fecha | #34: «conservando sus versiones» y «la campaña que corresponde a su referencia temporal» |
| `sync_contributions` (espejo local) | Sin espejo. El antecesor sale de las intenciones aceptadas, y el head remoto de una resolución queda en la fila en conflicto | Evita dos fuentes de verdad locales |
| 401: refresh desde el worker y un reintento | El worker no renueva. «Sincronizar ahora» verifica el acceso (acción explícita) y reintenta | F03: la rotación del refresh es una acción del agricultor. El contrato F05 dice «condicionado a refresh/reautenticación segura; no bucle auth» |
| Conflicto: «reintentar con el valor actual o descartar» | «Enviar mi valor actual» o «Retirar mi declaración» | Un aporte CONTESTED no cuenta en el consolidado. Dejarlo sin resolver no es una opción neutra |
| E2E en el POCO contra el Backend real | Recorrido **simulado** (Plan B) | Requiere D2 fusionado, un Backend accesible por HTTPS y el dispositivo |

## 5. Limitaciones declaradas

- **Sin E2E en el dispositivo.** §6 deja `NOT_MEASURED` los pasos 1 a 5 del brief sobre el POCO y el Backend real. `ApiEndpointConfig` sólo admite HTTPS, así que hace falta un Backend con TLS accesible desde el teléfono.
- **Sin consumo total.** No se produce `CONSUMPTION_TOTAL` ni su prueba de propiedad (D4, MOB #32/#33).
- **Sin acceso tras activar.** El token no se obtiene en la primera activación: hay que verificar el acceso (o pulsar «Sincronizar ahora») antes del primer envío.
- **Pausa por 403.** Lo pausado sólo se reanuda con «Sincronizar ahora» tras una verificación correcta del mismo titular.
- **Rechazos visibles.** Los rechazos quedan visibles en el indicador («Rechazado: n») de forma permanente, como historial.
- **Sin segundo plano.** No hay sincronización en segundo plano, sólo en primer plano.
- **Fecha de la campaña.** Se compara la fecha local con la parte de fecha de los inicios y fines guardados en UTC. Es correcto en Bolivia (UTC−4).
- **Unidades.** Sólo L y KG (F06 §2).

## 6. Recorrido completo: simulado, no medido en dispositivo

`test/sync_simulated_central_test.dart` reproduce los pasos 1 a 5 del brief contra un **Central simulado** en memoria. El simulador aplica:

- la identidad por `operationId`;
- el reenvío idéntico como ALREADY_APPLIED con la hora original;
- IDEMPOTENCY_MISMATCH ante otro contenido;
- un fork como CONFLICT, sin cantidad.

**No es el Backend real ni el POCO.**

| Paso del brief | Simulado (host) | Dispositivo + Backend real |
| --- | --- | --- |
| 1. Sin red: declarar → Pendiente | PASS (sin acceso no hay llamadas; estado PENDING) | NOT_MEASURED |
| 2. En línea → Sincronizado; una contribución y un journal | PASS (1 y 1) | NOT_MEASURED |
| 3. Respuesta perdida tras el commit → reintento ALREADY_APPLIED; conteos iguales | PASS (2 journals tras SUPERSEDE; sin duplicado; 2 intentos) | NOT_MEASURED |
| 4. Cierre forzado durante el envío → mismo resultado | PASS (mismo `operationId` al reabrir) | NOT_MEASURED |
| 5. Editar → SUPERSEDE; anular → CANCEL; estados coinciden | PASS (PUBLISH → SUPERSEDE → CANCEL, todo ACKED; Central CANCELLED sin cantidad) | NOT_MEASURED |
| Extra: fork desde otro teléfono → CONFLICT → decisión del propietario | PASS (CONTESTED sin cantidad → resolución aceptada) | NOT_MEASURED |

## 7. Revisiones

- Pruebas automatizadas: Claude Code, 2026-10-15 (arriba).
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte, por entregable o gate, en GOV-01.
- GATE-F05 (BE #19): Pending. Su acta se redactará con el E2E en el dispositivo.
