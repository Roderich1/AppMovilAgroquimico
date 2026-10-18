# F10 — Compatibilidad Mobile (RNF-08), serie 2: A4 y A4-F (HONOR JDY-LX3P, Android 16)

- **Fecha real:** 2026-10-18 (UTC), de 15:19Z (M1 de A4) a 18:42Z (ajustes restaurados). En America/La_Paz, de 11:19 a 14:42.
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica de Roderich Rendón. Operación por `adb`, datos sintéticos. **Sin inspección personal de Roderich, sin revisión del tutor, sin evaluación con usuarios.**
- **Protocolo:** v1.3 `9bfcad2` §2, **sin cambios**, más el suplemento `docs/evaluation/F10_SUPLEMENTO_BASE_2026-10-18.md` (PR BE #139; versión `93c90c1` con LISTO de B y C antes de M1; HEAD `731e548` añade sólo el párrafo de preparación de campañas de §3, con LISTO de C; cronología en su §8 y en `F10_RENDIMIENTO_MOBILE_S2.md` §9) §3: el HONOR entra como **A4** (`font_scale` 1,0) y **A4-F** (`font_scale` 1,3), configuración física nueva (el protocolo reserva A4/A5 a teléfonos adicionales). **A1, A1-F y A2 no se repiten** en esta serie y conservan su resultado de la serie 1 sobre `dff6802` (`F10_COMPATIBILIDAD_MOBILE.md`), incluido **A1-F NO CUMPLE M8** (MOB #97), que sólo se cierra midiendo en el POCO.
- **APK evaluada:** `com.comunidad.agro.agroquimicos.f10eval2` («Agrocuentas F10-EVAL2»), **profile**, SHA-256 `a0acfee1c3d01b8316d4711e7a31b8b61929fb572e43a2b724c98bcafb953794`, Mobile **`ad5b43d`**, `minSdkVersion 24`, `targetSdkVersion 36` (`aapt2`). Para **M1 de A4-F**, la segunda copia `com.comunidad.agro.agroquimicos.f10eval2f` («Agrocuentas F10-EVAL2F»), profile, SHA-256 `2fe61d37a21446e3aa3902af6ff72781866ff9234e72a2a4ddc7dd876edae082`, compilada el 2026-10-18 18:07–18:08Z desde el worktree limpio en `2b38bcf` (rama de herramientas sobre `ad5b43d`; `git diff ad5b43d 2b38bcf -- lib android pubspec.yaml` **vacío**: mismo código). **Desviación declarada** (precedente `.f10c23x` de la serie 1): distinta sólo por sufijo y etiqueta.
- **Backend:** `6c54c00` compilado (código `cab433d`), entorno `agro_a_f10eval2_pg`, túnel HTTPS (`F10_RENDIMIENTO_MOBILE_S2.md` §2).
- **Lo que no es:** no afirma compatibilidad con equipos no ejecutados ni que la selección sea la de los equipos reales de la Directiva.

## Matriz

| Flujo | A4 · HONOR, Android 16 / API 36, 720×1612, `font_scale` 1,0 (DEVICE) | A4-F · HONOR, `font_scale` 1,3 (DEVICE) |
|---|---|---|
| M1 Instalación y activación | CUMPLE | CUMPLE (copia `.f10eval2f`, ver detalle) |
| M2 Reapertura sin red | CUMPLE | CUMPLE |
| M3 Compra de 2 líneas sin red | CUMPLE | CUMPLE (tras dos intentos del instrumento, ver detalle) |
| M4 Aplicación y rechazo por saldo | CUMPLE | CUMPLE |
| M5 Foto de comprobante | CUMPLE | CUMPLE |
| M6 Necesidad y sincronización | CUMPLE | CUMPLE |
| M7 Respaldo: subir y restaurar | CUMPLE | CUMPLE |
| M8 Presentación | CUMPLE (con observaciones, MOB #129) | **NO CUMPLE** (MOB #129) |
| **Configuración** | **compatible** (DEVICE) | **no compatible** (M8) |

**RNF-08:** se informa configuración por configuración. **A4 compatible** sobre `ad5b43d`; **A4-F no compatible** (M8). A1 y A2 siguen con su resultado de la serie 1 sobre `dff6802`; A1-F sigue NO CUMPLE M8 (#97) sin repetición; A3 y A5 siguen NO EJECUTADAS. Por eso **RNF-08 no se declara cumplido globalmente**.

## A4 (`font_scale` 1,0; valor previo del equipo 1,45, restaurado al terminar)

**Entorno:** HONOR JDY-LX3P, Android 16 / API 36, build `JDY-L43P 10.0.0.181(C605E7R200P1)`, parche 2026-09-01, 720×1612, 320 dpi, barra de navegación de tres botones; cuenta sintética D, titular «Titular», **modalidad propia**; DS-V sembrado (`F10_RENDIMIENTO_MOBILE_S2.md` §3); app normal (instalada el 2026-09-06), `.f09voz` y `.f04date` intactas antes y después. `pointer_location` 1 durante las series (su barra y su cruz aparecen en las capturas: instrumento, no app).

| Flujo | Observado (UTC) |
|---|---|
| M1 | 15:19:51Z, `.f10eval2`: `POST /auth/v2/login 200`, `POST /auth/clients 201`, `POST /auth/v2/session/client 201`, `GET /auth/v2/me 200`. Titular creado en modalidad propia. Servidor: sesiones ACTIVE = 1, registros de cliente ACTIVE = 1. App normal intacta. (Dos `login 400` previos por la autocorrección del correo en SwiftKey, H-3 de rendimiento) |
| M2 | Serie R1 (17:03–17:05Z): 11 arranques en frío en modo avión + Wi‑Fi apagada hasta el Dashboard con importes, y serie R3 (17:06–17:08Z, misma sesión sin red): existencias visibles en la pestaña Inventario (fila `DSV-001` 1 895,8 L) en las 10 repeticiones; **0 peticiones** entre las 17:03Z y las 17:10Z; conteos sin cambio. **Nota (2026-10-18):** el dictamen de rendimiento de R1 se rectificó a BLOQUEADA por fin observado parcial (`F10_RENDIMIENTO_MOBILE_S2.md` §9); el resultado funcional de M2 se apoya en lo anterior, no en ese dictamen |
| M3 | Serie R2-b (17:22–17:36Z): 11 compras de 2 líneas sin red (una de ensayo + 10), cada una con +1 compra y +2 líneas (300 → 311, 600 → 622), listadas en **«Campaña DSV S2»**, la campaña de la fecha efectiva (hoy), tras la preparación de §3 del suplemento; 0 peticiones |
| M4 | 18:07:30Z, sin red: aplicación de DSV-002 (2 L) + DSV-005 (1 L) → aplicaciones 1 000 → 1 001, líneas +2, movimientos +2, en «Campaña DSV S2». Rechazo de 999 L de DSV-005 (había 192,3 L): «Disponible 192,3 L · stock después −806,7 L» en rojo y, al confirmar, «Revise las cantidades: todos los productos deben tener stock suficiente»; **conteos sin cambios** tras dos toques en «Confirmar aplicación»; borrador descartado |
| M5 | 18:12:57Z, sin red: Galería → Photo Picker de Android 16 → «Más opciones» → «Explorar…» → archivo `f10eval2_m5.jpg` elegido **por nombre** (sintético, SHA-256 `9108597c…47bd`, puesto en `Download/` por `adb push` y borrado al terminar; no se abrió ninguna foto personal). Compra de DSV-004 con «Factura»: compras 311 → 312, fotos 0 → 1, `app_flutter/invoices/invoice_…jpg` de 720 747 B (el selector entrega una copia recodificada) |
| M6 | Serie R4 (17:39–18:05Z): 11 intenciones (calentamiento + 10) declaradas sin red → PENDING / OUTCOME_UNKNOWN → `force-stop` → red → «Sincronizar ahora» → **ACKED**, journal FINAL APPLIED OK, 1 `refresh` + 1 `push` cada una; contribución `DECLARED_NEED` «Campana Invierno 2026 / Glifosato 48 SL», secuencia 11, 30 000 ML |
| M7 | 18:16:49Z: `POST /me/backups 201` (932 KB, esquema 10, SHA-256 `cccab257c510…`) y `GET /me/backups 200`. Restauración de esa copia en el mismo paquete (18:17:20Z `GET /me/backups/{id}/content 200`; diálogo «verificada con SHA-256. Contiene la base de datos y 1 fotografía(s)»; confirmada 18:17:49Z; se crea `agroquimicos_v2.db.previo-…`). **Huella de la base idéntica** (`8fa85b8e…`) y **conteos idénticos** (312/623/1 001/1 002/1 637, fotos 1, outbox 11 ACKED, integridad ok); **0 peticiones** en los 40 s siguientes |
| M8 | Capturas de la compra (arriba y abajo), de la aplicación con el rechazo, de Sincronización y del Inicio: sin textos cortados ni controles tapados por las barras del sistema. **Observaciones (MOB #129):** la etiqueta de la pestaña inferior se parte dentro de la palabra («Operacione / s»); el botón flotante «Nuevo» solapa parcialmente filas desplazables de las listas. No son cortes ni barras del sistema |

## A4-F (`font_scale` 1,3; 18:19:07Z – 18:42:40Z)

| Flujo | Observado (UTC) |
|---|---|
| M1 | Copia **`.f10eval2f`** instalada con `adb install -r` (Success); 5 paquetes `com.comunidad.agro.agroquimicos*` después, la app normal intacta. Activación con la cuenta sintética E2 a las 18:22:4xZ: `login 200`, `clients 201`, `session/client 201`, `me 200`; titular «Titular F10 A4F», modalidad propia; servidor: sesiones ACTIVE = 1, registros ACTIVE = 1. Pantallas de activación, titular e inicio sin cortes. **Incidente de instrumento:** con el IME desactivado, `input text` omitió letras del correo sintético (tres tecleos incompletos: el primero se envió y dio `login 401`; los dos siguientes se detectaron en el campo y no se enviaron; el HEAD `b83494c` decía «un intento sin enviar» por error de conteo, corregido el 2026-10-18 con el registro de la sesión); se tecleó por `keyevent` letra a letra y la contraseña con SwiftKey activo. La captura `af_m1_activacion.png` es anterior a la corrección del correo |
| M2 | 18:24:03Z, modo avión + Wi‑Fi apagada, `force-stop` y reapertura de `.f10eval2`: Dashboard («Campaña activa: Campaña DSV S2», Compras 1.300.263,64 Bs) e Inventario visibles; conteos iguales; **0 peticiones** |
| M3 | 18:24:51Z y 18:30:32Z: **dos intentos del instrumento** confirmaron compras de **una** línea (DSV-002 10 L, 500,00 Bs; compras 313 y 315) porque la recuperación de la cabecera de la línea con fuente grande falló y el guion confirmó sin comprobar el total; se declaran como **artefactos del arnés** (compras 313 y 315, +1 línea cada una) y motivaron los ajustes `758d9fe` de `ui.py`. **Tercer intento válido, 18:38:05Z:** compra de 2 líneas (DSV-002 10 × 50, DSV-003 5 × 40, «TOTAL COMPRA 2 productos · 700,00 Bs») confirmada sólo tras leer el total: compras 315 → 316, líneas 626 → 628, movimientos +2, en «Campaña DSV S2», 0 peticiones |
| M4 | 18:26:10Z, sin red: aplicación DSV-002 (2 L) + DSV-005 (1 L) → aplicaciones 1 001 → 1 002, líneas +2, movimientos +2. Rechazo de 999 L de DSV-005 (había 191,3 L): «Disponible 191,3 L · stock después −807,7 L» y «Revise las cantidades…»; conteos sin cambios; borrador descartado |
| M5 | 18:28:00Z, sin red: «Explorar…» → `f10eval2_m5.jpg` por nombre → compra de DSV-004 (3 × 20) con «factura adjunta» confirmada a las 18:30:16Z (el instrumento falló sólo en su comprobación final; la compra se confirmó a mano tras ver el formulario completo): compras 313 → 314, fotos 1 → 2, segundo `invoice_…jpg` de 720 747 B |
| M6 | 18:38:33Z, sin red: cambio de la necesidad a 31 L → outbox 12 `dc400dc4` SUPERSEDE (pred `6df147a1`) **PENDING** → `force-stop` → red → `am start` → «Sincronizar ahora» (18:39:53Z): 1 `refresh 200` + 1 `push 200` → **ACKED**, journal `dc400dc4` FINAL APPLIED OK, secuencia 12, aceptada 18:39:54Z; contribución ACTIVE 31 000 ML, head `dc400dc4`. «Sincronizado: 12» |
| M7 | 18:40:56Z: `POST /me/backups 201` (1,6 MB, 2 fotografías, SHA-256 `59120d1f8f60…`) + `GET 200`. Restauración de esa copia en el mismo paquete (18:41:12Z `GET …/content 200`; diálogo «verificada con SHA-256. Contiene la base de datos y 2 fotografía(s)»; confirmada 18:41:31Z): **huella idéntica** (`f14165b1…`), **conteos idénticos** (316/628/1 002/1 004/1 644, fotos 2, outbox 12 ACKED, necesidades 1), **0 peticiones** después; segundo `.previo-…` creado |
| M8 | **NO CUMPLE.** En «Nueva compra» el campo «Producto» de la línea muestra **«DSV-002 Producto si…»** (cortado con puntos suspensivos; el nombre completo sólo se lee en la cabecera de la línea); palabras partidas dentro de la palabra: **«Producto / s (1)»**, **«Pagado pr / oveedores»** (Inicio) y «Operacione / s» (pestaña); en el Inicio el botón flotante «Nuevo» **cubre el importe** de la tarjeta «Terceros por cobrar» hasta desplazar. La aplicación con el rechazo y Sincronización se leen completas. Issue **MOB #129** con reproducción |

## Capturas (SHA-256; sin barra de estado; se conservan en la carpeta local del ensayo y no se publican porque algunas muestran la cruz de `pointer_location`; ninguna contiene datos personales)

| Archivo | SHA-256 |
|---|---|
| `a4_m4_rechazo.png` | `b9390f997241f38dbfb849e2eccf2455d8c74c164c477350346437df872e921b` |
| `a4_m5_tras_elegir.png` | `c9fee82ef94642ebb889c27ed284dc44aa6f7ea89b6bf854be8cdfe86369da86` |
| `a4_m7_restaurar_dialogo.png` | `2ca37fe3b575928a047f61e7e1c440219bf2c42e26b372d4324eb3712ab33074` |
| `a4_m8_aplicacion_rechazo.png` | `54abd0eeb4f084005b8f2f3905fa6f46bcb1e722d23b80193ca3eac1559d789a` |
| `a4_m8_compra_top.png` | `5d96f81d602b7e5e1c6dffd23b9937bb89adc50eecb09981029186f2b28aea4d` |
| `a4_m8_compra_bottom.png` | `e60f0ac48fc2f71cda0612f689306999bfbc114863f2d1dfa6a883c845d28cf3` |
| `a4_m8_sync.png` | `cff28e744248e3b9a846519e91e2afbfba54a94ca721792f77e8234fdfdadbe4` |
| `af_m1_inicio.png` | `7a6464303b3e67acdad10e8e56264192c4fb16fc25e9eb96db77781a1e9a3ef4` |
| `af_m1_activacion.png` | `3bbffc7c8a20c4b4c8f2de9b6034d89639c8af0838cd1646638d5aab1f1552eb` |
| `af_m1_titular.png` | `27780af0788d940f00eb6d569cfa107eeec3d2e6486f93529da611d51125dfe1` |
| `af_m1_inicio_app.png` | `7a1fba51a9cc18895360768871de84e0795216a0232b7c870374ae4be6d94465` |
| `af_m8_inicio.png` | `7b917441d80787deddaac033687b61c57bfa037cad367ec4e5bad5b4b1dc2f2f` |
| `af_m8_compra_top.png` | `1c8fc79a041992e1d65d4e951118be80e7fa788556fadf38bf4782e2e988c331` |
| `af_m8_compra_bottom.png` | `0ea7f09e340e8a435875a72690b8b610f681169ce327f9aad0d8e6283eea4134` |
| `af_m8_aplicacion_rechazo.png` | `7e68f95e649feec799ea42397cc18ce26cda9a2340d1c2d83101c5c05d044718` |
| `af_m5_formulario.png` | `09bda03beddbd4c1e4d7f0814c5639c2be130b669d1e945e3cb3875ad6bd6b9d` |
| `af_m7_restaurar_dialogo.png` | `3b916c8a23ae2093bad01e61430d000e4fbc1dada1f20e00824fcaa8023a0a2a` |
| `af_m8_sync.png` | `bb1ada16e1047d20afabd3a8c3666529fa79c27c77a671544263177a178aab5e` |

## Logcat (`logcat_scan.sh`, en memoria, 18:42:38Z)

- `.f10eval2`: contraseñas 0, nombres de campos sensibles 0, FATAL/Unhandled 0, campos sensibles 0; **1 valor opaco de 43+ caracteres** en el logcat del sistema (no en el registro propio de la app, que da 88 líneas con JWT 0, UUID 0, refresh/token/password 0, opacos 0, campos 0). Se declara; la misma lectura aparece en la serie 1 como línea del sistema (IME).
- `.f10eval2f`: FATAL 0; 1 valor opaco de 43+ (sistema); registro propio 88 líneas, todo 0.

## Limitaciones

- Un solo teléfono físico en esta serie; A4-F es el mismo equipo con otra escala de fuente. La serie no repite A1, A1-F ni A2.
- La matriz no comprueba equipos reales de la Directiva ni de los agricultores.
- M2, M3 (A4) y M6 (A4) se toman de las series R1, R2-b y R4 de rendimiento (mismo equipo, misma copia, mismo día), como en la serie 1.
- Las dos compras de una línea de M3 (A4-F) son artefactos del arnés y quedan en la base de la copia aislada; se declaran y no se cuentan como flujo.
- Datos sintéticos, APK profile, operación por `adb`. Sin inspección personal de Roderich, sin revisión del tutor ni validación institucional. GATE-F10 (BE #49) sigue Pending.
