# 15 — Reglas de negocio

**Documento crítico.** Cada regla está extraída del código y verificada. Se distingue
explícitamente entre:

- **REGLA DE NEGOCIO** — se aplica en `AgroRepository`, dentro o antes de la transacción, y
  no se puede eludir desde ninguna vía. Es la verdad del sistema.
- **VALIDACIÓN DE INTERFAZ** — se aplica solo en el widget, para dar mejor mensaje; si se
  eludiera, la regla de repositorio (si existe) atraparía el caso.
- **RESTRICCIÓN DE ESQUEMA** — la impone SQLite (`CHECK`, `UNIQUE`, `FK`).

Las validaciones exclusivamente de interfaz se listan aparte en
[16_VALIDATIONS](16_VALIDATIONS.md).

---

## Grupo A — Personas y catálogos

### RN-01 · La política de cobro se deriva del rol
- **Descripción**: al crear una persona sin política explícita se asigna
  `ADMIN → MANUAL`, `FAMILY → BY_ACTUAL_USAGE`, `THIRD_PARTY → BY_PURCHASE_ALLOCATION`.
- **Ubicación**: `agro_repository.dart` → `addPerson`, expresión `switch (role)`.
- **Responsable**: `AgroRepository`.
- **Impacto**: **Máximo.** Es la regla de la que depende todo el modelo de deuda. Determina
  si a una persona se le cobra al comprar o al aplicar.
- **Nota**: el parámetro `policy` permite sobreescribirla, pero **la UI nunca lo usa**:
  `CatalogsScreen._add` llama `addPerson(name:, role:)`. En la práctica, rol y política son
  equivalentes uno a uno.

### RN-02 · La unidad base se deriva de la unidad del producto
- **Descripción**: `base_unit = (unit == 'L') ? 'ML' : 'G'`.
- **Ubicación**: `agro_repository.dart` → `addProduct`.
- **Restricción de esquema**: `CHECK(unit IN ('L','KG'))` y `CHECK(base_unit IN ('ML','G'))`.
- **Impacto**: garantiza que el factor 1 000 de las cantidades `_base` sea siempre coherente.
- **Nota**: la función acepta cualquier cadena en `unit`; si llegara `'X'`, el `CHECK` de
  SQLite la rechazaría. La UI solo ofrece L y KG mediante un `SegmentedButton`.

### RN-03 · Los catálogos se archivan, nunca se borran
- **Descripción**: `archiveCatalog` hace `active = 0` para `persons`, `farms`, `products`,
  `suppliers`; y `status = 'CLOSED'` para `campaigns`.
- **Ubicación**: `agro_repository.dart` → `archiveCatalog`.
- **Impacto**: preserva la integridad referencial histórica. Las consultas de catálogo
  (`people()`, `products()`, `suppliers()`, `farms()`) filtran `active = 1`, pero los
  registros históricos siguen resolviendo sus `JOIN`.
- **Seguridad**: `renameCatalog` y `archiveCatalog` validan la tabla contra una **lista
  blanca** (`{'persons','farms','products','suppliers','campaigns'}`); cualquier otra lanza
  `ArgumentError`. Esto neutraliza la inyección por nombre de tabla.

---

## Grupo B — Campañas

### RN-11 · Solo puede existir una campaña ACTIVE
- **Descripción**: doble refuerzo.
  1. **Restricción de esquema**: `CREATE UNIQUE INDEX idx_campaign_single_active ON campaigns((1)) WHERE status='ACTIVE'`.
  2. **Regla de negocio**: `activateCampaign` comprueba si hay otra activa y, si la hay y no
     se pasó `closeCurrent: true`, lanza `CampaignConflictException`.
- **Ubicación**: `app_database.dart` (índice); `agro_repository.dart` → `activateCampaign`.
- **Impacto**: **Alto.** Es la invariante mejor protegida del sistema.
- **Comportamiento derivado**: `addCampaign` cuenta las activas dentro de una transacción;
  si no hay ninguna, la nueva nace `ACTIVE`; si ya hay una, nace `PLANNED`. **La primera
  campaña creada en una base vacía queda activa automáticamente.**
- **Test**: `v4_repository_test.dart` — *"solo una campaña activa y el inventario sobrevive al cambio"*.

### RN-12 · Una campaña ARCHIVED no puede activarse
- **Ubicación**: `agro_repository.dart` → `activateCampaign`.
- **Mensaje**: *"Una campaña archivada no puede activarse."*
- **Impacto**: **Nulo en la práctica.** Ninguna ruta de código escribe jamás
  `status = 'ARCHIVED'`. La regla protege un estado inalcanzable. Ver [26](26_TECHNICAL_DEBT.md).

### RN-13 · Las operaciones exigen campaña activa
- **Descripción**: `_ensureCampaignActive(executor, campaignId)` consulta
  `WHERE id=? AND status='ACTIVE'` y lanza *"La campaña no está activa. Active una campaña
  para continuar."* si no encuentra fila.
- **Se aplica en**: `confirmPurchase`, `confirmApplication`, `addPlanMulti` — **dentro** de
  la transacción, antes de cualquier `INSERT`.
