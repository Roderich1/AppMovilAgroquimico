# Bloque de experiencia C1: cuatro correcciones (A1–A4), evidencia

- **Fecha real:** 2026-10-30 (America/La_Paz).
- **Rama:** `fix/ux-cuentas-compras-transferencias`.
- **Base:** Mobile `main` `186f4739b62245c5a91040e3eb0149a8888bb635`.
- **Commit verificado:** `94b9fde45b283a2d9f3fdaa14b85648ff9d57b96`.
- **Herramientas:** Flutter 3.47.2 (stable, `d3b14c8769`), Windows 11, pruebas en el ordenador con SQLite FFI.
- **Procedencia:** sólo **código y pruebas en el ordenador**.
  - **Emulador:** no se ejecutó. Una instalación nueva tiene que activarse contra un Central por HTTPS, y el único túnel autorizado es el del entorno de exploración de Roderich; activarla ahí lo modificaría.
  - **Teléfono físico:** no se usó.
  - **Personas:** no participó ninguna.
- **Lo que no cambia:** FIFO, la contabilidad (RN-36 a RN-40), la imputación entre campañas (D-04), la sincronización, los permisos y el cifrado. El esquema de la base no cambia y no se añade ninguna escritura.

## 1. Qué se corrigió

| Id | Defecto | Corrección | Archivos |
|---|---|---|---|
| A1 | Cuentas ofrecía «Registrar pago» y «Registrar adelanto», dos accesos con la misma mecánica (RN-39) | Un único «Registrar pago» en las tarjetas de persona y del titular. Lo nuevo se guarda como `PAYMENT`. El diálogo añade «Si no hay deuda, el pago queda a favor (como un adelanto).», salvo en el pago propio del titular, que no es un cobro (E-15) Los `ADVANCE` guardados se conservan y se leen como «Adelanto». `registerAccountPayment(advance:)` se mantiene en el repositorio | `settlements_screen.dart`, `account_texts.dart` |
| A2 | La tarjeta de una compra no se podía tocar y no había detalle | La tarjeta abre `/compras/detalle/:id`, un detalle **de sólo lectura** que funciona también con compras revertidas. Muestra lo guardado y nada más (§3) | `purchase_detail_screen.dart` (nuevo), `purchases_screen.dart`, `agro_repository.dart` (`purchaseDetail`: 4 SELECT), `app.dart`, `labels.dart`, `money.dart` |
| A3 | Tras revertir una transferencia, el texto del actor iba en el lateral y desbordaba la fila | «Revertida», el resumen y el actor van en el cuerpo de la fila, con todo el ancho. El lateral queda para la flecha. La auditoría se conserva completa: quién, cómo y el motivo | `transfers_screen.dart` |
| A4 | El campo del importe traía el ejemplo «1.500,25», que parecía un valor | Campo vacío, etiqueta «Importe del pago» y sufijo «Bs». La validación numérica (`parseNumericInput`) es la misma | `settlements_screen.dart` |
| E-1 (nuevo) | El selector «Filtrar por campaña» de Cuentas se desbordaba 77 px a 360 dp con letra ×1,3 | `isExpanded: true`: ocupa el ancho del campo y no se reduce la letra | `settlements_screen.dart` |
| E-2 (nuevo) | El diálogo «Registrar pago» con el teclado abierto se desbordaba: 133 px a ×1,3 y 684 px a ×2,0, en 360×640 | `AlertDialog(scrollable: true)`: el contenido se desplaza y «Registrar» queda a la vista | `settlements_screen.dart` |

E-1 y E-2 ya existían en `186f473`. Los encontraron las pruebas de teclado y letra ampliada que pide el encargo (§E).

## 2. Diferencias funcionales de PAYMENT y ADVANCE (A1)

**Consumidores revisados** (`grep` de `ADVANCE`, `'PAYMENT'` y `advance` en `lib/`, sin contar `voice_draft`):

