# Rediseño móvil — guía para la revisión del autor (2026-11-12)

**Aplicación:** «**AC RDM**» (`com.comunidad.agro.agroquimicos.rdm`) en el AVD **`RDM_Pixel8` / `emulator-5556`**. No usar el `Pixel_8` compartido (`emulator-5554`): allí hay una «AC RDM» **antigua** (`2d6aa0d`, bloque 1). Nada está aceptado hasta su valoración.

**Datos sintéticos** (inventario compartido, campaña «Invierno 2026»): Rosa Vargas (titular, Chaco Norte 3 ha) y Juan Mamani (familiar, Chaco Rio 2 ha); una compra de 5 L de «Herbicida sin red» a 80 Bs sin pagar (400,00 Bs); transferencia de 2 L Rosa → Juan; un plan para Chaco Rio aplicado (1 L, cargo de 80,00 Bs a Juan) y otro pendiente para Chaco Norte; pago de 50,00 Bs de Juan (le quedan 30,00 Bs).

**Versión instalada (noche del 2026-11-12):** `91f2e73` (rediseño + P-A), conectada a la Central aislada por un túnel temporal; cuenta en línea autenticada. Además de los datos de abajo hay dos convocatorias sintéticas: «Convocatoria P-A sustitución» (abierta, 12 KG, responsable sustituida y ya autorizada) y «Convocatoria P-A cerrada» (4 L, cerrada, sustituida y autorizada). En Convocatorias todavía aparece el «+ Registrar» flotante: corregido en la rama (`9264191`), no instalado.

**Comparativas lámina | integración:** `docs/evidence/rediseno-movil/2026-11-12/integracion/comparativas/` (49, nombradas por número de lámina). Las capturas de la derecha salen del arnés sobre la rama integrada (fuentes reales, 390×844) o del emulador cuando se indica.

## 1. Inicio y navegación

- **Mirar:** las 5 pestañas y su rótulo; «+ Registrar» en Actividad y Almacén (se recoge al desplazar); la hoja Registrar (Compra/Aplicación grandes; Plan, Pago, Transferencia, voz); Atrás desde subpantallas vuelve a la pestaña; el engranaje de Inicio abre «Ajustes y datos».
- **Diferencias:** Inicio conserva «Ver cuánto queda», «Enviar al sindicato», «Cuenta en línea» y los saldos principales; «Para atender» cuenta lotes («1 lote vencido…»); las cifras dicen «de todas las campañas»; no hay aviso de «Nueva compra conjunta» en Inicio; sin «+ Registrar» en pantallas con acción propia (Personas, Cuentas, Sindicato, listas).
- **Comparativas:** `1.2`, `1.3`, `1.4`, `1.5`, `1.6`, `1.7`.

## 2. Compra y revisión de voz

- **Mirar:** pasos 1 y 2, hoja del producto («Listo» / «Añadir otro»), «¿Descartar cambios?» con Atrás, panel de voz (abrir y cerrar sin hablar no cambia nada).
- **Diferencias:** «Listo» en vez de «Guardar» (la hoja no registra); revisión del precio con las opciones reales del intérprete y «Escribir otro valor»; sin «Usted dijo» ni transcripción; sin medidor de nivel (no existe ese dato); micrófono arriba en ambos pasos.
- **Voz:** este emulador no tiene audio. Los estados de voz se vieron en el bloque 1 (`d02`–`d08`, otra compilación); la **precisión con voz humana no está medida**.
- **Comparativas:** `2.1`–`2.8` (2.3 y 2.4 son del emulador del bloque 1).

## 3. Aplicación y planificación

- **Mirar:** «Persona → Chaco → Fecha», la mezcla con «Hay 3 L · quedarán 2 L», paso 3 «Se cargará a … », plan con dosis por ha y «Necesita».
- **Diferencias:** «Persona» con «Responsable del chaco · se usan sus productos» en vez de «Quién aplicó» (**decisión suya pendiente**); el área es un campo aparte con «ha»; el plan añade productos con selector + «Agregar al plan»; estados del plan en texto.
- **Comparativas:** `3.1`–`3.6`.

## 4. Actividad, Almacén y Personas

- **Mirar:** filtros de Actividad (Todo, Compras, Aplicaciones, Planes, Transferencias) y «Reportes» arriba; Almacén con «Previsto en planes»; detalle de producto; Personas → persona, cuenta, «Registrar pago» (hoja), propios y costos por chaco; transferencia.
- **Diferencias:** «Previsto en planes» en lugar de «Reservado»; producto en secciones seguidas (sin pestañas); transferencia con «Persona origen/destino» y sin botón de intercambio; Personas con cifras de todas las campañas; agregar personas está en Ajustes › Datos (Personas no tiene «Agregar»); en pantalla ancha Almacén no usa tabla (UIBUG-023, **decisión suya**).
- **Comparativas:** `1.4`, `1.5`, `2.8`, `4.1`–`4.3`, `5.1`–`5.7`.

## 5. Sindicato y convocatorias

- **Mirar:** tarjeta de envío, «Convocatorias», «Necesidad declarada», «Consumo», «Productos y campañas», identificación con foto.
- **Diferencias:** sin contadores en la tarjeta de convocatorias; estados de vínculos con los textos vigentes (no «Solicitud enviada» si sólo está en el teléfono); casillas de consentimiento sin marcar con el texto vigente FOTO-1/CONV-3; «Responsable: nombre» y fecha límite absoluta.
- **Textos de consentimiento:** CONV-3 trata de «tú» y **se conserva tal cual** (texto versionado); el resto de la app usa «usted».
- **P-A, recorrida conectada:** tarjeta «La persona responsable … cambió» con «Revisar autorización», diálogo con dos casillas sin marcar, «Sus cantidades no cambian», estados «Participación recibida» y «… aplicada en el sindicato» (`g01`–`g10`). Para ver de nuevo la tarjeta hace falta otra sustitución desde la Central (lo hago yo si lo pide).
- **Comparativas:** `1.6`, `4.4`–`4.6`, `6.1`–`6.5`.

## 6. Ajustes, reportes y respaldos

- **Mirar:** «Ajustes y datos» (Datos, Seguridad, Uso), Datos, Campañas, Reportes (tipo, campaña/persona, Excel/PDF, aviso de archivo sin cifrar), Respaldos (nube y «En este teléfono»), PIN, Modo de uso, Tardías, confirmaciones.
- **Diferencias:** Reportes no se repite en Ajustes (está en Actividad); Excel es la única exportación de hoja de cálculo (rama F); confirmaciones como diálogos con el estilo nuevo (no hojas); «Nuevo período histórico» sigue siendo el diálogo de Tardías; texto del PIN «sólo él puede aprobar» (anterior al rediseño, **decisión suya**).
- **Comparativas:** `7.1`–`7.8`, `8.1`, `9.1`.

## Cómo devolver la valoración

Por grupo: «aceptado», «aceptado con cambios: …» o «rechazado: …». Las correcciones se reparten por `COORDINACION.md` (las sesiones A/B/C sólo se reactivan para correcciones concretas).
