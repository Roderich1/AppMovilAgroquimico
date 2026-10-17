# D-F04-C2 — Período local contenido en el período central

- **Origen:** Live. **Fecha real:** 2026-10-17. Sesión B de Claude Code, por la delegación técnica de Roderich; decisión D-F04-C2 de `CIERRE_F01_F09_Y_SIGUIENTES_SESIONES_2026-10-17.md` §2 y encargo §4.
- **Base:** Mobile `main` `ec69ae81a6e1168dfb4dd8d7b8a7181f1da1fcd2` (CI 39063721692). **Rama:** `fix/f04-c2-periodo-local-central`.
- **Trazabilidad:** RN-15, RN-16, RF-03, RF-18, DAT-02; CU-06, CU-19. Refs #28 (GATE-F04 sigue Pending) y Refs Roderich1/Agro_Sindicato_Backend-Web#22 (GATE-F06 sigue Pending). Contratos F05 §6/§11 y F06 §6 (CANCEL admitido en campaña cerrada; una transición a cerrada exige revisión, no reapertura).
- **Alcance:** HOST (sqflite_common_ffi). Nada de esto es DEVICE. No cambia el contrato de proyección ni el envelope: no viaja ninguna fecha ni dato privado nuevo.

## 1. Regla aplicada

El vínculo de una campaña local con una campaña central (F05-SYNC-08) sólo está vigente si el **período local está contenido en el central, con extremos inclusivos**. Un fin local abierto no demuestra contención frente a un central con fin: se pide **fijar un fin previsto** compatible, sin cerrar la campaña. Período y estado siguen separados.

| Caso | Resultado |
|---|---|
| Local `[a, b]` dentro de central `[c, d]`, con `a ≥ c` y `b ≤ d` | Compatible (también si `a = c` y/o `b = d`) |
| Local empieza antes que la central | `PERIOD_INCOMPATIBLE`: «empieza antes que la del sindicato» |
| Local termina después que la central | `PERIOD_INCOMPATIBLE`: «termina después que la del sindicato» |
| Local sin fin, central con fin | `PERIOD_INCOMPATIBLE`: «fije un fin previsto hasta el dd/mm/aaaa como máximo (no hace falta cerrarla)» |
| Local sin fin, central sin fin | Compatible si la local no empieza antes |
| Vínculo anterior a esta regla, sin período central guardado | `PERIOD_UNVERIFIED` hasta actualizar las referencias |

Todo mensaje de rechazo muestra **los dos períodos**: «“Campaña local 2026” va desde el 01/09/2026; “Campaña sindicato 2026” del sindicato va del 01/09/2026 al 31/10/2026. …».

## 2. Fecha civil frente a instante

- **Central.** `GET /sync/v1/references` publica `start_date` y `end_date` como `date-time` ISO-8601 en UTC. La Web envía el día elegido con `type="date"` («2026-09-01») y Central lo guarda como medianoche UTC («2026-09-01T00:00:00.000Z»). El **día civil central es la parte de fecha en UTC** del valor (`centralCivilDay`). No se convierte a hora local: en La Paz (−04:00) eso lo movería al 31/08. Para una campaña cerrada, `end_date` es `closedAt` (un instante real): se toma igualmente su día UTC; esa campaña no admite aportes, así que no se vincula.
- **Local.** Las fechas locales son instantes guardados por el teléfono y siguen la regla de día local de #110 (`localDay`, `storedLocalDay`).
- **Normalización probada en cada extremo:** `f04_c2_campaign_period_test.dart`, grupo «fecha civil frente a instante» (incluye el centinela de zona, como `date_display_test.dart`) y «frontera inclusiva: fin local 31/12 cabe en central hasta 31/12». Con la conversión equivocada, en La Paz el fin central sería el 30/12 y esa contención fallaría.

## 3. Qué cambia