| Consumidor | Qué hace con el tipo |
|---|---|
| `agro_repository.dart` `registerAccountPayment` | Escribe `type` y `reference_type`. La imputación no depende del tipo |
| `account_ledger.dart` `receivedMinor` | Suma los dos tipos |
| `account_texts.dart` `AccountPaymentResult.message` | Escribe «Pago» o «Adelanto» en el mensaje de éxito |
| `labels.dart` `transactionTypeLabel` | Rótulo del historial y de las exportaciones |
| `voice_draft/interpretation/voice_intent.dart` | «adelanto» sólo marca la frase como no admitida (F09, en pausa) |

**Lo que no depende del tipo:** el libro D-04 clasifica los asientos por clase (RN-37), no por tipo. El criterio Q-1, «el crédito sin imputar queda separado», se aplica igual a los dos. **No hay diferencia funcional real:** sólo cambian el rótulo histórico y la palabra del mensaje.

**Prueba de equivalencia:** *«mismas imputaciones, saldos y totales; sólo cambia el tipo»*. Usa un cargo previo de un tercero y un pago de 30 Bs, y compara las `payment_allocations`, lo imputado, lo no imputado, el neto, «Pagos recibidos» y la deuda pendiente de la campaña. Los dos tipos dan exactamente lo mismo.

## 3. Qué muestra el detalle de compra (A2)

Todo sale de filas guardadas. Un campo vacío se omite y no se rellena.
- **Cabecera:**
  - proveedor y estado;
  - factura («Sin número» si falta);
  - fecha y campaña;
  - total y lo pagado (sin los pagos revertidos);
  - origen y nota del tipo de cambio, y notas, si están guardados;
  - «Revertida el» y quién lo autorizó, con su motivo (`ReversalActorText`);
  - «Ver foto de la factura», si hay foto.
- **Por línea:**
  - producto y cantidad;
  - precio guardado: en bolivianos, o en dólares con el tipo de cambio y el equivalente en Bs de `converted_unit_price_bob_minor`;
  - subtotal;
  - «Para X: cantidad · cómo se cobra», según `charge_policy_snapshot` y `amount_bob_minor_if_allocation_charge`.
- **Pagos al proveedor:** fecha, medio, pagador, importe y «(revertido el …)».
- **Lo que no muestra:** los lotes ni su costo unitario (A-08); las acciones que escriben, que siguen en el menú ⋮ de la tarjeta.

## 4. Reproducción y regresiones

**Pruebas nuevas:**
- `test/ux_c1_correcciones_test.dart` (10 casos);
- `test/ux_c1_detalle_compra_test.dart` (6 casos).

**Pruebas ajustadas porque fijaban «Registrar adelanto»:**
- `test/payment_dialog_test.dart` (el caso del adelanto ahora comprueba que el menú ya no lo ofrece y que el histórico se conserva);
- `test/e15_consumo_propio_base_test.dart`;
- `test/personal_mode_flows_test.dart`.

### 4.1 Antes, sobre `186f473`

```
git worktree add --detach _wt/A-UX-MOB-BASE 186f473   # worktree temporal, ya retirado
cp test/ux_c1_correcciones_test.dart <base>/test/
flutter test test/ux_c1_correcciones_test.dart -r expanded
→ +2 -8: Some tests failed.
```

| Caso | Resultado en `186f473` |
|---|---|
| A1, menú de la persona y del titular | FALLA: «Expected: not contains 'Registrar adelanto'» |
| A1, «Registrar pago» escribe PAYMENT y el adelanto histórico se lee «Adelanto» | pasa (es una prueba de conservación) |
| A1, RN-39 equivalencia | pasa (es una caracterización) |
| A4, campo vacío y sin ejemplo | FALLA: «Expected: null · Actual: '1.500,25'» (`hintText`) |
| A4, teclado en 360×640 a ×1,3 | FALLA: «overflowed by 77 pixels on the right» (selector, E-1) y «by 133 pixels on the bottom» (diálogo, E-2) |
| A4, teclado en 360×640 a ×2,0 | FALLA: desborde de 279 px a la derecha, y de 684 px y 17 px por abajo |
| A2, la tarjeta abre el detalle y no escribe nada | FALLA: no abre ninguna ruta |
| A3 a 360 dp, ×1,0 / ×1,3 / ×2,0 | FALLA: «overflowed by 72 / 175 / 392 pixels on the bottom» |

