# 07 — Pantallas

17 pantallas, todas en `lib/presentation/screens/`. Ninguna requiere permisos de acceso
(no hay autenticación); la columna "Permisos" se refiere a permisos de dispositivo.

Convención de estados usada abajo:
- **loading** — qué se muestra mientras el `Future` no resuelve
- **empty** — qué se muestra sin datos
- **error** — qué se muestra si el `Future` falla

---

## P-01 · DashboardScreen — `/`

| | |
|---|---|
| **Archivo** | `dashboard_screen.dart` (354 líneas) |
| **Tipo** | `ConsumerStatefulWidget` |
| **Objetivo** | Resumen ejecutivo de almacén y cuentas |
| **Datos recibidos** | Ninguno |
| **Servicios** | `dashboard()`, `inventorySummary(limit: 5)`, `applications(limit: 5)`, `topSettlements(limit: 5)`, `campaigns()` — agrupados en el record `_DashboardData` |
| **Datos mostrados** | Banner de campaña activa; 5 tarjetas (Compras, Pagado proveedores, Familias por cobrar, Terceros por cobrar, Pagos recibidos); `DataTable` de inventario proyectado (Producto, Unidad, Físico, Comprometido, Proyección, Valor); lista de 5 aplicaciones recientes; lista de 5 saldos principales |
| **Acciones** | Recargar (`IconButton.filledTonal`); buscar producto (filtro en cliente); "Ver todos" hacia `/inventario`, `/aplicaciones`, `/liquidacion`; tocar fila de la tabla → `/inventario/:id` |
| **Componentes** | `PageFrame`, `EmptyState`, `LayoutBuilder` (5/3/2 columnas según ancho), `Wrap`, `Card`, `DataTable` dentro de `SingleChildScrollView` horizontal, `FittedBox` en los importes |
| **Validaciones** | Ninguna (solo lectura) |
| **loading** | `CircularProgressIndicator` centrado |
| **empty** | `EmptyState` "Aún no hay inventario." en la tabla; las otras listas se renderizan vacías sin mensaje |
| **error** | `EmptyState` con `friendlyError(snapshot.error!)` |
| **Navegación entrante** | Ruta inicial; pestaña "Inicio" del shell |
| **Navegación saliente** | `/inventario`, `/inventario/:id`, `/aplicaciones`, `/liquidacion` |
| **Permisos** | Ninguno |

---

## P-02 · OperationsScreen — `/operaciones`

| | |
|---|---|
| **Archivo** | `operations_screen.dart` (79 líneas) |
| **Tipo** | `StatelessWidget` — **la única pantalla sin acceso a datos** |
| **Objetivo** | Menú de acciones del trabajo diario |
| **Datos mostrados** | 5 tarjetas estáticas: Planificar aplicación, Registrar compra, Registrar aplicación, Transferir inventario, Administrar datos |
| **Acciones** | `context.go(path)` a `/planificacion`, `/compras/nueva`, `/aplicaciones`, `/transferencias`, `/catalogos` |
| **Componentes** | `PageFrame`, `LayoutBuilder` (2 columnas ≥ 700px), `Wrap`, `Card`, `ListTile` |
| **Estados** | No aplica: contenido estático |
| **Navegación entrante** | Pestaña "Operaciones" del shell |
| **Nota** | Usa `context.go('/compras/nueva')`, misma vía que produce el defecto de navegación del FAB. Ver [27](27_KNOWN_ISSUES.md) |

---

## P-03 · CatalogsScreen — `/catalogos`