- **NO se aplica en**: `transferProductsFifo`, `addAccountPayment`, `addProviderPayment`.
- **Impacto**: **Alto.** Impide registrar operaciones contra campañas cerradas.
- **Asimetría deliberada**: transferir stock y registrar pagos son operaciones que **deben**
  poder hacerse fuera de campaña (p. ej. cobrar una deuda vieja tras cerrar el ciclo). Es
  coherente con `personCampaignBalance`, que calcula saldos que cruzan campañas.

### RN-14 · Solo una campaña ACTIVE puede cerrarse
- **Descripción**: `closeCampaign` ejecuta `UPDATE ... WHERE id=? AND status='ACTIVE'`; si
  `changed == 0`, lanza *"Solo una campaña activa puede cerrarse."*
- **Ubicación**: `agro_repository.dart` → `closeCampaign`.
- **Efecto**: `status = 'CLOSED'` y `end_date = ahora`. Reactivar limpia `end_date` a `NULL`.

### RN-15 · Cerrar campaña NO afecta al inventario ni a la deuda
- **Descripción**: `closeCampaign` solo modifica la fila de `campaigns`. Los lotes,
  movimientos y asientos contables permanecen intactos.
- **Impacto**: **Alto y explícito en la UI**: el diálogo de cierre advierte *"El inventario
  físico no se elimina y seguirá disponible en la próxima campaña."*
- **Test**: `v5_domain_test.dart` — *"catálogo, stock y deuda permanecen al cambiar campaña"*
  verifica que tras cambiar de campaña el producto sigue existiendo, el stock disponible
  sigue siendo 15 000 y el saldo de la persona no varía.

---

## Grupo C — Compras

### RN-04 · Una compra necesita al menos un producto
`confirmPurchase`: *"La compra necesita al menos un producto."*

### RN-05 · No se pueden repetir productos dentro de una compra
- **Descripción**: se compara el tamaño del `Set` de `productId` con el número de ítems.
- **Mensaje**: *"No repita productos dentro de la compra."*
- **Impacto**: evita ambigüedad en el costeo y en las asignaciones.

### RN-06 · Cantidad y precio deben ser mayores que cero
`if (item.quantityBase <= 0 || item.originalUnitPriceMinor <= 0)` →
*"Cantidad y precio deben ser mayores a cero."*

### RN-07 · Coherencia moneda ↔ tipo de cambio (regla bidireccional)
- **USD exige TC**: `currency == usd && (exchangeRateScaled ?? 0) <= 0` →
  *"Una compra en USD requiere tipo de cambio."*
- **BOB prohíbe TC**: `currency == bob && exchangeRateScaled != null` →
  *"Una compra en BOB no debe guardar tipo de cambio."*
- **Impacto**: **Alto.** La segunda mitad es la más valiosa: impide que un TC residual
  corrompa el costo de una línea en bolivianos.

### RN-08 · La suma asignada debe igualar exactamente la cantidad comprada
- **Descripción**: por cada ítem,
  `allocations.fold(sum) != item.quantityBase` → *"La cantidad asignada debe coincidir con
  la cantidad comprada."*
- **Impacto**: **Máximo.** Garantiza que todo el producto comprado tenga dueño, y que la
  suma de lotes creados sea exactamente igual a lo comprado. Es la regla que sostiene la
  ecuación de inventario.

### RN-09 · La compra crea lotes e inventario en la misma transacción
- **Descripción**: por cada asignación se insertan **cuatro** filas ligadas:
  `purchase_allocations` → `inventory_lots` → `inventory_movements(PURCHASE_IN)` →
  y opcionalmente `account_transactions`.
- **Impacto**: **Máximo.** Todo o nada.
- **Test**: *"fallo interno revierte toda la transacción de compra"* — con un `personId`
  inexistente no queda ni compra, ni ítems, ni lotes.

### RN-10 · Cobro al confirmar la compra solo si la política es BY_PURCHASE_ALLOCATION
- **Descripción**: se lee la política **de la persona en ese momento** y se guarda como
  `charge_policy_snapshot`. El asiento `PURCHASE_ALLOCATION_CHARGE` se crea **solo si** la
  política es `BY_PURCHASE_ALLOCATION`.
- **Cálculo**: `costForBaseQuantity(cantidadAsignada, precioUnitarioBOB)`.
- **Impacto**: **Máximo.** Es la regla que diferencia terceros de familiares.
  - Tercero → deuda inmediata por lo que se llevó.
  - Familiar → **sin deuda**; recibe stock "en custodia".
- **Snapshot**: guardar la política en la fila hace que cambiar el rol de una persona
  **no reescriba la historia**. Diseño correcto.
- **Test**: *"asignación familiar no crea deuda; uso y pago parcial sí"* verifica que tras
  una compra asignada a un familiar, `statement(familyId)` está **vacío**.

### RN-16 · El pago al proveedor no puede superar el saldo de la compra
- **Descripción**: `addProviderPayment` suma los pagos no revertidos y comprueba
  `paid + amount > total` → *"El pago supera el saldo de la compra."*