**Esquema v10** (`app_database.dart`). `campaign_bindings` gana `central_start_day` y `central_end_day` (días civiles, lo mínimo para comprobar sin red) y los motivos `PERIOD_INCOMPATIBLE` y `PERIOD_UNVERIFIED`. SQLite no amplía un CHECK: la tabla se reconstruye copiando todas las filas. Un vínculo VALID siempre tiene su período central (`CHECK(status = 'INVALID' OR central_start_day IS NOT NULL)`). En la migración, un vínculo que estaba VALID pasa a `PERIOD_UNVERIFIED` (su período no se conocía); uno INVALID conserva su motivo. Se anota `schema_v10_campaign_period_review` en `app_settings` con cuántos quedaron por revisar. Ninguna intención, necesidad ni operación se toca.

**Dónde se revalida** (`central_binding_store.dart`, `agro_repository.dart`):

| Punto | Qué pasa |
|---|---|
| `bindCampaign` | Rechaza con los dos períodos y sin escribir nada; si cabe, guarda el período central |
| `refreshFrom` (referencias) | Recalcula el motivo con el período central nuevo y lo guarda; referencia desaparecida o campaña que no admite aportes prevalecen sobre el período |
| `_endOpenCampaignBefore` (alta de la siguiente, activación de base anterior), `closeCampaign`, `setCampaignEnd` (nuevo) | En la misma transacción que cambia el calendario, asienta el estado del vínculo con el período central guardado: funciona sin red |
| `campaignBindingOf` / `liveCampaignBindings` | Devuelven el estado **efectivo**: el guardado, corregido si el período local actual ya no cabe. Lo usan `DeclaredNeedStore`, `ConsumptionPublisher` y la pantalla |
| Vista previa y `publish` del consumo | `_compute` usa el estado efectivo; `publish` lo recalcula dentro de la transacción y rechaza una vista previa vieja sin escribir nada |

**Fin previsto** (`AgroRepository.setCampaignEnd`): sólo campañas ACTIVE o PLANNED; fin ≥ inicio; ningún registro fechado fuera (compras, aplicaciones, necesidades y sus versiones, por `_lastOperationDay`); sin solapes; no cambia el estado. Si se rechaza, no escribe nada. La acción «Fijar fin previsto…» está en «Vincular con el sindicato» (`central_binding_screen.dart`).

**Aportes anteriores y cola** (`sync_outbox_store.dart`, `consumption_publisher.dart`):

| Situación | Tratamiento |
|---|---|
| Intención PUBLISH/SUPERSEDE **sin asentar** (`PENDING`, `SENDING` u `OUTCOME_UNKNOWN`, con o sin intentos) bajo una campaña cuya compatibilidad temporal no está demostrada | El worker la **retiene**: no sale por POST, no se reescribe ni se borra. `SyncQueueSummary.heldForPeriod` y `heldForPeriod()` la cuentan; la pantalla de sincronización la señala. Da igual el motivo de invalidez guardado: un vínculo migrado con `NOT_ACCEPTING` y sin fechas centrales también retiene (C2-R1) |
| Intención retenida que **ya salió alguna vez** (`attempts ≥ 1`) | Un intento registrado **no demuestra** que Central la recibiera (`markSending` cuenta el intento antes del envío): un reenvío podría ser la primera aceptación. Se **concilia** con `GET /operations/{id}` (§3 bis), nunca con otro POST. *(Antecedente: hasta `5c07dd1` esta fila decía «se reenvía igual… consulta segura»; era inexacto. Corregido el 2026-10-17 por C2-R1.)* |
| Período compatible | Sin cambios: reintentos con el mismo envelope e idempotencia, como en F05 §11 |
| `CANCEL` | Sale aunque el vínculo esté bloqueado (F06 §6) |
| Total de consumo **aceptado (ACKED)** bajo un vínculo bloqueado | Se muestra bloqueado con su total real y «requiere revisión»; no se envía un cero ni se reasigna a otra campaña. Acción permitida: «Retirar del sindicato» = `CANCEL` con antecesor la intención aceptada, con confirmación del titular (`ConsumptionPublisher.withdraw`). La fila aceptada no se modifica |
| Necesidad declarada vigente bajo un vínculo bloqueado | Un valor nuevo se rechaza con los dos períodos; retirar (`withdraw`) sigue permitido |
| Vínculo bloqueado con aportes | «Vincular con el sindicato» lista «Requiere revisión: período de campaña» con aportes aceptados y retenidos por vínculo (`campaignReviews`) |