| | |
|---|---|
| **Archivo** | `catalogs_screen.dart` (620 líneas) |
| **Tipo** | `ConsumerStatefulWidget` con `SingleTickerProviderStateMixin` |
| **Objetivo** | CRUD de las 5 entidades maestras |
| **Servicios** | `people()`, `farms()`, `products()`, `suppliers()`, `campaigns()` vía `Future.wait`; `addPerson`, `addFarm`, `addProduct`, `addSupplier`, `addCampaign`, `renameCatalog`, `archiveCatalog`, `activateCampaign`, `closeCampaign`, `campaignCloseSummary` |
| **Estructura** | `TabController(length: 5)` cuya selección se expone como `ChoiceChip`s (no como `TabBar`); la lista vive en un `SizedBox(height: 520)` |
| **Pestañas** | 0 Personas · 1 Chacos · 2 Productos · 3 Proveedores · 4 Campañas — **el índice mapea posicionalmente** a `['persons','farms','products','suppliers','campaigns']` |
| **Acciones comunes** | "Agregar" (diálogo según pestaña); ⋮ → Editar (renombrar) / Archivar |
| **Acciones de campaña** | ⋮ → Editar / Activar (si no está activa) / Cerrar (si está activa) |
| **Diálogos internos** | `_NameDialog`, `_PersonDialog` (nombre + rol), `_FarmDialog` (propietario + nombre + superficie ha), `_ProductDialog` (nombre + ingrediente + `SegmentedButton` L/KG) |
| **Búsqueda** | Un `TextField` filtra en cliente sobre **todos los valores** de la fila (`row.values.any(...)`) |
| **Validaciones** | Nombre no vacío en los diálogos; superficie parseada con `tryParseDecimal` (si es inválida → 0, y el `CHECK(area_m2 > 0)` de SQLite lo rechaza) |
| **loading** | `CircularProgressIndicator` |
| **empty** | `EmptyState` "No hay registros. Usa Agregar para comenzar." |
| **error** | `EmptyState` con `snapshot.error.toString()` **sin pasar por `friendlyError`** — inconsistencia con el resto |
| **Navegación entrante** | Operaciones → "Administrar datos"; diálogo de campaña faltante de `ApplicationsScreen` |
| **Permisos** | Ninguno |

---

## P-04 · PlanningScreen — `/planificacion`

| | |
|---|---|
| **Archivo** | `planning_screen.dart` (141 líneas) |
| **Tipo** | `ConsumerStatefulWidget` |
| **Objetivo** | Listar planes agrupados y lanzar la aplicación |
| **Servicios** | `plans()` (límite 400), `activeCampaign()` |
| **Datos mostrados** | Por plan: chaco · propietario, campaña, nº de productos; al expandir, cada producto con área en ha, dosis y cantidad requerida |
| **Agrupación** | En cliente: `groups.putIfAbsent(row['plan_id'], () => []).add(row)` |
| **Acciones** | Filtro por campaña (`DropdownButtonFormField`); "Nuevo plan" → `push /planificacion/nueva`; "Aplicar" → `push /aplicaciones/nueva?planId=N` |
| **Validaciones** | `add()` exige campaña activa, si no: `showError('Active una campaña antes de planificar.')` |
| **loading / empty / error** | Spinner · `EmptyState` "No hay planes para mostrar." · `EmptyState` con `friendlyError` |
| **Componentes** | `ExpansionTile` dentro de `ListView.separated` con `shrinkWrap: true` y `NeverScrollableScrollPhysics` |

---

## P-05 · PlanFormScreen — `/planificacion/nueva`

| | |
|---|---|
| **Archivo** | `plan_form_screen.dart` (343 líneas) |
| **Tipo** | `ConsumerStatefulWidget`, pantalla completa (fuera del `ShellRoute`) |
| **Objetivo** | Crear un plan multiproducto |
| **Servicios** | `activeCampaign()`, `farms()`, `products()`, `personStockSummary(propietario)`, `addPlanMulti` |
| **Datos recibidos** | Ninguno |
| **Precarga** | Al elegir chaco: superficie en ha con `toStringAsFixed(0 o 2)`, y `ownerStock` del propietario |
| **Cálculo en vivo** | Por línea: *"Necesita X · stock Y · cubierto / comprar Z"* |
| **Acciones** | Elegir chaco, editar área, agregar/quitar productos, teclear dosis, Guardar |
| **Validaciones** | Chaco + ≥1 producto; dosis > 0; producto no repetido |
| **Salida protegida** | `PopScope(canPop: !dirty && !saving)` + diálogo "¿Descartar cambios?" |
| **error** | `EmptyState` con `friendlyError` — incluye "Active una campaña antes de planificar." lanzada desde `_load` |
| **Navegación saliente** | `pop(true)` al guardar; `pop()` al descartar |
| **Cobertura** | `regression_widget_test.dart` (precarga de 80 ha), `responsive_v5_test.dart` (5 tamaños) |