- **Además**: importe > 0 (*"El pago debe ser mayor a cero."*) y compra no revertida
  (*"La compra no está activa."*).
- **Desde el 2026-10-26**: la fecha del pago no puede ser posterior a hoy (*"La fecha del
  pago (…) es posterior a hoy (…). Un pago ya hecho no puede tener una fecha futura. No se
  registró nada."*), como la de la compra. No se exige que sea posterior a la compra (un
  anticipo es legítimo). El medio se guarda tal como lo indicó la persona (`PaymentMethod`,
  con `UNSPECIFIED` = «Sin indicar»); el pagador es el titular vigente. Sólo para pagos
  nuevos: los guardados no se reescriben.
- **Impacto**: Alto. Impide sobrepagar a un proveedor.
- **Asimetría notable**: los pagos a **personas** (`addAccountPayment`) **no tienen tope**.
  Ver [16_VALIDATIONS](16_VALIDATIONS.md).

---

## Grupo D — Planificación

### RN-17 · Un plan necesita área y al menos un producto
`addPlanMulti`: `areaM2 <= 0 || items.isEmpty` →
*"El plan necesita área y al menos un producto."*

### RN-18 · No se repiten productos en un plan
- **Regla de negocio**: comparación de `Set` → *"No repita productos dentro del plan."*
- **Restricción de esquema**: `UNIQUE INDEX idx_plan_item_unique (plan_id, product_id)`
  — ⚠️ **solo en instalaciones nuevas**; ver la divergencia de migración en [10](10_DATA_MODEL.md).

### RN-19 · Todas las dosis deben ser mayores que cero
*"Todas las dosis deben ser mayores a cero."*

### RN-20 · Cálculo de la necesidad teórica
- **Fórmula**: `required_quantity_base = divideRoundedHalfUp(area_m2 × dose_base_per_ha, 10000)`
- **Ubicación**: `agro_repository.dart` → `addPlanMulti`.
- **Impacto**: Alto. Convierte "dosis por hectárea" a cantidad total con redondeo mitad arriba.
- **Verificación**: 28 ha (280 000 m²) × 1,5 L/ha (1 500 base) / 10 000 = **42 000** = 42 L.
  Confirmado por dos tests (`repository_test.dart`, `e2e_scenario_test.dart`).

### RN-21 · Los planes pendientes comprometen inventario
- **Descripción**: `inventorySummary` e `inventoryProductHeader` calculan `committed_base`
  como la suma de `required_quantity_base` de planes con
  `status IN ('DRAFT','PLANNED')` **de campañas con `status='ACTIVE'`**.
- **Derivado**: `projected_base = available_base − committed_base`.
- **Impacto**: Medio. Es un cálculo de **presentación**, no bloquea ninguna operación: se
  puede aplicar producto comprometido por otro plan sin advertencia.

---

## Grupo E — Aplicaciones

### RN-22 · Una aplicación necesita al menos un producto
*"La aplicación necesita al menos un producto."*

### RN-23 · No se repiten productos en una aplicación
- **Regla de negocio**: comparación de `Set`.
- **Restricción de esquema**: `UNIQUE INDEX idx_application_item_unique (application_id, product_id)`
  — ⚠️ misma advertencia de migración.
- **Test**: *"duplicados se bloquean en aplicación, plan y transferencia"*.

### RN-24 · La cantidad aplicada debe ser mayor que cero
*"La cantidad aplicada debe ser mayor a cero."*

### RN-25 · Stock suficiente del propietario (regla nuclear del inventario)
- **Descripción**: antes de consumir, se consultan los lotes **de esa persona y ese
  producto** con saldo positivo y se suma el disponible. Si
  `available < line.quantityBase` → *"Stock insuficiente para confirmar la aplicación."*
- **Consulta**:
  ```sql
  SELECT l.*, COALESCE(SUM(m.quantity_signed), 0) AS available
  FROM inventory_lots l JOIN inventory_movements m ON m.lot_id = l.id
  WHERE l.product_id = ? AND l.owner_person_id = ? AND l.reversed_at IS NULL
  GROUP BY l.id HAVING available > 0 ORDER BY l.acquired_date, l.id
  ```
- **Impacto**: **Máximo.** Impide stock negativo. Nótese que el stock es **por persona**:
  no se puede aplicar producto de otro aunque exista en el almacén global.
- **Test**: *"detalle de producto expone stock, lotes y bloquea exceso"* — con 20 L
  disponibles, aplicar 21 L lanza `BusinessRuleException`.
