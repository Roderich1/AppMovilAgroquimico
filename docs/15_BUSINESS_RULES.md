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

---

## Grupo G — Cuentas y pagos

### RN-36 · El importe de un pago o adelanto debe ser mayor que cero
`addAccountPayment`: *"El importe debe ser mayor a cero."*

### RN-37 · Signo de los asientos
- **Descripción**: cargo = **positivo**; pago/adelanto/crédito = **negativo**
  (`-amountBobMinor`). El saldo es `SUM(amount_bob_minor_signed)`.
- **Impacto**: **Máximo.** Es la convención sobre la que se apoyan `settlements`,
  `topSettlements`, `personProfile`, `personCampaignBalance` y `dashboard`.
- **Interpretación en la UI**: saldo > 0 = "Saldo pendiente" (naranja); saldo ≤ 0 = "Saldo a
  favor" (verde).

### RN-38 · Imputación cronológica de pagos a deudas (FIFO de deuda)
- **Descripción**: tras insertar el pago, se consultan los cargos de esa persona con
  `amount_bob_minor_signed > 0`, calculando el pendiente de cada uno como
  `cargo − SUM(payment_allocations ya imputadas)`, ordenados por `transaction_date, id`.
  Se van creando filas en `payment_allocations` hasta agotar el importe.
- **Ubicación**: `agro_repository.dart` → `addAccountPayment`.
- **Impacto**: **Alto.** Determina qué deuda se considera saldada primero.
- **Cruza campañas deliberadamente**: la consulta **no filtra por `campaign_id`**. Un pago
  registrado en la campaña 2 cancela primero deuda de la campaña 1.
- **Test**: *"saldo inicial cruza campañas y el pago se imputa a deuda antigua"* —
  `opening_balance` 100 000, pago de 4 000 en la campaña nueva, `total_balance` 96 000, y la
  única fila de `payment_allocations` vale 4 000, imputada al cargo antiguo.

### RN-39 · Adelanto y pago comparten mecánica
- **Descripción**: la única diferencia es `type` (`ADVANCE` vs `PAYMENT`) y
  `reference_type`. Ambos son negativos y **ambos se imputan** a cargos existentes.
- **Consecuencia**: un "adelanto" registrado cuando ya hay deuda **no queda como crédito
  libre**: se consume contra esa deuda.
- **Test**: *"tercero genera cargo por allocation y adelanto lo compensa"* — adelanto de
  336 000 antes de la compra; al confirmarse la compra el cargo es 336 000, los pagos
  336 000 y el saldo **0**.
- **Detalle fino**: en ese test el adelanto se registró **antes** que el cargo, por lo que
  la imputación no ocurrió al pagar sino que el saldo neto quedó en cero por suma de
  asientos. La `payment_allocation` solo se crea si el cargo ya existía.

### RN-40 · El sobrante de un pago no se imputa, pero sí se contabiliza
- **Descripción**: el bucle de imputación termina cuando `remaining == 0` o se acaban los
  cargos. Si sobra dinero, **no** se crea más `payment_allocations`, pero el asiento
  negativo completo ya está insertado.
- **Impacto**: Medio. El saldo queda negativo (a favor), correctamente. Pero
  `payment_allocations` no cuadra con el total pagado, lo que hay que tener en cuenta si
  alguna vez se hace un informe de conciliación.

### RN-41 · Los administradores se excluyen de la liquidación
- **Descripción**: `settlements` y `topSettlements` filtran `WHERE p.role <> 'ADMIN'`.
- **Impacto**: Medio. El administrador puede tener asientos (si alguien se los creara), pero
  nunca aparece en la pantalla de cuentas.

### RN-42 · Saldo inicial de campaña
- **Descripción**: `personCampaignBalance` calcula `opening_balance` como la suma de los
  asientos cuyas campañas tienen `start_date` **anterior** a la de la campaña consultada.
- **Impacto**: Alto. Es lo que permite mostrar un estado de cuenta por campaña sin perder el
  arrastre.
- **Caso borde no cubierto**: los asientos con `campaign_id = NULL` (posibles: un pago
  registrado con "Todas las campañas" seleccionado) hacen `LEFT JOIN campaigns` → `c.start_date`
  es `NULL` → la comparación `NULL < ?` es falsa → **no cuentan en el saldo inicial** aunque
  sí en `total_balance`. Registrado en [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md).

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