---

## P-06 · PurchasesScreen — `/compras`

| | |
|---|---|
| **Archivo** | `purchases_screen.dart` (658 líneas, de las cuales **~350 son código muerto**) |
| **Tipo** | `ConsumerStatefulWidget` |
| **Objetivo** | Listar compras y operar sobre ellas |
| **Servicios** | `purchases()` (límite 200), `people()`, `addProviderPayment`, `reversePurchase` |
| **Datos mostrados** | Por compra: proveedor · nº de factura, campaña, nº de productos, Total, pagado, estado (Confirmada/Revertida) |
| **Acciones** | "Nueva compra" (`push`); filtro por campaña; buscador de proveedor/factura; ⋮ → Ver factura (solo si hay imagen) / Registrar pago / Revertir compra |
| **Diálogos** | `_PaymentDialog` (pagador ADMIN + importe con máximo precargado); visor de factura con `InteractiveViewer` |
| **Validaciones** | `_pay` avisa si no hay ningún `ADMIN`; `_viewInvoice` comprueba que el archivo exista |
| **loading / empty / error** | Spinner · `EmptyState` "No hay compras confirmadas." · `EmptyState` con `snapshot.error.toString()` |
| **Defecto de orden** | Comprueba `!snapshot.hasData` **antes** que `snapshot.hasError`, por lo que un error muestra el spinner indefinidamente en vez del mensaje. Ver [27](27_KNOWN_ISSUES.md) |
| **Permisos** | Lectura del archivo de factura en el sandbox de la app (no requiere permiso explícito) |

---

## P-07 · PurchaseFormScreen — `/compras/nueva`

| | |
|---|---|
| **Archivo** | `purchase_form_screen.dart` (772 líneas — **la pantalla más grande**) |
| **Tipo** | `ConsumerStatefulWidget`, pantalla completa con `CustomScrollView` + `SliverAppBar` fijo |
| **Objetivo** | Registrar una factura multiproducto, multi-moneda, con reparto entre personas |
| **Servicios** | `suppliers()`, `campaigns()`, `products()`, `people()`, `storeInvoiceImage`, `confirmPurchase`, `addProviderPayment` |
| **Estructura** | Sección Factura → N tarjetas de línea (`_LineCard`) → Sección Pago al proveedor → tarjeta TOTAL |
| **Clases auxiliares** | `_PurchaseLineEditor` (controllers + getters derivados `quantityBase`, `priceMinor`, `exchangeRateScaled`, `unitBob`, `subtotalBob`, `assignedBase`), `_AllocationEditor`, `_LineCard`, `_Section` |
| **Cálculo en vivo** | Por línea: `Costo Bs X/unidad · Subtotal Bs Y` y en el subtítulo `cantidad · subtotal · pendiente de asignar`; total general en la tarjeta inferior |
| **Precarga** | La campaña `ACTIVE` se preselecciona en `_loadCatalogs` |
| **Filtro inteligente** | El selector de producto de cada línea **excluye los productos ya usados en otras líneas** (`usedProductIds`) |
| **Acciones** | Cámara / Galería; agregar y quitar líneas; agregar y quitar asignaciones; switch de pago total (autoselecciona el ADMIN si solo hay uno); Confirmar |
| **Validaciones** | 7 comprobaciones secuenciales, ver [UF-04 en 06](06_USER_FLOWS.md) |
| **loading** | Spinner mientras cargan los catálogos; spinner de 16px en el botón Confirmar mientras `saving` |
| **error** | `showError(context, error)` como snackbar rojo — **no** hay estado de error de pantalla |
| **Salida protegida** | `PopScope` + diálogo "¿Descartar cambios?"; el botón atrás se deshabilita mientras `saving` |
| **Permisos** | **Cámara y galería** (ver [18](18_PERMISSIONS.md)) |
| **Código muerto** | `_confirm(List<Map<String,Object?>> people)` recibe `people` y **nunca lo usa** |

