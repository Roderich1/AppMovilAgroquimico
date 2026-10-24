# F04: actor de reversión (RF-13) y operación tardía con revisión (RF-03) — contrato

- **Fecha real:** 2026-10-23 (America/La_Paz). Sesión A, sobre Mobile `b0d169b` + `f90d330` (dependencia `cryptography`) y F03 (`cc88fdd`, `7713f9c`).
- **Fuente:** `01_DECISIONES_APROBADAS.md` §3, §4 y §9. Es una decisión del autor para el entorno sintético, no una aprobación institucional.
- **Revisión:** C revisa la identidad y la auditoría (§1) y su relación con la restauración; B revisa el diseño temporal (§2) y su relación con el sellado (§3).
- **Trazabilidad:** RF-03, RF-13, RN-15, RN-16, CU-06, CU-09 y DAT.
- **Esquema:** Mobile **v11**, reservada para A en CONTROL.

**Qué enmienda.** El código actual (`463d3ec`) tiene dos limitaciones:
- `reversePurchase`, `reverseApplication` y `reverseTransfer` aceptan un motivo opcional y no registran quién autoriza.
- `_ensureCampaignActive` y `_ensureEffectiveDateInCampaign` rechazan toda compra o aplicación con fecha de una campaña cerrada («requiere revisión»), y no hay ningún circuito de revisión.

Este contrato añade los dos circuitos, sin quitar esas guardas para el registro ordinario.

## 1. RF-13: actor de reversión

### 1.1 Quién autoriza

- **Sólo el titular**, también en modo compartido, con una `OwnerAuthorization` de un solo uso: PIN local y propósito `REVERSE_PURCHASE`, `REVERSE_APPLICATION` o `REVERSE_TRANSFER`, sobre `subjectRef` = `purchase:<id>`, `application:<id>` o `transfer:<id>` (F03 §4).
- **El repositorio exige la autorización.** Las tres reversiones públicas tienen la firma `reverseX(id, {required String reason, required OwnerAuthorization authorization})`. La consumen (`consumeOwnerAuthorization`) **dentro de la transacción que escribe**, contra el vínculo vigente leído en esa transacción. Llamar al repositorio sin autorización, con una vencida o ya usada, o con la de otra acción, falla sin escribir nada.
- **Pantalla y repositorio no aceptan un identificador de actor:** el actor sale de la autorización, no de la pantalla.

### 1.2 Qué se guarda (tablas nuevas de v11, sólo locales)

`reversal_audit`: una fila por reversión, **inmutable** (disparadores sin UPDATE ni DELETE).

| Columna | Contenido |
|---|---|
| `reversal_ref` | UUID estable de la reversión |
| `operation_type` y `operation_id` | `PURCHASE`, `APPLICATION` o `TRANSFER`, con su id. **Único**: una sola reversión por operación (doble toque o reintento) |
| `original_person_id` y `original_effective_date` | El responsable y la fecha efectiva de la operación original, copiados tal como estaban. **La operación original no se reasigna** |
| `reason` | Obligatorio y no vacío |
| `actor_person_id`, `actor_binding_id`, `actor_member_id` y `actor_tenant_id` | Quién autoriza: el titular del vínculo vigente |
| `actor_method` (`LOCAL_PIN`) y `credential_enrolment_ref` | Cómo se verificó. No se guarda el PIN |
| `recorded_at` | Fecha de registro (UTC) |

`reversal_audit_effects`: las filas compensatorias que escribió la reversión. Una por fila, con `(audit_id, table_name, row_id)`, de `inventory_movements`, `account_transactions`, `inventory_lots` o `provider_payments`.

**Atomicidad.** Los efectos, la fila de auditoría y sus referencias se escriben en **la misma transacción**. Si algo falla, no queda nada.

**Lo que esto no prueba.** La credencial identifica una **autorización**, no quién sostenía el teléfono.

### 1.3 Reversiones anteriores y bases sin titular