- **Precisión D-03 (decisión del autor, Roderich Rendón, 2026-10-27)**: la consulta de
  arriba vale para una aplicación con fecha de **hoy** (día local). Con fecha **pasada**,
  también dentro de la campaña activa, sólo cuentan los lotes con día de `acquired_date`
  ≤ día efectivo y un cupo que no deja negativo ningún saldo posterior (la misma regla de
  RF-03, `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md` §2.3 y §2.6). Si no alcanza,
  `HistoricalStockException` (también si tampoco alcanza el saldo de hoy), sin efectos
  parciales, con un mensaje que nombra el producto, la fecha y la existencia de ese día:
  *"Bellator: el 15/10/2026 esa persona no tenía este producto; pidió 0,8 L. …"* o
  *"Bellator: el 15/10/2026 esa persona tenía 1 L; de eso quedan 0,3 L sin usar en
  operaciones posteriores; pidió 0,5 L. …"*. Con fecha de hoy, el mensaje sigue siendo el
  de arriba. Con los productores actuales vale para el formulario, la voz y los planes,
  porque vive en `confirmApplication`; las transferencias con fecha pasada quedan fuera. No recalcula costos ni consumos ya
  confirmados ni corrige registros históricos. Desde el 2026-10-28 (decisión del autor), el
  cupo se calcula sobre la proyección corregida: no cuentan los pares operación + reversión
  con vínculo de anulación demostrado (F04 §2.6), sin duplicar existencias, con el saldo de
  hoy como tope y sin PIN para permitir existencias insuficientes. Tests:
  `test/f10_d03_existencia_historica_test.dart`, `test/f10_d03_anulaciones_demostradas_test.dart`.

### RN-26 · Costeo FIFO por lote
- **Descripción**: el consumo recorre los lotes ordenados por `acquired_date, id` y toma de
  cada uno `min(pendiente, disponible)`. Por cada lote tocado se insertan una fila de
  `application_consumptions` y un `inventory_movements(APPLICATION_OUT)`.
- **Costo de cada tramo**: `costForBaseQuantity(take, lot.unit_cost_bob_minor_per_major_unit)`.
- **Costo de la línea**: suma de los tramos → `application_items.cost_bob_minor`.
- **Costo total**: suma de las líneas → `applications.total_cost_bob_minor`.
- **Impacto**: **Máximo.** Es el corazón del sistema de costeo.
- **Test verificado numéricamente**: *"FIFO consume lotes de costos diferentes y valoriza
  Bs 5.450"* — 20 L a Bs 100/L (1/1/2026) + 30 L a Bs 115/L (1/2/2026); aplicar 50 L
  produce consumos de **200 000** y **345 000** centavos, total **545 000** = Bs 5 450,00.

### RN-27 · Cargo por consumo solo si la política es BY_ACTUAL_USAGE
- **Descripción**: tras costear, si la política de la persona es `BY_ACTUAL_USAGE` se
  inserta `account_transactions` de tipo `USAGE_CHARGE` por `total_cost_bob_minor`.
- **Impacto**: **Máximo.** Complementa RN-10: el familiar paga por lo que **usa**, el
  tercero por lo que **se lleva**.
- **Diferencia con RN-10**: aquí se lee la política **actual** de la persona, no un
  snapshot; a diferencia de las compras, la aplicación no guarda `charge_policy_snapshot`.
  Es una asimetría de diseño; ver [26_TECHNICAL_DEBT](26_TECHNICAL_DEBT.md).

### RN-28 · Aplicar desde un plan lo marca como COMPLETED
- **Descripción**: si `draft.planId != null`, se hace
  `UPDATE application_plans SET status='COMPLETED'`.
- **Reversibilidad**: `reverseApplication` lo devuelve a `'PLANNED'`.
- **Test**: *"aplicación desde plan conserva líneas y completa/reabre el plan"*.

### RN-29 · El plan debe pertenecer a la campaña activa
- **Descripción**: `ApplicationFormScreen._load` compara
  `plan.first['campaign_id'] != active['id']` → *"El plan no pertenece a la campaña activa."*
- **Ubicación**: **la pantalla**, no el repositorio.
- **Clasificación**: 🟡 **VALIDACIÓN DE INTERFAZ, no regla de negocio.** `confirmApplication`
  acepta cualquier `planId` sin verificar su campaña. Registrado en
  [29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).

---

## Grupo F — Transferencias

### RN-30 · Origen y destino deben ser distintos
- **Regla de negocio**: `transferProductsFifo` → *"El origen y el destino deben ser diferentes."*
- **Restricción de esquema**: `CHECK(from_person_id <> to_person_id)` en `transfers`.
- **Doble refuerzo**, correcto.

### RN-31 · Al menos un ítem con cantidad positiva
- **Descripción**: se filtra `items.where((i) => i.quantityBase > 0)`; si queda vacío →
  *"Seleccione al menos un producto para transferir."*
- **Nota**: los ítems con cantidad 0 se **descartan silenciosamente**, no producen error.
  Es lo que permite al formulario inicializar todos los campos en `'0'`.

### RN-32 · No se repiten productos en una transferencia
*"No repita productos dentro de la transferencia."* + `UNIQUE(transfer_id, product_id)` en
`transfer_items`.

### RN-33 · Stock suficiente por producto, con atomicidad total
- **Descripción**: por cada producto se verifica el disponible del origen. Si falta en
  cualquiera → *"Stock insuficiente en uno de los productos. No se transfirió ningún item."*
- **Impacto**: **Alto.** La transacción envuelve todos los productos: un fallo en el último
  deshace los anteriores.
