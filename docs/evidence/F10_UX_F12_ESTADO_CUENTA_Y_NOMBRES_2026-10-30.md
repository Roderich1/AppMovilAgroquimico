# F-1 y F-2 · estado de cuenta y nombres legibles en teléfono (2026-10-30)

| | |
|---|---|
| Origen | Hallazgos F-1 y F-2 de `F10_UX_C1_EMULADOR_2026-10-30.md` §5 (comprobación de C1 en el emulador). Corrección pedida por Roderich el 2026-10-30, como PR aparte de C1 |
| Rama | `fix/ux-estado-cuenta-y-nombres` desde Mobile `main` `7ce98c8` (merge de #162) |
| Código | `00daa8869d11c5dda436f5a785277e41e30cdb02` (corrección y pruebas) · `729ff6b` (documentos) · este archivo en el commit que lo añade |
| Fecha real | 2026-10-30 |
| Dónde se observó | **HOST** = pruebas de widget en el PC (fuente de pruebas `FlutterTest`, 1 em por glifo). **EMULADOR** = Pixel_8 API 34 x86_64 (`emulator-5554`), paquete aislado `com.comunidad.agro.agroquimicos.uxc1` («AC UX-C1») actualizado con `adb install -r` a la APK profile x86_64 de `00daa88` (SHA-256 `694da34517efb20d9e9993578624c77584d855e69e04c74b0dee4e54b098efdf`), con los datos sintéticos de la comprobación de C1; y paquete nuevo `…uxc2` («AC UX-P», SHA-256 `7ecaafb23c5cda8a4b814bd428bb63806230ca09f53c9762f0c629da5d440bf3`) para la modalidad propia (§4). Ningún teléfono ni persona |

## 1. Qué fallaba y qué cambia

| Id | Antes | Ahora | Archivo |
|---|---|---|---|
| **F-1** | En «Estado de cuenta» el importe y el acumulado iban en una columna lateral fija de 140 px; en un teléfono de 411 dp al concepto le quedaban ~55 px y se partía por carácter («Adelant / o») | `MovementTile`: con menos de 480 px de contenido, el importe y «Acumulado» van debajo del concepto, a lo ancho de la fila; con más, la columna lateral de siempre. El diálogo deja 16 px de margen lateral (antes 40). Igual en «Movimientos propios» | `lib/presentation/widgets/account_statement_view.dart`, `settlements_screen.dart` (`_statementInsets`) |
| **F-2** | En la tarjeta de persona de Cuentas el nombre compartía el ancho con la columna del importe (`flex` 5/4), con `maxLines: 2` y puntos suspensivos («Don Carlos Gutiérrez Villarr…»); el importe se encogía con `FittedBox` | El nombre ocupa su fila entera, sin recorte, con el menú ⋮ al lado; `_AccountFigures` pone las líneas contables y el importe lado a lado si hay ≥ 420 px o apilados en teléfono. Sin `FittedBox`: el importe sigue la escala del sistema | `lib/presentation/screens/settlements_screen.dart` |

No cambian importes, signos, fechas, tipos históricos, imputaciones ni acciones; nada de contabilidad, esquema, sincronización, permisos ni reglas. Los textos son los mismos de D-04/E-15.

## 2. HOST · reproducción y pruebas de widget

`test/ux_f12_estado_cuenta_y_nombres_test.dart` (repositorio real sobre base en memoria; la persona es un tercero con nombre de 31 caracteres, un cargo por compra y un adelanto histórico de 20 Bs; para F-2 un cargo de 1.350.000,00 Bs).

**Reproducción sobre el código anterior** (`7ce98c8`, `flutter test test/ux_f12_estado_cuenta_y_nombres_test.dart`, 2026-10-30, 6 de 7 fallan):

- F-1 a 411 dp y a 360 dp ×1,3: «una línea parte una palabra en «05/01/2026 · Cargo por compra · Verano 2026 …» (posición 8)».
- F-2 a 411, 360 ×1,3 y 320 ×2,0: «Expected: not TextOverflow.ellipsis · Actual: TextOverflow.ellipsis».
- La única que pasaba era la de pantalla ancha (la columna lateral ya existía).

**Con la corrección** (`00daa88`): `00:05 +7: All tests passed!`. Qué comprueba cada caso:

| Caso | Tamaños | Comprobación |
|---|---|---|
| F-1 «el concepto, la fecha y el importe se leen enteros» | 411 ×1,0 · 360 ×1,3 · 320 ×2,0 | Abre el diálogo desde el menú de la tarjeta; desplaza el cronológico; la fila del cargo y la del adelanto se leen con `getLineBoundary`: ninguna línea parte una palabra (se tolera sólo una palabra más ancha que el párrafo entero, que es el caso de la fuente de pruebas a ×2,0); importes `+45,00 Bs`, `-20,00 Bs` y los dos «Acumulado» presentes, sin `ellipsis`, con todas sus líneas pintadas; `ADVANCE −2000` leído de `account_transactions` |
| F-1 «en pantalla ancha el importe conserva su columna lateral» | 1024 | El `ListTile` conserva `trailing` y el concepto va en una línea |
| F-2 «el nombre se lee completo y el importe no se reduce» | 411 ×1,0 · 360 ×1,3 · 320 ×2,0 | El `Text` del nombre no tiene `ellipsis`, pinta todas las líneas que necesita y no parte palabras; el importe mostrado es `formatBob` del `netMinor` real del ledger (> 1.000.000,00 Bs), sin `FittedBox` en la tarjeta y con `textScaler` igual a la escala pedida; el menú ⋮ sigue en la tarjeta |

**Pruebas relacionadas** (`flutter test` de `ux_c1_correcciones_test`, `payment_dialog_test`, `e15_consumo_propio_base_test`, `personal_mode_flows_test`, `regression_widget_test`, sobre `00daa88`): `00:50 +61: All tests passed!`. En una pasada anterior con los nueve archivos (`d04_imputacion_ledger_test`, `rec_015_logbook_profile_test`, `report_composer_test` incluidos): 142 en verde y 4 fallos de la prueba nueva que después se corrigieron en la propia prueba (altura de pantalla y tolerancia de la fuente de pruebas), no en el código. `dart format` y `flutter analyze` limpios.

**Límite de HOST:** la fuente de pruebas mide 1 em por glifo (el doble que Roboto): a 320 dp y ×2,0 «Adelanto» no cabe en una línea en HOST pero sí con la fuente real; por eso la lectura con la fuente real se hace en el EMULADOR.

## 3. EMULADOR · «AC UX-C1» (.uxc1, conjunto compartido)

Datos: los del conjunto compartido de C1 (titular Rosa Mamani Quispe de Condori; María Fernanda Quispe Mamani, familiar, con adelanto histórico de 20 Bs del 08/10 y cargo por consumo de 22,50 Bs; Don Carlos Gutiérrez Villarroel, tercero, con cargo por compra de 45 Bs, pagos de 30 y 50 Bs y 35 Bs a favor). Copia de la base antes de empezar (`f12_before`) y al terminar (`f12_after`, `f12_after2`, `f12_after3`): **SHA-256 idéntico `ebd8eb22eb7d76aa744b6db639d223d6810c3496560b504f72cdce913e2be17e`**, el mismo con el que terminó la comprobación de C1: consultar no escribió nada. Guarda de primer plano (`topResumedActivity` = `.uxc1`) antes de cada acción; `font_scale` 1.0 y `wm size reset` restaurados al final. Capturas (reducidas a 540 px) en `docs/evidence/img/ux_f12/`.

| Comprobación | 411 dp ×1,0 | 360 dp ×1,3 | 320 dp ×2,0 |
|---|---|---|---|
| **F-2 · tarjeta de Don Carlos** (31 caracteres) y de María (28) | Nombre en una línea, entero, con el ⋮ a su derecha; líneas contables y «Deuda pendiente por origen · Verano 2026» con el importe «0,00 Bs» / «22,50 Bs» a tamaño completo, apilados debajo (`f12_411_cuentas_carlos`) | Nombre en dos líneas enteras; importe a tamaño completo (`f12_360x13_cuentas_carlos`) | «Don Carlos / Gutiérrez / Villarroel» en tres líneas, sin puntos suspensivos, importe a tamaño completo; el FAB «Nuevo» sigue tapando parte de la tarjeta de abajo (F-3, se retira con el rediseño) (`f12_320x20_cuentas_carlos`) |
| **F-1 · «Estado de cuenta» de Don Carlos** | Filas «Glifosato Demo · 12/10/2026 · Cargo por compra · Verano 2026 · Pagado · +45,00 Bs · Acumulado 45,00 Bs», «Pago · 30/10/2026 · … Imputado: Verano 2026 30,00 Bs · −30,00 Bs · Acumulado 15,00 Bs», «Pago … 15,00 Bs · sin imputar 35,00 Bs (queda a favor, sin campaña) · −50,00 Bs · Acumulado −35,00 Bs», «Saldo a hoy −35,00 Bs»: importe y acumulado debajo del concepto, ninguna palabra partida (`f12_411_estado_carlos_a/b`) | Igual, con el importe y el acumulado en dos líneas; las palabras enteras (`f12_360x13_estado_carlos_a/b`) | Igual; la cabecera «Deuda pendiente por origen (a hoy)» y las filas se leen enteras desplazando (`f12_320x20_estado_carlos_a/b`) |
| **F-1 · «Estado de cuenta» de María** (adelanto histórico, el caso de la captura 17 de C1) | «Adelanto · 08/10/2026 · Adelanto · registrado en Verano 2026 · Sin imputación registrada: 20,00 Bs (queda a favor, sin campaña) · −20,00 Bs · Acumulado −20,00 Bs» y el cargo por consumo de 22,50 Bs con «Pendiente a hoy 22,50 Bs»; «Saldo a hoy 2,50 Bs» (`f12_411_estado_maria_a/b`) | Igual (`f12_360x13_estado_maria_a/b`) | Igual (`f12_320x20_estado_maria_a/b`) |
| **«Movimientos propios» del titular** (misma fila, E-15) | «Glifosato Demo · 25/10/2026 · Cargo por consumo · Chaco Norte · Verano 2026 · +45,00 Bs» con el importe debajo (`f12_411_movimientos_propios_a`) | Igual (`f12_360x13_movimientos_propios_a`) | Igual (`f12_320x20_movimientos_propios_a`) |

Lo mostrado coincide con lo guardado en la copia `f12_before` (mismos importes, signos, fechas, tipos «Adelanto»/«Cargo por compra»/«Cargo por consumo»/«Pago» e imputaciones que en la comprobación de C1, §3 y §4 de `F10_UX_C1_EMULADOR_2026-10-30.md`).

**Incidencias del arnés (no de la app):** el guion automático falló varias veces al localizar el ⋮ de la tarjeta (el volcado de uiautomator entrega la fila del nombre y el botón a la misma altura; el primer localizador buscaba «la siguiente línea»), y un guion de una pasada anterior siguió vivo tras detener su tarea y pisó al siguiente; se mataron todos los procesos propios y el resto se hizo paso a paso. Al detener `.uxc1`, el paquete EXP-D (de Roderich, con su diálogo «no responde») volvió a quedar en primer plano: la guarda abortó la acción («ABORTADO: el primer plano no es …uxc1») y no se tocó EXP-D; se relanzó `.uxc1` y se continuó sólo cuando volvió a estar delante. Dos pares de capturas `a/b` salieron iguales porque el diálogo ya estaba desplazado al tomar la primera.

## 4. EMULADOR · modalidad propia en «AC UX-P» (.uxc2, instalación nueva y aislada)

Instalación nueva del paquete `…uxc2` («AC UX-P», APK de `00daa88`), cuenta sintética `u2-ux@agrocuentas.example.test` creada en el Central propio para este fin (`ux_central_user.cjs`; contraseña inutilizable, activación con una de un solo uso tecleada por adb y no mostrada), activada por la interfaz: «Activar en línea», «Crear el titular» («Don Carlos Gutierrez Villarroel», sin tilde: `adb shell input text` no teclea caracteres no ASCII), modalidad **«Propio»**, «Confirmar titular» («Titular vinculado. Usa inventario propio; puede cambiarlo en Operaciones › Más › Modo de uso.»), PIN creado en la oferta de la activación con el PIN que vivió sólo en la memoria del holder y se descartó al terminar. El conjunto compartido de `.uxc1` no se tocó ni cambió de modalidad (su base conserva el hash `ebd8eb22…`).

Siembra sobre la copia bajada (`tool/ux/seed_ux_propio.dart`, por `AgroRepository`): chaco «Chaco Norte de la Loma Alta» (1,2 ha), proveedor de 51 caracteres, compras F-2029 (Glifosato 4 L a 45 Bs y Mancozeb 2 kg a 6,50 US$ con tipo de cambio 6,96; pago parcial de 100 Bs en efectivo) y F-2040 (Glifosato 20 L, 900 Bs), aplicación propia de 1,5 L (25/10) y pago propio de 50 Bs (26/10). `integrity_check ok`; base sembrada `f41d621cba06b3791c36a295af132689f192e305b53466aa79b52245f6fee8eb` (PC y emulador iguales). Copia `p_before` y `p_after`: **hash idéntico `f41d621c…`**, consultar no escribió nada.

| Comprobación | Qué se vio | Coincide con lo guardado | Captura |
|---|---|---|---|
| Inicio en PROPIA | «Compras 1.170,48 Bs», «Pagado proveedores 100,00 Bs», «Familias por cobrar 0,00 Bs», «Terceros por cobrar 0,00 Bs» | 270,48 + 900,00 = 1.170,48; pago 100 | `p_411_inicio` es la pantalla de arranque (el volcado llegó antes que la interfaz); el texto consta en el volcado del arnés |
| Cuentas: tarjeta del titular (F-2 en PROPIA) | «Consumo y costos propios · Don Carlos Gutierrez Villarroel · Consumo aplicado (costo FIFO) · Verano 2026 67,50 Bs · 1 aplicación vigente · Asientos … cargos anotados 67,50 Bs · … pagos y ajustes registrados 50,00 Bs» y «En inventario propio no hay cuentas por cobrar.» | 1,5 L × 45 = 67,50; pago propio 50 | `p_411_cuentas`, `p_320x20_cuentas` |
| Menú del titular (A1 en PROPIA) | Sólo «Ver movimientos propios», «Exportar movimientos propios» y «Registrar pago» | — | `p_411_menu_titular` |
| «Registrar pago» propio (A4 en PROPIA) | «Pago propio: se registra aparte y no es un cobro ni una deuda.», campo **vacío** con sufijo «Bs», «Cancelar» / «Registrar» (se canceló) | — | `p_411_dialogo_pago_propio` |
| «Movimientos propios» (F-1, variante propia) | «Consumo aplicado (costo FIFO) · Verano 2026: 67,50 Bs (1 aplicación)»; filas «Glifosato Demo · 25/10/2026 · Cargo por consumo · Chaco Norte de la Loma Alta · Verano 2026 · +67,50 Bs» y «Pago · 26/10/2026 · Pago · registrado en Verano 2026 · Imputado: Verano 2026 50,00 Bs · −50,00 Bs», importe debajo del concepto, palabras enteras, también a 320 dp ×2,0 | aplicación 1,5 L; pago 50 | `p_411_movimientos_propios_a`, `p_320x20_movimientos_propios_a/b` |
| Detalle de compra F-2029 (A2 en PROPIA) | «Detalle de compra», «Confirmada», «2 productos · Glifosato Demo · 4 L · Precio: 45,00 Bs por L · Subtotal: 180,00 Bs · Para Don Carlos Gutierrez Villarroel …»; lista con «F-2040 · 1 producto · Total 900,00 Bs» y «F-2029 · 2 productos · Total 270,48 Bs» | totales 900,00 y 270,48 | `p_411_detalle_compra_a` |
| Modo de uso | «Modalidad actual: inventario propio», «Cambiar a inventario compartido» (no se tocó) | — | `p_411_modo` |

## 5. Limitaciones declaradas

- **Teclado:** la comprobación con teclado en pantalla sigue **parcial**: el emulador tiene `hw.keyboard=yes` y no muestra las teclas; no se reinició porque comparte con los paquetes EXP de Roderich. Las pruebas de widget con `viewInsets` no equivalen a esa ejecución.
- **Fuente de pruebas (HOST):** mide el doble que Roboto; por eso las aserciones toleran una palabra más ancha que el párrafo y la lectura real se hizo en el EMULADOR (§3 y §4).
- **Nombre con tilde en PROPIA:** el titular de `.uxc2` se creó sin tilde por el límite de `adb shell input text`; los nombres con tilde (María, Don Carlos Gutiérrez) se comprobaron en `.uxc1`.
- **Importe de millones:** sólo en HOST (F-2, 1.350.000,00 Bs). En el emulador el importe mayor fue 900,00 Bs (compra) y 22,50 / 35,00 Bs en tarjetas.
- **Pantalla ancha:** la columna lateral del importe (≥ 480 px) sólo se comprobó en HOST (1024 px); no se usó tableta.
- **F-3 (FAB «Nuevo» tapando la tarjeta de abajo) y F-4 (etiquetas de pestañas reducidas)** siguen visibles en las capturas y quedan para el rediseño de la navegación, como decidió Roderich.
- No se probó con personas ni en un teléfono físico; nada de lo anterior es evaluación humana.
