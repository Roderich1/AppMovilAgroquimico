# Rediseño móvil — inventario prototipo ↔ Flutter

Prototipo: lienzo «Agrocuentas — Rediseño de pantallas clave» (56 láminas de 390×844, más «Hoy»), leído el 2026-11-12 desde el artefacto `CddqjNWu6qNar1Xb8HZgvi`. El prototipo fija la dirección visual; el comportamiento lo fijan el código de la base `01b2576` y las reglas aceptadas.

Tipos: **P** = pantalla (ruta), **H** = hoja o diálogo sobre una pantalla, **E** = estado o variante de otra lámina (no es ruta propia).

## Bloque 1 — estilos y compra (hecho, ver continuidad)

| Lámina | Tipo | Flutter | Se conserva | Diferencias / decisiones |
|---|---|---|---|---|
| 1.7 Registrar (hoja) | H | FAB «+» del shell (`app_shell.dart`) | Compra, Aplicación, Planificación, Pago (en Cuentas), Transferencia (sólo compartido) | Pendiente del bloque 3 (va con la navegación nueva). |
| 2.1 Compra · paso 1 | P | `/compras/nueva` paso `items` | Proveedor con «Crear proveedor», fecha (hoy, sólo hacia atrás), líneas, validación por línea, Atrás con «¿Descartar cambios?» | Línea vacía = botón punteado «Añadir producto»; con datos = tarjeta resumen. Total «—» mientras falte un dato. |
| 2.2 · panel de voz abierto | E | panel anclado (`VoiceFormPanel(docked: true)`) | Abrir no enciende el micrófono; «Hablar»; cerrar sin perder nada | Sustituye a «Continuar» mientras está abierto (como la lámina); se cierra con ✕. |
| 2.3 · escuchando | E | fase `recording` | «Terminar» y «Cancelar» | **Sin** texto parcial ni medidor de nivel: el motor de la compra (Whisper small, turno entero) no da ni lo uno ni lo otro. |
| 2.4 · procesando | E | fase `processing` | «Cancelar» (descarta el resultado tardío) | Título «Procesando tu voz» (encargo), barra indeterminada, «Lo que ya escribió a mano se conserva.». **No** se muestra «Usted dijo»: no hay transcripción mientras el motor no termina y no se muestra después (privacidad, capturas). |
| 2.5 · tras dictar | E | aviso oscuro `VoiceResultBanner` + tarjetas con revisión | Resumen del dictado, avisos del intérprete, «Dictar más», «Deshacer último dictado», elegir/revisar por campo | Las opciones de revisión son **sólo** las del intérprete (p. ej. «Por L» / «Total de la línea»); se añade «Escribir otro valor» / «Elegir otro», que abre la hoja del producto. No se inventan alternativas como «118,00 / 180,00». |
| 2.6 Producto (hoja) | H | hoja en la misma página (`InPageSheet`) sobre la misma línea del borrador | Producto con «Crear producto», cantidad, precio, BOB/USD y tipo de cambio, «¿Para quién es?» (una persona / repartir, sin opción por defecto), «Agregar persona», vencimiento y lote, quitar línea | «Guardar» → **«Listo»** y «Añadir otro»: la hoja no guarda nada, lo escrito ya está en el borrador. El problema de validación de la línea aparece arriba de la hoja (una barra flotante tapaba sus botones). |
| 2.7 Compra · paso 2 | P | paso `review` | Resumen, «¿Ya pagó al proveedor?» sin respuesta por defecto, paga el titular, medio y fecha visibles, factura/notas/campaña plegadas, una sola compra aunque se toque dos veces | El micrófono de la cabecera vuelve al paso 1 con el panel abierto. |
| 2.8 Compra · detalle | P | `/compras/detalle/:id` | — | Pendiente (bloque 3, Actividad). |

## Bloques siguientes (sin empezar)