### 4.2 Después, sobre `94b9fde`

```
flutter test test/ux_c1_correcciones_test.dart       → +10: All tests passed!
flutter test test/ux_c1_detalle_compra_test.dart     → +6: All tests passed!
flutter analyze                                      → No issues found!
dart format --output=none --set-exit-if-changed lib test → 0 changed
flutter test (suite completa)                        → +2094 ~3: All tests passed!
```

**Una ejecución anterior de la suite completa** tuvo 5 fallos. Ninguno fue un defecto:
- 2 eran de las pruebas de teclado recién añadidas, que encontraron E-1 y E-2;
- 3 eran de restauración y descompresión, por haber lanzado otra ejecución en paralelo en el mismo worktree (`sqlite3.dll` bloqueado, tiempo agotado de 30 s).

Las tres de restauración y descompresión pasaron solas (`f04_admin_owner_restore_ui_test.dart` y `f10_backup_extract_limits_test.dart`: +35) y en la suite completa sin ejecuciones simultáneas.

## 5. Qué comprueban las regresiones

| Comprobación | Prueba |
|---|---|
| **Importes:** total, precio, subtotal, tipo de cambio, pagado y cargo por compra iguales a lo guardado (se leen de la base dentro de la prueba) | detalle, compra confirmada |
| **Destinatarios:** «Para Titular: 3 L · se cobra al aplicar» y «Para Don Carlos Gutiérrez: 1 L · cargo por compra …» | detalle, compra confirmada |
| **Cuentas y movimientos:** un pago nuevo es `PAYMENT −2000` y el `ADVANCE −5000` histórico se conserva | A1 |
| **Imputación:** PAYMENT y ADVANCE escriben las mismas `payment_allocations` | A1, RN-39 |
| **No se escribe al consultar:** volcado completo de todas las tablas antes y después de abrir el listado, los detalles, otro detalle, una compra inexistente y de reconstruir la pantalla | A2 y detalle |
| **Pantallas estrechas y letra:** 320 dp ×1,0; 360 dp ×1,3 y ×2,0, sin excepción de desborde. Sin `FittedBox` ni elipsis, y la escala pedida llega a cada texto | detalle, A3 |
| **Teclado:** 300 dp de teclado en 360×640, «Registrar» visible por encima del teclado y el error de formato completo | A4 |
| **Texto largo:** proveedor «Comercializadora Agroquímica del Valle Alto S.R.L.», persona «María Fernanda Quispe Mamani» y el motivo de la reversión largo | todas |

## 6. Revisión cruzada (2026-10-30)

Revisión de sólo lectura del diff `186f473..fd6f525` por una sesión distinta de la que escribió el código. **Veredicto: LISTO con observaciones**, ninguna bloqueante:
- confirma que `purchaseDetail` son cuatro `SELECT` sin transacción ni escritura, y que `registerAccountPayment(advance:)` se conserva;
- confirma que las pruebas no pasan de forma trivial (volcado de tablas, comparación de `payment_allocations`, igualdad exacta de textos leídos de la base);
- observaciones aplicadas en el commit siguiente: `docs/07_SCREENS.md` citaba `_viewInvoice` (ya `showInvoiceImage`); la frase del diálogo no aparece en el pago propio del titular (matizado arriba); `mainAxisSize.min` en la `Column` del subtítulo de Transferencias; el FAB global se oculta en el detalle de compra, que es de sólo lectura.

## 7. Limitaciones declaradas

- **Sin ejecución en emulador ni teléfono.** Los tiempos y la apariencia real con el teclado del sistema no se midieron.
- **El manual de usuario** (Backend `docs/manuals/F11_MANUAL_USUARIO.md` §4.1) todavía describe «Registrar adelanto» y el campo «Importe BOB». Se actualiza después de integrar este PR, para no describir un código que no está en `main`.
- **Instrumentos humanos sin tocar.** Las tarjetas T1–T6 y el guion de usabilidad no nombran el adelanto, el detalle de compra ni el actor de las transferencias.