- **Reversiones sin auditoría** (anteriores a v11): se muestran como «Actor no registrado». No se infiere el actor y no se hace backfill.
- **Base sin titular vinculado** (`legacyUnbound`) o sin PIN enrolado: **no se pueden autorizar reversiones nuevas** hasta activar, elegir el titular y configurar el PIN (F03 §5). El resto de la gestión privada sigue igual: no se bloquean compras, aplicaciones, transferencias ni consultas.

### 1.4 Privacidad

La auditoría es privada:
- viaja en el respaldo como cualquier tabla de SQLite y se conserva al restaurar;
- **no** entra en ningún payload de Sync v1;
- no amplía la lista blanca F06.

## 2. RF-03: operación tardía con revisión

### 2.1 Recorrido

1. **Fecha efectiva.** El usuario la introduce en la compra o la aplicación.
2. **Clasificación** (`_ensureEffectiveDateInCampaign`, sin cambios):
   - futura → rechazo;
   - ambigua (períodos solapados) → rechazo;
   - sin campaña → rechazo, con la opción de **crear un período histórico** (§2.5);
   - en `PLANNED` → rechazo;
   - **en una campaña `CLOSED`** → se ofrece **«Registrar para revisión»**.
3. **Borrador pendiente.** Exige un motivo. Se guarda en `late_operation_drafts`, **separado** de las operaciones confirmadas: **no** afecta a existencias, costos, consumo, liquidación, reportes ni publicaciones. Persiste sin red y al reabrir la app.
4. **Revisión.** El titular confirma o rechaza con su PIN (`CONFIRM_LATE_OPERATION` o `REJECT_LATE_OPERATION`, `subjectRef` = `late:<draft_ref>`). Una vez resuelto, el borrador no se edita. La Directiva no participa ni ve operaciones privadas.
5. **Confirmación.** En **una transacción**:
   - se consume la autorización;
   - se revalidan la campaña de la fecha (única y `CLOSED`), el producto, las personas y la modalidad;
   - se aplican los efectos **una sola vez** en la campaña de esa fecha;
   - el borrador queda `CONFIRMED`, con la referencia a la operación creada.
6. **Rechazo:** el borrador queda `REJECTED`, sin efectos.

**Nunca:** se reabre la campaña, se cambia la campaña activa ni se registra en otra campaña.

### 2.2 Tabla `late_operation_drafts` (v11)

- **Identidad y contenido:** `draft_ref` (UUID), `kind` (`PURCHASE` o `APPLICATION`), `campaign_id` (la clasificada al capturar), `effective_date`, `captured_at`, `reason` (no vacío) y `payload` (JSON del borrador del formulario, el mismo `PurchaseDraft` o `ApplicationDraft`).
- **Estado:**
  - `status` (`PENDING`, `CONFIRMED` o `REJECTED`);
  - `last_conflict_code` y `last_conflict_at`: el último intento de confirmar que no pudo aplicarse;
  - `resolved_at`;
  - `resolver_*`: persona, vínculo, Member, tenant, método y enrolamiento, como en la auditoría de §1.2;
  - `resolution_note`;
  - `result_operation_id`.
- **Disparadores:**
  - un borrador resuelto no cambia;
  - `PENDING` sólo pasa a `CONFIRMED` o `REJECTED`, una vez;
  - no se borra.

Una confirmación doble falla, porque el borrador ya no está `PENDING` dentro de la misma transacción. La autorización es de un solo uso.

### 2.3 Efectos sobre operaciones posteriores (definidos antes del código)

**Principio:** una operación tardía **añade** filas con su fecha efectiva. **Nunca modifica** las asignaciones FIFO, los costos, los consumos ni las fechas de operaciones ya confirmadas.

**Compra tardía:**
- Crea la compra, los lotes (`acquired_date` = fecha efectiva), los movimientos `PURCHASE_IN` y los cargos de la campaña cerrada, como `confirmPurchase`.
- Las aplicaciones posteriores **no** se recalculan: siguen con los lotes que consumieron.
- El lote nuevo queda disponible desde ahora para operaciones futuras.

