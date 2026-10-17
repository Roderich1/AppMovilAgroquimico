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
| Intención PUBLISH/SUPERSEDE que **nunca salió** (`PENDING`, `attempts = 0`) bajo una campaña con período incompatible o sin comprobar | El worker la **retiene**: no se envía, no se reescribe ni se borra. `SyncQueueSummary.heldForPeriod` y `heldForPeriod()` la cuentan; la pantalla de sincronización la señala |
| Intención que ya salió alguna vez (`attempts ≥ 1`, por ejemplo `OUTCOME_UNKNOWN`) | Se reenvía igual: mismo operationId y contenido; Central responde por idempotencia (consulta segura, no un aporte nuevo) |
| `CANCEL` | Sale aunque el vínculo esté bloqueado (F06 §6) |
| Total de consumo **aceptado (ACKED)** bajo un vínculo bloqueado | Se muestra bloqueado con su total real y «requiere revisión»; no se envía un cero ni se reasigna a otra campaña. Acción permitida: «Retirar del sindicato» = `CANCEL` con antecesor la intención aceptada, con confirmación del titular (`ConsumptionPublisher.withdraw`). La fila aceptada no se modifica |
| Necesidad declarada vigente bajo un vínculo bloqueado | Un valor nuevo se rechaza con los dos períodos; retirar (`withdraw`) sigue permitido |
| Vínculo bloqueado con aportes | «Vincular con el sindicato» lista «Requiere revisión: período de campaña» con aportes aceptados y retenidos por vínculo (`campaignReviews`) |

**Pantallas:** `central_binding_screen.dart` (períodos local y central en cada fila, opciones centrales deshabilitadas con el motivo, «Fijar fin previsto…», tarjeta de revisión), `consumption_publish_screen.dart` (detalle del bloqueo con los dos períodos, «Retirar del sindicato»), `sync_status_screen.dart` (tarjeta «Envíos retenidos por el período de la campaña»).

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
| Filas ya en cola / ACKED | grupo «cola» (retenida y luego enviada igual; ya enviada se reenvía) y «total ya aceptado (ACKED)…» (señalado, sin cero, retirada con CANCEL, la aceptada intacta) |
| Fecha civil frente a timestamp; America/La_Paz | grupo «fecha civil frente a instante» + paso regional de la CI |
| Migración: actualización y recuperación | grupo «migración v9 → v10» (actualización con mismo esquema que una base nueva; restauración de una copia v9 con `BackupService`) |
| Fallo previo | `f04_c2_period_regression_test.dart` sobre `ec69ae8` |

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

**CI (GitHub Actions) sobre el HEAD del PR:** se registra en el PR y se añade aquí cuando termine.

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
- **Intenciones retenidas** siguen `PENDING` hasta que el período quepa (se envían iguales) o el titular retire la necesidad; no se descartan solas ni hay un estado nuevo en la outbox (habría exigido reconstruir `sync_outbox`).
- **Intenciones que ya salieron alguna vez** no se retienen: son la misma intención (idempotencia); si Central las acepta, el total aceptado pasa a «requiere revisión» como cualquier otro.
- **Un total aceptado bajo un período incompatible** sólo admite la retirada (`CANCEL`) o corregir el período local sin dejar registros fuera. Si las operaciones locales caen fuera del período central, no hay resolución permitida distinta de retirar: queda bloqueado y explícito. No se emite SQL ni se reasigna.
- **«Fijar fin previsto…»** está sólo en «Vincular con el sindicato»; Catálogos (`catalogs_screen.dart`, de A) no cambió.
- **Pantallas** verificadas por las pruebas de almacén y por las pruebas de pantalla existentes (`sync_screens_test.dart`, `consumption_publish_screen_test.dart`, `f10_mensajes_autorizacion_test.dart`); no se añadieron pruebas de widget nuevas para la tarjeta de revisión ni para «Fijar fin previsto…».
- **Rendimiento:** `campaignBindingOf` lee además el período local (una consulta más por lectura). El resumen de la cola y el worker sólo miran los vínculos cuando hay intenciones que nunca salieron.

## 6. Decisiones que siguen con Roderich

- GATE-F04 (#28) y GATE-F06 (BE #22) siguen **Pending**: este PR corrige D-F04-C2 y lo verifica en HOST; el cierre lo decide Roderich tras integrar y comprobar el efecto.
- Integración: después del PR de C (precisión del área), rebasado sobre el `main` resultante, con la CI en verde sobre el HEAD final.
