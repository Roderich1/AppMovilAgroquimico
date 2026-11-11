# Capturas actuales de la aplicación móvil — 2026-11-11

**Conjunto vigente** para Claude Design. No reemplaza las evidencias anteriores (`docs/evidence/img/ux_c1/`, `docs/evidence/img/ux_f12/`, `docs/evidence/oe3_device*/`), que siguen describiendo sus fechas.

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-11, entre las 19:00Z y las 22:05Z (UTC) |
| Procedencia | **EMULADOR** Pixel_8 (`emulator-5554`), Android 16, API 36. **No es un teléfono físico.** |
| Código | Mobile `7257816` (rama `feat/etapa1-productos-identificacion-foto`: UXJ + F09 formulario único con voz + etapa 1); desde la 32, con `bce8e59` (dos correcciones de etapa 1); 55–66 con `6bac5a3` (etapa 2, convocatorias, rama `feat/etapa2-convocatorias`). Esas ramas **no** están publicadas: esta rama sólo contiene imágenes y este índice. |
| Paquete instalado | `com.comunidad.agro.agroquimicos.et1` («AC ET1»), `versionName` 1.0.0, `versionCode` 1, APK *profile* x86_64. La app normal y la DEMO no se tocaron. |
| Pantalla | 1080 × 2400 px, densidad 420 dpi, escala de texto 1.0. Barra de estado del emulador en hora UTC. |
| Central | Copia aislada de etapa 1 (PostgreSQL y API locales, accesibles por un túnel HTTPS temporal que sólo dejaba pasar `/api/v1/`). Ni la DEMO oficial ni datos reales. |
| Datos | Exclusivamente sintéticos: cuenta `agricultor15.demo@example.test` (Central sembrada con la herramienta «rica»); en el teléfono, titular «Rosa Vargas sintetica» y la siembra local DEMO (Beto Mamani (DEMO), Carmen Choque (DEMO, tercera), Agroinsumos DEMO (sintético), Chaco Norte/Río DEMO, campaña Invierno 2026 (DEMO), Herbicida/Fungicida/Insecticida DEMO, tres compras, dos aplicaciones). Producto local «Abono foliar casero» con una etiqueta inventada creada para esta prueba. |
| Voz | Las tres pantallas de voz muestran el panel **en reposo** («Listo para dictar»). No se grabó audio, no se usó audio sintético ni se inyectaron transcripciones: **no** son una evaluación de precisión ni muestran campos completados por voz. |

## Acceso y ajustes

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="00_acceso_titular.png" width="150" alt="Titular de los datos y modalidad de inventario (primera activación)">](00_acceso_titular.png) | Titular de los datos y modalidad de inventario (primera activación) | Activar en línea → cuenta sintética → Titular de los datos | `7257816` |  |
| [<img src="31_volver_a_autenticar.png" width="150" alt="Volver a autenticar">](31_volver_a_autenticar.png) | Volver a autenticar | Inicio → «Volver a autenticar» (sesión vencida tras cerrar la app) | `7257816` | Correo sintético; contraseña oculta. |
| [<img src="50_modo_de_uso.png" width="150" alt="Modo de uso">](50_modo_de_uso.png) | Modo de uso | Más → Modo de uso | `bce8e59` | No se cambió. |
| [<img src="51_pin_del_titular.png" width="150" alt="PIN del titular (sin crear)">](51_pin_del_titular.png) | PIN del titular (sin crear) | Más → PIN del titular | `bce8e59` | No se creó PIN. |
| [<img src="52_respaldo_en_la_nube.png" width="150" alt="Respaldo en la nube">](52_respaldo_en_la_nube.png) | Respaldo en la nube | Más → Respaldo en la nube | `bce8e59` | No se creó clave ni se subió nada. |
| [<img src="53_copias_de_seguridad_menu.png" width="150" alt="Menú de copias de seguridad">](53_copias_de_seguridad_menu.png) | Menú de copias de seguridad | Cuentas → carpeta | `bce8e59` |  |

## Inicio

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="01_inicio.png" width="150" alt="Inicio (resumen y accesos)">](01_inicio.png) | Inicio (resumen y accesos) | Pestaña Inicio | `7257816` |  |
| [<img src="01b_inicio_inventario_proyectado.png" width="150" alt="Inicio desplazado: inventario proyectado">](01b_inicio_inventario_proyectado.png) | Inicio desplazado: inventario proyectado | Pestaña Inicio → desplazar | `7257816` |  |

