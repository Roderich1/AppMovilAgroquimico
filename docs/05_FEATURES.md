# 05 — Inventario de funcionalidades

Cada funcionalidad se describe **solo** con lo confirmado en el código. Las reglas de
negocio se detallan en [15_BUSINESS_RULES](15_BUSINESS_RULES.md); aquí se referencian por
identificador `RN-xx`.

---

## F-01 · Gestión de catálogos

| Campo | Contenido |
|---|---|
| **Propósito** | Alta, renombrado y archivado de las cinco entidades maestras |
| **Actor** | Operador de la app (no hay roles de acceso) |
| **Pantalla** | `CatalogsScreen` — `/catalogos` |
| **Archivos** | `catalogs_screen.dart`; `agro_repository.dart`: `addPerson`, `addFarm`, `addProduct`, `addSupplier`, `addCampaign`, `renameCatalog`, `archiveCatalog`, `people`, `farms`, `products`, `suppliers`, `campaigns` |
| **Datos requeridos** | Persona: nombre + rol. Chaco: propietario + nombre + superficie (ha). Producto: nombre + ingrediente activo + unidad (L/KG). Proveedor: nombre. Campaña: nombre |
| **Almacenamiento** | Tablas `persons`, `farms`, `products`, `suppliers`, `campaigns` |
| **Reglas** | RN-01 (política por rol), RN-02 (unidad base derivada), RN-11 (campaña única activa), RN-12 (campaña archivada no se activa) |
| **Validaciones** | UI: nombre no vacío antes de habilitar Guardar. Repositorio: `renameCatalog` rechaza nombre vacío y tabla fuera de la lista blanca |
| **Estados** | loading (`CircularProgressIndicator`), empty (`EmptyState` "No hay registros"), error (`EmptyState` con `snapshot.error.toString()`) |
| **Errores posibles** | `BusinessRuleException` al activar/cerrar campaña; `ArgumentError` si la tabla no está permitida (inalcanzable desde la UI) |
| **Resultado** | Fila creada/actualizada y `_refresh()` recarga las cinco listas |

Detalle relevante: el archivado es **lógico**, no físico. Para `persons`, `farms`,
`products`, `suppliers` pone `active = 0`; para `campaigns` pone `status = 'CLOSED'`.
Nada se borra nunca.

---

## F-02 · Ciclo de vida de campañas

| Campo | Contenido |
|---|---|
| **Propósito** | Delimitar temporalmente compras, aplicaciones, planes y cargos |
| **Pantalla** | `CatalogsScreen`, pestaña "Campañas" |
| **Archivos** | `agro_repository.dart`: `addCampaign`, `activeCampaign`, `activateCampaign`, `closeCampaign`, `campaignCloseSummary`, `_ensureCampaignActive` |
| **Estados de campaña** | `PLANNED`, `ACTIVE`, `CLOSED`, `ARCHIVED` (este último solo se lee, nunca se escribe desde el código) |
| **Reglas** | RN-11, RN-12, RN-13 |
| **Errores** | `CampaignConflictException` (lleva `activeCampaignId`/`activeCampaignName` para que la UI ofrezca "Cerrar y activar"); `BusinessRuleException` si no existe, si está archivada, o si se intenta cerrar una no activa |

La invariante "una sola campaña activa" está reforzada **en dos niveles**: por índice único
parcial en SQLite (`idx_campaign_single_active ON campaigns((1)) WHERE status='ACTIVE'`) y
por lógica transaccional en `activateCampaign`. Es el control de integridad mejor
implementado del proyecto.

Antes de cerrar, `campaignCloseSummary` muestra al usuario: nº de compras, importe comprado,
nº de aplicaciones, importe aplicado, planes pendientes y saldo por cobrar.

---

## F-03 · Planificación de aplicaciones