- **Test**: *"un item insuficiente revierte toda transferencia multiproducto"* — 5 000 de A
  (que sí hay) y 11 000 de B (que no hay) → no se transfiere **nada** y ambos stocks quedan
  en 10 000.

### RN-34 · La transferencia preserva el costo histórico y el orden FIFO
- **Descripción**: el lote destino hereda del origen `unit_cost_bob_minor_per_major_unit`,
  `currency_code`, `original_unit_price_minor`, `exchange_rate_scaled`, `purchase_item_id` y
  **`acquired_date`**, y registra `parent_lot_id`.
- **Impacto**: **Máximo.** Heredar `acquired_date` es lo que hace que el FIFO del receptor
  siga siendo cronológicamente correcto: un lote transferido no "rejuvenece".
- **Test**: *"transferencia divide lote sin modificar costo histórico"* — el lote destino
  conserva `unit_cost = 11200` y `original_unit_price_minor = 11200`, y el stock global
  sigue siendo 50 000.

### RN-35 · Transferir NO genera efecto contable
- **Descripción**: `transferProductsFifo` **no inserta ninguna fila en `account_transactions`**.
- **Impacto**: **Alto.** Es una decisión de negocio significativa: mover producto entre
  familiares no crea ni cancela deuda. La deuda del familiar nace solo al **aplicar**, y el
  costo que se le imputa es el del lote que consuma, sea propio o recibido.
- **Efecto secundario a tener presente**: si un familiar transfiere producto a otro y este
  lo aplica, **el cargo recae en quien aplica**, no en quien compró. Es coherente con
  `BY_ACTUAL_USAGE`, pero conviene que el usuario lo entienda.
- **Actualización 2026-10-27 (D-07, bloque 2) · la regla se mantiene y se avisa.**
  Decisión del autor (Roderich Rendón) del 2026-10-27: RN-35 **se mantiene** también
  cuando el destino es un tercero con cobro por compra (`THIRD_PARTY`,
  `BY_PURCHASE_ALLOCATION`); no hay `TRANSFER_CHARGE` ni ningún otro asiento por
  transferir, y no se modifican transferencias, asientos ni saldos históricos. Lo que
  cambia es la interfaz:
  - Antes de confirmar, el diálogo «Confirmar transferencia» dice, con el nombre del
    destinatario: «Esta transferencia entrega producto a [persona], pero no genera una
    deuda.», seguido de «Esta transferencia no registra ningún cargo ni cobro a [persona].
    El costo del producto entregado sólo es de referencia, no un precio de venta.». Ambas
    van justo después de De/A, antes de las líneas, y el diálogo se desplaza si hay
    muchas. La frase es la misma con uno o varios productos. El aviso se limita a la
    operación: no anticipa cargos que nazcan después, por ejemplo al aplicar lo recibido
    con cobro por consumo (efecto secundario de RN-35, más arriba).
  - El costo FIFO de una transferencia **no es un precio de venta**: en la lista, el
    detalle, la reversión y el formulario se rotula como costo de referencia.
  - El historial dice el carácter de la operación: «Entrega sin deuda» en cada fila de
    Transferencias y «entrega sin deuda» / «sin deuda» en los movimientos del detalle de
    producto (pases y sus reversiones).
  - Queda **fuera** de este bloque vender, prestar o cobrar entregas. Hueco conocido: el
    tercero que paga por compra no queda debiendo lo que recibe por transferencia (RN-10
    sólo carga al comprar y RN-27 sólo carga por consumo con `BY_ACTUAL_USAGE`); el
    titular que lo compró no tiene cómo cobrarlo dentro de la app.
  - **Prueba**: `test/f10_d07_transferencia_sin_deuda_test.dart`; evidencia en
    `docs/evidence/F10_BLOQUE2_D07_TRANSFERENCIA_SIN_DEUDA.md`. Trazabilidad: RN-35,
    RN-10, RN-27, CU-08, RF-11.

---

## Grupo G — Cuentas y pagos

### RN-36 · El importe de un pago o adelanto debe ser mayor que cero
`addAccountPayment`: *"El importe debe ser mayor a cero."*

### RN-37 · Signo de los asientos
- **Descripción**: cargo = **positivo**; pago/adelanto/crédito = **negativo**
  (`-amountBobMinor`). El saldo es `SUM(amount_bob_minor_signed)`.
- **Impacto**: **Máximo.** Es la convención sobre la que se apoyan `settlements`,
  `topSettlements`, `personProfile`, `personCampaignBalance`, el libro de cuentas de D-04 y
  `dashboard`.
- **Interpretación en la UI** (D-04, decisión del autor del 2026-10-27): con «Todas las
  campañas», Cuentas muestra el **saldo neto** (> 0 debe; < 0 a favor). Con una campaña,
  muestra la **deuda pendiente por origen** de esa campaña (≥ 0) y, aparte, el saldo neto
  y lo que queda a favor sin campaña. Ver
  [D04_E15](architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md) §2.3.