## Operaciones

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="02_operaciones.png" width="150" alt="Operaciones">](02_operaciones.png) | Operaciones | Pestaña Operaciones | `7257816` |  |
| [<img src="02b_operaciones_registrar.png" width="150" alt="Menú «Registrar operación»">](02b_operaciones_registrar.png) | Menú «Registrar operación» | Operaciones → botón «Registrar operación» | `7257816` |  |
| [<img src="03_mas_menu_opciones.png" width="150" alt="Más (menú de opciones)">](03_mas_menu_opciones.png) | Más (menú de opciones) | Operaciones → Más | `7257816` |  |
| [<img src="03b_mas_menu_opciones_abajo.png" width="150" alt="Más, parte inferior (Registrar por voz, Licencias)">](03b_mas_menu_opciones_abajo.png) | Más, parte inferior (Registrar por voz, Licencias) | Operaciones → Más → desplazar | `7257816` |  |

## Campañas y reportes

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="04_campanas.png" width="150" alt="Campañas">](04_campanas.png) | Campañas | Operaciones → Campañas | `7257816` |  |
| [<img src="05_reportes.png" width="150" alt="Reportes">](05_reportes.png) | Reportes | Operaciones → Reportes | `7257816` |  |

## Compras

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="06_compras_lista.png" width="150" alt="Lista de compras">](06_compras_lista.png) | Lista de compras | Operaciones → Compras | `7257816` |  |
| [<img src="06b_compras_menu_fila.png" width="150" alt="Menú de una compra (pago, reversión)">](06b_compras_menu_fila.png) | Menú de una compra (pago, reversión) | Compras → ⋮ de una fila | `7257816` |  |
| [<img src="07_compra_detalle.png" width="150" alt="Detalle de compra">](07_compra_detalle.png) | Detalle de compra | Compras → DEMO-002 | `7257816` |  |
| [<img src="07b_compra_detalle_abajo.png" width="150" alt="Detalle de compra, parte inferior">](07b_compra_detalle_abajo.png) | Detalle de compra, parte inferior | Detalle → desplazar | `7257816` |  |
| [<img src="08_compra_formulario_paso1.png" width="150" alt="Nueva compra, paso 1 (formulario único)">](08_compra_formulario_paso1.png) | Nueva compra, paso 1 (formulario único) | Compras → Nueva compra | `7257816` |  |
| [<img src="08b_compra_selector_producto.png" width="150" alt="Selector de producto">](08b_compra_selector_producto.png) | Selector de producto | Nueva compra → Producto | `7257816` |  |
| [<img src="08c_compra_formulario_completo.png" width="150" alt="Nueva compra, paso 1 completo">](08c_compra_formulario_completo.png) | Nueva compra, paso 1 completo | Nueva compra → producto, cantidad, precio, persona | `7257816` | No se confirmó: los datos no cambian. |
| [<img src="08d_compra_paso2_revision.png" width="150" alt="Nueva compra, paso 2 (revisión y pago)">](08d_compra_paso2_revision.png) | Nueva compra, paso 2 (revisión y pago) | Nueva compra → Continuar | `7257816` |  |
| [<img src="08e_compra_descartar_cambios.png" width="150" alt="Diálogo «¿Descartar cambios?»">](08e_compra_descartar_cambios.png) | Diálogo «¿Descartar cambios?» | Nueva compra → Atrás | `7257816` |  |

