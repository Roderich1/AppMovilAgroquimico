# Sesión C — Chacos y costos (modo individual)

Rama `feat/modo-individual-c` (`_wt/IND-C`), base `3d6eef4`. Fecha real: 2026-11-13. Sin push.

## Commits

| Commit | Contenido |
|---|---|
| `286a9f1` | Textos visibles «Modo individual» / «Modo con varias personas» en Datos (`catalogs_screen`), alta de persona (`catalog_dialogs`) y Cuentas (`persons_screen`); pruebas que los citan. Las excepciones del repositorio no se tocaron. |
| `bd0635b` | Chacos: lecturas (`lib/data/ind_c_chacos_reads.dart`), piezas (`widgets/ind_c_chacos_ui.dart`), lista (`ind_chacos_screen.dart`), detalle (`ind_c_chaco_detail_screen.dart`), costos (`ind_c_chaco_costs_screen.dart`), `farm_logbook_screen.dart` (en modo individual `/chacos/:id` muestra el detalle), pruebas. |
| `cfa02a8` | `personal_mode_flows_test`: toca el chip «Chacos» de Datos (con la barra individual de la base común había dos textos «Chacos»). |
| `28c4421` | Rótulos cortos en Costos, superficie bajo el nombre con letra ≥ 150 %, arnés `tool/rediseno/capturas_ind_c_test.dart`. |
| `1f7052c` | Capturas en `docs/evidence/rediseno-individual/2026-11-13/c/`. |

## Láminas

| Lámina | Implementación |
|---|---|
| I-40 Chacos | `/chacos` `ChacosScreen`: título + «+» (alta con `createFarmFromDialog`: titular fijo en modo individual), tarjeta oscura «Costos · <campaña activa>» que abre Costos, tarjetas con actividad («2 aplicaciones · 1 plan por hacer» / «Sin aplicaciones en esta campaña») y superficie. |
| I-41 Detalle | `/chacos/:id` (vía `FarmLogbookScreen` en modo individual): campaña, «Editar» (cambiar nombre / archivar, como Datos), superficie del chaco, costo aplicado y «Por ha del chaco (X ha)», plan(es) por hacer con «Aplicar» (`/aplicaciones/nueva?planId=`), aplicaciones con superficie tratada y costo (anuladas tachadas, no suman), productos utilizados por unidad, «Ver todos los costos», «Ver bitácora completa (lotes y dosis)». |
| I-42 Costos | `IndCChacoCostsScreen` (apilada con `Navigator`, ver peticiones): selector de campaña (incl. «Todas las campañas»), pestañas Chacos/Productos/Campañas, cifra «Costo de productos aplicados · <alcance>» con nota «No incluye compras ni lo que sigue en el almacén», tarjetas por chaco con costo por hectárea o «No disponible» + motivo, superficie tratada acumulada, exportación a Reportes (Excel o PDF) con el informe y la campaña. |
| I-43 Sin chacos | Estado vacío con «Agregar chaco» (mismo diálogo). Probado: crea el chaco con el titular como propietario. |

## Criterios de cálculo (reutilizados)

- Costo aplicado por chaco: Σ `applications.total_cost_bob_minor` no revertidas del alcance = `farmCostReport` (prueba de igualdad).
- Costo por producto: Σ `application_items.cost_bob_minor` = criterio de `productCostReport`; cantidades por producto con su unidad; el pie «Cantidad aplicada por unidad: 8 L · 1 KG» nunca suma unidades distintas.
- Costo por hectárea: `FarmCostRead.costPerHectareMinor` (costo del alcance ÷ **superficie del chaco** `farms.area_m2`, redondeo del informe). Nunca la superficie tratada. «No disponible» si no hay superficie utilizable o no hay aplicaciones en el alcance.
- Alcance de personas: en modo individual sólo chacos del titular vigente (como `farmsAndContext`); en el modo con varias personas, todos con su propietario. Los chacos archivados con aplicaciones en el alcance cuentan en Costos y salen de la lista.
- Alcance de campaña: la activa por defecto (o todas si no hay activa); cada cifra dice su campaña.

## Pruebas (todas con el candado `ftest.sh`)