| Láminas | Flutter actual | Bloque | A comprobar antes de implementar |
|---|---|---|---|
| 3.1–3.4 Aplicación (3 pasos) + 3.2 voz | `/aplicaciones/nueva` (`application_form_screen.dart` + `_voice`) | 2 | «Quién aplicó» (lámina 3.1): en el código es el selector «Persona» del paso 1 (en propio, «Aplica el titular», sin elegir); el código lo llama responsable y, si la voz pone un chaco, pasa a ser su dueño (`application_form_screen.dart`, comprobado el 2026-11-12). Antes de rotularlo, confirmar su significado exacto y usar el término vigente; no crear un campo nuevo ni cambiarlo. Vosk + revisión Whisper base sin cambios. Avisos de lote vencido, falta de existencias y cambio de chaco. |
| 3.5–3.6 Plan + voz | `/planificacion/nueva` | 2 | Crear un plan no descuenta inventario ni genera cargos. |
| 1.1–1.6 Principal | `/`, `/operaciones`, `/inventario`, `/personas`, `/liquidacion` | 3 | Barra nueva Inicio · Actividad · Almacén · Personas · Sindicato: reubicar Operaciones › Más, Cuentas, Sincronización y Catálogos sin perder acceso. |
| 4.1 Producto, 4.2 Avisos, 4.3 Estimación, 4.4 Vínculos | `/inventario/:id`, `/inventario/avisos`, `/inventario/estimacion`, `/sindicato/vinculos` | 3/4 | «Reservado 6 L · quedarán 4 L» (4.1) **no** es una reserva real: en el código es `committedBase`, «reservado por planes pendientes de la campaña activa», y «quedarán» es `projectedBase` (puede ser negativo) (`domain/read_models.dart`, comprobado el 2026-11-12). Rotular «Previsto en planes». La estimación conserva el alcance de cada cifra (F12). |
| 4.5 Identificación, 4.6 Etiqueta (hojas) | `label_photo_sheet.dart`, `identification_texts.dart` | 4 | La foto es opcional; compartirla requiere su autorización. «La verá la Directiva» (4.5) no se usa: el texto sale de los permisos vigentes. |
| 5.1–5.7 Personas, cuentas, pago, transferencia, propios, costos, bitácora | `/personas/:id`, `/liquidacion`, `/transferencias/nueva`, `/chacos/:id` | 3 | Saldos, pagos y costos sin cambiar cálculos. |
| 6.1–6.5 Convocatorias, participar, necesidad, consumo | `/compras-conjuntas`, `/compras-conjuntas/:id`, `/planificacion/necesidades`, `/sincronizacion/consumo` | 4 | El texto «la Directiva verá mi nombre…» (6.3) **no** se usa: el alcance es el del consentimiento aceptado (CONV-1/CONV-2, `joint_purchase_texts.dart`). Consentimientos nuevos sin marcar; distinguir aceptación previa válida de nueva. Estados: pendiente local, recibido, modificación pendiente, fuera de plazo, cerrada, cancelada. Participar no genera compra, deuda ni inventario. |
| 7.1–7.10 Ajustes, datos, campañas, reportes, PIN, respaldos, modo de uso, tardías | `/mas`, `/catalogos`, `/campanas`, `/reportes`, `/titular/pin`, `/respaldo-remoto`, `/modo`, `/operaciones/tardias` | 5 | — |
| 8.1–8.3 Acceso | `/activar`, `/reauth`, `/recuperar` | 5 | — |
| 9.1–9.3 Confirmaciones | `owner_reversal_flow.dart`, diálogos | 5 | — |

## Funciones actuales que el prototipo no muestra (y dónde quedan)

- Compra: moneda USD con tipo de cambio, reparto entre varias personas, número de lote, «Quitar selección» de un selector (pasa a la hoja del selector), cámara/galería de la factura, campaña distinta de la activa → todas siguen en la hoja del producto o en «Factura, notas y campaña».
- Panel de voz: «Abrir ajustes» cuando el micrófono está bloqueado, mensajes de error del motor, avisos del intérprete, panel de diagnóstico (sólo en la compilación de diagnóstico).
- Resto: se inventaría por bloque antes de implementarlo.