**Pantallas:** `central_binding_screen.dart` (períodos local y central en cada fila, opciones centrales deshabilitadas con el motivo, «Fijar fin previsto…», tarjeta de revisión), `consumption_publish_screen.dart` (detalle del bloqueo con los dos períodos, «Retirar del sindicato»), `sync_status_screen.dart` (tarjeta «Envíos retenidos por el período de la campaña»).

## 3 bis. C2-R1 y C2-R2: despacho de la cola (2026-10-17, tras la revisión de #116)

Hallazgos de la revisión de Roderich sobre `77a55ab` (`CONTINUACION_TRAS_115_REVISION_116_2026-10-17.md` §2), confirmados por el arnés adversarial de C sobre `5c07dd1`: la retención sólo miraba `isUnsent`, y `readyToSend` comprobaba el período fuera de la transacción de `markSending`.

**Regla (C2-R1).** La retención se decide con `CampaignBinding.periodHold(local)`: hay retención si el vínculo no tiene período central guardado, si no hay período local legible (falla cerrado; revisión de A sobre `c252dca`) o si el período local no cabe, **sea cual sea** el motivo de invalidez que se muestre. `SyncOutboxStore._heldForPeriod` retiene toda intención con valor (acción distinta de `CANCEL`) de una referencia retenida, sin mirar `attempts`. Las retenidas con `attempts > 0` son **inciertas**: el worker las resuelve con la consulta owner-scoped `GET /api/v1/sync/v1/operations/{operationId}` (`SyncApi.operation`, que valida la respuesta con `OperationView.validate`: exactamente `{ack, contribution}`, ACK de las siete claves para **ese** operationId).

| Respuesta de la consulta | Qué hace el worker (`SyncWorker._reconcile`) |
|---|---|
| `APPLIED` / `ALREADY_APPLIED` válido | `recordAccepted(onlyIfUnsettled: true)`: ACK con el `serverAcceptedAt` de Central, sólo si la fila sigue sin asentar. Sin POST |
| `CONFLICT` | `recordConflict`, como por ACK: decide el titular |
| `REJECTED` | `recordTerminal(rejected)`, como por ACK |
| `RETRYABLE` | Sigue retenida; `last_code` = código del ACK |
| **404** `OPERATION_NOT_FOUND` | Sigue retenida con `last_code = OPERATION_NOT_FOUND`. Central no la conoce **ahora**: no autoriza publicar bajo el período incompatible y no demuestra que una petición anterior no pueda terminar después |
| 401 | Acceso descartado; bloqueo `accessRequired`; fila intacta |
| 403 | `pauseForAuthorization` del vínculo (como con un POST); bloqueo `forbidden` |
| 429 / 503 | `last_code` del error; bloqueo `throttled`; fila intacta |
| Sin red / otro HTTP | `last_code` (`UNAVAILABLE` o `HTTP_nnn`); bloqueo `unreachable` |
| 200 con cuerpo inválido o ACK de otra operación | `last_code = INVALID_RESPONSE`; sigue retenida. No se confía |

Nunca se cambia `operation_id`, payload, causalidad ni el historial de intentos: la consulta no cuenta como intento. `CANCEL` nunca se retiene (F06 §6) y conserva su antecesor. Las consultas comparten el presupuesto del ciclo (`budget`) y sólo se hacen si el resumen de la cola (`SyncQueueSummary.uncertainValues`, calculado en la misma consulta agregada) indica intenciones con valor ya intentadas.

