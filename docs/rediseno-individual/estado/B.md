# Sesión B — Almacén, Actividad y Proveedores (modo individual)

Rama `feat/modo-individual-b` (`_wt/IND-B`), base `3d6eef4`. Todo condicionado a `personalModeProvider`; el modo con varias personas no cambia (pruebas abajo).

## Commits

Ver `git log 3d6eef4..feat/modo-individual-b`. Resumen en «Entrega» al final.

## Archivos

| Archivo | Cambio |
|---|---|
| `lib/presentation/screens/inventory_screen.dart` | Variante individual (I-30/I-32/I-33): buscador fijo, filtros Todos/Por vencer/Con planes, píldora de avisos, estado vacío con «Registrar una compra», enlace «Registrar una aplicación»; sólo productos con compras, consumos, existencia o planes; sin «Poco por responsable». Cuadrícula extraída a `_ProductGrid` (misma lógica para los dos modos). |
| `lib/presentation/screens/inventory_detail_screen.dart` | Variante individual (I-31): «Tiene ahora», sin «Quién lo tiene», tarjeta «Previsto en planes» con barra y proyección («Un plan no descuenta existencias»), movimientos «Compra · proveedor» sin el nombre del titular, lotes sin el nombre del titular, textos de «i» sin asignaciones. Lee el nombre del titular (una consulta más, sólo en individual) para conservar el de otra persona en la historia. |
| `lib/presentation/screens/operations_screen.dart` | Variante individual (I-04): tarjeta «Proveedores y saldos» con la deuda de todas las campañas; aplicaciones y planes sin repetir al titular; buscador sin «persona». En individual las compras se leen sin límite en la misma consulta (para la deuda); el historial sigue con 200. Compartido: exactamente las mismas consultas. |
| `lib/presentation/screens/ind_b_suppliers_screen.dart` (nuevo) | Pantalla «Proveedores» (I-05): deuda total y por proveedor, compras con saldo con «Pagar» (flujo existente `payPurchaseProvider`), últimas pagadas, enlace a la lista de compras. Funciones `purchaseBalanceMinor`/`supplierDebt` con el criterio de Inicio. |
| `lib/presentation/widgets/rdm2_b_lotes.dart` | `LotCard.person` opcional (lote del titular sin nombre). |
| `lib/presentation/screens/inventory_alerts_screen.dart` | Terminología: «inventario compartido» → «modo con varias personas». |
| `test/ind_b_almacen_actividad_test.dart`, `test/support/ind_b_individual_seed.dart` (nuevos) | Pruebas de los dos modos y base sintética individual (cambio de modo con condiciones reales). |
| `tool/rediseno/capturas_ind_b_test.dart` (nuevo) | Arnés de capturas. |

## Láminas

| Lámina | Estado | Notas |
|---|---|---|
| I-04 Actividad | Hecha | Ver diferencias. |
| I-05 Proveedores y saldo | Hecha (pantalla) | Falta la ruta en `app.dart` (petición P-1). |
| I-30 Almacén | Hecha | |
| I-31 Detalle de producto | Hecha | |
| I-32 Almacén vacío | Hecha | |
| I-33 Letra ampliada y nombres largos | Hecha | Capturas a 1,3 y 2,0. |

## Pruebas (focalizadas, con el candado `ftest.sh`, 2026-11-13)

- `test/ind_b_almacen_actividad_test.dart`: **11/11** sobre `f8e62c2` + ajustes de texto. Cubre, en los dos modos: Almacén (filtros, búsqueda, píldora, catálogo sin uso oculto, unidades L/KG, valoración, «Previsto en planes · quedarían»), estado vacío → formulario de compra, detalle (Tiene/Hay ahora, «Quién lo tiene», proyección, movimientos y lotes sin el titular), Actividad (deuda 2.185,00 de todas las campañas, filas sin el titular, tarjeta → `/proveedores`), Proveedores (deuda total y por proveedor, «Pagar»: pago del titular en `provider_payments` por 625,00, **sin** filas nuevas en `account_transactions`, deuda que baja a 1.560,00 en pantalla).
  - La prueba de «Pagar» encontró un defecto propio (`setState(() => future = next)` devolvía un Future y cortaba el refresco); corregido antes del commit.