| Campo | Contenido |
|---|---|
| **Propósito** | Calcular cuánto producto se necesita para tratar un chaco, y cuánto falta comprar |
| **Pantallas** | `PlanningScreen` (`/planificacion`), `PlanFormScreen` (`/planificacion/nueva`) |
| **Archivos** | `plan_form_screen.dart`, `planning_screen.dart`; `agro_repository.dart`: `addPlanMulti`, `addPlan`, `plans`, `planForApplication`, `personStockSummary` |
| **Datos recibidos** | Chaco (precarga superficie del chaco en ha) y, por producto, la dosis en unidad/ha |
| **Cálculo** | `required_quantity_base = redondeoMitadArriba(area_m2 × dose_base_per_ha / 10000)` — `agro_repository.dart:251` |
| **Reglas** | RN-14 (área > 0 y al menos un producto), RN-15 (sin productos repetidos), RN-16 (dosis > 0), RN-13 (campaña activa) |
| **Almacenamiento** | `application_plans` + `application_plan_items` |
| **Estados del plan** | `PLANNED` al crear; `COMPLETED` cuando se confirma una aplicación con ese `planId`; vuelve a `PLANNED` si esa aplicación se revierte |
| **Funcionalidad poco visible** | Al elegir chaco, la pantalla consulta `personStockSummary(propietario)` y muestra por producto: *necesita X · stock Y · cubierto / comprar Z*. Es el puente entre planificación y compra |

---

## F-04 · Registro de compras multiproducto y multi-moneda

| Campo | Contenido |
|---|---|
| **Propósito** | Registrar una factura con varios productos, en BOB o USD, y repartir cada producto entre personas |
| **Pantallas** | `PurchasesScreen` (`/compras`), `PurchaseFormScreen` (`/compras/nueva`) |
| **Archivos** | `purchase_form_screen.dart`, `purchases_screen.dart`; `agro_repository.dart`: `confirmPurchase`, `purchases`, `storeInvoiceImage` |
| **Datos requeridos** | Proveedor, campaña activa, nº de factura (opcional), y por línea: producto, cantidad, moneda, precio unitario, tipo de cambio si es USD, y una o varias asignaciones persona+cantidad |
| **Reglas** | RN-03…RN-08 (ver [15](15_BUSINESS_RULES.md)) |
| **Efectos en cadena (una sola transacción)** | `purchases` → `purchase_items` → por asignación: `purchase_allocations` + `inventory_lots` + `inventory_movements(PURCHASE_IN)` + `account_transactions(PURCHASE_ALLOCATION_CHARGE)` **solo si** la política es `BY_PURCHASE_ALLOCATION` |
| **Errores** | Cantidad/precio ≤ 0; USD sin TC; BOB con TC; suma asignada ≠ cantidad comprada; productos repetidos; campaña no activa; persona inexistente (rompe la transacción entera) |
| **Resultado** | Compra confirmada, lotes creados, deuda generada solo para terceros |
| **Cobertura de test** | `repository_test.dart` (3 tests), `e2e_v5_test.dart` (12 líneas en una factura) |

Un test confirma el rollback completo: *"fallo interno revierte toda la transacción de
compra"* — con un `personId` inexistente, no queda ni compra, ni ítems, ni lotes.

---

## F-05 · Foto de factura (cámara y galería)

