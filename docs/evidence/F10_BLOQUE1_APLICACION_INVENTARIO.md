# Bloque 1 de la revisión integral — Aplicación (existencias, costo y cargo, dosis) e inventario (movimientos)

- **Fecha real:** 2026-10-27 (America/La_Paz). Sesión A, por encargo de Roderich del 2026-10-26 (frente 3, parte de aplicación e inventario). Rama `fix/aplicacion-existencias-costo-movimientos` sobre `main` `a68285c`.
- **Trazabilidad:** CU-09 (aplicación), CU-07 (inventario), RN-25 (stock suficiente), RN-26 (FIFO), RN-27 (cargo por consumo); INT-01. Issue MOB #37.

## 1. Commits

| SHA | Qué |
|---|---|
| `967fcf9` | Hoja «Agregar producto»/«Cambiar producto»: cantidad > disponible → error en el campo «Pediste X y hay Y. Baja la cantidad o registra primero la compra.» y botón deshabilitado; `confirmApplication` intacto |
| `0e513ad` | Paso 3: costo estimado por producto, «Costo total estimado» y cargo según `settlement_policy` de la persona |
| `e1d5119` | Sin dosis, `theoretical_quantity_base` nulo (sin «teórico 0»); dosis y área validadas con los mensajes de formato |
| `2756a54` | Detalle del producto: sección «Movimientos» (`productMovements`, consulta de lectura nueva), lotes y valor plegados, «Reservado por planes», «Quedará libre», futuros en `initState` |
| `b48ae7a` | Revisión cruzada: «Costo propio: X (queda anotado en la cuenta de T)» en propio con cobro por consumo; movimientos agrupados por operación; pruebas de «Cambiar producto», disponible por persona y política MANUAL |

## 2. Pruebas de host

- `f10_x01_aplicacion_productos_test` (reescrita: rechazo en la hoja y rechazo transaccional cuando el stock cambia entre medio; queda una sola aplicación) 6/6; `fix_aplicacion_costo_cargo_test` 3/3; `fix_aplicacion_dosis_area_test` 5/5 (incluye repositorio: `theoretical_quantity_base IS NULL`); `fix_aplicacion_hoja_existencias_test` 3/3; `fix_inventario_movimientos_test` + `rec_046_051_net_figures_test` + `rec_046_inventory_detail_test` 17/17 → tras `b48ae7a` `00:10 +23: All tests passed!`. Las pruebas nuevas fallan sobre `a68285c` (botón habilitado, claves inexistentes, teórico 0, sección inexistente).
- Suite completa en la rama (`2756a54`, con otra suite en paralelo): 1 862 pasan, 3 omitidas, **1 fallo** en `operation_mode_onboarding_test` (`database_closed`), prueba ajena: en `main` aislada 3/3; en esta rama el autor la ejecutó 9 veces (una con otra suite en paralelo) siempre en verde. Inestable bajo carga, no regresión.
- `dart format` sin cambios; `flutter analyze` «No issues found!». Commits sin trailers.
- **Revisión cruzada:** LISTO; ajustes incluidos en `b48ae7a`. Seguimientos fuera de alcance: la bitácora del chaco sigue mostrando «Teórico 0 L» para nulo y la voz guarda `0` sin dosis; «Comprometido» sigue en Inventario e Inicio.

## 3. Comprobación en EMULADOR (integración local de las cuatro ramas)

Ver `F10_BLOQUE1_INTEGRACION_EMULADOR.md`: en COMPARTIDA, con Titular y Norte, la hoja con 200 mostró «Pediste 200 L y hay 1,3 L. Baja la cantidad o registra primero la compra.» (1,3 L = 1 L inicial + 0,3 L del reparto del Titular, no el físico 1,5 L) con «Agregar a la mezcla» deshabilitado; con 0,2 se agregó («Hay 1,3 L · quedarán 1,1 L»); paso 3: «Bellator · 0,2 L 36,00 Bs», «Glifosato Demo · 1 L 45,00 Bs», «Costo total estimado: 81,00 Bs», «Se cargará a Titular: 81,00 Bs»; base: `total_cost 8 100`, `USAGE_CHARGE 8 100` al Titular, `theoretical_quantity_base` nulo. En PROPIA: «Aplica el titular: Titular», «Costo propio: 36,00 Bs (queda anotado en la cuenta de Titular)»; base `USAGE_CHARGE 3 600`. Detalle de Bellator: «Movimientos · Lo que explica el saldo…»: «Aplicación en Norte 27/10/2026 · Titular −0,2 L», «Compra 27/10/2026 · Familiar Demo · Proveedor Demo +0,2 L», «Compra 27/10/2026 · Titular · Proveedor Demo +0,3 L», «Compra 17/10/2026 · Titular · Proveedor Demo +1 L»; «Reservado por planes 0 L», «Quedará libre 1,3 L», «Lotes disponibles y valor físico» plegado.

## 4. Lo que no cambia y decisión pendiente

Stock, FIFO, costos, políticas, transacciones, esquema, bitácora, lista de inventario, reportes, Inicio. E-15 (el titular figura como «pendiente» en Cuentas por su propio consumo) sigue como decisión de Roderich; el resumen ahora lo dice en vez de ocultarlo.