## Voz integrada

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="09_voz_compra_panel_listo.png" width="150" alt="Compra con el panel de voz abierto">](09_voz_compra_panel_listo.png) | Compra con el panel de voz abierto | Nueva compra → «Completar por voz» | `7257816` | Formulario con controles de voz en reposo («Listo para dictar»). Sin audio: no se grabó ni se dictó nada. |
| [<img src="12_voz_aplicacion_panel_listo.png" width="150" alt="Aplicación con el panel de voz abierto">](12_voz_aplicacion_panel_listo.png) | Aplicación con el panel de voz abierto | Nueva aplicación → «Completar por voz» | `7257816` | Formulario con controles de voz en reposo («Listo para dictar»). Sin audio: no se grabó ni se dictó nada. |
| [<img src="15_voz_plan_panel_listo.png" width="150" alt="Planificación con el panel de voz abierto">](15_voz_plan_panel_listo.png) | Planificación con el panel de voz abierto | Nuevo plan → «Completar por voz» | `7257816` | Formulario con controles de voz en reposo («Listo para dictar»). Sin audio: no se grabó ni se dictó nada. |
| [<img src="16_registrar_por_voz.png" width="150" alt="Registrar por voz (entrada desde Más)">](16_registrar_por_voz.png) | Registrar por voz (entrada desde Más) | Operaciones → Más → Registrar por voz | `7257816` |  |

## Aplicaciones

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="10_aplicaciones_lista.png" width="150" alt="Lista de aplicaciones">](10_aplicaciones_lista.png) | Lista de aplicaciones | Operaciones → Aplicaciones | `7257816` |  |
| [<img src="11_aplicacion_formulario.png" width="150" alt="Nueva aplicación, paso 1 vacío">](11_aplicacion_formulario.png) | Nueva aplicación, paso 1 vacío | Aplicaciones → Registrar | `7257816` |  |
| [<img src="11c_aplicacion_selector_chaco.png" width="150" alt="Selector de chaco">](11c_aplicacion_selector_chaco.png) | Selector de chaco | Nueva aplicación → Chaco | `7257816` |  |
| [<img src="11b_aplicacion_formulario_paso1.png" width="150" alt="Nueva aplicación, paso 1 completo">](11b_aplicacion_formulario_paso1.png) | Nueva aplicación, paso 1 completo | Persona y chaco elegidos | `7257816` |  |
| [<img src="11c2_aplicacion_agregar_producto.png" width="150" alt="Agregar producto a la mezcla">](11c2_aplicacion_agregar_producto.png) | Agregar producto a la mezcla | Paso 2 → Agregar producto | `7257816` |  |
| [<img src="11d_aplicacion_formulario_paso2.png" width="150" alt="Nueva aplicación, paso 2 (productos y cantidades)">](11d_aplicacion_formulario_paso2.png) | Nueva aplicación, paso 2 (productos y cantidades) | Paso 2 con un producto | `7257816` |  |
| [<img src="11e_aplicacion_paso3_revision.png" width="150" alt="Nueva aplicación, paso 3 (resumen y confirmación)">](11e_aplicacion_paso3_revision.png) | Nueva aplicación, paso 3 (resumen y confirmación) | Paso 3 | `7257816` | No se confirmó. |

## Planificación

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="13_planificacion_lista.png" width="150" alt="Lista de planes (un plan sintético desplegado)">](13_planificacion_lista.png) | Lista de planes (un plan sintético desplegado) | Operaciones → Planificación | `7257816` | El plan se creó en esta sesión con el formulario. |
| [<img src="14_plan_formulario.png" width="150" alt="Nueva planificación vacía">](14_plan_formulario.png) | Nueva planificación vacía | Planificación → Nuevo plan | `7257816` |  |
| [<img src="14b_plan_formulario_completo.png" width="150" alt="Nueva planificación completa">](14b_plan_formulario_completo.png) | Nueva planificación completa | Chaco, área, producto y dosis | `7257816` |  |

## Inventario

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="17_inventario.png" width="150" alt="Inventario">](17_inventario.png) | Inventario | Pestaña Inventario | `7257816` |  |
| [<img src="18_inventario_detalle.png" width="150" alt="Detalle de producto en inventario">](18_inventario_detalle.png) | Detalle de producto en inventario | Inventario → Fungicida DEMO | `7257816` |  |
| [<img src="18b_inventario_detalle_abajo.png" width="150" alt="Detalle de inventario, distribución por persona">](18b_inventario_detalle_abajo.png) | Detalle de inventario, distribución por persona | Detalle → desplazar | `7257816` |  |
| [<img src="19_inventario_avisos.png" width="150" alt="Avisos de inventario">](19_inventario_avisos.png) | Avisos de inventario | Inventario → Avisos de inventario | `7257816` |  |
| [<img src="19b_inventario_avisos_abajo.png" width="150" alt="Avisos de inventario, parte inferior">](19b_inventario_avisos_abajo.png) | Avisos de inventario, parte inferior | Avisos → desplazar | `7257816` |  |
| [<img src="20_estimacion_consumo.png" width="150" alt="Estimación del consumo (sin copia descargada)">](20_estimacion_consumo.png) | Estimación del consumo (sin copia descargada) | Inventario → Estimación del consumo | `7257816` | No se consultó en línea. |

