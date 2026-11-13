# Matriz de vistas — modo individual

Láminas: `ProyectoAgro/_artefactos/modo_individual/laminas/I-NN.png`. Cada sesión completa **Prueba** y **Captura** al entregar; el ORQ marca la revisión. «Estado»: Pendiente → Entregada → Revisada (ORQ) → (aceptación visual: sólo el autor; no se registra aquí automáticamente).

| Lámina | Ruta / componente | Comportamiento en modo individual | Resp. | Prueba | Captura | Estado |
|---|---|---|---|---|---|---|
| I-01 Inicio | `/` `DashboardScreen` | Costo aplicado (campaña), Compras (campaña), Debe a proveedores (todas las campañas); sin cobros/pagos de personas; Planes, Ver cuánto queda, Sindicato (→ `/sindicato`); avisos | ORQ | | | Pendiente |
| I-02 Inicio sin datos | `/` | Sin cifras en cero; pasos: chaco, compra, aplicación | ORQ | | | Pendiente |
| I-03 Registrar (hoja) | `register_sheet.dart` | Compra, Aplicación, Plan, Pago a un proveedor; sin transferencia ni cobro a personas | ORQ | | | Pendiente |
| I-04 Actividad | `/operaciones` `OperationsScreen` | Operaciones del titular sin repetir su nombre; detalle, anulación y corrección permitidas | B | | | Pendiente |
| I-05 Proveedores y saldo | ruta a definir por B (desde Actividad/Inicio) | Compras, pagos y saldo por proveedor; deuda real siempre visible | B | | | Pendiente |
| I-10 Compra paso 1 | `/compras/nueva` `PurchaseFormScreen` | Sin «¿Para quién es?» ni selector de persona; proveedor, fecha, campaña, moneda/TC | A | | | Pendiente |
| I-11 Compra producto (hoja) | hoja de producto | Pantalla anterior atenuada, mismo borrador; cantidad, unidad, precio, subtotal, vencimiento, n.º de envase opcional | A | | | Pendiente |
| I-12 Compra revisión | revisión | Múltiples productos, pago/saldo con proveedor, comprobante; doble toque no duplica | A | | | Pendiente |
| I-13 Voz escuchando | `VoiceFormPanel` | Sin transcripción; Cancelar | A | | | Pendiente |
| I-14 Voz procesando | `VoiceFormPanel` | Procesando; cancelar descarta resultados tardíos | A | | | Pendiente |
| I-15 Voz revisar | revisión tras dictar | Dictar más, Deshacer último dictado; sin destinatarios; nombres no crean personas | A | | | Pendiente |
| I-20 Aplicación formulario | `/aplicaciones/nueva` | Sin selector de persona ni «Quién aplicó»; chaco, fecha, superficie tratada, productos, dosis | A | | | Pendiente |
| I-21 Aplicación con teclado | idem | Teclado abierto sin tapar el campo ni la acción | A | | | Pendiente |
| I-22 Aplicación revisión | idem | Consumo y costo propios según reglas actuales | A | | | Pendiente |
| I-23 Plan formulario | `/planificacion/nueva` | Plan sin descontar existencias ni generar deuda | A | | | Pendiente |
| I-24 Plan revisión | idem | «Previsto en planes», no reserva | A | | | Pendiente |
| I-30 Almacén | `/inventario` `InventoryScreen` | Existencias propias, sin filtro por persona ni «Quién lo tiene»; planes como previsión | B | | | Pendiente |
| I-31 Almacén detalle | `/inventario/:id` | Lotes, movimientos, vencimientos, valoración, avisos; sin transferir | B | | | Pendiente |
| I-32 Almacén vacío | `/inventario` | Estado vacío con acceso a Compra | B | | | Pendiente |
| I-33 Almacén letra ampliada | `/inventario` a 200 % | Nombres largos sin cortes ni desbordes | B | | | Pendiente |
| I-40 Chacos | `/chacos` `ChacosScreen` | Chacos del titular, crear/editar permitidos | C | | | Pendiente |
| I-41 Chaco detalle | `/chacos/:id` | Superficie, aplicaciones, planes, productos usados, costos con campaña | C | | | Pendiente |
| I-42 Chacos costos | a definir por C | Costos por campaña, chaco y producto; Bs/ha sólo con denominador real, si no «No disponible»; Excel/PDF | C | | | Pendiente |
| I-43 Sin chacos | `/chacos` | Estado vacío | C | | | Pendiente |
| I-50 Ajustes y datos | `/mas` `MoreScreen` | Modo actual y titular; datos, cuenta, PIN, respaldos, ayuda, licencias | ORQ | | | Pendiente |
| I-51 Modo: cambio disponible | `/modo` `OperationModeScreen` | Condiciones reales (`evaluateModeTransition`); confirmación | ORQ | | | Pendiente |
| I-52 Modo: cambio bloqueado | `/modo` | Motivos reales (personas con stock, planes abiertos, saldos, sin titular) | ORQ | | | Pendiente |
| I-53 Sin conexión (hoja) | Sindicato › estado de conexión | Presentación de pendientes con estados existentes; nada se envía al abrir | ORQ (coordinado con `cb`) | | | Pendiente |