---

## P-08 · ApplicationsScreen — `/aplicaciones`

| | |
|---|---|
| **Archivo** | `applications_screen.dart` (193 líneas) |
| **Tipo** | `ConsumerStatefulWidget` |
| **Objetivo** | Listar eventos de fumigación y revertirlos |
| **Servicios** | `applications(limit: 200)`, `activeCampaign()`, `reverseApplication` |
| **Datos mostrados** | Persona · chaco; campaña · nº productos; `items_summary` (concatenación `producto cantidad unidad · …` generada en SQL); costo total; botón ↩ si no está revertida |
| **Acciones** | "Registrar" (con guardia de campaña activa y diálogo de ayuda); filtro por campaña; buscador; revertir |
| **Búsqueda** | `'$row'.toLowerCase().contains(query)` — serializa **todo el `Map`** a texto y busca ahí. Funciona, pero busca también en ids y timestamps |
| **loading / empty / error** | Spinner · `EmptyState` "No hay aplicaciones para mostrar." · `EmptyState` con `friendlyError` |
| **Layout adaptativo** | Filtros en `Row` si ≥ 600px, en `Column` si menos |
| **Navegación saliente** | `push /aplicaciones/nueva`; `go /catalogos` desde el diálogo de campaña |

---

## P-09 · ApplicationFormScreen — `/aplicaciones/nueva[?planId=N]`

| | |
|---|---|
| **Archivo** | `application_form_screen.dart` (584 líneas) |
| **Tipo** | `ConsumerStatefulWidget`, pantalla completa |
| **Datos recibidos** | `planId` opcional por query param (`int.tryParse`) |
| **Servicios** | `activeCampaign()`, `people()`, `farms()`, `planForApplication`, `availableProductsForOwner`, `estimateFifoCost`, `confirmApplication` |
| **Datos mostrados** | Banner de campaña activa; selectores Persona/Chaco; área tratada en ha; selector "Agregar producto" con *stock disponible · costo FIFO próximo*; una tarjeta por producto con Disponible, "stock después", dosis y cantidad real; notas |
| **Acoplamiento** | Elegir chaco cambia la persona al propietario; cambiar persona limpia el chaco y recarga stock |
| **Cálculo en vivo** | `theoretical(line) = área_ha × dosis × 1000`; `estimateFifoCost` al teclear cantidad real, con guarda anti-carrera (`if (q == tryParseBase(line.real.text))`) |
| **Validaciones** | Persona + chaco + ≥1 línea; cada cantidad real > 0 y ≤ stock; producto no repetido |
| **Botón principal** | En `bottomNavigationBar`, con su propio `FutureBuilder`; texto cambia a "Guardando…" |
| **loading / error** | Spinner · `EmptyState` con `friendlyError` (cubre "Active una campaña…", "El plan no existe.", "El plan no pertenece a la campaña activa.") |
| **Salida protegida** | `PopScope` + diálogo |
| **Defecto menor** | El campo Notas hace `onChanged: (_) => dirty = true` **sin `setState`**, por lo que escribir solo en notas no marca el formulario como sucio de forma consistente |

---

## P-10 · SettlementsScreen — `/liquidacion`