## Personas, chacos y cuentas

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="21_personas.png" width="150" alt="Personas">](21_personas.png) | Personas | Pestaña Personas | `7257816` |  |
| [<img src="21b_persona_detalle_titular.png" width="150" alt="Detalle de la titular">](21b_persona_detalle_titular.png) | Detalle de la titular | Personas → Rosa Vargas | `7257816` |  |
| [<img src="21c_persona_chacos.png" width="150" alt="Chacos de una persona">](21c_persona_chacos.png) | Chacos de una persona | Personas → Beto → Chacos | `7257816` |  |
| [<img src="22_cuentas.png" width="150" alt="Liquidación y cuentas">](22_cuentas.png) | Liquidación y cuentas | Pestaña Cuentas | `7257816` |  |
| [<img src="22b_cuenta_detalle.png" width="150" alt="Cuenta de una persona">](22b_cuenta_detalle.png) | Cuenta de una persona | Cuentas → Beto Mamani | `7257816` |  |

## Catálogos

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="23_catalogos_personas.png" width="150" alt="Catálogos: personas">](23_catalogos_personas.png) | Catálogos: personas | Más → Administrar datos | `7257816` |  |
| [<img src="23b_catalogos_chacos.png" width="150" alt="Catálogos: chacos">](23b_catalogos_chacos.png) | Catálogos: chacos | Administrar datos → Chacos | `7257816` |  |
| [<img src="23c_catalogos_productos.png" width="150" alt="Catálogos: productos">](23c_catalogos_productos.png) | Catálogos: productos | Administrar datos → Productos | `7257816` |  |
| [<img src="23d_catalogos_proveedores.png" width="150" alt="Catálogos: proveedores">](23d_catalogos_proveedores.png) | Catálogos: proveedores | Administrar datos → Proveedores | `7257816` |  |
| [<img src="23e_catalogos_campanas.png" width="150" alt="Catálogos: campañas">](23e_catalogos_campanas.png) | Catálogos: campañas | Administrar datos → Campañas | `7257816` |  |
| [<img src="23f_catalogos_productos_con_foto.png" width="150" alt="Productos con «Con foto de la etiqueta»">](23f_catalogos_productos_con_foto.png) | Productos con «Con foto de la etiqueta» | Administrar datos → Productos | `7257816` |  |

## Foto de etiqueta

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="24_producto_local_nuevo_sin_conexion.png" width="150" alt="Nuevo producto local sin conexión">](24_producto_local_nuevo_sin_conexion.png) | Nuevo producto local sin conexión | Productos → Agregar producto (Wi‑Fi y datos apagados) | `7257816` | El teclado del emulador alteró el texto escrito por ADB; luego se corrigió el nombre. |
| [<img src="24b_producto_menu_fila.png" width="150" alt="Menú del producto (Editar, Foto de la etiqueta, Archivar)">](24b_producto_menu_fila.png) | Menú del producto (Editar, Foto de la etiqueta, Archivar) | Productos → ⋮ | `7257816` |  |
| [<img src="25_foto_etiqueta_vacia.png" width="150" alt="Hoja «Foto de la etiqueta» sin foto">](25_foto_etiqueta_vacia.png) | Hoja «Foto de la etiqueta» sin foto | ⋮ → Foto de la etiqueta | `7257816` |  |
| [<img src="26_foto_etiqueta_guardada_sin_conexion.png" width="150" alt="Foto guardada en el teléfono, sin conexión">](26_foto_etiqueta_guardada_sin_conexion.png) | Foto guardada en el teléfono, sin conexión | Elegir de la galería → etiqueta sintética | `7257816` | Imagen de una etiqueta inventada («ABONO FOLIAR CASERO, etiqueta sintética»). |
| [<img src="32_foto_etiqueta_con_aviso_respaldo.png" width="150" alt="Hoja de la foto con el aviso de respaldo">](32_foto_etiqueta_con_aviso_respaldo.png) | Hoja de la foto con el aviso de respaldo | ⋮ → Foto de la etiqueta | `bce8e59` | Incluye el aviso nuevo: las fotos de etiqueta no entran en los respaldos. |
| [<img src="33_reemplazo_pide_autorizacion_nueva.png" width="150" alt="Reemplazar: pregunta si se envía la foto nueva">](33_reemplazo_pide_autorizacion_nueva.png) | Reemplazar: pregunta si se envía la foto nueva | Foto de la etiqueta → Reemplazar → galería | `bce8e59` | Autorización nueva y aparte para la foto nueva. |
| [<img src="34_foto_reemplazada_autorizada.png" width="150" alt="Foto reemplazada, pendiente de envío">](34_foto_reemplazada_autorizada.png) | Foto reemplazada, pendiente de envío | Elegir «Enviar al sindicato» | `bce8e59` |  |
| [<img src="40_quitar_foto_confirmacion.png" width="150" alt="Quitar la foto (confirmación)">](40_quitar_foto_confirmacion.png) | Quitar la foto (confirmación) | Foto de la etiqueta → Quitar | `bce8e59` |  |
| [<img src="41_foto_quitada_hoja.png" width="150" alt="Sin foto; retiro pendiente de envío">](41_foto_quitada_hoja.png) | Sin foto; retiro pendiente de envío | Quitar | `bce8e59` | La hoja no se refresca sola tras el envío en segundo plano. |

