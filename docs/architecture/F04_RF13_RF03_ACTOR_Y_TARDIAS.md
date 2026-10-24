# F04: actor de reversión (RF-13) y operación tardía con revisión (RF-03) — contrato

- **Fecha real:** 2026-10-23 (America/La_Paz). Sesión A, sobre Mobile `b0d169b` + `f90d330` (dependencia `cryptography`) y F03 (`cc88fdd`, `7713f9c`).
- **Fuente:** decisión de Roderich Rendón del 2026-10-23 (bloque de decisiones F01–F08, §3, §4 y §9; el archivo de trabajo no está en el repositorio). Es una decisión del autor para el entorno sintético, no una aprobación institucional.
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

`reversal_audit_effects`: las filas compensatorias que escribió o anuló la reversión. Una por fila, con `(audit_id, table_name, row_id)`. Un CHECK limita la tabla a `inventory_movements`, `account_transactions`, `inventory_lots`, `provider_payments` y `application_consumptions`.

**Atomicidad.** Los efectos, la fila de auditoría y sus referencias se escriben en **la misma transacción**, por `_write`, que respeta la exclusión de sustitución de la base (`DatabaseReplacementGuard`; R4 de C). Si algo falla, no queda nada.

**Lo que esto no prueba.** La credencial identifica una **autorización**, no quién sostenía el teléfono.

### 1.3 Reversiones anteriores y bases sin titular

- **Reversiones sin auditoría** (anteriores a v11): se muestran como «Actor no registrado». No se infiere el actor y no se hace backfill.
- **Credencial de otra instalación** (R3 de C). `credential_enrolment_ref` apunta a un enrolamiento del almacén seguro, que no viaja en el respaldo. Tras restaurar en otro teléfono, la auditoría sigue mostrando al titular de `actor_*` como autorizante con su PIN: nunca un error ni «Actor no registrado».
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
- **Foto de factura** (R1 de C): va en la columna propia `invoice_image_path`, sólo si `kind = PURCHASE`, nunca dentro del JSON. Así el respaldo la incluye y la reapunta igual que la de `purchases`; el cambio del módulo de respaldos lo hace C. La ruta se puede reapuntar también en un borrador resuelto, sin tocar nada más.
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
1. **Lotes elegibles:** no anulados y con día de `acquired_date` ≤ día efectivo. **Un lote adquirido el mismo día es elegible.** Nunca uno adquirido después.
2. **Cupo de cada lote** (I1 de B):
   - Los movimientos del lote se ordenan por **día efectivo** (`movement_date`) y, dentro del día, por `id`. Nunca sólo por `id` ni por orden de inserción: un movimiento tardío se inserta después con una fecha anterior.
   - **La operación tardía se coloca al final de su día efectivo**, después de todo lo de ese día.
   - El cupo es el `min` del saldo acumulado al final del día efectivo y del saldo acumulado al final de cada día posterior con movimientos.
   - Así, restar la cantidad en la fecha efectiva **no deja negativo ningún saldo histórico ni el actual**. No se consume material que otra operación ya usó después.
3. **Orden:** FIFO por `acquired_date, id`. El costo es el del lote.
4. **Si el cupo total no alcanza**, la confirmación **no se aplica**:
   - el borrador sigue `PENDING`, con `last_conflict_code = LATE_STOCK_UNAVAILABLE` y un mensaje que dice la causa;
   - camino explícito: rechazarlo, o registrar antes la compra tardía que faltaba (también con revisión) y volver a confirmar;
   - no se presenta como aceptada.

**Lote de una compra tardía** (m1 de B): los lotes no van por campaña. Un lote creado por una compra tardía confirmada puede consumirlo el FIFO ordinario de la campaña activa, como cualquier lote del titular con saldo, con la regla de arrastre vigente. No se crea ninguna regla nueva.

**Vistas privadas de saldo e historial** (I1 de B): ordenan por día efectivo y, dentro del día, por `id`, para que una tardía no muestre saldos intermedios negativos o incoherentes.

**La publicación no cambia por una confirmación** (I2 de B):
- confirmar una operación tardía **no encola nada**: ningún PUBLISH ni SUPERSEDE automático hacia una campaña cerrada o sellada;
- al confirmar, la interfaz avisa: «Es una corrección privada de una campaña cerrada. El consolidado del sindicato (sellado o no) no se actualiza con ella».

**Liquidación y reportes privados de la campaña cerrada.** Cambian sólo por la confirmación expresa:
- se añaden los cargos y consumos de la operación confirmada;
- las vistas privadas de esa campaña muestran «Incluye operaciones tardías confirmadas»;
- la auditoría (el borrador resuelto) dice cuándo y por quién.

**La campaña ya no es la misma al confirmar** (I4 de B): si la fecha efectiva ya no clasifica en `draft.campaign_id` (cambió un período o una campaña), la confirmación **no se aplica**. El borrador sigue `PENDING` con `last_conflict_code = LATE_CAMPAIGN_CHANGED`. Nunca se confirma en otra campaña sin una revisión nueva: el camino es rechazarlo y capturar uno nuevo.

### 2.4 Campaña cerrada frente a consolidado sellado (con B)