| | |
|---|---|
| **Archivo** | `settlements_screen.dart` (432 líneas) |
| **Tipo** | `ConsumerStatefulWidget` |
| **Objetivo** | Saldos por persona, registro de pagos y reportes de costo |
| **Servicios** | `campaigns()`, `settlements(campaignId)`, `farmCostReport(campaignId)`, `productCostReport(campaignId)`, `detailedStatement`, `personCampaignBalance`, `addAccountPayment`, `exportBackup` |
| **Datos mostrados** | Por persona (excluye ADMIN): nombre, cargos, pagos/créditos, etiqueta "Saldo pendiente"/"Saldo a favor" y el importe en naranja/verde. Debajo: "Costo por chaco y hectárea" y "Costo consumido por producto" |
| **Acciones** | Filtro por campaña (preselecciona la activa la primera vez, vía `campaignInitialized`); buscador de persona; ⋮ → Ver detalle cronológico / Registrar pago / Registrar adelanto; "Exportar backup" |
| **Diálogo de estado de cuenta** | 620×420 px, con saldo inicial de campaña + movimientos con saldo acumulado |
| **Validaciones** | El importe se parsea con `parseMinor` (vacío → 0, y el repositorio rechaza ≤ 0) |
| **loading / empty** | Spinner · `EmptyState` "Registra familiares o terceros para ver su liquidación." |
| **error** | **No hay rama de error de pantalla**: si el `Future` falla, se queda en el spinner. Ver [27](27_KNOWN_ISSUES.md) |
| **Permisos** | Escritura en Descargas para el backup (gestionada por `path_provider`) |

---

## P-11 · InventoryScreen — `/inventario`

| | |
|---|---|
| **Archivo** | `inventory_screen.dart` (106 líneas) |
| **Servicios** | `inventorySummary()` (sin límite) |
| **Datos mostrados** | Por producto: nombre; "Físico X · comprometido Y"; proyectado como *trailing*, **en color de error si es negativo** |
| **Acciones** | Buscar (cliente); recargar; tocar → `/inventario/:id` |
| **loading / empty / error** | Spinner · `EmptyState` "No hay productos para mostrar." · `EmptyState` con `friendlyError` |

---

## P-12 · InventoryDetailScreen — `/inventario/:id`

| | |
|---|---|
| **Archivo** | `inventory_detail_screen.dart` (198 líneas) |
| **Tipo** | `ConsumerWidget` (sin estado) |
| **Datos recibidos** | `productId` (`int.parse` del path param) |
| **Servicios** | `inventoryProductHeader`, `inventoryProductDistribution`, `inventoryProductLots` |
| **Datos mostrados** | 6 métricas (Comprado, Consumido, Físico, Comprometido, Libre proyectado, Valor físico); distribución por persona (asignado/consumido/disponible); lista de lotes con proveedor, campaña, costo unitario y origen (compra o "transferencia del lote #N") |
| **Subtítulo** | "Detalle físico y trazabilidad FIFO. El inventario continúa entre campañas." |
| **error** | `PageFrame` + `EmptyState` con `friendlyError` (cubre "El producto no existe.") |
| **Defecto de rendimiento** | El `Future` se crea en `build()` vía `_load(ref)`, por lo que **cada reconstrucción relanza las 3 consultas**. Ver [25](25_PERFORMANCE_AUDIT.md) |
| **Riesgo de ruta** | `int.parse` sin `tryParse`: `/inventario/abc` lanza `FormatException` durante la construcción de la ruta |

---

## P-13 · PersonsScreen — `/personas`

| | |
|---|---|
| **Archivo** | `persons_screen.dart` (55 líneas — la más pequeña con datos) |
| **Tipo** | `ConsumerWidget` |
| **Servicios** | `personProfiles()` |
| **Datos mostrados** | Avatar con inicial; nombre; "Familiar/Tercero/Administrador · N ha"; saldo |
| **Acciones** | Tocar → `/personas/:id` |
| **Sin refresco** | No tiene botón de recarga; el `Future` se crea en `build()`, de modo que se recarga en cada reconstrucción |
| **Formato de superficie** | `(row['area_m2'] as int) / 10000` sin formatear → puede mostrar `28.0 ha` o `2.8000000000000003 ha`. Ver [27](27_KNOWN_ISSUES.md) |