- **Clases de asiento** (D-04 §2.1):
  - cargo: > 0, sin `reversal_of_id`;
  - reversión de cargo: < 0, `reversal_of_id` apunta a un cargo;
  - crédito: < 0, el resto;
  - compensación de un crédito: > 0 con `reversal_of_id`; no existe hoy.

  Las cifras salen de la clase, no de una lista cerrada de tipos.

### RN-38 · Imputación cronológica de pagos a deudas (FIFO de deuda)
- **Descripción**: tras insertar el pago, se consultan los **cargos** de esa persona
  (importe > 0 y `reversal_of_id IS NULL`), con pendiente =
  `importe − revertido − SUM(payment_allocations ya imputadas)`, ordenados por **día local
  de `transaction_date` y luego `id`** (F04 §2.3). Se van creando filas en
  `payment_allocations` hasta agotar el importe.
- **Ubicación**: `agro_repository.dart` → `registerAccountPayment` (y `addAccountPayment`,
  que la llama).
- **Impacto**: **Alto.** Determina qué deuda se considera saldada primero. Desde D-04 es
  además la fuente de «qué deuda quedó pagada» en Cuentas, el detalle, la exportación y el
  resumen de campaña.
- **Cruza campañas deliberadamente**: la consulta **no filtra por `campaign_id`**. Un pago
  registrado en la campaña 2, o sin campaña, cancela primero deuda de la campaña 1. La
  campaña del pago es sólo su campaña de registro.
- **Cargos revertidos** (D-04, criterio Q-5; D-15): un cargo revertido no es deuda
  pendiente y un pago **nuevo** no se le imputa.
  - Las imputaciones guardadas antes no se tocan.
  - Lo imputado a un cargo que después se revirtió queda «liberado por reversión», a favor
    y sin campaña.
- **Tests**: *"saldo inicial cruza campañas y el pago se imputa a deuda antigua"* y
  `d04_imputacion_ledger_test.dart` / `d04_imputacion_base_test.dart` (D04-01 a D04-09,
  M-1 a M-8).

### RN-39 · Adelanto y pago comparten mecánica
- **Descripción**: la única diferencia es `type` (`ADVANCE` vs `PAYMENT`) y
  `reference_type`. Ambos son negativos y **ambos se imputan** a cargos existentes.
- **Consecuencia**: un "adelanto" registrado cuando ya hay deuda **no queda como crédito
  libre**: se consume contra esa deuda.
- **Detalle fino**: la `payment_allocation` sólo se crea si el cargo ya existía. Un
  adelanto anterior a los cargos queda **sin imputar**.
  - El saldo neto lo compensa por suma.
  - La deuda por cargo y lo que queda a favor se muestran por separado.
  - El adelanto no se atribuye a ninguna campaña (D-04, criterio Q-1; ejemplo D04-05).
  - Ninguna lectura crea imputaciones.

### RN-40 · El sobrante de un pago no se imputa, pero sí se contabiliza
- **Descripción**: el bucle de imputación termina cuando `remaining == 0` o se acaban los
  cargos. Si sobra dinero, **no** se crea más `payment_allocations`, pero el asiento
  negativo completo ya está insertado.
- **Impacto**: Medio. El saldo queda negativo (a favor). Desde D-04 se informa como
  «A favor (no aplicado a deuda)», sin campaña: pagos sin imputar + liberado por
  reversión − otros ajustes.

### RN-41 · Los administradores se excluyen de la liquidación
- **Descripción**: `settlements` y `topSettlements` filtran `WHERE p.role <> 'ADMIN'`.
  Desde D-04 también lo hacen la lista de Cuentas y el resumen de campaña.
- **Impacto**: Medio. El administrador puede tener asientos (si alguien se los creara), pero
  nunca aparece en la liquidación.

### RN-42 · Estado de cuenta cronológico con apertura (por fecha)
- **Descripción** (D-04, criterio Q-4; decisión del autor del 2026-10-27): con una
  campaña K, el estado cronológico muestra **todos** los asientos de la persona cuyo
  **día local** cae en el período de K, de cualquier campaña o sin campaña.
  - Empieza por «Saldo al inicio del período», que suma los asientos con día anterior al
    inicio.
  - Termina en «Saldo al cierre del período» si el período ya terminó (fin anterior a hoy,
    con cualquier estado de la campaña) o en «Saldo a hoy».
- **Es un cálculo distinto del desglose por campaña de origen**. El desglose dice cuánto
  falta pagar hoy de los cargos de K, a partir de las imputaciones guardadas («Deuda
  pendiente por origen · K»). No comparten etiqueta.
- **Antes**: la apertura sumaba los asientos de las campañas que empezaban antes, y los
  asientos sin campaña no contaban (KI-05, resuelto). `personCampaignBalance` conserva ese
  cálculo para su caracterización, pero ninguna pantalla lo usa.
- **Tardías**: confirmar una operación tardía en una campaña cerrada añade filas en su
  período, así que el «Saldo al cierre del período» puede cambiar después (ejemplo M-4).
  La leyenda «Incluye operaciones tardías confirmadas» que pide F04 §2.3 sigue sin
  implementarse (carencia previa, C-13 de D04_E15).

---

## Grupo H — Reversiones