- Nuevas: `test/ind_c_chacos_reads_test.dart` (7) y `test/ind_c_chacos_ui_test.dart` (3): titular vs. chaco ajeno, igualdad con `farmCostReport`, costo/ha 266,67 sobre 3 ha (no sobre 4 ha tratadas), unidades L y kg separadas, nombre largo, segunda campaña sin aplicaciones, anulación que deja de contar, archivado, fila sin superficie → «No disponible», plan que no cambia existencias, lectura que no escribe (volcado completo igual), detalle de chaco ajeno = no disponible en modo individual, recorrido UI lista → detalle → costos → Atrás del sistema, alta del primer chaco desde el vacío, modo con varias personas sin cambios (barra con Personas y bitácora en `/chacos/:id`).
- Existentes de lo tocado: `campaign_lifecycle_ui`, `catalogs_archive_confirm`, `e15_consumo_propio_base`, `e1_catalog_label_photo`, `f04_campaign_dialogs_ui`, `hierarchical_navigation`, `rdm2_c_buscador`, `rdm2_c_pago_titular`, `rdm2_c_personas_areas`, `rec_015_logbook_profile`, `set_state_contract`, `ui_polish`, `personal_mode_flows` → 133 + 20 pasan tras `cfa02a8`.
- `flutter analyze` de los archivos tocados: sin avisos.
- Defecto encontrado y corregido en el camino: `setState(() => data = _load())` devolvía un `Future` (aserción de Flutter).

## Capturas

`docs/evidence/rediseno-individual/2026-11-13/c/`: `i40_chacos`, `i41_chaco_detalle`, `i41b_chaco_detalle_final`, `i42_costos_por_chaco`, `i42b_costos_por_producto`, `i42c_costos_por_campana`, `i43_chacos_vacio`, cada una en 1,0 / `_x13` / `_x20` / `_w900`. Arnés con fuentes reales, base sintética, no teléfono.

## Diferencias intencionales con las láminas

- «Falta la superficie» (I-40 Chaco Alto): el esquema exige `farms.area_m2 > 0` (`CHECK`) y el diálogo la valida, así que en datos reales no ocurre. La insignia y el «No disponible · Falta registrar la superficie» existen sólo para filas anómalas de bases antiguas. En los datos reales, «No disponible» aparece cuando el chaco no tiene aplicaciones en el alcance.
- Pestañas «Chacos · Productos · Campañas» en vez de «Por chaco · Por producto · Por campaña»: con los rótulos largos `SegmentToggle` se apila a 360–390 dp.
- Detalle: «Productos utilizados» como lista (uno por fila, con su costo) en vez de una línea; se añaden «Ver bitácora completa» (lotes, dosis) y la nota de que un plan es previsión.
- Detalle sin «Volver» cuando se llega con `go` (sin pila); con `push` desde la lista sí aparece.
- Cantidades en kg se muestran «1 KG» (formato existente `formatQuantity`).
- Costo por hectárea con 2 decimales (redondeo del informe): 1.010,00 / 3 ha = 336,67.

## Peticiones al orquestador (no editadas)

1. **Ruta de Costos** (`app.dart`, antes de `/chacos/:id`):
   ```dart
   GoRoute(
     path: '/chacos/costos',
     builder: (_, state) => IndCChacoCostsScreen(
       initialCampaignId: int.tryParse(state.uri.queryParameters['campana'] ?? ''),
     ),
   ),
   ```
   y en `ind_c_chaco_costs_screen.dart` `openIndCCosts` pasaría a `GoRouter.of(context).push('/chacos/costos${campaignId == null ? '' : '?campana=$campaignId'}')` (lo cambio yo cuando exista la ruta). Hoy se apila con `Navigator` dentro de la pestaña: Atrás funciona (probado), pero no hay enlace directo.
2. **Botón flotante «Registrar» en Chacos** (`app_shell.dart` `hidesGlobalFab`): las láminas I-40 a I-43 no lo tienen y en I-40 compite con «+ Agregar chaco». Propuesta: añadir `'/chacos'` a `_routesWithoutGlobalFab` y `location.startsWith('/chacos/')` a `hidesGlobalFab`. Decisión del ORQ (sale en todas las capturas).
3. `SegmentToggle` (`agro_ui.dart`) mide el rótulo entero aunque el comentario dice «sin partir una palabra»; midiendo por palabra «Por producto» cabría en dos líneas sin apilar. Opcional.
4. Superficie del chaco no editable: el repositorio sólo tiene `renameCatalog`/`archiveCatalog`. No se añadió (cambiaría costos por hectárea ya presentados); queda para decisión del autor.

## Pendientes y observaciones

- Exportación: abre Reportes con `tipo` y `campana` existentes. El informe «Costo por chaco» conserva su alcance actual (todos los chacos con columna Propietario), así que en modo individual con historial de terceros el Excel/PDF incluiría esos chacos y la pantalla no. No se tocó `reports_screen.dart` (cruce con `proyectoagro-cb`).
- «Resumen de campaña» desde la pestaña Campañas con «Todas las campañas»: Reportes pide la campaña.
- En una superficie de prueba de 800×600 un `tap` sobre «Ver todos los costos» tras `ensureVisible` cayó sobre la barra inferior; a 393×852 queda por encima (comprobado con una aserción). Vale la pena mirarlo en el emulador apaisado.
- No probado en emulador ni teléfono.