---

## P-14 · PersonDetailScreen — `/personas/:id`

| | |
|---|---|
| **Archivo** | `person_detail_screen.dart` (182 líneas) |
| **Tipo** | `ConsumerWidget` con `DefaultTabController(length: 5)` |
| **Datos recibidos** | `personId` |
| **Servicios** | `personProfile`, `farmsForPerson`, `applications(personId:)`, `personStockSummary`, `detailedStatement` |
| **Pestañas** | Resumen (superficie, saldo) · Chacos (→ `/chacos/:id`) · Aplicaciones · Inventario · Cuenta |
| **Altura fija** | `SizedBox(height: 480)` para el `TabBarView` — no se adapta al contenido ni a pantallas cortas |
| **empty** | `_Section` muestra `EmptyState` "Sin registros." si la pestaña no tiene filas |
| **error** | `PageFrame(title: 'Persona')` + `EmptyState` con `friendlyError` |
| **Defecto de rendimiento** | `_load(ref)` en `build()` → 5 consultas por reconstrucción |

---

## P-15 · FarmLogbookScreen — `/chacos/:id`

| | |
|---|---|
| **Archivo** | `farm_logbook_screen.dart` (82 líneas) |
| **Tipo** | `ConsumerWidget` |
| **Datos recibidos** | `farmId` |
| **Servicios** | `farmProfile`, `farmLogbook` |
| **Datos mostrados** | Título = nombre del chaco; subtítulo "Bitácora · propietario · N ha"; por entrada: producto, fecha (10 primeros caracteres del ISO), campaña, persona, cantidad; al expandir: área, dosis, teórico vs real, costo y **detalle de lotes FIFO** |
| **empty** | `EmptyState` "Todavía no hay aplicaciones en este chaco." |
| **Filtros no expuestos** | `farmLogbook` acepta `campaignId` y `productId`; la pantalla no los usa |
| **Navegación entrante** | **Solo** desde `PersonDetailScreen` → pestaña Chacos |
| **Riesgo de casts** | `row['treated_area_m2'] as int? ?? 0` está protegido, pero `row['quantity_base'] as int` y `row['unit'] as String` no |

---

## P-16 · TransfersScreen — `/transferencias`

| | |
|---|---|
| **Archivo** | `transfers_screen.dart` (103 líneas) |
| **Servicios** | `transfers()` (límite 50), `reverseTransfer` |
| **Datos mostrados** | "Origen → Destino"; `products_summary` (generado con `GROUP_CONCAT` en SQL); al expandir: "N producto(s) · M lote(s) · costo Bs X"; botón ↩ o texto "Revertida" |
| **Acciones** | "Nueva" (`push`); revertir |
| **loading / empty / error** | Spinner · `EmptyState` "No hay transferencias." · `EmptyState` con `friendlyError` |

---

## P-17 · TransferFormScreen — `/transferencias/nueva`

| | |
|---|---|
| **Archivo** | `transfer_form_screen.dart` (361 líneas) |
| **Tipo** | `ConsumerStatefulWidget`, pantalla completa |
| **Servicios** | `people()`, `availableProductsForOwner`, `transferProductsFifo` |
| **Estructura** | 3 secciones numeradas: "1. Origen", "2. Productos disponibles", "3. Destino" |
| **Datos mostrados** | Por producto: nombre, "X disponibles · N lote(s) · próximo FIFO Bs Y/unidad", campo de cantidad de 105px |
| **Gestión de controllers** | Un `TextEditingController` por producto en un `Map<int, TextEditingController>`, recreado al cambiar de origen, con `dispose()` de los anteriores |
| **Buscador** | Aparece **solo si hay ≥ 8 productos** |
| **Altura acotada** | La lista se limita a `MediaQuery.sizeOf(context).height * 0.48` |
| **Confirmación** | Diálogo con resumen De/A y lista de productos, botones "Revisar" / "Confirmar" |
| **Validaciones** | Origen ≠ destino, ≥1 cantidad > 0, cada cantidad ≤ stock |
| **Salida protegida** | `PopScope` + diálogo |
| **empty específico** | "Esta persona no tiene stock disponible." cuando el origen no tiene nada |
| **Cobertura** | `responsive_v5_test.dart` |

