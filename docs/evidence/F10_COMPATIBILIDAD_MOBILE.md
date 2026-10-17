# F10 — Compatibilidad Mobile (RNF-08): A1, A1-F, A2 y A3

- **Fecha real:** 2026-10-17 (UTC), de 01:10Z a 04:40Z.
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica. Sin inspección personal de Roderich ni revisión del tutor.
- **Protocolo:** v1.0 `72a03be`, v1.1 `7581af2`, v1.2 `9292425` y v1.3 `9bfcad2` (rama del PR BE #122), §2.
- **APK evaluada** (la misma en todas las configuraciones):
  - copia aislada `com.comunidad.agro.agroquimicos.f10eval`, modo profile, SHA-256 `93939041348bc102d5c38f158bf2b4bfb3ff588934f74ca9f91658e897022428`;
  - Mobile `dff6802`;
  - `minSdkVersion` **24** y `targetSdkVersion` **36**, leídos con `aapt2 dump badging`, que es lo que exige la configuración A3.
- **Backend:** `ed069a6` compilado, entorno `agro_a_f10eval_pg`, túnel HTTPS.
- **Lo que no es:** este documento **no** afirma compatibilidad con equipos que no se ejecutaron, ni que la selección sea la de los equipos reales de la Directiva.

## Matriz

Resultados por celda: **CUMPLE**, NO CUMPLE, BLOQUEADA o **NO EJECUTADA**. Las procedencias no se mezclan.

| Flujo | A1 · POCO, Android 12 (DEVICE) | A1-F · POCO, `font_scale` 1,3 (DEVICE) | A2 · Pixel_8, Android 16 / API 36 (EMULADOR) | A3 · API 24, pantalla pequeña (EMULADOR) |
|---|---|---|---|---|
| M1 Instalación y activación | CUMPLE | CUMPLE (copia `.f10c23x`, ver detalle) | CUMPLE | NO EJECUTADA |
| M2 Reapertura sin red | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M3 Compra de 2 líneas sin red | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M4 Aplicación y rechazo por saldo | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M5 Foto de comprobante | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M6 Necesidad y sincronización | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M7 Respaldo: subir y restaurar | CUMPLE | CUMPLE | CUMPLE | NO EJECUTADA |
| M8 Presentación | CUMPLE (con observación, MOB #97) | **NO CUMPLE** (MOB #97) | CUMPLE | NO EJECUTADA |
| **Configuración** | **compatible** (DEVICE) | **no compatible** (M8) | **compatible** (EMULADOR) | **NO EJECUTADA** |
| A4, A5 (otro teléfono físico) | — | — | — | **NO EJECUTADAS:** no hay equipo real disponible. No se afirma compatibilidad |

**RNF-08:** se informa configuración por configuración.
- **A1** (DEVICE) y **A2** (EMULADOR): compatibles.
- **A1-F:** no compatible (M8, MOB #97).
- **A3, A4 y A5:** no se ejecutaron.

Por eso **RNF-08 no se declara cumplido globalmente** para la selección.

## A2 (EMULADOR): detalle

**Entorno:**
- emulador Android 37.1.11.0 con el AVD `Pixel_8` (imagen `android-36.1;google_apis_playstore_ps16k`, x86_64, 1080×2400, 420 dpi, `font_scale` 1.0, 2 GB de RAM);
- cuenta sintética S, titular «Titular F10 A2», modalidad propia;
- DS-V sembrado igual que en A1, con la base devuelta y el SHA verificado;
- sesión de 01:18Z a 01:41Z.

El AVD tiene instaladas otras apps (la app normal y bancos de voz de trabajos anteriores), que no se tocaron.

| Flujo | Observado |
|---|---|
| M1 | Login 200, `auth/clients` 201, `session/client` 201 y `me` 200 (01:18:44–46Z). Titular creado. En el servidor: sesiones ACTIVE = 1, registros ACTIVE = 1 |
| M2 | En modo avión y tras `force-stop`: Dashboard con DS-V e Inventario visibles; conteos iguales antes y después; **0 peticiones** |
| M3 | Sin red: compra de 2 líneas (DSV-002 10 L y DSV-004 5 L, 700,00 Bs). Compras 300 → 301, líneas 600 → 602, +2 movimientos, integridad ok, 0 peticiones |
| M4 | Aplicación de DSV-002 (2 L) + DSV-005 (1 L): aplicaciones +1, líneas +2. Rechazo de 999 L de DSV-005 (había 192,3 L): mensaje «Revise las cantidades: todos los productos deben tener stock suficiente», disponible en rojo con «stock después −806,7 L» y **conteos sin cambios** |
| M5 | Galería → Photo Picker de Android 16 → foto sintética `dsv_photo_001.jpg` (con «factura adjunta»). Compra 301 → 302, fotos 0 → 1, archivo en `app_flutter/invoices` (788 856 B: el selector entrega una copia recodificada) |
| M6 | Vínculos con «Campana Verano 2026» y «Glifosato 48 SL». Necesidad de 12 L declarada sin red: `OUTCOME_UNKNOWN/NETWORK`, con acceso verificado en memoria (válido según el M6 corregido). Con red y «Sincronizar ahora»: un push 200 → **ACKED**. Journal `1e57c97f` FINAL APPLIED, secuencia 1, contribución ACTIVE |
| M7 | Subida: 998 KB, `POST /me/backups` 201 y `GET` 200. Restauración de esa copia en la misma copia aislada: «verificada con SHA-256… 1 fotografía». **Conteos iguales antes y después** (compras 302, líneas 603, aplicaciones 1 001, líneas 1 002, movimientos 1 617, fotos 1, outbox 1 ACKED, integridad ok); **0 peticiones en 38 s** tras confirmar |
| M8 | Capturas de la compra (arriba y abajo), de la aplicación con el rechazo y de Sincronización. Sin controles tapados por las barras del sistema (edge-to-edge de Android 15+) y sin textos cortados |

**Capturas** (SHA-256; se conservan en la carpeta del ensayo):

| Archivo | SHA-256 |
|---|---|
| `m4_rechazo2.png` | `4a6e7508c7eba7437d4940de8df9444f173a896bea26fd7789f5e3cd103ea0c1` |
| `m5_tras_elegir.png` | `91396cbc5d689c458e190cb4596c345cc811662590cc529ce527abf59ccf31a7` |
| `m8_compra_top.png` | `737c980221668a54f15b5432a8384e3bc19494b394c3b938553b1c216de77810` |
| `m8_compra_bottom.png` | `f34ac7ad1cd2fae85250ae5f4ca18811cb5cdaa80ef0f88169592989752d3a99` |
| `m8_sync.png` | `0ae1ff7bcf1c6d188b9160e62e8f1e8b94e979e1af6ede47fdc17154720b0995` |

La captura del selector no se publica: muestra capturas antiguas del emulador ajenas al ensayo.

## A1 y A1-F (DEVICE)

**Entorno:**
- POCO X5 Pro 5G `22101320G`, Android 12 / API 31, MIUI `V14.0.7.0.SMSMIXM`, 1080×2400, 440 dpi;
- cuenta sintética D, titular «Titular F10 EVAL», modalidad propia, DS-V sembrado (`F10_RENDIMIENTO_MOBILE.md`);
- la app normal sigue intacta (instalación del 2026-09-24 13:04:32) y las copias de ensayos anteriores no se tocaron.

**Ajustes durante la sesión:**
- `font_scale` 1,0 en A1 y 1,3 en A1-F (desde las 04:23:54Z);
- `pointer_location` 1 desde la serie R3 (instrumento; su barra aparece en las capturas y no es de la app).

**Ajustes restaurados al terminar (04:49Z):** `font_scale` 1.0, `pointer_location` sin definir (como antes), `show_touches` 0, `stay_on_while_plugged_in` 0 y modo avión 0.

**A1** (`font_scale` 1,0):

| Flujo | Observado (UTC) |
|---|---|
| M1 | 01:10:34Z: login 200, `auth/clients` 201, `session/client` 201 y `me` 200. Titular creado. En el servidor: sesiones ACTIVE = 1, registros ACTIVE = 1. App normal intacta |
| M2 | Serie R1: 11 arranques en frío en modo avión hasta el Dashboard con datos, con **0 peticiones** (01:49–01:53Z). R1 no cambia conteos |
| M3 | Series R2-a y R2-b: 20 compras de 2 líneas sin red. En cada una, +1 compra y +2 líneas y la compra listada. 0 peticiones entre 01:53Z y 02:29Z |
| M4 | 04:19Z, sin red: aplicación de DSV-002 (2 L) + DSV-005 (1 L) → aplicaciones 1 000 → 1 001, líneas +2. Rechazo de 999 L (había 192,3 L): «Revise las cantidades: todos los productos deben tener stock suficiente», conteos sin cambios |
| M5 | 04:21Z, Android 12: Galería → Photo Picker → «Más opciones» → «Explorar…» → archivo `f10eval_m5.jpg` (sintético, elegido por nombre, sin ver fotos personales). Compra con «factura adjunta»: compras 321 → 322, fotos 62 → 63, `invoice_…jpg` de 788 936 B. 0 peticiones |
| M6 | Serie R4: 10 intenciones (+1 calentamiento) declaradas sin red → OUTCOME_UNKNOWN → «Sincronizar ahora» → **ACKED**, con journal 1 cada una y 1 refresh + 1 push |
| M7 | Serie R6: 18 subidas con 201 y verificación. Restauración completa de la copia S3 más reciente (49,6 MB, 62 fotografías, «verificada con SHA-256»). Descarga a las 04:12:14Z y restauración a las 04:13:17Z (se crea `.previo`). **Conteos idénticos** (321/642/1 000/1 000/1 654, fotos 62, outbox 11 ACKED, integridad ok) y **0 peticiones** después, hasta las 04:17:35Z |
| M8 | Compra (arriba y abajo), aplicación y Sincronización: nada tapado por las barras ni texto cortado. **Observación:** el título «Sincronización» se parte dentro de la palabra («Sincronizació / n») junto a «Sincronizar ahora» (MOB #97). No es un corte de texto |

**A1-F** (`font_scale` 1,3, 04:23–04:40Z):

| Flujo | Observado |
|---|---|
| M1 | Con la copia nueva `com.comunidad.agro.agroquimicos.f10c23x`, preparada para C23: APK profile del **mismo código** `dff6802`, distinta sólo por el sufijo y la etiqueta (SHA-256 `878916a5e4e44c861184664977d565d462578b2468a5a45a2e4967c58a4f9d52`). Activación con la cuenta sintética E2 a las 04:39:14Z: login 200, `auth/clients` 201, `session/client` 201 y `me` 200. Titular «Titular C23». ACTIVE = 1/1. Pantallas de activación y titular sin cortes. **Desviación:** no es la misma APK que `.f10eval`, que no se reinstaló para no perder sus datos |
| M2 | En modo avión y tras `force-stop`: Dashboard («Campaña activa», compras) e Inventario visibles. Conteos iguales; 0 peticiones |
| M3 | Compra de 2 líneas sin red: 322 → 323, líneas 643 → 645, listada. El controlador de interfaz tuvo que desplazarse más con la fuente grande; no es un fallo de la app |
| M4 | Aplicación de 2 productos: +1/+2. Rechazo de 999 L con el mismo mensaje, conteos sin cambios |
| M5 | Foto por «Explorar…»: «factura adjunta», compras 323 → 324, fotos 63 → 64 |
| M6 | Cambio de la necesidad a 31 L sin red (SUPERSEDE `b3cb4ca6`, PENDING) → `force-stop` → red → «Sincronizar ahora» → `refresh` 200 + `push` 200 (04:31:44Z) → ACKED. Journal FINAL APPLIED, secuencia 12 |
| M7 | Subida de 51,1 MB (`POST /me/backups` 201, 04:33:19Z) y restauración de esa copia en el mismo paquete (04:34:39Z; «verificada con SHA-256… 64 fotografías»). Conteos idénticos (324/646/1 002/1 004/1 662, fotos 64, outbox 12 ACKED, integridad ok) y 0 peticiones después |
| M8 | **NO CUMPLE:** el título de «Nueva compra» se corta como **«Nueva com…»** junto a «Confirmar», y la persona de «Asignaciones», como «Titular F1…». Además, «Sincroni / zación» se parte dentro de la palabra. Issue **MOB #97** con reproducción. La aplicación y el Dashboard se leen completos |

**Capturas** (SHA-256; se conservan en la carpeta del ensayo; las del selector de fotos no se tomaron):

| Archivo | SHA-256 |
|---|---|
| `a1/m8_compra_top.png` | `29698edc3e9a2ee137b22c027e547ee978a09ebae8a73f9da98d9de427c87f05` |
| `a1/m8_compra_bottom.png` | `8c4f513c480e2c159103b5b89586f008047823ffd04d7a1a1ec1270cda1fc3c2` |
| `a1/m8_aplicacion.png` | `8f0e78f556212b0a9aa42e3a823438bfa130206f7eb4f206773db68224e1df44` |
| `a1/m8_sync.png` | `062b7696b0130955b02a9676ff007d581be8a26e8e03384b1fa12e7bb10d9569` |
| `a1_m4_rechazo.png` | `4549fa7c420346f15bcfd77f991df996217be31753eea9647db2053e345bc59e` |
| `a1_m5_tras_elegir.png` | `b395d3a447c6bcdc3d45fda02f9f641a76db7254788904d25ae8f391449d237c` |
| `af/m1_activacion.png` | `fc6340dfb57cc188ea038fa711f2c3e4661a0ad43158a9169fda81e4cde7cddf` |
| `af/m1_titular.png` | `3a7b589dc4eddc8ea5590f045fef19df22845f2663599682896de6d9b80cf97b` |
| `af/m1_inicio.png` | `29b1b48059bccc36bbba50dfd179dc7e19f744ca4c14acfc5a9508e98366b47d` |
| `af/m8_compra_top.png` | `3f205cfc5f6a6262f89c6ae2e3dd4717c6660debb02ccd9bc0a8dfd43fe11e49` |
| `af/m8_compra_bottom.png` | `122d15c8b3305975729a0acd6adc48f14b91008278f57d0b96db15792daecafd` |
| `af/m8_aplicacion_rechazo.png` | `2d6ead6ad1ff326417df40b8739b7fc9d9472fc38fecdab0a1b4329ad49e8a86` |
| `af/m8_inicio.png` | `f09565b3db9758db761e63fcf08c4cbc5d0cc9452b0b6dffe9d1668e84f61deb` |
| `af/m8_sync.png` | `4e47617a84a60b8766abfea2b61213ec00e5bf1c73217bd1fd725c6d33e31682` |

**Logcat de `.f10eval`** (`logcat_scan.sh`, 949 líneas, en memoria):
- JWT 0, UUID completos 0, contraseñas 0, campos sensibles 0, valores opacos 0 y FATAL 0;
- registro propio: 99 líneas, todo 0.


## A3: NO EJECUTADA

- **Configuración exigida:** la API del `minSdk` real de la APK, **24**, con pantalla pequeña.
- **Causa:** en este PC sólo está instalada la imagen `system-images;android-36.1;google_apis_playstore_ps16k` (comprobado en `Android/Sdk/system-images`).
- **Decisión:** no se descargó una imagen de API 24 en este bloque. Por capacidad de la máquina, la ventana de medición se reservó para R1–R6 en el POCO.
- **No se sustituye** por otra API.

## Limitaciones

- **Un solo teléfono físico** (MIUI). A1-F es el mismo equipo con otra escala de fuente.
- **Procedencias separadas:** el emulador no es un dispositivo.
- **La matriz no comprueba equipos reales de la Directiva** ni de los agricultores.