## Vínculos e identificación

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="27_vinculos_sin_conexion.png" width="150" alt="Vincular con el sindicato (sin conexión)">](27_vinculos_sin_conexion.png) | Vincular con el sindicato (sin conexión) | Más → Vínculos con el sindicato | `7257816` |  |
| [<img src="27b_vinculos_opciones_producto_local.png" width="150" alt="Opciones de un producto sin vínculo">](27b_vinculos_opciones_producto_local.png) | Opciones de un producto sin vínculo | Vínculos → ⋮ del producto local | `7257816` |  |
| [<img src="28_solicitud_identificacion_dialogo.png" width="150" alt="Diálogo «Pedir identificación al sindicato»">](28_solicitud_identificacion_dialogo.png) | Diálogo «Pedir identificación al sindicato» | ⋮ → Pedir identificación | `7257816` | Muestra exactamente lo que se envía. |
| [<img src="28b_solicitud_con_foto_autorizada.png" width="150" alt="Diálogo con la foto autorizada (casilla FOTO-1 marcada)">](28b_solicitud_con_foto_autorizada.png) | Diálogo con la foto autorizada (casilla FOTO-1 marcada) | Marcar «Compartir también la foto» | `7257816` |  |
| [<img src="37_identificado_por_el_sindicato.png" width="150" alt="Identificado por el sindicato, botón Vincular">](37_identificado_por_el_sindicato.png) | Identificado por el sindicato, botón Vincular | La Directiva creó el producto colectivo en la Web → Actualizar | `bce8e59` |  |
| [<img src="38_confirmar_vinculo.png" width="150" alt="Confirmar vínculo (diálogo existente)">](38_confirmar_vinculo.png) | Confirmar vínculo (diálogo existente) | Vincular | `bce8e59` | Nunca se vincula automáticamente. |
| [<img src="39_vinculo_confirmado.png" width="150" alt="Producto local vinculado y vigente">](39_vinculo_confirmado.png) | Producto local vinculado y vigente | Confirmar | `bce8e59` | Compras, aplicaciones e inventario sin cambios (huella antes/después). |
| [<img src="42_foto_retirada_vinculos.png" width="150" alt="Foto retirada">](42_foto_retirada_vinculos.png) | Foto retirada | Vínculos tras el envío del retiro | `bce8e59` |  |
| [<img src="43_solicitud_sin_compartir_foto.png" width="150" alt="Pedir identificación sin compartir la foto">](43_solicitud_sin_compartir_foto.png) | Pedir identificación sin compartir la foto | Producto con foto → casilla sin marcar | `bce8e59` |  |