### RN-43 · No se puede revertir una compra con lotes consumidos
- **Descripción**: se cuentan las `application_consumptions` no revertidas cuyos lotes
  provengan de esa compra. Si hay alguna → *"La compra tiene lotes consumidos. Revierta
  primero las aplicaciones relacionadas."*
- **Impacto**: **Máximo.** Impide dejar aplicaciones costeadas contra lotes inexistentes.
- **Test**: *"compra consumida bloquea cancelación directa"*.

### RN-44 · No se puede revertir una compra cuyos lotes se movieron
- **Descripción**: por cada lote se comprueba
  `SUM(quantity_signed) != initial_quantity_base` → *"El lote fue transferido o ajustado;
  requiere reversión consistente previa."*
- **Impacto**: Alto. Cubre el caso de transferencias parciales, que RN-43 no atrapa.

### RN-45 · La reversión de compra revierte también los pagos al proveedor
- **Descripción**: `UPDATE provider_payments SET reversed_at = ahora WHERE purchase_id = ? AND reversed_at IS NULL`.
- **Impacto**: Medio. Mantiene coherente el total pagado a proveedores del dashboard.

### RN-46 · Las reversiones compensan, no borran
- **Descripción**: por cada cargo original se inserta un `CREDIT_ADJUSTMENT` con el importe
  **negado** y `reversal_of_id` apuntando al cargo. El cargo original permanece intacto.
- **Ubicación**: `reverseApplication` y `reversePurchase`.
- **Impacto**: **Máximo.** Es la garantía de auditabilidad del sistema.
- **Test**: *"reversión de aplicación restaura inventario y revierte el cargo"* — tras
  revertir, el stock vuelve a 50 000, el saldo vuelve a 0 y `status` es `REVERSED`.

### RN-47 · No se puede revertir una transferencia cuyo destino ya se movió
- **Descripción**: por cada `transfer_lot_items` se comprueba que el saldo del lote destino
  siga siendo igual a lo transferido → *"El stock transferido ya tuvo movimientos.
  Reviértalos antes de continuar."*
- **Detalle correcto**: la verificación se hace **para todos los ítems antes** de escribir
  nada, no en el mismo bucle que inserta. Evita reversiones a medias.

### RN-48 · Una operación no puede revertirse dos veces
- **Descripción**: los tres métodos filtran `reversed_at IS NULL` (y `status='CONFIRMED'` en
  transferencias) y lanzan *"…ya fue revertida o no existe."* si no encuentran fila.
- **Impacto**: Alto. Idempotencia garantizada.

### RN-49 · Revertir una aplicación no tiene guardias
- **Descripción**: a diferencia de compras y transferencias, `reverseApplication` **no
  comprueba nada** salvo que no esté ya revertida.
- **Justificación**: consumir producto es el final de la cadena; no hay operaciones
  posteriores que dependan de ella.
- **Riesgo de UX**: combinado con la **ausencia de diálogo de confirmación** en
  `ApplicationsScreen`, un toque accidental en el icono ↩ revierte de forma inmediata una
  operación contable. Registrado en [29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md).

---

## Reglas de aritmética monetaria

### RN-50 · Redondeo mitad hacia arriba, siempre
`divideRoundedHalfUp(n, d) = (n + d ~/ 2) ~/ d`, con `ArgumentError` si `d <= 0` o `n < 0`.

Se usa en **todos** los cálculos monetarios y de cantidad. La consistencia es total; no hay
ningún punto del código que use `round()`, `floor()` o `/` en coma flotante sobre dinero.

### RN-51 · Conversión de moneda con FX escalado
- `convertedUnitPriceBobMinor(precio, fx) = fx == null ? precio : redondeo(precio × fx / 1e6)`
- `subtotalMinor(cant, precio, fx) = redondeo(cant × precio × (fx ?? 1e6) / (1000 × 1e6))`

**Verificado numéricamente por test**: 420 L × USD 16 con FX 7,00 = **Bs 47 040,00**; con
FX 12,10 = **Bs 81 312,00**.

### RN-52 · El FX se congela en el momento de la compra
`exchange_rate_scaled` se guarda en `purchase_items` **y** se copia a `inventory_lots`, junto
con `original_unit_price_minor`. Un cambio posterior del tipo de cambio **no altera** el
costo de lo ya comprado. Ver RN-34 para su preservación en transferencias.

---

## Mapa de reglas por método

| Método de `AgroRepository` | Reglas que aplica |
|---|---|
| `addPerson` | RN-01 |
| `addProduct` | RN-02 |
| `addCampaign` | RN-11 (parcial) |
| `activateCampaign` | RN-11, RN-12 |
| `closeCampaign` | RN-14, RN-15 |
| `renameCatalog` / `archiveCatalog` | RN-03 |
| `addPlanMulti` | RN-13, RN-17, RN-18, RN-19, RN-20 |
| `confirmPurchase` | RN-04…RN-10, RN-13, RN-51, RN-52 |
| `addProviderPayment` | RN-16 |
| `confirmApplication` | RN-13, RN-22…RN-28, RN-50 |
| `addAccountPayment` | RN-36, RN-37, RN-38, RN-39, RN-40 |
| `transferProductsFifo` | RN-30…RN-35 |
| `reversePurchase` | RN-43, RN-44, RN-45, RN-46, RN-48 |
| `reverseApplication` | RN-46, RN-48, RN-49, RN-28 (reapertura) |
| `reverseTransfer` | RN-47, RN-48 |
| `settlements` / `topSettlements` | RN-41 |
| `personCampaignBalance` | RN-42 |
| `inventorySummary` | RN-21 |

