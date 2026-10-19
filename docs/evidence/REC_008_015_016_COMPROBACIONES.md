# REC-008 (#44), REC-015 (#51) y REC-016 (#52): comprobaciones de interfaz, lecturas y reportes

- **Fecha:** 2026-10-19 (America/La_Paz). Sesión C de Claude Code. Es el encargo de Roderich Rendón, transmitido por la sesión A, sobre las comprobaciones de `REC_CONCILIACION_2026-10-19.md` §4.
- **Base:** Mobile `main` `324df1a`. Flutter 3.47.2 en Windows 11.
- **Tipo de prueba:** host (`flutter test`, `sqflite_common_ffi`). **Sin dispositivo.**
- **Regla aplicada:** comprobaciones de comportamiento, sin meta de cobertura. Los valores esperados los fija la fixture y se calculan a mano. Ninguna prueba compara una exportación con su propia lectura.

## #44 · `test/rec_008_invoice_viewer_test.dart` (commit `ccc9dc5`)

| Criterio | Caso | Qué comprueba |
|---|---|---|
| 1 (sin cámara) | «copia la foto a invoices/ con sus bytes y su extensión, sin moverla» | `storeInvoiceImage` deja `invoice_<µs>.png` en `<documentos>/invoices` con los mismos 4096 bytes, y el original del selector sigue existiendo |
| 1 | «sin extensión guarda .jpg» | `invoice_<µs>.jpg` con los bytes de origen |
| 1 | «la compra conserva la ruta guardada y apunta al archivo» | `invoice_image_path` de la compra es la ruta devuelta y el archivo existe. Es lo que hace `purchase_form_screen.dart` al guardar |
| 2 | «“Ver factura” sólo aparece en la compra con fotografía» | `PurchasesScreen`: el menú de la compra sin foto no ofrece «Ver factura» y el de la compra con foto sí |
| 2 | «abre el diálogo con la imagen guardada y se cierra» | El diálogo «Factura» contiene un `Image` con `FileImage` de esa ruta (un PNG válido de 1×1) y no lanza excepción. Con «Cerrar» desaparece |
| 2 | «si la foto ya no existe lo avisa y no abre el diálogo» | Muestra «La imagen de factura ya no está disponible en este dispositivo.» y no abre ningún `AlertDialog` |

**Mutaciones** (detectadas y restauradas con `git checkout`):
- «Ver factura» siempre visible: falla el caso de la compra sin foto;
- `.png` como extensión por defecto: falla el caso sin extensión.

**Sigue sin cubrir:**
- **la cámara**: no se ejercita en ningún soporte, ni se simula `ImagePicker`;
- el recorrido completo del formulario con el selector del sistema; la galería ya se registró en dispositivo en las series F10 1 y 2.

## #51 · `test/rec_015_logbook_profile_test.dart` (commits `f1519d2` y `82d02fc`)

La fixture está explicada en la cabecera del archivo:
- tres compras: Glifosato a 100,00 y 120,00 Bs/L, y Paraquat a 50,00 Bs/kg;
- cinco aplicaciones de Ana en dos chacos y dos campañas;
- A3 revertida;
- Campaña 1 cerrada y Campaña 2 activa.

Saldo esperado: 650,00 Bs. Stock esperado: Glifosato 2,5 L y Paraquat 3 KG. Superficie: 12,5 ha.

| Criterio | Caso | Resultado |
|---|---|---|
| 3 | `farmLogbook`, «sólo las aplicaciones del chaco… con todos los campos del criterio» | Orden A4, A3, A2, A1. A1 lleva fecha, campaña, persona, producto, unidad, área 100 000 m², dosis 400, teórico y real 4000, costo 42 000 y `fifo_lots` `#g1: 3000,#g2: 1000`. A2 y A4 llevan también su costo y sus lotes |
| 3 | «la aplicación revertida sigue en la bitácora, marcada y sin lotes consumidos» | A3: `REVERSED`, 500 y 6000, `fifo_lots` nulo. Las demás están `CONFIRMED` |
| 3 | «filtra por campaña», «filtra por producto», «combina los dos filtros», «el otro chaco tiene su propia bitácora» | C1 → A3, A2, A1. C2 → A4. Glifosato → A4, A3, A1. Paraquat → A2. C1 + Glifosato → A3, A1. C2 + Paraquat → vacío. Chaco Chico → A5 |
| 3 | `FarmLogbookScreen`, «muestra el chaco y cada aplicación con sus datos» | Título, subtítulo «Bitácora · Ana Familiar · 10 ha» y 4 filas; A5, del otro chaco, no aparece. El detalle desplegado de A1 y de A2 (área, dosis, teórico, real, costo y lotes) se compara con los valores fijados |
| 3 | «la aplicación revertida se distingue de las confirmadas» | **Falló sobre `324df1a`.** Pasa con `82d02fc` (defecto 1) |
| 2 | `PersonDetailScreen`, «resumen: superficie y saldo total» | Superficie 12,5 ha y saldo 650,00 Bs, en la fila y en el subtítulo |
| 2 | «chacos: los dos, con su superficie» | 10 ha y 2,5 ha |
| 2 | «inventario: stock por producto y unidad» | Glifosato 2,5 L y Paraquat 3 KG |
| 2 | «cuenta: la reversión conserva el cargo y añade el crédito» | Seis asientos en orden de fecha. Los cinco cargos valen 420,00, 50,00, 60,00 (A3, conservado), 60,00 y 120,00. El crédito es de −60,00 y su concepto es el motivo de la reversión. Se comprueba el acumulado de cada asiento: 420, 470, 530, 590, 710 y 650 |