## Publicación y estados de envío

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="29_solicitud_pendiente_de_envio.png" width="150" alt="Solicitud «Pendiente de envío» y «Foto pendiente de envío»">](29_solicitud_pendiente_de_envio.png) | Solicitud «Pendiente de envío» y «Foto pendiente de envío» | Pedir identificación sin conexión | `7257816` |  |
| [<img src="29b_solicitud_pendiente_tras_reabrir.png" width="150" alt="Mismo estado tras cerrar y reabrir la app">](29b_solicitud_pendiente_tras_reabrir.png) | Mismo estado tras cerrar y reabrir la app | Forzar cierre → abrir → Vínculos | `7257816` |  |
| [<img src="29c_enviar_ahora_sin_conexion.png" width="150" alt="«Enviar ahora» sin conexión: sigue pendiente">](29c_enviar_ahora_sin_conexion.png) | «Enviar ahora» sin conexión: sigue pendiente | Vínculos → Enviar ahora | `7257816` | No se muestra éxito sin respuesta del servidor. |
| [<img src="30_datos_recibidos_foto_fallida.png" width="150" alt="Datos recibidos por el sindicato con la foto fallida">](30_datos_recibidos_foto_fallida.png) | Datos recibidos por el sindicato con la foto fallida | Enviar ahora con un 503 inyectado sólo en la subida de la foto | `7257816` | Muestra un defecto real (texto de fallo definitivo ante un 503 transitorio), corregido después en 8a45484. |
| [<img src="35_foto_fallo_reintentable.png" width="150" alt="Foto no enviada (se reintentará)">](35_foto_fallo_reintentable.png) | Foto no enviada (se reintentará) | Enviar con un 503 inyectado en la subida de la foto | `bce8e59` | Tras la corrección 8a45484: sigue reintentable aun con doble toque. |
| [<img src="36_recibida_foto_enviada.png" width="150" alt="Recibida, esperando identificación, foto enviada">](36_recibida_foto_enviada.png) | Recibida, esperando identificación, foto enviada | Sin fallo inyectado → Enviar ahora | `bce8e59` |  |
| [<img src="44_solicitud_sin_foto_recibida.png" width="150" alt="Solicitud recibida sin foto">](44_solicitud_sin_foto_recibida.png) | Solicitud recibida sin foto | Pedir identificación → Enviar ahora | `bce8e59` | El servidor la guarda sin foto ni consentimiento. |
| [<img src="45_sincronizacion.png" width="150" alt="Sincronización">](45_sincronizacion.png) | Sincronización | Inicio → Enviar al sindicato | `bce8e59` |  |
| [<img src="45b_sincronizacion_con_envio.png" width="150" alt="Sincronización tras publicar">](45b_sincronizacion_con_envio.png) | Sincronización tras publicar | Volver de Necesidades | `bce8e59` |  |
| [<img src="46_necesidades_declaradas.png" width="150" alt="Necesidad declarada (vacía)">](46_necesidades_declaradas.png) | Necesidad declarada (vacía) | Sincronización → Necesidades declaradas | `bce8e59` |  |
| [<img src="47_declarar_necesidad.png" width="150" alt="Declarar necesidad">](47_declarar_necesidad.png) | Declarar necesidad | Declarar → producto recién vinculado, 20 L | `bce8e59` |  |
| [<img src="47b_confirmar_declaracion.png" width="150" alt="Confirmar declaración">](47b_confirmar_declaracion.png) | Confirmar declaración | Continuar | `bce8e59` |  |
| [<img src="48_necesidad_estado_envio.png" width="150" alt="Necesidad aceptada por el sindicato">](48_necesidad_estado_envio.png) | Necesidad aceptada por el sindicato | Declarar | `bce8e59` | Push real aceptado por la Central aislada. |
| [<img src="49_consumo_para_el_sindicato.png" width="150" alt="Consumo para el sindicato (sin publicar)">](49_consumo_para_el_sindicato.png) | Consumo para el sindicato (sin publicar) | Sincronización → Consumo para el sindicato | `bce8e59` | No se publicó. |

## Compras conjuntas