---

## Resumen de patrones de estado por pantalla

| Pantalla | loading | empty | error | Refresco |
|---|:--:|:--:|:--:|:--:|
| Dashboard | ✅ | ✅ parcial | ✅ | botón |
| Operations | n/a | n/a | n/a | n/a |
| Catalogs | ✅ | ✅ | ⚠️ sin `friendlyError` | tras cada acción |
| Planning | ✅ | ✅ | ✅ | tras guardar |
| PlanForm | ✅ | ✅ | ✅ | n/a |
| Purchases | ✅ | ✅ | ❌ inalcanzable | tras acción |
| PurchaseForm | ✅ | n/a | ⚠️ solo snackbar | n/a |
| Applications | ✅ | ✅ | ✅ | tras acción |
| ApplicationForm | ✅ | ✅ | ✅ | n/a |
| Settlements | ✅ | ✅ | ❌ **ausente** | tras acción |
| Inventory | ✅ | ✅ | ✅ | botón |
| InventoryDetail | ✅ | ⚠️ listas vacías sin mensaje | ✅ | ❌ ninguno |
| Persons | ✅ | ❌ ausente | ✅ | ❌ ninguno |
| PersonDetail | ✅ | ✅ | ✅ | ❌ ninguno |
| FarmLogbook | ✅ | ✅ | ✅ | ❌ ninguno |
| Transfers | ✅ | ✅ | ✅ | tras acción |
| TransferForm | ✅ | ✅ | ✅ | n/a |

---

# Actualización 2026-09-06 — Cambios de pantalla al congelar la baseline

| Pantalla | Cambio |
|---|---|
| **UI-01 `/`** Inicio | El inventario proyectado usa **tarjetas** por debajo de 560 px (nombre por encabezado, cifras rotuladas) y conserva la `DataTable` en pantalla ancha. La cinta "Campaña activa" reparte el ancho y ya no desborda con nombres largos |
| **UI-03 `/catalogos`** Catálogos | **Sin FAB global.** La acción primaria dice qué crea: "Agregar persona / chaco / producto / proveedor / campaña". Los cuatro diálogos validan en línea. El menú de una campaña ofrece "Activar" **sólo** si está `PLANNED`, y el cierre pide confirmación irreversible |
| **UI-04 `/planificacion`** Planificación | Muestra los planes **pendientes**; un interruptor secundario añade los aplicados, marcados "Aplicado" y sin acción. Recarga al volver del formulario de aplicación |
| **UI-07 `/compras/nueva`** Compra | Proveedor/campaña y cantidad/moneda se **apilan** por debajo de 420 px. Sin producto: "Precio por unidad" y sólo "Subtotal". El campo de la asignación se llama "Cantidad" y lleva su unidad; el de la línea, "Cantidad comprada". La tarjeta reserva relleno superior, así que la etiqueta "Producto" no se recorta. El estado de la línea declara qué falta |
| **UI-10 `/liquidacion`** Liquidación | El respaldo informa de cuántas fotografías incluye; la restauración declara antes de aceptar qué trae el archivo, y avisa después si hubo discrepancias |
| **UI-17 `/transferencias/nueva`** Transferencia | Sin origen elegido: estado vacío *"Seleccione un origen para ver su inventario."*, sin recuento y sin controles de cantidad |
| **Shell (todas)** | En horizontal, el `NavigationRail` **se desplaza**, así que al 130 % ningún destino queda inalcanzable |

Evidencia por pantalla: `artifacts/ui-audit/fixed/final-freeze/` (60 capturas) y
[`43_UIBUG_FIX_TRACEABILITY`](43_UIBUG_FIX_TRACEABILITY.md).
