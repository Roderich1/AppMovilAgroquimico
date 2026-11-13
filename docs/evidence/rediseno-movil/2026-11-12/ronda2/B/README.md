# Ronda 2, sesión B — detalle de producto de Almacén y lotes

- **Fecha real:** 2026-11-12.
- **Rama:** `feat/rdm-correcciones-b` (worktree `_wt/RDM2-B`), base `77deb95`.
- **Código verificado:** `a31a285` (cambio de presentación) sobre `77deb95`.
- **Dónde:** arnés de pruebas de Flutter 3.47.2 en Windows (no es un teléfono ni el emulador). Datos **sintéticos** de `test/support_rdm2/b_almacen_seed.dart`; fechas relativas al día del equipo (2026-11-12).

## Capturas

Comando (una ejecución por configuración, una a la vez):

```
RDM_SHOTS=<carpeta> [RDM_TEXT_SCALE=1.3|2.0] [RDM_WIDTH=900] \
  flutter test --no-pub tool/rediseno/capturas_rdm2_b_test.dart
```

- `antes/`: el mismo arnés sobre los cuatro archivos de pantalla de `77deb95` (`git checkout 77deb95 -- <archivos>` temporal; después se restauró el trabajo). 40 PNG.
- `despues/`: sobre `a31a285`. 44 PNG (el historial `b5_*` no existe antes).
- Sufijos: sin sufijo = 390×844 y letra 1.0; `_x13` = letra 1.3; `_x20` = letra 2.0; `_w900` = 900 dp de ancho, letra 1.0.

| Captura | Qué muestra |
|---|---|
| `b0_lista` | Lista de Almacén, tarjeta del producto (etiqueta de vencimiento con cantidad). |
| `b1_detalle_arriba` | Cabecera y primeras secciones del detalle. |
| `b2_detalle_movimientos` | Movimientos (antes, lista entera; después, cinco recientes y «Ver todo el historial»). |
| `b3_lotes_desplegados`, `b3b_lotes_fin` | Lotes desplegados y el final de la página. |
| `b4_dialogo_avisos` | Diálogo «Avisos de …». |
| `b5_historial` | Historial completo (sólo después). |
| `b6_avisos_inventario` | Avisos de inventario. |
| `b7_compra_detalle`, `b7b_compra_lotes` | Detalle de una compra con vencimiento y número del fabricante. |
| `b8_compra_sin_numero` | Detalle de una compra sin número del fabricante ni vencimiento. |

Revisadas una a una (lectura de los PNG): sin desbordes ni franjas de error. Con letra 2.0 el diálogo de avisos se desplaza dentro de sí (el resto del contenido se alcanza desplazando).

## Pruebas (resultado de la consola)

`flutter test --no-pub <archivos> --concurrency=2`, en lotes:

| Archivos | Resultado |
|---|---|
| `rdm2_b_almacen_detalle_test`, `fix_inventario_movimientos_test`, `f10_d07_transferencia_sin_deuda_test`, `rec_046_051_net_figures_test` | `+28: All tests passed!` |
| `f04_av_inventory_alerts_ui_test`, `rec_046_inventory_detail_test`, `f04_av_inventory_alerts_test`, `ux_c1_detalle_compra_test` | `+51: All tests passed!` |
| `rdm_flotante_no_tapa_test`, `rdm_registrar_relee_test`, `rdm_textos_autor_test`, `ux_c1_correcciones_test` | `+37: All tests passed!` |
| `hierarchical_navigation_test`, `ui_polish_test`, `set_state_contract_test`, `f12_est_07_estimation_ui_test` | `+36: All tests passed!` |
| `f10_x01_inicio_mas_test`, `oe3_fab_sincronizacion_test`, `e2_joint_purchase_screens_test` | `+36: All tests passed!` |

`flutter analyze` de los archivos tocados: `No issues found!`. No se corrió la suite completa (le corresponde al orquestador).

## Límites

- Arnés, no dispositivo: no prueba lector de pantalla real, teclado del sistema ni rendimiento.
- No recorrido en el emulador ni revisado por el autor.
