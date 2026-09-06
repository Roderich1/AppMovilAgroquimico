# 31 — Matriz de trazabilidad

Relaciona **funcionalidad → pantalla → archivo → regla de negocio → "API" → modelo →
persistencia → test**.

Como el sistema no tiene API HTTP ([11_API_INTEGRATION](11_API_INTEGRATION.md)), la columna
**API** contiene el **método de `AgroRepository`** que hace las veces de endpoint.

Su propósito es doble: navegar el sistema, y **detectar funcionalidades sin pruebas y partes
desconectadas**.

## Matriz principal

| Funcionalidad | Pantalla | Archivo principal | Reglas | Método de repositorio | Modelo / Draft | Persistencia | Test |
|---|---|---|---|---|---|---|---|
| **F-01** Catálogo de personas | Catalogs | `catalogs_screen.dart` | RN-01, RN-03 | `addPerson`, `people`, `renameCatalog`, `archiveCatalog` | `PersonRole`, `SettlementPolicy` | `persons` | 🟡 Indirecto (todos los `setUp`) |
| **F-01** Catálogo de chacos | Catalogs | `catalogs_screen.dart` | RN-03 | `addFarm`, `farms`, `farmsForPerson` | — | `farms` | 🟡 Indirecto |
| **F-01** Catálogo de productos | Catalogs | `catalogs_screen.dart` | RN-02, RN-03 | `addProduct`, `products` | — | `products` | 🟢 `repository_test` (unidad L/KG) |
| **F-01** Catálogo de proveedores | Catalogs | `catalogs_screen.dart` | RN-03 | `addSupplier`, `suppliers` | — | `suppliers` | 🟡 Indirecto |
| **F-02** Ciclo de campañas | Catalogs | `catalogs_screen.dart` | RN-11…RN-15 | `addCampaign`, `activateCampaign`, `closeCampaign`, `activeCampaign` | `CampaignConflictException` | `campaigns` | 🟢 `v4_repository_test`, `v5_domain_test` |
| **F-02** Resumen de cierre | Catalogs (diálogo) | `catalogs_screen.dart` | — | `campaignCloseSummary` | — | (agregado) | 🔴 **Sin test** |
| **F-03** Planificación | Planning, PlanForm | `plan_form_screen.dart`, `planning_screen.dart` | RN-13, RN-17…RN-20 | `addPlanMulti`, `plans`, `planForApplication` | `PlanItemDraft` | `application_plans`, `application_plan_items` | 🟢 `repository_test`, `e2e_scenario_test`, `v5_domain_test`, `regression_widget_test` |
| **F-03** Cobertura de stock del plan | PlanForm | `plan_form_screen.dart` | RN-21 | `personStockSummary` | — | (agregado) | 🟡 El método sí; el cálculo de la UI no |
| **F-04** Compra multiproducto | Purchases, PurchaseForm | `purchase_form_screen.dart` | RN-04…RN-10, RN-13, RN-51, RN-52 | `confirmPurchase`, `purchases` | `PurchaseDraft`, `PurchaseItemDraft`, `AllocationDraft`, `CurrencyCode`, `ExchangeRateSource` | `purchases`, `purchase_items`, `purchase_allocations`, `inventory_lots`, `inventory_movements`, `account_transactions` | 🟢 **Fuerte**: `repository_test` (4), `e2e_v5_test` (12 líneas) |
| **F-05** Foto de factura | PurchaseForm, Purchases | `purchase_form_screen.dart`, `purchases_screen.dart` | — | `storeInvoiceImage` | — | Sistema de archivos + `purchases.invoice_image_path` | 🟡 Solo se verifica que la ruta se persiste; el copiado real **sin test** |
| **F-06** Pago a proveedor | Purchases, PurchaseForm | `purchases_screen.dart` | RN-16 | `addProviderPayment` | — | `provider_payments` | 🟡 Se prueba el registro; **el tope de RN-16 no** |
| **F-07** Inventario global | Inventory | `inventory_screen.dart` | RN-21 | `inventorySummary` | — | (agregado sobre `inventory_movements`) | 🟡 Se prueba la separación L/KG; `committed`/`projected`/`value` **sin test** |
| **F-07** Detalle de producto | InventoryDetail | `inventory_detail_screen.dart` | RN-21 | `inventoryProductHeader`, `inventoryProductDistribution`, `inventoryProductLots` | — | (agregado) | 🟡 `productStockInsight` sí; los tres métodos de la pantalla **no** |
| **F-08** Aplicación con FIFO | Applications, ApplicationForm | `application_form_screen.dart` | RN-13, RN-22…RN-28, RN-50 | `confirmApplication`, `applications`, `estimateFifoCost`, `availableProductsForOwner` | `ApplicationDraft`, `ApplicationLineDraft` | `applications`, `application_items`, `application_consumptions`, `inventory_movements`, `account_transactions` | 🟢 **Muy fuerte**: `repository_test` (3), `v5_domain_test` (3), `e2e_*` |
| **F-08** Aplicación desde plan | ApplicationForm | `application_form_screen.dart` | RN-28, RN-29 | `planForApplication`, `confirmApplication` | — | `application_plans.status` | 🟢 `v5_domain_test` (completa y reabre el plan) |
| **F-09** Transferencia | Transfers, TransferForm | `transfer_form_screen.dart` | RN-30…RN-35 | `transferProductsFifo`, `transfers`, `reverseTransfer` | `TransferItemDraft` | `transfers`, `transfer_items`, `transfer_lot_items`, `inventory_lots`, `inventory_movements` | 🟢 **Fuerte**: `v4_repository_test` (2), `v5_domain_test` (2), `repository_test` |
| **F-10** Pagos y adelantos | Settlements | `settlements_screen.dart` | RN-36…RN-40 | `addAccountPayment`, `settlements`, `topSettlements` | — | `account_transactions`, `payment_allocations` | 🟢 `repository_test` (2), `v4_repository_test` |
| **F-10** Saldo por campaña | Settlements | `settlements_screen.dart` | RN-42 | `personCampaignBalance` | — | (agregado) | 🟢 `v4_repository_test` |
| **F-11** Estado de cuenta | Settlements, PersonDetail | `settlements_screen.dart` | RN-37 | `detailedStatement`, `statement` | — | `account_transactions` | 🟡 `regression_widget_test` prueba abrir/cerrar 20 veces; **el contenido no** |
| **F-12** Reversión de aplicación | Applications | `applications_screen.dart` | RN-46, RN-48, RN-49, RN-28 | `reverseApplication` | — | `inventory_movements`, `account_transactions`, `applications` | 🟢 `repository_test`, `v5_domain_test` |
| **F-12** Reversión de compra | Purchases | `purchases_screen.dart` | RN-43…RN-46, RN-48 | `reversePurchase` | — | `inventory_lots`, `inventory_movements`, `account_transactions`, `provider_payments` | 🟡 Se prueba el **bloqueo** (RN-43); la reversión con éxito **sin test** |
| **F-12** Reversión de transferencia | Transfers | `transfers_screen.dart` | RN-47, RN-48 | `reverseTransfer` | — | `inventory_movements`, `inventory_lots`, `transfers` | 🟢 `v4_repository_test` |
| **F-13** Costo por chaco | Settlements | `settlements_screen.dart` | — | `farmCostReport` | — | (agregado) | 🔴 **Sin test** |
| **F-13** Costo por producto | Settlements | `settlements_screen.dart` | — | `productCostReport` | — | (agregado) | 🔴 **Sin test** — y tiene el defecto [KI-04](27_KNOWN_ISSUES.md) |
| **F-14** Bitácora de chaco | FarmLogbook | `farm_logbook_screen.dart` | — | `farmProfile`, `farmLogbook` | — | (agregado) | 🔴 **Sin test** |
| **F-15** Dashboard | Dashboard | `dashboard_screen.dart` | — | `dashboard`, `topSettlements` | `DashboardSummary` | (agregado) | 🟡 `dashboard().stockBase` se comprueba en `repository_test`; el resto **no** |
| **F-15** Perfiles de persona | Persons, PersonDetail | `persons_screen.dart` | RN-37 | `personProfiles`, `personProfile` | — | (agregado) | 🔴 **Sin test** |
| **F-16** Exportar backup | Settlements | `settlements_screen.dart` | — | `exportBackup` | — | Sistema de archivos | 🔴 **Sin test** |
| **F-17** Selector adaptativo | Todas | `adaptive_entity_picker.dart` | — | — | Genérico `<T>` | — | 🟢 `adaptive_picker_test` (2) |
| **Aritmética monetaria** | Todas | `domain/money.dart` | RN-50, RN-51 | — | — | — | 🟢 `money_test` (3) |
| **Migraciones** | — | `data/app_database.dart` | — | — | — | Esquema | 🟡 v1→v2 y v3→v4 parcial; **v2→v3 y propiedades de índice sin test** |
| **Navegación** | AppShell | `app_shell.dart` | — | — | — | — | 🔴 **Insuficiente** — ver [KI-01](27_KNOWN_ISSUES.md) |

