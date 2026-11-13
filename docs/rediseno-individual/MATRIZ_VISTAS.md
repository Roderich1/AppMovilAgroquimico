# Matriz de vistas — modo individual

Láminas: `ProyectoAgro/_artefactos/modo_individual/laminas/I-NN.png`. Cada sesión completa **Prueba** y **Captura** al entregar; el ORQ marca la revisión. «Estado»: Pendiente → Entregada → Revisada (ORQ) → (aceptación visual: sólo el autor; no se registra aquí automáticamente).

| Lámina | Ruta / componente | Comportamiento en modo individual | Resp. | Prueba | Captura | Estado |
|---|---|---|---|---|---|---|
| I-01 Inicio | `/` `DashboardScreen` | Costo aplicado (campaña), Compras (campaña), Debe a proveedores (todas las campañas); sin cobros/pagos de personas; Planes, Ver cuánto queda, Sindicato (→ `/sindicato`); avisos | ORQ | `ind_orq_test` | `orq/o01_*`, `emulador/e29`, `e40`, `e52` | Revisada ORQ + emulador |
| I-02 Inicio sin datos | `/` | Sin cifras en cero; pasos: chaco, compra, aplicación | ORQ | `ind_orq_test` | `orq/o02_*`, `emulador/e07` | Revisada ORQ + emulador |
| I-03 Registrar (hoja) | `register_sheet.dart` | Compra, Aplicación, Plan, Pago a un proveedor; sin transferencia ni cobro a personas | ORQ | `ind_orq_test` (ambos modos) | `orq/o03_*`, `emulador/e16` | Revisada ORQ + emulador |
| I-04 Actividad | `/operaciones` `OperationsScreen` | Operaciones del titular sin repetir su nombre; detalle, anulación y corrección permitidas | B | `ind_b_almacen_actividad_test` | `b/i04_*`, `emulador/e15` | Revisada ORQ + emulador |
| I-05 Proveedores y saldo | ruta a definir por B (desde Actividad/Inicio) | Compras, pagos y saldo por proveedor; deuda real siempre visible | B | `ind_b_almacen_actividad_test` (pago → `provider_payments`, sin `account_transactions`) | `b/i05_*`, `emulador/e17`, `e19` | Revisada ORQ + emulador (pago parcial 1.000 Bs) |
| I-10 Compra paso 1 | `/compras/nueva` `PurchaseFormScreen` | Sin «¿Para quién es?» ni selector de persona; proveedor, fecha, campaña, moneda/TC | A | `ind_a_modo_individual_test` | `a/I-10_*`, `emulador/e10`, `e12` | Revisada ORQ + emulador |
| I-11 Compra producto (hoja) | hoja de producto | Pantalla anterior atenuada, mismo borrador; cantidad, unidad, precio, subtotal, vencimiento, n.º de envase opcional | A | `ind_a_modo_individual_test`, `rdm2_a_hoja_compra_test` | `a/I-11*`, `emulador/e11*` | Revisada ORQ + emulador (teclado, añadir otro, L y KG) |
| I-12 Compra revisión | revisión | Múltiples productos, pago/saldo con proveedor, comprobante; doble toque no duplica | A | `ind_a_modo_individual_test` (doble toque = 1 compra) | `a/I-12*`, `emulador/e13`, `e14`, `e46` | Revisada ORQ + emulador (doble toque, crédito, contado sin conexión) |
| I-13 Voz escuchando | `VoiceFormPanel` | Sin transcripción; Cancelar | A | `ind_a_modo_individual_test` (motor falso) | `a/I-13*`, `emulador/e49`, `e50` | Revisada ORQ + emulador (sin audio real) |
| I-14 Voz procesando | `VoiceFormPanel` | Procesando; cancelar descarta resultados tardíos | A | `ind_a_modo_individual_test` (cancelación y resultado tardío) | `a/I-14*`, `emulador/e51` | Revisada ORQ (procesando sólo en arnés) |
| I-15 Voz revisar | revisión tras dictar | Dictar más, Deshacer último dictado; sin destinatarios; nombres no crean personas | A | `ind_a_modo_individual_test` (nombre dictado no crea persona) | `a/I-15_*` | Revisada ORQ (sólo arnés) |
| I-20 Aplicación formulario | `/aplicaciones/nueva` | Sin selector de persona ni «Quién aplicó»; chaco, fecha, superficie tratada, productos, dosis | A | `ind_a_modo_individual_test` | `a/I-20*`, `emulador/e21`, `e22*` | Revisada ORQ + emulador |
| I-21 Aplicación con teclado | idem | Teclado abierto sin tapar el campo ni la acción | A | — | `a/I-21_*`, `emulador/e21b` | Revisada ORQ + emulador |
| I-22 Aplicación revisión | idem | Consumo y costo propios según reglas actuales | A | `ind_a_modo_individual_test` (26 → 24 L) | `a/I-22_*`, `emulador/e23`, `e25` | Revisada ORQ + emulador (12 → 10 L, 236 Bs) |
| I-23 Plan formulario | `/planificacion/nueva` | Plan sin descontar existencias ni generar deuda | A | `ind_a_modo_individual_test` | `a/I-23*`, `emulador/e26*` | Revisada ORQ + emulador |
| I-24 Plan revisión | idem | «Previsto en planes», no reserva | A | `ind_a_modo_individual_test` (sin movimientos ni pagos) | `a/I-24_*`, `emulador/e27`, `e28` | Revisada ORQ + emulador (stock sin cambio, «Previsto en planes 3 KG») |
| I-30 Almacén | `/inventario` `InventoryScreen` | Existencias propias, sin filtro por persona ni «Quién lo tiene»; planes como previsión | B | `ind_b_almacen_actividad_test` | `b/i30_*`, `emulador/e20`, `e25`, `e48` | Revisada ORQ + emulador |
| I-31 Almacén detalle | `/inventario/:id` | Lotes, movimientos, vencimientos, valoración, avisos; sin transferir | B | `ind_b_almacen_actividad_test` | `b/i31_*` | Revisada ORQ (sólo arnés) |
| I-32 Almacén vacío | `/inventario` | Estado vacío con acceso a Compra | B | `ind_b_almacen_actividad_test` | `b/i32_*` | Revisada ORQ (sólo arnés) |
| I-33 Almacén letra ampliada | `/inventario` a 200 % | Nombres largos sin cortes ni desbordes | B | — | `b/*_x20`, `emulador/e42_almacen_x20` | Revisada ORQ + emulador 200 % |
| I-40 Chacos | `/chacos` `ChacosScreen` | Chacos del titular, crear/editar permitidos | C | `ind_c_chacos_ui_test` | `c/i40_*`, `emulador/e09`, `e30`, `e45` | Revisada ORQ + emulador |
| I-41 Chaco detalle | `/chacos/:id` | Superficie, aplicaciones, planes, productos usados, costos con campaña | C | `ind_c_chacos_reads_test`, `ind_c_chacos_ui_test` | `c/i41*`, `emulador/e31` | Revisada ORQ + emulador (78,67 Bs/ha sobre 3 ha) |
| I-42 Chacos costos | a definir por C | Costos por campaña, chaco y producto; Bs/ha sólo con denominador real, si no «No disponible»; Excel/PDF | C | `ind_c_chacos_reads_test` (= `farmCostReport`) | `c/i42*`, `emulador/e32` | Revisada ORQ + emulador |
| I-43 Sin chacos | `/chacos` | Estado vacío | C | `ind_c_chacos_ui_test` (crea el primero con el titular) | `c/i43_*`, `emulador/e08` | Revisada ORQ + emulador |
| I-50 Ajustes y datos | `/mas` `MoreScreen` | Modo actual y titular; datos, cuenta, PIN, respaldos, ayuda, licencias | ORQ | `ind_orq_test` | `orq/o50_*`, `emulador/e34` | Revisada ORQ + emulador |
| I-51 Modo: cambio disponible | `/modo` `OperationModeScreen` | Condiciones reales (`evaluateModeTransition`); confirmación | ORQ | `ind_orq_test`, `operation_mode_*_test` | `orq/o51_*`, `emulador/e35`–`e40` | Revisada ORQ + emulador (ida y vuelta sin pérdida) |
| I-52 Modo: cambio bloqueado | `/modo` | Motivos reales (personas con stock, planes abiertos, saldos, sin titular) | ORQ | `ind_orq_test` (tablas sin cambios) | `orq/o52_*` | Revisada ORQ (sólo arnés: el emulador no tiene terceros) |
| I-53 Sin conexión (hoja) | Sindicato › estado de conexión | Presentación de pendientes con estados existentes; nada se envía al abrir | ORQ (coordinado con `cb`) | — | `orq/o53_*` | Revisada ORQ (sólo estado vacío; sin envíos reales) |