### Defecto 1 (corregido): la bitácora no distinguía una aplicación revertida

`FarmLogbookScreen` no leía el `status` que devuelve `farmLogbook`. A3, revertida, se pintaba igual que una aplicación hecha:
- «Glifosato 0,5 L», con costo 60,00 Bs;
- sin ninguna marca de reversión.

Sólo la delataba «Lotes sin detalle».

- **Reproducción:** `f1519d2`. `flutter test test/rec_015_logbook_profile_test.dart` → `+11 -1: Some tests failed.` No se encontró el texto «01/03/2026 · Campaña 1 · Ana Familiar · Revertida».
- **Corrección:** `82d02fc`, sólo en `farm_logbook_screen.dart`. El subtítulo de una fila `REVERSED` termina en «· Revertida» (`operationStatusLabel`), como el historial de compras. No cambian la consulta, el esquema ni las reglas.
- **Después:** `+12: All tests passed!` También `hierarchical_navigation_test.dart`, que llega a `/chacos/:id`, sigue `+11`.

### Observación 2 (no corregida; la decide Roderich): «Consumido» incluye la aplicación revertida

En la pestaña Inventario del perfil, el subtítulo «Consumido» sale de `personStockSummary.consumed_base = −SUM(APPLICATION_OUT)`. La reversión no borra el `APPLICATION_OUT` de A3: añade un `APPLICATION_REVERSAL` positivo.

Con esta fixture, leído el 2026-10-19 con una prueba temporal que no se commitea:
- `personStockSummary` da Glifosato `assigned 8500`, `consumed 6000`, `available 2500`;
- `inventoryProductHeader` da `purchased 8000`, `consumed 6000`, `physical 2500`.

El consumo neto es 5,5 L. La cabecera de inventario muestra «comprado 8 − consumido 6» y «físico 2,5», que no cuadran a la vista. El saldo (2,5 L) y el costo son correctos.

No se corrige aquí, por dos razones:
- cambia la semántica de lecturas compartidas por varias pantallas: el perfil y el detalle de inventario, este último de #46;
- elegir entre consumo bruto y neto es una decisión de diseño.

La prueba de #51 no afirma el texto «Consumido».

## #52 · `test/rec_016_export_coherence_test.dart` (commit `20e0660`)

Se exporta en CSV:
- el costo por producto y el costo por chaco, con todas las campañas, con la Campaña 1 y con la Campaña 2;
- el resumen de la Campaña 1 y el de la Campaña 2.

Se compara **el archivo completo**, registro a registro: título, filtro, cabeceras, filas, totales y orden. Sólo se omite la línea «Generado», porque su hora local depende de la zona del equipo. También se comprueba el BOM.

La fixture incluye:
- dos campañas;
- tres chacos, uno de otra persona y sin aplicaciones;
- una aplicación revertida;
- un consumo FIFO que cruza dos lotes de Paraquat (3 KG a 50,00 + 0,5 KG a 55,00 = 177,50);
- un plan pendiente en la Campaña 2.

| Reporte | Esperado clave |
|---|---|
| Costo por producto | Todas: Glifosato 5,5 L 600,00 y Paraquat 4,5 KG 227,50, total 827,50 (A3 no cuenta). C1: 4,5 L 480,00 y 1 KG 50,00, total 530,00. C2: 1 L 120,00 y 3,5 KG 177,50, total 297,50 |
| Costo por chaco | Todas: Beto 5 ha 0,00 / 0,00; Chico 2,5 ha 237,50 / 95,00; Grande 10 ha 590,00 / 59,00; total 827,50. C1: 60,00 / 24,00 y 470,00 / 47,00. C2: 177,50 / 71,00 y 120,00 / 12,00 |
| Resumen de campaña | C1: compras 2 / 1100,00; aplicaciones 3 / 530,00; planes 0; saldo 530,00 (cargos 590 − crédito 60). C2: 1 / 110,00; 2 / 297,50; planes 1; saldo 297,50 |

**Mutación:** se quitó el filtro de campaña del cableado de costo por producto en `ReportExportService.compose`. Fallaron los dos casos filtrados. Se restauró con `git checkout`.

**Límite:**
- sólo se compara el contenido del CSV;
- el PDF se genera desde el mismo `ReportTable`, que cubre `report_composer_test`, pero su texto no se extrae aquí.

## Ejecución local (2026-10-19)

| Comando | Resultado |
|---|---|
| `flutter test test/rec_008_invoice_viewer_test.dart` | `+6: All tests passed!` |
| `flutter test test/rec_015_logbook_profile_test.dart` | `+12: All tests passed!` (con `82d02fc`) |
| `flutter test test/rec_016_export_coherence_test.dart` | `+8: All tests passed!` |
| `flutter test test/hierarchical_navigation_test.dart` | `+11: All tests passed!` |
| `dart format --set-exit-if-changed lib test` y `flutter analyze` | sin cambios, sin incidencias |

Por la memoria del PC, la suite completa no se corrió en local: corre en el CI del PR.