| Campo | Contenido |
|---|---|
| **Propósito** | Adjuntar evidencia fotográfica de la factura |
| **Pantallas** | `PurchaseFormScreen` (captura), `PurchasesScreen` (visualización) |
| **Archivos** | `purchase_form_screen.dart` `_pickImage`; `agro_repository.dart` `storeInvoiceImage`; `purchases_screen.dart` `_viewInvoice` |
| **Comportamiento** | `ImagePicker().pickImage(source:, imageQuality: 82, maxWidth: 1800)`; la imagen se **copia** a `<documentos app>/invoices/invoice_<microsegundos>.<ext>` y se guarda la ruta absoluta en `purchases.invoice_image_path` |
| **Permisos** | iOS: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`. Android: ninguno declarado por la app (ver [18](18_PERMISSIONS.md)) |
| **Visualización** | `_viewInvoice` comprueba `file.exists()`; si falta muestra "La imagen de factura ya no está disponible en este dispositivo"; si existe abre un `AlertDialog` con `InteractiveViewer` (zoom) |
| **Errores** | Cualquier excepción del picker → snackbar "No se pudo adjuntar la factura. Revise los permisos." |
| **Limitación confirmada** | Se guarda **ruta absoluta**. En iOS el contenedor de la app cambia de UUID entre reinstalaciones/actualizaciones, y una restauración de backup en otro dispositivo no traerá los archivos. Ver [13](13_LOCAL_STORAGE.md) y [27](27_KNOWN_ISSUES.md) |

---

## F-06 · Pagos a proveedores

| Campo | Contenido |
|---|---|
| **Propósito** | Registrar cuánto se le pagó al proveedor por una compra, separado de las cuentas internas |
| **Pantallas** | `PurchaseFormScreen` (switch "Registrar pago total ahora"), `PurchasesScreen` (menú "Registrar pago" con `_PaymentDialog`) |
| **Archivos** | `agro_repository.dart` `addProviderPayment`; `purchases_screen.dart` `_pay` |
| **Actor pagador** | **Solo personas con rol `ADMIN`**: ambas pantallas filtran `role == 'ADMIN'` antes de ofrecer el selector |
| **Reglas** | RN-09 (importe > 0), RN-10 (pagado acumulado + nuevo ≤ total de la compra), compra no revertida |
| **Almacenamiento** | `provider_payments` |
| **Estados** | El diálogo precarga el saldo pendiente `total − pagado` como importe por defecto y lo muestra como "Máximo" |
| **Errores** | "El pago debe ser mayor a cero", "El pago supera el saldo de la compra", "La compra no está activa" |
| **Nota** | Estos pagos **no** tocan `account_transactions`: son la deuda con el proveedor, no con las personas. Esa separación es intencional y correcta |

---

## F-07 · Inventario por lotes y movimientos

| Campo | Contenido |
|---|---|
| **Propósito** | Saber cuánto producto físico existe, de quién es, cuánto costó y de qué compra vino |
| **Pantallas** | `InventoryScreen` (`/inventario`), `InventoryDetailScreen` (`/inventario/:id`), pestaña Inventario de `PersonDetailScreen` |
| **Archivos** | `agro_repository.dart`: `inventorySummary`, `inventoryProductHeader`, `inventoryProductDistribution`, `inventoryProductLots`, `personStockSummary`, `availableProductsForOwner`, `stock`, `productStockInsight` |
| **Modelo** | El stock **nunca se almacena como saldo**: siempre es `SUM(inventory_movements.quantity_signed)` agrupado por lote/producto/persona |
| **Tipos de movimiento observados** | `PURCHASE_IN`, `APPLICATION_OUT`, `APPLICATION_REVERSAL`, `PURCHASE_REVERSAL`, `TRANSFER_OUT`, `TRANSFER_IN`, `TRANSFER_REVERSAL_IN`, `TRANSFER_REVERSAL_OUT` |
| **Métricas del detalle** | Comprado, Consumido, Físico, Comprometido, Libre proyectado, Valor físico; más distribución por persona y lista de lotes con su origen (compra o transferencia del lote #N) |
| **"Comprometido"** | Suma de `required_quantity_base` de planes en estado `DRAFT`/`PLANNED` de la **campaña activa**. "Proyectado" = físico − comprometido |
| **Separación por unidad** | El inventario nunca mezcla L y KG: la unidad viene de `products.unit` y se muestra siempre. Confirmado por test |

---

## F-08 · Registro de aplicaciones (fumigaciones) con costeo FIFO

| Campo | Contenido |
|---|---|
| **Propósito** | Registrar el consumo real de producto en un chaco y costearlo contra los lotes más antiguos |
| **Pantallas** | `ApplicationsScreen` (`/aplicaciones`), `ApplicationFormScreen` (`/aplicaciones/nueva`, acepta `?planId=`) |
| **Archivos** | `application_form_screen.dart`, `applications_screen.dart`; `agro_repository.dart`: `confirmApplication`, `applications`, `estimateFifoCost`, `availableProductsForOwner`, `planForApplication` |
| **Datos requeridos** | Persona, chaco (del propietario), área tratada en ha, y por producto: dosis y cantidad real |
| **Algoritmo FIFO** | Se consultan los lotes de esa persona y producto con saldo > 0, ordenados por `acquired_date, id`; se consume secuencialmente creando una fila en `application_consumptions` y un `inventory_movements(APPLICATION_OUT)` por lote tocado |
| **Reglas** | RN-17 (líneas ≥ 1), RN-18 (sin productos repetidos), RN-19 (cantidad > 0), RN-20 (stock suficiente), RN-21 (cargo solo si `BY_ACTUAL_USAGE`), RN-22 (marca el plan como `COMPLETED`) |
| **Cálculo teórico vs real** | `theoretical = area_ha × dosis × 1000`; la variación se persiste en `application_items.variance_quantity_base` |
| **Estimación en vivo** | Al teclear la cantidad real, `estimateFifoCost` calcula el costo sin escribir nada, y se muestra en el subtítulo de la línea |
| **Errores** | "Stock insuficiente para confirmar la aplicación", "No repita productos dentro de la aplicación", "La cantidad aplicada debe ser mayor a cero", "Active una campaña antes de registrar aplicaciones" |
| **Guardia previa** | `ApplicationsScreen.add()` comprueba `activeCampaign()`; si no hay, ofrece un diálogo con acceso directo a `/catalogos` |

---

## F-09 · Transferencias de stock entre personas

| Campo | Contenido |
|---|---|
| **Propósito** | Mover producto físico de una persona a otra conservando el costo histórico |
| **Pantallas** | `TransfersScreen` (`/transferencias`), `TransferFormScreen` (`/transferencias/nueva`) |
| **Archivos** | `transfer_form_screen.dart`, `transfers_screen.dart`; `agro_repository.dart`: `transferProductsFifo`, `transferProductFifo`, `transferStock`, `reverseTransfer`, `transfers` |
| **Flujo de UI** | 3 pasos numerados: 1. Origen → 2. Productos disponibles con cantidad por fila → 3. Destino; luego diálogo de confirmación con el resumen |
| **Mecánica** | Por cada producto se recorren los lotes origen en FIFO; por cada lote tocado se crea un **lote destino nuevo** con `parent_lot_id` apuntando al origen y **el mismo `unit_cost_bob_minor_per_major_unit`**, más dos movimientos (`TRANSFER_OUT` / `TRANSFER_IN`) y una fila en `transfer_lot_items` |
| **Reglas** | RN-23 (origen ≠ destino), RN-24 (al menos un ítem con cantidad > 0), RN-25 (sin productos repetidos), RN-26 (stock suficiente por ítem, atómico) |
| **Atomicidad confirmada por test** | *"un item insuficiente revierte toda transferencia multiproducto"* — si el segundo producto no alcanza, el primero tampoco se mueve |
| **Efecto contable** | **Ninguno.** Transferir no genera ni cancela deuda; solo mueve inventario |
| **Filtro de personas** | El formulario excluye `ADMIN` de origen y destino |

---

## F-10 · Cuentas corrientes, pagos y adelantos

| Campo | Contenido |
|---|---|
| **Propósito** | Llevar el saldo de cada familiar y tercero, y aplicar sus pagos contra las deudas más antiguas |
| **Pantalla** | `SettlementsScreen` (`/liquidacion`); estado de cuenta también en `PersonDetailScreen` pestaña "Cuenta" |
| **Archivos** | `agro_repository.dart`: `addAccountPayment`, `settlements`, `topSettlements`, `statement`, `detailedStatement`, `personCampaignBalance` |
| **Modelo contable** | Libro de asientos inmutables en `account_transactions` con `amount_bob_minor_signed`: **positivo = cargo** (deuda), **negativo = pago/crédito** |
| **Tipos de asiento** | `PURCHASE_ALLOCATION_CHARGE`, `USAGE_CHARGE`, `PAYMENT`, `ADVANCE`, `CREDIT_ADJUSTMENT` |
| **Imputación de pagos** | `addAccountPayment` recorre los cargos pendientes de esa persona **ordenados por fecha e id**, y crea filas en `payment_allocations` hasta agotar el importe. El sobrante queda sin imputar (efectivamente, saldo a favor) |
| **Adelanto vs pago** | Idéntico mecanismo; solo cambia el `type` (`ADVANCE` vs `PAYMENT`). Un adelanto **también** se imputa a cargos existentes |
| **Continuidad entre campañas** | `personCampaignBalance` calcula `opening_balance` sumando asientos de campañas cuya `start_date` es anterior. La imputación de pagos **no filtra por campaña**: un pago de la campaña 2 puede cancelar deuda de la campaña 1 (confirmado por test) |
| **Reportes en la misma pantalla** | Costo por chaco y por hectárea; costo consumido por producto |

---

## F-11 · Estado de cuenta cronológico

| Campo | Contenido |
|---|---|
| **Propósito** | Ver el detalle movimiento a movimiento con saldo acumulado |
| **Ubicación** | `SettlementsScreen._statement` (diálogo) y `PersonDetailScreen` pestaña "Cuenta" |
| **Archivos** | `agro_repository.dart` `detailedStatement`, `personCampaignBalance` |
| **Enriquecimiento** | `detailedStatement` resuelve un `concept` legible por `COALESCE`: nombres de productos de la aplicación → nombre del producto de la asignación de compra → `notes` → `type`; y añade `farm_name` cuando el asiento viene de una aplicación |
| **Saldo acumulado** | Se calcula **en la UI**, partiendo de `opening_balance` y sumando cada movimiento |
| **Etiquetas** | `_transactionLabel` traduce los códigos a español ("Cargo por consumo", "Cargo por compra", "Pago", "Adelanto", "Crédito por reversión") |
| **Cobertura de test** | *"estado de cuenta abre y cierra 20 veces sin perder la pantalla"* — regresión de fuga de diálogos |

---

## F-12 · Reversiones (compra, aplicación, transferencia)

| Campo | Contenido |
|---|---|
| **Propósito** | Deshacer una operación sin borrar historia |
| **Archivos** | `agro_repository.dart`: `reversePurchase`, `reverseApplication`, `reverseTransfer` |
| **Patrón común** | Marcar `reversed_at` + `status = 'REVERSED'`, insertar **movimientos compensatorios** de inventario e insertar `CREDIT_ADJUSTMENT` con `reversal_of_id` apuntando al cargo original |
| **Guardias** | `reversePurchase`: falla si algún lote fue consumido (RN-27) o si el saldo del lote ≠ cantidad inicial (RN-28). `reverseTransfer`: falla si el lote destino ya tuvo movimientos (RN-29). `reverseApplication`: sin guardias — siempre se puede revertir |
| **Efecto adicional** | `reversePurchase` marca también `provider_payments.reversed_at`. `reverseApplication` devuelve el plan asociado a `PLANNED` |
| **Acceso desde UI** | Icono ↩ en `PurchasesScreen` (menú), `ApplicationsScreen` (botón por fila), `TransfersScreen` (botón por fila) |
| **Funcionalidad ausente** | **No hay diálogo de confirmación** en aplicaciones ni transferencias: un toque revierte inmediatamente. Ver [27](27_KNOWN_ISSUES.md) |

---

## F-13 · Reportes de costos

| Campo | Contenido |
|---|---|
| **Propósito** | Responder "cuánto costó tratar este chaco" y "cuánto se consumió de este producto" |
| **Pantalla** | `SettlementsScreen` (secciones inferiores) |
| **Archivos** | `agro_repository.dart` `farmCostReport`, `productCostReport` |
| **Costo por hectárea** | Calculado en la UI: `divideRoundedHalfUp(total_cost × 10000, area_m2)` |
| **Filtro** | Ambos aceptan `campaignId` opcional, alimentado por el desplegable de la pantalla |
| **Limitación confirmada** | `productCostReport` con campaña usa `WHERE a.campaign_id=?` sobre una tabla `LEFT JOIN`, lo que la convierte en `INNER JOIN`: los productos sin aplicaciones en esa campaña **desaparecen** del reporte, en lugar de aparecer en cero. Con "Todas las campañas" sí aparecen. Ver [27](27_KNOWN_ISSUES.md) |

---

## F-14 · Bitácora de chaco

| Campo | Contenido |
|---|---|
| **Propósito** | Historial de todo lo aplicado en un chaco concreto |
| **Pantalla** | `FarmLogbookScreen` — `/chacos/:id` |
| **Acceso** | Solo desde `PersonDetailScreen` → pestaña "Chacos" → tocar un chaco |
| **Archivos** | `agro_repository.dart` `farmProfile`, `farmLogbook` |
| **Datos por entrada** | Producto, fecha, campaña, persona, área tratada, dosis, teórico vs real, costo y **el detalle de lotes FIFO consumidos** (`#lote: cantidad`) |
| **Parámetros no usados** | `farmLogbook` acepta `campaignId` y `productId`, pero la pantalla **nunca los pasa**: no hay filtros en la UI |