---

# Actualización 2026-09-06 — Dos reglas de ciclo de vida decididas

Dos preguntas que este documento no podía responder leyendo el código, porque eran decisiones
de producto, quedan decididas por el propietario e implementadas.

## RN-PLAN-01 · Un plan representa UNA aplicación planificada

**MODELO A.** Un plan **no** es una plantilla reutilizable.

| | |
|---|---|
| Estados | `PLANNED` a `APPLIED`. (`DRAFT` es el valor por defecto histórico de la columna y se trata como pendiente.) |
| Transición | al registrar la aplicación que lo consume |
| Reaplicar | **prohibido**, con `BusinessRuleException`: *Este plan ya fue aplicado y no puede volver a aplicarse. Cree un plan nuevo si necesita repetir la aplicación.* |
| Revertir la aplicación | el plan **permanece `APPLIED`** |

**Por qué la reversión no reabre el plan.** Revertir corrige un movimiento que ocurrió de
verdad; no devuelve la intención al futuro. Reabrirlo en silencio dejaría un plan listo para
volver a aplicarse sin que nadie lo hubiera pedido, y borraría el rastro de que ya se usó. Si
hay que ejecutar otra vez la planificación, se crea un plan nuevo, y así queda registrado.

**Dónde vive la regla.** En tres capas, a propósito:

1. `confirmApplication` comprueba **dentro de la transacción** que el plan siga pendiente,
   mirando el estado **y** la existencia de una aplicación que lo referencie. Basta una de las
   dos señales para rechazar, de modo que un estado desincronizado por cualquier motivo no
   abra la puerta a duplicar el movimiento.
2. Índice único parcial `applications(plan_id) WHERE plan_id IS NOT NULL`: la invariante es de
   los datos, así que vive en el motor. Protege de cualquier camino futuro.
3. La pantalla no ofrece la acción sobre un plan aplicado.

Un doble toque produce **una sola** aplicación (verificado con dos llamadas concurrentes en la
suite y con doble confirmación en el dispositivo).

**Presentación.** La vista operativa de Planificación muestra los **pendientes**: con los años,
decenas de planes consumidos convertirían la lista de trabajo en un archivo. Los aplicados
**se conservan íntegros** para trazabilidad y se consultan con un interruptor secundario, donde
se marcan "Aplicado" y no ofrecen la acción.

## RN-CAMPAIGN-02 · Una campaña cerrada es terminal

El ciclo es **monótono** en operación normal.

| | |
|---|---|
| Estados | `PLANNED` a `ACTIVE` a `CLOSED` |
| `CLOSED` de vuelta a `ACTIVE` | **prohibido**, con `BusinessRuleException`: *Una campaña cerrada no puede volver a activarse. Cree una campaña nueva para seguir operando.* |
| Campañas activas | como antes, **exactamente una** (índice único parcial `idx_campaign_single_active`) |
| `ARCHIVED` a `ACTIVE` | prohibido (regla anterior, sin cambios) |

**Por qué.** Una campaña cerrada representa un periodo contable ya rendido. Reabrirlo dejaría
entrar movimientos nuevos en un ejercicio dado por concluido, y desharía un cierre que el
usuario confirma sabiendo que es irreversible.

**Dónde vive la regla.** `activateCampaign` rechaza `CLOSED` **antes** de tocar nada, así que
también cubre la vía de cerrar la activa y activar otra (`closeCurrent: true`). Esconder el
botón no bastaba: la comprobación de dominio protege igualmente de una pantalla
desactualizada, de una doble ejecución y de cualquier camino indirecto que aparezca después.

**Presentación.** Sólo una campaña `PLANNED` ofrece "Activar"; la cerrada sólo "Editar"; la
activa sólo "Cerrar". Cerrar pide confirmación declarando la campaña, su periodo, que dejará
de admitir compras, aplicaciones, transferencias y planes, y que **no podrá reactivarse**.

**No se añadió ninguna reapertura administrativa.** Si algún día hace falta, será una
funcionalidad explícita y auditable, y no pertenece a esta baseline.

## Alcance de los saldos (registro de la decisión de UIBUG-013)

No se renombró el concepto de saldo: **cada cifra declara su alcance en la propia pantalla**
("Pendiente · Verano 2026", "Saldo total · todas las campañas"). Un glosario nuevo habría
obligado a reeducar al usuario; decir en cada sitio qué se está sumando resuelve la ambigüedad
sin cambiar el modelo.

Detalle y evidencia: [`46_BASELINE_FINAL_FREEZE`](46_BASELINE_FINAL_FREEZE.md), secciones 7 y 8.