- **Son conceptos distintos.** Cerrar (Mobile y Central) termina la operación ordinaria. Sellar (Central, BE F07) fija una versión colectiva.
- **Una confirmación tardía es privada:** **no se publica automáticamente**, y la publicación de consumo sigue siendo una acción expresa del agricultor.
- **Si el agricultor intenta publicar un valor de una campaña cerrada o sellada**, Central responde `REJECTED / CAMPAIGN_NOT_OPEN` o `REJECTED / CAMPAIGN_SEALED` (contrato de B, `F07_SEALED_HISTORY_CONTRACT.md` §7). Mobile:
  - acepta `CAMPAIGN_SEALED` en la lista cerrada de códigos de `REJECTED` (`sync_wire.dart`);
  - lo trata como un **fallo terminal que requiere intervención**: sin backoff ni reintentos, sin reasignar a otra campaña. **Tampoco se reenvía al reiniciar la app** (m4 de B): queda en el estado terminal de la outbox;
  - conserva el dato local;
  - explica: «Esta campaña está sellada en el sindicato: el histórico colectivo sellado no se actualiza con correcciones posteriores. Su registro privado se conserva».
  - El mensaje de `CAMPAIGN_NOT_OPEN` no dice «sellada» (m3 de B): «La campaña ya no admite publicaciones en el sindicato. Su registro privado se conserva».
- **Se distinguen tres cosas:**
  - un replay ya aceptado, que conserva su resultado original;
  - una retirada (CANCEL), que sigue la causalidad de siempre;
  - una publicación nueva rechazada.
- **No se construye corrección ni reapertura en Central.**

### 2.5 Período histórico explícito

Si la fecha no está en ninguna campaña, `addHistoricalCampaign(name, start, end)`:
- crea una campaña `CLOSED` con inicio y fin **anteriores a hoy**;
- exige que **no se solape** con ninguna campaña local, **incluidas las vinculadas a campañas centrales** (I3 de B);
- **no cambia la campaña activa ni el orden** de las demás;
- es una acción expresa, con confirmación en la interfaz.

**Un período local no es una campaña central** (I3 de B):
- no tiene `campaign_ref` y **nunca se publica desde él**; la interfaz lo explica;
- si después llega del Central una campaña que se solapa, nada se reclasifica ni se reasigna solo: los borradores pendientes quedan en conflicto (`LATE_CAMPAIGN_CHANGED` al intentar confirmar) y las tardías confirmadas se quedan en su período local.

Después, la fecha clasifica en ese período cerrado y sigue el recorrido de §2.1. **No se reabren campañas.**

## 3. Pruebas mínimas

Además de las de abajo (m2 de B y el oráculo de I1):
- el historial de saldos de un lote, contra un oráculo, antes, durante y después de varias tardías confirmadas en un orden distinto del cronológico, incluida una reversión posterior de una compra;
- la reversión (RF-13) de una compra tardía cuyo lote ya consumió otra tardía: se rechaza porque tiene consumos, como cualquier compra.

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
  - `CAMPAIGN_SEALED` terminal, sin reintentos, tampoco al reiniciar.

## 4. Revisiones aplicadas (2026-10-23)

- **C** (identidad, auditoría y restauración), sobre `bdfeb66`: LISTO con condiciones. R1–R4 aplicados en §1.2, §1.3 y §2.2. R5 es información.
- **B** (diseño temporal y sellado), sobre `bdfeb66`: LISTO con condiciones. I1–I4 y m1–m5 aplicados en §2.3, §2.4, §2.5 y §3, y la fuente corregida (m5).
- **C sobre el código de RF-13** (`6e5db96`, `48dd1b7`, y su relación con la restauración), 2026-10-23, por lectura: LISTO con condiciones.
  - **R1, un fallo de lectura no es «sin actor»:** si no se puede leer la auditoría, la pantalla dice «No se pudo leer quién autorizó esta reversión». «Actor no registrado» queda sólo para las reversiones anteriores a v11 (`reversalActorLabel`).
  - **R2, otra credencial:** la pantalla compara `credential_enrolment_ref` con el enrolamiento del PIN configurado ahora.
    - Si coinciden: «con el PIN de este teléfono».
    - Si no coinciden: «con un PIN que ya no está configurado en este teléfono (anterior o de otra instalación)».
    - El enrolamiento cambia también al restablecer el PIN en el mismo teléfono, así que no se afirma «otra instalación».
    - Si no se puede leer el PIN: «con su PIN (no se pudo comprobar en este teléfono)».
  - **R3, prueba del respaldo:** `f04_rf13_reversal_backup_test`. Exporta una base con una reversión auditada y la restaura en otra base. `reversal_audit` y `reversal_audit_effects` llegan idénticas, el texto es el de otro PIN y revertir de nuevo la misma operación falla sin escribir nada.
  - **R4, se consume antes de aplicar** (también lo señala B en la revisión del PIN): la autorización se marca usada antes de los efectos. Si la transacción se deshace, hay que volver a poner el PIN. Es deliberado, porque falla cerrado.
- **Decisión de Roderich, aplicada el 2026-10-24:** autoridad de la autorización. Toda reversión (RF-13) y toda confirmación o rechazo de una operación tardía (RF-03) exigen que la autorización se haya emitido con el PIN vigente en la instalación. Lo compara `consumeOwnerAuthorization` con `currentEnrolmentId`, dentro de la transacción.
  - Restablecer el PIN invalida al instante las autorizaciones anteriores.
  - Una credencial fabricada sobre otro almacén no autoriza nada.
  - Detalle, pruebas y límites en F03 §8.
  - Revisión de B sobre `f4c85c5`: R1 y R3 importantes, R2 recomendada; aplicadas. La autorización vale sólo si la emitió el almacén de la instalación con el PIN vigente (`installation.accepts`).