**Regla (C2-R2).** `markSending` es la única transacción que marca el despacho: dentro de ella relee la fila (debe seguir enviable), y si la acción no es `CANCEL` consulta `periodHeldCampaignRefs(txn)`; si la referencia está retenida lanza `SyncHeldForPeriodException` **antes** de escribir: ni `SENDING`, ni `attempts + 1`, ni transporte. El worker excluye esa intención del resto del ciclo (`readyToSend(exclude:)`), la cuenta en `SyncRunReport.held` y sigue con las demás; no oculta otros errores (`SyncOutboxRaceException` sigue cerrando el ciclo como antes).

**Consultas SQL efectivamente implementadas:**
- `periodHeldCampaignRefs`: `campaign_bindings ⋈ campaigns` (una consulta), compatibilidad evaluada en Dart;
- `heldForPeriod`/`heldUncertain`: `sync_outbox ⋈ owner_bindings ⋈ campaign_bindings (misma tenant) ⋈ campaigns` sobre las filas sin asentar con valor (una consulta);
- `summary`: la agregación por estado incorpora `values_n` y `uncertain_n`, para no consultar vínculos cuando no hay nada que retener ni conciliar.

**Límites declarados:**
- La conciliación sólo se intenta para intenciones retenidas con `attempts > 0`. Una intención incierta cuya campaña **sí** es compatible sigue el camino normal de reintento (F05 §11), como antes.
- Una intención incierta sin confirmación fiable queda retenida indefinidamente, visible en «Sincronización» y en «Vincular con el sindicato», hasta que el período quepa (entonces sale el mismo envelope), Central la confirme por consulta o el titular retire la necesidad. No se descarta sola.
- El 404 se registra pero no se reinterpreta: no hay un plazo tras el cual se considere «no recibida».
- No cambia el contrato ni el envelope; no hay migración nueva: los estados de la outbox son los mismos; sólo cambian `last_code`/`updated_at` de filas sin asentar.
- La API del despacho cambió para la revisión de C: `readyToSend` admite `exclude`; `markSending` puede lanzar `SyncHeldForPeriodException`; `recordAccepted` devuelve `bool` y admite `onlyIfUnsettled`; nuevos `heldUncertain`, `recordHeldQuery`, `SyncRunReport.queried/held`, `SyncQueueSummary.uncertainValues`.

## 4. Pruebas

Archivo principal: `test/f04_c2_campaign_period_test.dart` (28 pruebas; la CI lo repite en America/La_Paz). Demostración del fallo previo: `test/f04_c2_period_regression_test.dart` (3 pruebas con la API anterior).