---

## F-15 · Dashboard

| Campo | Contenido |
|---|---|
| **Propósito** | Resumen ejecutivo de un vistazo |
| **Pantalla** | `DashboardScreen` — `/` |
| **Archivos** | `agro_repository.dart` `dashboard`, `inventorySummary(limit:5)`, `applications(limit:5)`, `topSettlements(limit:5)`, `campaigns` |
| **Tarjetas** | Compras, Pagado proveedores, Familias por cobrar, Terceros por cobrar, Pagos recibidos |
| **Secciones** | Banner de campaña activa; tabla de inventario proyectado (con buscador en cliente); aplicaciones recientes; principales saldos |
| **Interacción** | Cada fila de inventario navega a `/inventario/:id`; los enlaces "Ver todos" van a las pantallas completas |
| **Refresco** | Botón manual de recarga; no hay refresco automático |

---

## F-16 · Exportación de backup

| Campo | Contenido |
|---|---|
| **Propósito** | Sacar una copia del archivo de base de datos |
| **Pantalla** | `SettlementsScreen`, botón "Exportar backup" |
| **Archivo** | `agro_repository.dart` `exportBackup` |
| **Mecánica** | `PRAGMA wal_checkpoint(FULL)` → copia el `.db` a `getDownloadsDirectory()` (o Documentos como respaldo) con nombre `agroquimicos_backup_<ISO8601>.db` |
| **Resultado** | Snackbar con la ruta completa del archivo |
| **Errores** | "Esta base de datos no admite exportación a archivo" si la BD es `:memory:` |
| **Ausente** | **No existe importación/restauración.** Solo se puede exportar. Ver [27](27_KNOWN_ISSUES.md) |
| **Ausente** | Las fotos de factura **no** se incluyen en el backup |