Capturas: `docs/evidence/rediseno-individual/2026-11-13/<orq|a|b|c>/` (sufijos `_x13`, `_x20` = letra 130/200 %; `_w900` = 900 dp).

## Diferencias intencionales (ORQ)

| Lámina | Lámina dice | App | Motivo |
|---|---|---|---|
| I-01 | «Sindicato · 1 convocatoria abierta» | «Sindicato» sin recuento | El único recuento disponible es el de convocatorias **no vistas** (`jointPurchaseNoticeProvider`, de `cb`); llamarlo «abiertas» sería falso. |
| I-01 | «Vencimientos y existencias · 2 avisos» | Igual, suma lotes vencidos/por vencer y productos con poca existencia | Los mismos avisos de «Avisos de inventario»; sin avisos, la fila no aparece. |
| I-01 | Cifras ilustrativas | Cifras reales de `campaignCloseSummary` y del saldo de compras | No se cambian fórmulas. |
| I-02 | Paso 1 siempre pendiente | Si ya hay chacos: «Sus chacos · N chacos» con ✓ | No se pide crear lo que ya existe. |
| I-03 | — | Sin «Completar por voz» en la hoja; nota de la lámina | La voz vive en cada formulario; `/voz` sigue existiendo. |
| I-50 | «Ayuda» | No aparece | La app no tiene pantalla de ayuda; no se inventa. |
| I-50 | «Verificada» | «Activada» | Es el estado local de activación; no hay verificación en línea al abrir Ajustes. |
| I-53 | «Sin conexión» | «Pendientes de envío» / «Envíos por revisar» / «Sin pendientes»; el último aviso del envío si lo hay | La app no sondea la red; el aviso del intento sí dice si no hubo conexión. «Enviar ahora» queda disponible. Participaciones en convocatorias no se listan aquí (son de `cb`). |

## Diferencias intencionales de A, B y C

Detalle en `estado/A.md`, `estado/B.md`, `estado/C.md`. Resumen: hoja de producto con «Listo/Añadir otro» (no «Guardar»); n.º de envase plegado; sin forma de onda de voz (no hay nivel de audio real); Actividad sin campaña en la cabecera (no filtra por campaña); Almacén sin «Entró hoy»; detalle sin «Vínculo con el sindicato» (reservado a `cb`); Chacos con pestañas «Chacos · Productos · Campañas»; «Falta la superficie» sólo como protección (el esquema exige `area_m2 > 0`).