**Aplicación tardía.** FIFO con validación temporal, para cada línea (persona y producto):
1. **Lotes elegibles:** no anulados y con `acquired_date` ≤ fecha efectiva. Nunca un lote adquirido después.
2. **Cupo de cada lote:** `min` del saldo del lote al final del día efectivo y de su saldo tras cada movimiento posterior a ese día. Así, restar la cantidad en la fecha efectiva **no deja negativo ningún saldo histórico ni el actual**. No se consume material que otra operación ya usó después.
3. **Orden:** FIFO por `acquired_date, id`. El costo es el del lote.
4. **Si el cupo total no alcanza**, la confirmación **no se aplica**:
   - el borrador sigue `PENDING`, con `last_conflict_code = LATE_STOCK_UNAVAILABLE` y un mensaje que dice la causa;
   - camino explícito: rechazarlo, o registrar antes la compra tardía que faltaba (también con revisión) y volver a confirmar;
   - no se presenta como aceptada.

**Liquidación y reportes privados de la campaña cerrada.** Cambian sólo por la confirmación expresa:
- se añaden los cargos y consumos de la operación confirmada;
- las vistas privadas de esa campaña muestran «Incluye operaciones tardías confirmadas»;
- la auditoría (el borrador resuelto) dice cuándo y por quién.

### 2.4 Campaña cerrada frente a consolidado sellado (con B)

- **Son conceptos distintos.** Cerrar (Mobile y Central) termina la operación ordinaria. Sellar (Central, BE F07) fija una versión colectiva.
- **Una confirmación tardía es privada:** **no se publica automáticamente**, y la publicación de consumo sigue siendo una acción expresa del agricultor.
- **Si el agricultor intenta publicar un valor de una campaña cerrada o sellada**, Central responde `REJECTED / CAMPAIGN_NOT_OPEN` o `REJECTED / CAMPAIGN_SEALED` (contrato de B, `F07_SEALED_HISTORY_CONTRACT.md` §7). Mobile:
  - acepta `CAMPAIGN_SEALED` en la lista cerrada de códigos de `REJECTED` (`sync_wire.dart`);
  - lo trata como un **fallo terminal que requiere intervención**: sin backoff ni reintentos, sin reasignar a otra campaña;
  - conserva el dato local;
  - explica: «Esta campaña está sellada en el sindicato: el histórico colectivo sellado no se actualiza con correcciones posteriores. Su registro privado se conserva».
- **Se distinguen tres cosas:**
  - un replay ya aceptado, que conserva su resultado original;
  - una retirada (CANCEL), que sigue la causalidad de siempre;
  - una publicación nueva rechazada.
- **No se construye corrección ni reapertura en Central.**

### 2.5 Período histórico explícito

Si la fecha no está en ninguna campaña, `addHistoricalCampaign(name, start, end)`:
- crea una campaña `CLOSED` con inicio y fin **anteriores a hoy**;
- exige que **no se solape** con ninguna campaña;
- **no cambia la campaña activa ni el orden** de las demás;
- es una acción expresa, con confirmación en la interfaz.

Después, la fecha clasifica en ese período cerrado y sigue el recorrido de §2.1. **No se reabren campañas.**

## 3. Pruebas mínimas

- **RF-13:**
  - reversión con autorización: efectos, auditoría y referencias juntos;
  - sin autorización, vencida, usada, de otra acción o de otro vínculo: nada escrito;
  - doble toque: una sola reversión;
  - un fallo inyectado tras los efectos revierte todo;
  - motivo vacío rechazado;
  - históricos sin actor mostrados como «Actor no registrado»;
  - la auditoría viaja en el respaldo y no en Sync;
  - migración v10 → v11 con los datos intactos y el esquema equivalente.
- **RF-03:**
  - la compra y la aplicación tardías válidas se confirman en su período, con existencias y costos antes y después contra un oráculo;
  - el pendiente no altera existencias, reportes ni outbox;
  - el rechazo no tiene efectos;
  - confirmación doble;
  - fallo transaccional;
  - lote adquirido después de la fecha: no elegible;
  - cupo consumido por una operación posterior: `LATE_STOCK_UNAVAILABLE`, sin efectos, y después la resolución válida;
  - fechas futura, ambigua o sin campaña, con el período histórico creado sin cambiar la activa;
  - persistencia al reabrir;
  - `CAMPAIGN_SEALED` terminal, sin reintentos.