Leyenda: 🟢 bien cubierto · 🟡 parcial · 🔴 sin cobertura

---

## Funcionalidades sin cobertura de test

**Esta es la lista de mayor valor de todo el documento.**

| Funcionalidad | Método | Riesgo si falla | Prioridad |
|---|---|---|---|
| **Navegación de la app** | — | **La app se rompe** — ya ocurre ([KI-01](27_KNOWN_ISSUES.md)) | **P0** |
| Costo por producto | `productCostReport` | Cifra incorrecta y silenciosa — **ya ocurre** ([KI-04](27_KNOWN_ISSUES.md)) | **P1** |
| Costo por chaco | `farmCostReport` | Cifra incorrecta y silenciosa | **P1** |
| Dashboard | `dashboard` | 5 cifras incorrectas en la pantalla principal | **P1** |
| Perfiles de persona | `personProfiles`, `personProfile` | Saldo o superficie incorrectos en la lista | **P1** |
| Resumen de cierre de campaña | `campaignCloseSummary` | Decisión de cierre basada en datos falsos | **P1** |
| Métricas de inventario | `inventorySummary` (`committed`, `projected`, `value`) | Proyección incorrecta — y el valor ya tiene el defecto [KI-09](27_KNOWN_ISSUES.md) | **P1** |
| Detalle de inventario | `inventoryProductHeader`, `...Distribution`, `...Lots` | Trazabilidad incorrecta | P2 |
| Bitácora de chaco | `farmLogbook` | Historial incorrecto | P2 |
| Reversión exitosa de compra | `reversePurchase` (camino feliz) | Inventario o saldos incorrectos tras revertir | **P1** |
| Tope de pago a proveedor | `addProviderPayment` (RN-16) | Sobrepago no detectado | P2 |
| Exportar backup | `exportBackup` | Backup corrupto o inexistente | P2 |
| Guardar imagen de factura | `storeInvoiceImage` | Imagen perdida | P3 |
| Contenido del estado de cuenta | `detailedStatement` | Concepto o saldo acumulado incorrectos | P2 |

