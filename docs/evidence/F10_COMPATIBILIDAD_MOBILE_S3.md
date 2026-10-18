# F10 — Compatibilidad Mobile (RNF-08), serie 3 acotada: M8 en A1 y A1-F y M3 en A1-F (POCO X5 Pro, Android 12) tras MOB #129

- **Fecha real:** 2026-10-18 (UTC), de 22:11Z (M8 de A1) a 22:23Z (ajustes restaurados). En America/La_Paz, de 18:11 a 18:23.
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica de Roderich Rendón. Operación por `adb`, datos sintéticos. **Sin inspección personal de Roderich, sin revisión del tutor, sin evaluación con usuarios.**
- **Protocolo:** v1.3 `9bfcad2` §2, **sin cambios**, más el suplemento `docs/evaluation/F10_SUPLEMENTO_SERIE3_2026-10-18.md` (PR BE #141, `b3013f0` con LISTO limpio de B y C antes de medir) §3: en esta serie se repiten **sólo M8 en A1 y A1-F y M3 en A1-F**, que son los flujos afectados por la corrección de MOB #129. **M1, M2, M4, M5, M6 y M7 no se repiten** y conservan su resultado de la serie 1 (POCO, `dff6802`): por eso **ninguna configuración se declara compatible globalmente desde este documento**.
- **APK evaluada:** `com.comunidad.agro.agroquimicos.f10eval3` («Agrocuentas F10-EVAL3»), **profile**, SHA-256 `f585c09846a4462a74d6030e717ced105c2071691cb24ce609d5968efe9c17f8`, compilada desde el worktree limpio en **`9cbd565`** (código `lib/` = `27c4654`, PR MOB #131; igual a `main` `196372a` en `lib/`, `android/` y `pubspec.yaml`), `minSdkVersion 24`, `targetSdkVersion 36` (`aapt2`). Una sola copia para A1 y A1-F (sólo cambia `font_scale`; la activación no es un caso de esta serie).
- **Backend:** `6c54c00` (código `cab433d`), entorno `agro_a_f10eval3_pg`; sólo para la activación (`F10_RENDIMIENTO_MOBILE_S3.md` §2–§3).
- **Herramienta:** `tool/f10_eval/ui.py` de `758d9fe` (rama; PR #128 abierto), con pasos manuales por `adb` donde falló (§3 y H-1).
- **Lo que no es:** no afirma compatibilidad con A2, A3, A4, A4-F ni A5; no repite el HONOR con el POCO; no decide GATE-F10.

## 1. Criterio y precisiones (fijados en el suplemento §3 antes de medir)

- **Criterio v1.3 M8 (decide CUMPLE / NO CUMPLE):** en las pantallas de M3, M4 y M6 (Nueva compra, Nueva aplicación, Sincronización), sin controles tapados por las barras del sistema ni textos cortados; A1-F con `font_scale` 1,3.
- **Precisiones derivadas de #129 y #97 (se evalúan aparte, sin subir ni bajar el umbral):** (p1) Inicio y barra de pestañas: tarjetas, botón «Nuevo» sin cubrir importes ni controles sin desplazar, último elemento de las listas por encima del botón; (p2) sin palabras partidas de forma incomprensible en tarjetas, cabeceras y navegación; (p3) nombre de producto legible completo en el contexto de selección.

## 2. Matriz

| Flujo | A1 · POCO, Android 12 / API 31, 1080×2400, `font_scale` 1,0 (DEVICE) | A1-F · POCO, `font_scale` 1,3 (DEVICE) |
|---|---|---|
| M3 Compra de 2 líneas sin red | no repetido (serie 1: CUMPLE sobre `dff6802`) | **CUMPLE** (compra confirmada tras leer el total; +1 compra, +2 líneas, +2 movimientos; incidente del instrumento declarado, §3) |
| M8 Presentación, criterio v1.3 | **CUMPLE** | **CUMPLE** (antes, serie 1: NO CUMPLE por MOB #97) |
| Precisión p1 (Inicio, botón «Nuevo», último elemento) | satisfecha, con una **observación**: a 1,0 el botón «Nuevo» cubre el extremo derecho del campo «Buscar producto» (zona sin texto ni icono); no cubre importes; el último elemento de la lista queda por encima del botón | satisfecha: importes y último elemento fuera del botón |
| Precisión p2 (palabras partidas) | satisfecha («Operaciones», «Pagado proveedores», «Productos (2)», «Inventario proyectado» enteros) | satisfecha (saltos por palabra: «Pagado / proveedores», «DSV-002 Producto / sintético», «Titular · Chaco DSV / Norte»; «Operaciones» entera en la barra) |
| Precisión p3 (nombre de producto completo en el selector) | satisfecha («DSV-002 Producto sintético» entero en el campo «Producto») | satisfecha (campo «Producto» con el nombre entero; cabecera de línea con salto por palabra) |
| M1, M2, M4, M5, M6, M7 | no repetidos (serie 1) | no repetidos (serie 1) |
| **Configuración** | **no se redeclara** (flujos no repetidos sobre esta base) | **no se declara compatible** por lo mismo; **M8 ya no es el obstáculo** |

**MOB #97 (A1-F):** su criterio de cierre propuesto («títulos de la barra y encabezados de Nueva compra y Sincronización completos a 1,3 y 1,0; prueba de widget a 360 dp con textScaler 1,3; comprobación en el dispositivo») queda cubierto: títulos «Nueva compra» y «Sincronización» enteros a 1,0 y 1,3 en el POCO (capturas), prueba de widgets en `test/f10_compat_129_presentacion_test.dart` (PR #131) y esta comprobación en el dispositivo. El caso «Titular F1…» de Asignaciones no aplica en modalidad propia (sin campo de asignación); no se comprobó en modalidad compartida. La decisión de cerrar #97 es de Roderich.

**RNF-08:** sigue informándose configuración por configuración y **no se declara cumplido globalmente** (A3 y A5 NO EJECUTADAS; A4-F NO CUMPLE M8 en la serie 2 sin repetir en el HONOR; A1/A1-F con flujos no repetidos sobre esta base).

## 3. Detalle

**Entorno común:** POCO X5 Pro 5G `22101320G`, Android 12 / API 31, MIUI V14 (`SKQ1.220303.001`), 1080×2400 a 440 dpi (≈ 392,7×872,7 px lógicos; barra de estado 94 px, barra de navegación de tres botones 130 px), 120 Hz; cuenta sintética D, titular «Titular», modalidad propia; DS-V sembrado (300/600/1000/1000/1612). Modo avión activo durante toda la matriz (N0; sin peticiones). `pointer_location` 1 (su barra aparece en las capturas: instrumento, no app).

### A1 (`font_scale` 1,0; 22:11–22:16Z)

| Pantalla | Observado (UTC) | Captura (SHA-256, no publicada) |
|---|---|---|
| Inicio (arriba) | 22:05:15Z (comprobación (c) de R1): tarjetas en dos columnas con importes enteros; «Inventario proyectado» + «Ver todos» en una línea; buscador; primera fila con el nombre; botón «Nuevo» sobre el extremo derecho del buscador (observación p1); barra con «Inicio · Operaciones · Inventario · Personas · Cuentas» enteras | `a1_c_inicio_1_0.png` `975b2c8b…c9d1c` |
| Nueva aplicación con rechazo (M4) | 22:11:18–22:12:12Z: DSV-005 999 L → «Disponible 193,3 L · stock después −805,7 L» en rojo y «Revise las cantidades: todos los productos deben tener stock suficiente.» al confirmar; conteos sin cambio; borrador descartado. Sin cortes ni controles tapados | `a1_m8_aplicacion_rechazo.png` `bd5513c0…42a3` |
| Nueva compra, arriba (M3) | 22:13:51–22:15:23Z: título «Nueva compra» entero; «Productos (2)» con «Agregar producto» en la misma línea; cabecera «1 DSV-002 Producto sintético / 10 L · 500,00 Bs · Para el titular»; campo «Producto» con el nombre entero | `a1_m8_compra_top.png` `8aa0e284…7d7b6` |
| Nueva compra, abajo (M3) | «Costo 40,00 Bs /L · Subtotal 200,00 Bs», «Pago al proveedor», «TOTAL COMPRA 2 productos · sin foto 700,00 Bs», «Confirmar compra» entero; borrador descartado («¿Descartar cambios?» → «Descartar cambios»); conteos 300/600 sin cambio | `a1_m8_compra_bottom.png` `38541b33…3eb2` |
| Sincronización (M6) | 22:15:51Z: título «Sincronización» entero; «Sincronizar ahora», «Vincular con el sindicato», «Necesidades declaradas», «Consumo para el sindicato» enteros; sin cortes | `a1_m8_sync.png` `c6caf644…fe0b` |
| Inicio, final de la lista | 22:16:04Z: «Principales saldos» → «Titular / Familiar 98.513,66 Bs» como último elemento, por encima del botón «Nuevo» | `a1_m8_inicio_fin.png` `4ec680f7…a177` |

### A1-F (`font_scale` 1,3 desde las 22:16:37Z hasta las 22:23:18Z)

| Pantalla | Observado (UTC) | Captura (SHA-256, no publicada) |
|---|---|---|
| Inicio (arriba) | 22:16:49Z: «Campaña activa: Campaña DSV / 2025-2026» en dos líneas por palabra; tarjetas en dos columnas con «Pagado / proveedores», «Familias por / cobrar», «Terceros por / cobrar», «Pagos / recibidos» (saltos por palabra) e importes enteros; botón «Nuevo» sobre espacio vacío a la derecha de «Pagos recibidos», sin cubrir importes; cabecera «Inventario proyectado» justo sobre la barra (la lista queda bajo el borde: irrelevante para M8); barra con las cinco etiquetas enteras («Operaciones» incluida) | `af_m8_inicio.png` `e4485be9…ef0d41` |
| Inicio, final de la lista | 22:17:34Z: «Principales saldos» → «Titular / Familiar 98.513,66 Bs» último, por encima del botón; filas de «Aplicaciones recientes» con salto por palabra («Titular · Chaco DSV / Norte») | `af_m8_inicio_fin.png` `5be374ce…5fbbe` |
| Nueva compra, arriba (M3) | 22:19:56Z: título **«Nueva compra» entero** (serie 1: «Nueva com…»); «Productos (2)» y «Agregar producto» en líneas distintas (Wrap), sin partir; cabecera de línea «DSV-002 Producto / sintético / 10 L · 500,00 Bs · Para el / titular» por palabra; campo «Producto» con «DSV-002 Producto sintético» entero | `af_m8_compra_top.png` `edf8d8d7…1bcd1` |
| Nueva compra, abajo (M3) | 22:21:14Z: línea 2 «5 L», «BOB», «40», «Costo 40,00 Bs /L · Subtotal 200,00 Bs», «Para el titular: Titular», «Pago al proveedor», «TOTAL COMPRA 2 productos · sin foto 700,00 Bs» (texto e importe contiguos, sin solaparse), «Confirmar compra» entero | `af_m8_compra_bottom.png` `b93dbed4…8e14d` |
| **M3: compra confirmada** | 22:21:14Z, tras leer «TOTAL COMPRA 2 productos … 700,00 Bs»: la lista de Compras encabezada por «Proveedor DSV 1 · Campaña DSV 2025-2026 · 2 productos · Total 700,00 Bs · pagado 0,00 Bs»; conteos **300 → 301 compras, 600 → 602 líneas, 1 612 → 1 614 movimientos**, integridad ok, outbox 0; 0 peticiones | `af_m3_compras_lista.png` `a75b7b4e…4733` |
| Nueva aplicación con rechazo (M4) | 22:21:24–22:22:10Z: «Productos (1)», DSV-005 999 L → «Disponible 193,3 L · stock después / −805,7 L» (salto por palabra) y el aviso «Revise las cantidades: todos los / productos deben tener stock suficiente.» entero; conteos sin cambio (1 000 aplicaciones); borrador descartado | `af_m8_aplicacion_rechazo.png` `23c5cb8b…8acc7` |
| Sincronización (M6) | 22:22:35Z: título **«Sincronización» entero** (serie 1: «Sincroni / zación»); botones y textos enteros; «Todavía no hay nada que enviar / al sindicato.» por palabra | `af_m8_sync.png` `ff8beea8…89de0` |

Huellas completas de las 13 capturas en `f10_eval_s3/capturas_sha256.txt`.

## 4. Hallazgos e incidentes del arnés

- **H-1. Instrumento de compra (`ui.py purchase-form`, `758d9fe`) en el POCO.** A 1,0 se detuvo tras elegir el producto de la línea 2 («no se ve la cabecera de la línea 2»; cantidad y precio sin rellenar) y la línea se completó a mano por `adb` (campos bajo la cabecera «2 DSV-003»), sin escritura. A 1,3 la herramienta sí completó la línea 2 pero informó «total no visible», y el paso manual de respaldo **añadió dígitos a campos ya rellenos** (55 L y 4 040 Bs/L; subtotal 222 200,00 Bs): se detectó en la cabecera de la línea y se retecleó (5 L, 40 Bs/L) **antes de confirmar**; la compra confirmada es la de 700,00 Bs. Nada se escribió con los valores erróneos (conteos 300/600 hasta la confirmación). La herramienta de la serie 2 no está ajustada al POCO con esta base; se declara y no se corrige en esta serie.
- **H-2. Descartar borradores:** un BACK con el teclado cerrado abre «¿Descartar cambios?»; se confirmó con «Descartar cambios» y se verificaron los conteos. En la primera compra de A1 el primer BACK no abrió el diálogo (teclado residual) y se repitió.
- **H-3.** Las capturas incluyen la barra de `pointer_location` (instrumento). No se publican por contener datos sintéticos de pantalla, como en las series anteriores; se publican sus huellas.

## 5. Limitaciones

- **Alcance acotado:** sólo M8 (A1, A1-F) y M3 (A1-F); los demás flujos no se repitieron sobre esta base. Ninguna configuración se redeclara compatible.
- **Un solo teléfono físico**; A4/A4-F (HONOR) no se repiten con el POCO; A3/A5 siguen NO EJECUTADAS.
- **Modalidad propia:** el caso «Titular F1…» de Asignaciones (#97) no aplica y no se comprobó en modalidad compartida.
- La observación de p1 (botón «Nuevo» sobre el extremo derecho del buscador a 1,0) queda para la decisión de Roderich; no es un fallo del criterio v1.3.
- Datos sintéticos, APK profile, operación por `adb`. Sin inspección personal de Roderich, sin revisión del tutor ni validación institucional. GATE-F10 (BE #49) sigue Pending.