| Caso pedido | Prueba |
|---|---|
| Contención exacta y estricta; fronteras inclusivas; salida antes/después; fin abierto; ambas abiertas | grupo «regla de contención (pura)» y «vincular» |
| Mensaje con ambos períodos | «el mensaje muestra los dos períodos»; «rechazo por fin abierto…» |
| Preservación de tablas ante rechazo | «rechazo por fin abierto…» (volcado completo igual), «rechazos: antes del inicio, deja registros fuera…», «vista previa vieja…» |
| Fin previsto sin cerrar; invariantes de #110 | grupo «fin previsto (sin cerrar)» |
| Referencia central actualizada | grupo «referencia central actualizada» (gana fin; mueve inicio; motivo ajeno prevalece) |
| Edición posterior del calendario | grupo «edición posterior del calendario local» (alargar/acortar fin, alta de la siguiente, cierre) |
| Persistencia / reapertura sin red | grupo «persistencia y reapertura» |
| Publicación con vista previa vieja | «vista previa vieja: si el vínculo se volvió incompatible, publicar no escribe nada» |
| Filas ya en cola / ACKED | grupo «cola» (retenida y luego enviada igual cuando cabe) y «total ya aceptado (ACKED)…» (señalado, sin cero, retirada con CANCEL, la aceptada intacta). *(La prueba «ya enviada se reenvía igual» se retiró el 2026-10-17: presuponía recepción; la sustituyen las regresiones de C2-R1.)* |
| **C2-R1 / C2-R2, regresiones 1–7 del encargo** | `test/f04_c2_queue_reconciliation_test.dart`, con un Central falso que distingue «no llegó» (500 sin registrar) de «aceptó y perdió el ACK» (registra y corta la respuesta), cuenta aceptaciones nuevas y responde al GET: 1 primera petición nunca recibida → ningún POST con valor bajo incompatibilidad, ninguna aceptación nueva, `OPERATION_NOT_FOUND` visible, y al caber sale el mismo envelope; 2 aceptada con ACK perdido → conciliada por GET sin POST nuevo; 3 migración v9 con `OUTCOME_UNKNOWN` y período sin comprobar → sin POST; 4 consulta con 401, 403, 429, sin red, cuerpo inválido y ACK de otra operación → ni ACK inventado ni POST; 5 período invalidado entre selección y marcado (`RacingOutbox`) → cero POST, `attempts` sin incremento, negocio y outbox intactos; 6 vínculo migrado `NOT_ACCEPTING` sin fechas → retiene; 7 camino compatible (reintento normal) y `CANCEL` bajo incompatibilidad con antecesor y causalidad intactos |
| Fecha civil frente a timestamp; America/La_Paz | grupo «fecha civil frente a instante» + paso regional de la CI |
| Migración: actualización y recuperación | grupo «migración v9 → v10» (actualización con mismo esquema que una base nueva; restauración de una copia v9 con `BackupService`) |
| Fallo previo | `f04_c2_period_regression_test.dart` sobre `ec69ae8` |
| Pantalla «Fijar fin previsto…» (revisión de A sobre #116) | `test/f04_c2_binding_screen_test.dart` (2 pruebas de widget): la fecha elegida en el selector llega a `setCampaignEnd` y el vínculo pasa de `PERIOD_INCOMPATIBLE` a VALID sin cambiar el estado; un fin ya pasado se advierte antes de confirmar; un fin que deja registros fuera muestra «tiene registros del dd/mm/aaaa» y no escribe nada (volcado completo igual). **Mutación comprobada:** pasar la fecha inicial del selector en vez de la elegida hace fallar la primera prueba (`Expected: '2026-10-15' / Actual: '2026-10-31'`) |

### Resultados (HOST, Windows 11, zona del sistema −04:00)

| Comando | Sobre | Resultado |
|---|---|---|
| `flutter test test/f04_c2_period_regression_test.dart` | **`ec69ae8`** (worktree temporal con el archivo copiado) | **3 fallan, 0 pasan**: «Expected: throws CentralBindingException / Actual: Future<CampaignBinding>» (×2) y «Expected: false / Actual: true» (el vínculo seguía vigente tras refrescar) |
| `flutter test test/f04_c2_period_regression_test.dart` | la rama | 3 pasan |
| `flutter test test/f04_c2_campaign_period_test.dart` | la rama | 27 pasan, 1 omitida (centinela, sólo en el paso regional) |
| `AGRO_TZ_REGRESSION=America/La_Paz flutter test test/f04_c2_campaign_period_test.dart test/declared_need_test.dart test/date_display_test.dart` | la rama, zona del sistema −04:00 | **45 pasan**, centinela incluido |
| `flutter test` (suite completa) | la rama | **1477 pasan, 3 omitidas, 0 fallos** (base `ec69ae8`: 1446 pasan, 3 omitidas) |
| `flutter analyze lib test` | la rama | `No issues found!` |
| `dart format --set-exit-if-changed lib test` | la rama | exit 0 |

| `flutter test test/f04_c2_binding_screen_test.dart` | la rama (tras la revisión de A) | 2 pasan; con la mutación «fecha inicial en vez de la elegida», 1 falla |
| `flutter test test/f04_c2_queue_reconciliation_test.dart` | **`5c07dd1`** (worktree temporal con el archivo copiado; usa sólo la API anterior) | **11 fallan, 3 pasan.** Fallan: C2-R1 1 (nunca llegó: el código anterior reenviaba por POST y Central la aceptaba por primera vez), 2 (ACK perdido: volvía a hacer POST en vez de consultar), 3 (migración v9 con `OUTCOME_UNKNOWN`: POST), 6 (vínculo migrado `NOT_ACCEPTING` sin fechas: POST), las seis de la consulta (401, 403, 429, sin red, cuerpo inválido, ACK de otra operación: el código anterior no consultaba y hacía POST) y C2-R2 5 (carrera: marcaba `SENDING`, contaba el intento y hacía POST). Pasan las tres de control: «CANCEL no se retiene al marcar», «reintento normal» y «CANCEL bajo incompatibilidad con causalidad» |
| `flutter test test/f04_c2_queue_reconciliation_test.dart` | la rama (C2-R1/C2-R2) | 14 pasan |
| Arnés adversarial de C (`_wt/C-REV-116/test/c_rev_116_adversarial_test.dart`, copiado y ejecutado sobre la rama, no incluido en ella) | la rama | **13 pasan, 1 falla**: «el período se invalida entre la selección y el marcado». Su volcado de comparación excluye `sync_outbox` y `campaign_bindings` pero no `product_bindings`, cuyo `checked_at` cambia al refrescar las referencias en su propio `makeIncompatible`; el POST es cero, `attempts` 0 y el negocio intacto. Sobre `5c07dd1` C midió 1 pasa y 13 fallan |
| `flutter test` (suite completa) | la rama, HEAD final | **1496 pasan, 3 omitidas, 0 fallos** |
| `AGRO_TZ_REGRESSION=America/La_Paz flutter test …` (tres archivos de fechas) | la rama, zona del sistema −04:00 | 44 pasan, centinela incluido |

**CI (GitHub Actions):**
- run [39067645517](https://github.com/Roderich1/AppMovilAgroquimico/actions/runs/39067645517) sobre `3596985` (primer HEAD del PR, antes de la prueba de pantalla): **SUCCESS**;
- run [39069260220](https://github.com/Roderich1/AppMovilAgroquimico/actions/runs/39069260220) sobre `77a55ab` (con la prueba de pantalla): **SUCCESS**, 1478 pasan y 4 omitidas (en CI se omite una prueba más que en local, por plataforma); 45 en America/La_Paz; build de release.
- **Rebase** sobre `main` `078d638` (que integra #115 de C, #113 y #114) el 2026-10-17, sin conflictos: los cuatro commits se aplicaron tal cual. La CI del HEAD rebasado se registra en el PR.

### Revisión

- **Sesión A sobre `3596985`:** LISTO, con un hallazgo medio (prueba de pantalla de «Fijar fin previsto…», añadida) y uno menor (fin anterior a hoy en la campaña activa, advertido en el diálogo y declarado en §5). A revisa el HEAD final tras el rebase sobre el `main` que resulte del PR de C.
- **Revisión de Roderich Rendón:** pendiente. GATE-F04 y GATE-F06 siguen **Pending**.

### Pruebas existentes que cambiaron

| Archivo | Antes | Ahora | Por qué |
|---|---|---|---|
| `test/f04_restore_authorization_test.dart`, `test/remote_backup_client_test.dart` | Vinculaban «Campaña 1» (desde el 01/01/2026 UTC; día local anterior en La Paz) con una central que empezaba el 01/09/2026 | La central empieza el 01/01/2025 y contiene a la local | Con la regla nueva el vínculo anterior se rechaza, como debe. La lógica de las pruebas (restauración, respaldo remoto) no cambia |
| `test/central_reference_binding_test.dart` | Columnas de `campaign_bindings` sin período | Añade `central_start_day` y `central_end_day` | Esquema v10 |
| `test/migration_test.dart` | Esperaba `user_version = 9` | Espera `AppDatabase.schemaVersion` | Esquema v10; las filas conservadas se comprueban igual |
| `test/support/f05_sync_fixtures.dart` | `centralCampaign()` con fechas fijas | Parámetros opcionales `startDate` y `endDate` | Las pruebas nuevas necesitan centrales con fin |

## 5. Casos residuales y límites

- **Sólo HOST.** El teléfono no ejecutó esta regla. Si A congela la base para el ensayo físico antes de integrar, el caso «fecha dentro del período, frontera y rechazo fuera de campaña» de #110 no cambia por este PR; la vinculación con período sí sería un caso nuevo para un ensayo posterior.
- **Vínculos anteriores a v10** quedan `PERIOD_UNVERIFIED` hasta que el titular actualice las referencias una vez con red. Mientras tanto no publican valores nuevos; retirar sigue permitido.
- **Campaña central cerrada** (`end_date = closedAt`, instante real): su día civil es el día UTC del cierre. No admite aportes, así que no afecta a vínculos nuevos; en un vínculo existente, «no admite aportes» prevalece sobre el período.
- **Fin previsto:** no se puede volver a dejar abierto ni cambiar el de una campaña cerrada o archivada desde la aplicación. Si hace falta, es otra acción explícita.
- **Intenciones retenidas** conservan su estado (`PENDING`, `SENDING` u `OUTCOME_UNKNOWN`) hasta que el período quepa (entonces sale el mismo envelope), Central las confirme por consulta o el titular retire la necesidad; no se descartan solas ni hay un estado nuevo en la outbox (habría exigido reconstruir `sync_outbox`).
- **Intenciones que ya salieron alguna vez** también se retienen (C2-R1) y se concilian por consulta; los límites de esa conciliación están en §3 bis. *(Antecedente: hasta `5c07dd1` este punto decía que no se retenían porque «son la misma intención (idempotencia)»; era inexacto: un intento no demuestra recepción.)*
- **Un total aceptado bajo un período incompatible** sólo admite la retirada (`CANCEL`) o corregir el período local sin dejar registros fuera. Si las operaciones locales caen fuera del período central, no hay resolución permitida distinta de retirar: queda bloqueado y explícito. No se emite SQL ni se reasigna.
- **«Fijar fin previsto…»** está sólo en «Vincular con el sindicato»; Catálogos (`catalogs_screen.dart`, de A) no cambió.
- **Fin anterior a hoy en la campaña activa.** `setCampaignEnd` lo admite (no rompe ninguna invariante: fin ≥ inicio, sin solapes, ningún registro fuera), pero desde ese día las compras y aplicaciones nuevas caen en «ninguna campaña» y se rechazan hasta crear y activar la siguiente. El diálogo lo advierte antes de confirmar («Atención: ese fin ya pasó…»); la prueba de pantalla lo comprueba. Revisión de A sobre #116, hallazgo menor.
- **Pantallas:** «Fijar fin previsto…» tiene prueba de widget (`f04_c2_binding_screen_test.dart`). La tarjeta de revisión se comprueba dentro de esas pruebas (aparece y desaparece); «Retirar del sindicato» y «Envíos retenidos» se verifican en el almacén (`withdraw`, `heldForPeriod`) y no tienen prueba de widget propia.
- **Rendimiento:** `campaignBindingOf` lee además el período local (una consulta más por lectura). El resumen de la cola y el worker sólo miran los vínculos cuando hay intenciones con valor sin asentar, y `markSending` añade una consulta dentro de su transacción. Las pruebas de pantalla `sync_screens_test` y `f10_mensajes_autorizacion_test` esperan con tiempo fijo y son sensibles a este número; se repitieron tres veces en verde.

## 6. Decisiones que siguen con Roderich

- GATE-F04 (#28) y GATE-F06 (BE #22) siguen **Pending**: este PR corrige D-F04-C2 y lo verifica en HOST; el cierre lo decide Roderich tras integrar y comprobar el efecto.
- Integración: después del PR de C (precisión del área), rebasado sobre el `main` resultante, con la CI en verde sobre el HEAD final.