---

## F-17 · Selector adaptativo de entidades

| Campo | Contenido |
|---|---|
| **Propósito** | Componente transversal para elegir persona/producto/chaco/proveedor/campaña sin desbordar la pantalla |
| **Archivo** | `widgets/adaptive_entity_picker.dart` |
| **Comportamiento** | Abre un bottom sheet al 65% de la altura; muestra un buscador **solo si hay 8 o más ítems**; muestra contador `filtrados/total`; **autoselecciona** si hay exactamente una opción y ninguna seleccionada |
| **Accesibilidad** | Envuelto en `Semantics(button: true, label:, value:)` — es el único widget del proyecto con semántica explícita |
| **Estados** | `enabled`, `loading` (spinner en el prefijo), `error` (`errorText`), lista vacía (snackbar con `emptyMessage`) |
| **Cobertura de test** | 2 tests dedicados |

---

## Funcionalidades buscadas y NO encontradas

Se buscaron explícitamente y **no existen** en el código:

| Funcionalidad | Estado |
|---|---|
| Registro / login / recuperación de contraseña / logout | **No existe.** No hay concepto de sesión |
| Edición de perfil de usuario | **No existe** (sí se puede renombrar una persona del catálogo) |
| Onboarding / tutorial / primera ejecución | **No existe** |
| Sincronización con servidor | **No existe** |
| Modo offline conmutable | **No aplica**: la app es offline por diseño, no hay modo online |
| Exportación a CSV / PDF / Excel | **No existe** (solo copia del `.db`) |
| Importación / restauración de backup | **No existe** |
| Compartir (share sheet) | **No existe** |
| Impresión | **No existe** |
| Notificaciones (push o locales) | **No existe** |
| Configuración / preferencias de usuario | **No existe.** La tabla `app_settings` está creada pero **nunca se lee ni se escribe** |
| Tema oscuro | **No existe**: solo `theme:`, sin `darkTheme:` ni `themeMode:` |
| Selección de idioma / i18n | **No existe**: español hardcodeado, locale `es_BO` fijo |
| Edición de compras/aplicaciones/transferencias ya confirmadas | **No existe**: solo reversión |
| Borrado de registros | **No existe**: solo archivado lógico y reversión |
| Selección manual de fecha de operación | **No existe**: compras, aplicaciones y transferencias usan `DateTime.now()` desde la UI, aunque el repositorio **sí** acepta fecha. Ver [27](27_KNOWN_ISSUES.md) |
| Búsqueda global | **No existe**: cada pantalla filtra su propia lista en memoria |
| Paginación / scroll infinito | **No existe**: las consultas usan `LIMIT` fijo (50/200/400/500) |