| Captura | Pantalla | Cómo llegar | Código | Nota |
|---|---|---|---|---|
| [<img src="55_compras_conjuntas_lista.png" width="150" alt="Lista de convocatorias (nueva, abierta)">](55_compras_conjuntas_lista.png) | Lista de convocatorias (nueva, abierta) | Más → Compras conjuntas | `6bac5a3` | Mobile 6bac5a3 (etapa 2). |
| [<img src="56_inicio_aviso_nueva_convocatoria.png" width="150" alt="Aviso en Inicio «Nueva convocatoria»">](56_inicio_aviso_nueva_convocatoria.png) | Aviso en Inicio «Nueva convocatoria» | Inicio tras actualizar | `6bac5a3` | Aviso dentro de la app, sin push. |
| [<img src="57_convocatoria_detalle.png" width="150" alt="Detalle de la convocatoria">](57_convocatoria_detalle.png) | Detalle de la convocatoria | Tocar el aviso | `6bac5a3` | La necesidad declarada sólo como referencia. |
| [<img src="58_participacion_cantidades.png" width="150" alt="Cantidades que solicita">](58_participacion_cantidades.png) | Cantidades que solicita | Participar (sin conexión) | `6bac5a3` |  |
| [<img src="59_consentimiento_conv1.png" width="150" alt="Consentimiento CONV-1">](59_consentimiento_conv1.png) | Consentimiento CONV-1 | Continuar | `6bac5a3` | El botón se activa sólo al marcar «Entiendo y acepto». |
| [<img src="60_participacion_pendiente_sin_conexion.png" width="150" alt="Participación pendiente de envío">](60_participacion_pendiente_sin_conexion.png) | Participación pendiente de envío | Confirmar sin conexión | `6bac5a3` |  |
| [<img src="61_participacion_recibida.png" width="150" alt="Participación recibida">](61_participacion_recibida.png) | Participación recibida | Reconectar → Enviar ahora | `6bac5a3` |  |
| [<img src="62_participacion_modificada.png" width="150" alt="Participación modificada y recibida">](62_participacion_modificada.png) | Participación modificada y recibida | Modificar → 12 L | `6bac5a3` |  |
| [<img src="63_modificacion_pendiente_antes_del_plazo.png" width="150" alt="Lo aceptado y lo pendiente a la vez">](63_modificacion_pendiente_antes_del_plazo.png) | Lo aceptado y lo pendiente a la vez | Modificar sin conexión antes del plazo | `6bac5a3` |  |
| [<img src="64_fuera_de_plazo.png" width="150" alt="Fuera de plazo">](64_fuera_de_plazo.png) | Fuera de plazo | Enviar 29 s después de la fecha límite del servidor | `6bac5a3` |  |
| [<img src="65_lista_convocatoria_cerrada.png" width="150" alt="Lista con la convocatoria cerrada">](65_lista_convocatoria_cerrada.png) | Lista con la convocatoria cerrada | Actualizar tras el cierre automático | `6bac5a3` |  |
| [<img src="66_participacion_en_consolidado.png" width="150" alt="Incluida en el consolidado al cierre">](66_participacion_en_consolidado.png) | Incluida en el consolidado al cierre | Abrir la convocatoria cerrada | `6bac5a3` |  |

## Pantallas pendientes y motivo

- Campos completados por voz: requieren audio sintético autorizado o datos de prueba inyectados y señalados; no se hicieron.
- Clave de recuperación del respaldo, PIN creado y subida o restauración de copias: se omitieron a propósito (pantallas con secretos o acciones no reversibles).
- Mensaje tras exportar un respaldo local: la notificación desapareció antes de capturarla; su texto está cubierto por una prueba automatizada.

## Diferencias con las capturas anteriores

- `ux_c1` y `ux_f12` (2026-10-30) y `oe3_device*` (2026-11-03) son de `main` o anteriores: no tienen el **formulario único** de compra, aplicación y planificación (pasos, resumen «Lo que se va a guardar», diálogo de descarte) ni los controles **«Completar por voz»** ni la entrada **«Registrar por voz»**.
- Nuevas en este conjunto: **foto de la etiqueta** del producto, **solicitud de identificación** al sindicato con su autorización aparte para la foto, y los **estados de envío** («Pendiente de envío», «Foto pendiente de envío», «Recibida por el sindicato», «Esperando identificación»).
- Muestran también **avisos de inventario** (vencidos, vencen hoy, próximos, bajos) y la **estimación del consumo** sin copia descargada.
- Observación para el diseño: en las subpantallas de Más (p. ej. Vínculos) la barra inferior resalta «Inicio» aunque se llegó desde Operaciones.