- Regresión de las pruebas existentes que tocan estas pantallas (25 archivos: `e12_pin_offer_screen`, `f04_admin_owner_restore_ui`, `f04_av_inventory_alerts(_ui)`, `f10_d07_transferencia_sin_deuda`, `f10_x01_inicio_mas`, `f12_est_07_estimation_ui`, `fix_inventario_movimientos`, `hierarchical_navigation`, `navigation`, `oe3_fab_sincronizacion`, `operation_mode_leave_during_save`, `operation_mode_onboarding`, `personal_mode_flows`, `purchases_access`, `rdm2_b_almacen_detalle`, `rdm_flotante_no_tapa`, `rdm_registrar_relee`, `rec_046_051_net_figures`, `ui_polish`, `ux_altas_en_contexto`, `ux_altas_teclado`, `uxj_a_navegacion`, `set_state_contract`, `ux_c1_detalle_compra`): **232 pasan, 1 falla**.
  - Falla `personal_mode_flows_test.dart:361` («catálogos: no se agregan responsables…»): `tap(find.text('Chacos'))` encuentra dos textos, la pestaña de Catálogos y el destino «Chacos» de la barra individual. Viene de la **base común** (`3d6eef4`, barra individual), no de B; la prueba es de Catálogos (sesión C / ORQ). Ver P-4.
- `flutter analyze` de `lib/presentation`, las pruebas nuevas y el arnés: sin avisos.

## Capturas

`docs/evidence/rediseno-individual/2026-11-13/b/` — arnés con fuentes reales, base sintética: `i30_almacen`, `i30_almacen_final`, `i31_detalle`, `i31_detalle_movimientos`, `i31_detalle_lotes`, `i04_actividad`, `i05_proveedores`, `i32_almacen_vacio`, cada una a 1,0 (sin sufijo), 1,3 (`_x13`), 2,0 (`_x20`) y 900 dp (`_w900`). Revisadas contra sus láminas: sin desbordes; a 2,0 los filtros se desplazan en horizontal y los importes/botones bajan debajo del texto. `i05_proveedores` sin barra inferior (ruta del arnés hasta P-1).

## Diferencias intencionales con las láminas

- **I-04, campaña en la cabecera («Invierno 2026»):** no se muestra. Actividad no filtra por campaña; poner una campaña haría creer que el historial es sólo de ella.
- **I-30, «Entró hoy · 12 L»:** no se muestra. Necesita otra consulta por producto (riesgo de pruebas con espera fija) y no aporta una cifra que no esté en el detalle.
- **I-30, tarjeta:** se conserva «Valor …» y «Previsto en planes · quedarían/faltarían» (encargo: conservar valoración; la proyección es la misma cifra que la lámina).
- **I-30/I-32, productos del catálogo sin uso:** no aparecen en el Almacén individual (siguen en Ajustes › productos). Con ellos el estado vacío nunca saldría.
- **I-31, «Entradas y valoración», «Avisos de este producto», «Vínculo con el sindicato»:** se conservan los bloques existentes («Más datos»: lotes, cifras netas y valor, avisos con PIN). El vínculo con el sindicato es del área reservada a `proyectoagro-cb`.
- **I-05, «Fecha anterior al 1 nov»:** se muestra la fecha real de la compra.
- **I-05, compras pagadas:** las tres más recientes por proveedor; el resto en la lista de compras.
- **I-30, píldora:** cuenta lotes vencidos, que vencen hoy o pronto y productos con poca existencia (las mismas listas que «Avisos de inventario»); los lotes sin fecha siguen en «Todos los avisos».
- **Detalle, historial:** un movimiento, lote o plan de otra persona (anterior al cambio de modo) conserva su nombre; la comparación es por nombre del titular (ver P-3).

## Peticiones al orquestador

- **P-1 (ruta I-05):** añadir dentro del `ShellRoute` de `lib/app.dart`:
  ```dart
  GoRoute(
    path: indProvidersPath, // '/proveedores', de ind_b_suppliers_screen.dart
    builder: (_, __) => const SuppliersBalanceScreen(),
  ),
  ```
  y en `lib/presentation/app_shell.dart`: `'/proveedores'` en `sectionRoutes['/operaciones']` (Actividad resaltada, Atrás vuelve a Actividad) y en `_routesWithoutGlobalFab` (la lámina no tiene botón; «Pagar» es su acción). Después, `indProvidersRoute` = `indProvidersPath`.
- **P-2 (terminología, archivo ORQ):** `lib/presentation/widgets/mode_notice.dart` (líneas 31–47) dice «inventario propio/compartido».
- **P-4 (prueba de la base común):** en `test/personal_mode_flows_test.dart:361` acotar el toque a la pestaña de Catálogos (p. ej. `find.descendant(of: find.byType(TabBar), matching: find.text('Chacos'))`), o decidir otro rótulo. No la toco: no es de B.
- **P-3 (opcional, repositorio):** añadir `m.owner_person_id` al `SELECT` de `productMovements` para comparar por id y no por nombre del titular.

## Pendientes

- Recorrido en emulador (ORQ): Almacén, detalle, Actividad, Proveedores y «Pagar» sobre la candidata integrada (no hecho por B: sin emulador, según el reparto).
- Teléfono físico: no probado.
- Aceptación visual: sólo el autor.