---

# Actualización 2026-09-06 — Cambios de alcance al congelar la baseline

| Funcionalidad | Antes | **Ahora** |
|---|---|---|
| **Respaldo y restauración** | copia de la base de datos | contenedor `.agrobackup` con **la base y las fotografías de factura**, manifiesto con checksums, reconstrucción de rutas al restaurar en otro dispositivo, y compatibilidad con los `.db` anteriores |
| **Planificación** | los planes se podían aplicar sin límite; la lista mostraba todos | un plan es **una aplicación planificada**: `PLANNED` a `APPLIED`, sin reaplicación ni al revertir. La lista operativa muestra los pendientes; los aplicados se conservan en un histórico secundario |
| **Campañas** | se podía reactivar una cerrada | una campaña `CLOSED` es **terminal**; el cierre pide confirmación explícita advirtiendo de que es irreversible |
| **Catálogos** | dos acciones primarias (botón + FAB global) | una sola acción primaria, que además dice qué crea en la sección abierta |
| **Inventario en Inicio** | tabla con desplazamiento horizontal | por debajo de 560 px, lista con el nombre del producto por encabezado y cada cifra rotulada |

No se añadió ninguna funcionalidad nueva: la fase era de cierre. Lo que se ve arriba son
reglas decididas, limitaciones cerradas y presentación corregida.

Funcionalidades explícitamente **fuera** de esta baseline y diferidas:
[`46` sección 16](46_BASELINE_FINAL_FREEZE.md).