**Patrón evidente**: la cobertura es **excelente en las escrituras** (compra, aplicación,
transferencia, reversiones, contabilidad) y **casi nula en las lecturas** (reportes,
dashboard, perfiles, bitácora).

Es exactamente el reparto opuesto al deseable en términos de detección: un error de escritura
suele fallar de forma ruidosa; **un error de lectura muestra un número equivocado sin fallar
nunca**. Los defectos [KI-04](27_KNOWN_ISSUES.md) y [KI-09](27_KNOWN_ISSUES.md) son la
prueba: ambos están en consultas de lectura y ambos son silenciosos.

Esto justifica **M-19** ([29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md)) como una de las
mejoras de mayor retorno del plan.

---

## Partes desconectadas

Elementos que existen en una capa pero no llegan a la siguiente:

| Elemento | Existe en | No llega a | Detalle |
|---|---|---|---|
| Filtros de bitácora | `farmLogbook(campaignId, productId)` | La UI | La pantalla nunca los pasa |
| Fecha de operación | Los 3 métodos de escritura | La UI | Las pantallas envían siempre `DateTime.now()` ([KI-14](27_KNOWN_ISSUES.md)) |
| `SettlementPolicy` manual | `addPerson(policy:)` | La UI | Nunca se pasa; la política siempre se deriva del rol |
| `ExchangeRateSource` | Enum de 4 valores | La UI | Siempre `agreedWithSupplier` |
| `method` de pago | Columna `NOT NULL` | La UI | Siempre `'TRANSFER'` |
| `purchases.notes`, `exchange_rate_note` | `PurchaseDraft` | La UI | Nunca se rellenan |
| `application_plans.planned_date` | Esquema | La UI | Nunca se rellena |
| `persons.phone`, `farms.location` | Esquema y `addPerson`/`addFarm` | La UI | Nunca se rellenan |
| `archiveCatalog` para campañas | Repositorio | La UI | Inalcanzable ([KI-18](27_KNOWN_ISSUES.md)) |
| Tabla `app_settings` | Esquema | Todo | Nunca leída ni escrita |
| `price_major_unit` | Esquema | Todo | Nunca leída ni escrita |
| `application_items.notes` | Esquema (v4) | Todo | Nunca usada |
| Estado `ARCHIVED` | RN-12 lo comprueba | Ninguna escritura | Estado inalcanzable |
| Estado `DRAFT` de plan | `DEFAULT` y consultas | Ninguna escritura | `addPlanMulti` siempre pone `PLANNED` |
| `_PurchaseDialog` | `purchases_screen.dart` | Ninguna referencia | ~350 líneas muertas |
| `transferProductFifoV3Legacy`, `transferStockLegacy` | Repositorio | Ninguna llamada | `@Deprecated`, ~183 líneas |

---

## Matriz regla de negocio → test

Las 52 reglas de [15_BUSINESS_RULES](15_BUSINESS_RULES.md), con su cobertura:

| Grupo | Reglas | Cobertura |
|---|---|---|
| **A** Personas y catálogos | RN-01…RN-03 | 🟡 Indirecta: RN-01 se ejercita en cada `setUp` pero ningún test la afirma explícitamente |
| **B** Campañas | RN-11…RN-15 | 🟢 RN-11, RN-13, RN-15 con test propio. RN-12 **sin test** (estado inalcanzable). RN-14 indirecta |
| **C** Compras | RN-04…RN-10, RN-16 | 🟢 RN-04…RN-10 bien cubiertas. **RN-16 (tope de pago) sin test** |
| **D** Planificación | RN-17…RN-21 | 🟢 RN-17…RN-20 cubiertas. **RN-21 (comprometido) sin test** |
| **E** Aplicaciones | RN-22…RN-29 | 🟢 **La mejor cubierta.** RN-29 solo en la UI, sin test |
| **F** Transferencias | RN-30…RN-35 | 🟢 **Muy bien cubierta**, incluida la atomicidad multiproducto |
| **G** Cuentas | RN-36…RN-42 | 🟢 RN-37…RN-39, RN-42 cubiertas. **RN-40 (sobrante) y RN-41 (exclusión de ADMIN) sin test** |
| **H** Reversiones | RN-43…RN-49 | 🟡 RN-43, RN-46, RN-48 cubiertas. **RN-44, RN-45, RN-47 sin test propio** |
| **Aritmética** | RN-50…RN-52 | 🟢 RN-50 y RN-51 con test exacto. RN-52 verificada en el test de transferencia |

**Reglas sin ningún test**: RN-12, RN-16, RN-21, RN-29, RN-40, RN-41, RN-44, RN-45.

De ellas, las de mayor riesgo son **RN-16** (un sobrepago a proveedor no se detectaría) y
**RN-44/RN-45** (guardias de reversión de compra: si fallaran, se podría revertir una compra
cuyos lotes ya se movieron, descuadrando el inventario).

---

## Cómo usar esta matriz

- **Para localizar código**: busca la funcionalidad en la primera columna y sigue la fila.
- **Para valorar un cambio**: mira las columnas *Reglas* y *Test*. Una fila con 🔴 en Test
  significa que **no hay red de seguridad**: hay que escribir el test antes de tocarla.
- **Para planificar testing**: la sección "Funcionalidades sin cobertura" ya está priorizada.
- **Para limpiar**: la sección "Partes desconectadas" lista todo lo que existe pero no se usa.

---

# Actualización 2026-09-06 — Reglas nuevas y sus pruebas

| Regla / funcionalidad | Código | Tests | Pixel 8 |
|---|---|---|---|
| Un plan se aplica una sola vez | `agro_repository.dart` `_ensurePlanNotApplied`, `app_database.dart` v6 | `plan_lifecycle_test.dart` (14) | ✅ segundo intento rechazado, sin duplicar |
| Revertir no reabre el plan | `agro_repository.dart` `reverseApplication` | `plan_lifecycle_test.dart`, `v5_domain_test.dart`, `e2e_v5_test.dart` | ✅ el plan sigue `APPLIED` |
| La lista de planificación muestra pendientes | `agro_repository.dart` `plans(includeApplied:)`, `planning_screen.dart` | `plan_lifecycle_test.dart`, `plan_lifecycle_ui_test.dart` (4) | ✅ lista operativa e histórico |
| Recarga al volver de aplicar | `planning_screen.dart` `applyPlan` | `plan_lifecycle_ui_test.dart` | ✅ el plan sale de la lista al instante |
| Una campaña cerrada es terminal | `agro_repository.dart` `activateCampaign` | `campaign_lifecycle_test.dart` (10) | ✅ dominio y menú |
| Confirmación de cierre irreversible | `catalogs_screen.dart` | `campaign_lifecycle_ui_test.dart` (5) | ✅ texto y botón de acción irreversible |
| Respaldo con fotografías | `backup_service.dart`, `invoice_storage.dart` | `backup_container_test.dart` (27) | ✅ ciclo completo, la factura se abre tras restaurar |
| Compatibilidad con respaldos `.db` | `backup_service.dart` `validate` | `backup_container_test.dart` | ✅ restaurado un `.db` v5, migrado a v6 |
| Rollback de la restauración | `backup_service.dart` `restore` | `backup_container_test.dart` | cubierto por la suite (fallo forzado a mitad) |
| Migración v5 a v6 | `app_database.dart` `_upgradeToV6` | `plan_lifecycle_test.dart`, `schema_equivalence_test.dart` | ✅ ejecutada al restaurar en el dispositivo |
| `setState` no devuelve `Future` | 5 pantallas | `set_state_contract_test.dart` (3) | ✅ 0 avisos en `logcat` |
| Validación visible en catálogos | `catalogs_screen.dart` | `ui_polish_test.dart` | ✅ error en línea, nada escrito |
| Identidad del producto sin scroll horizontal | `dashboard_screen.dart` | `ui_polish_test.dart` | ✅ vertical y a 130 % |
| Etiquetas con unidad y estado de la línea | `purchase_form_screen.dart` | `ui_polish_test.dart` | ✅ con y sin producto elegido |
| Una sola acción primaria en Catálogos | `app_shell.dart`, `catalogs_screen.dart` | `ui_polish_test.dart` | ✅ sin FAB, etiqueta por sección |
| Sin origen no hay cero engañoso | `transfer_form_screen.dart` | `ui_polish_test.dart` | ✅ estado vacío explícito |
| El rail no desborda en horizontal a 130 % | `app_shell.dart` | `ui_polish_test.dart` (3) | ✅ sin desbordamiento, "Cuentas" alcanzable |
| Puerta de calidad automática | `.github/workflows/flutter-ci.yml` | los cuatro gates en cada PR | ✅ run `33999797085` verde |
