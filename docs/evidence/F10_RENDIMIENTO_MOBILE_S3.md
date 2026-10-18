# F10 — Rendimiento Mobile (RNF-06), serie 3 acotada: R1 en el POCO (A1) sobre la base con MOB #129

- **Fecha real:** 2026-10-18 (UTC), de 21:55Z (entorno) a 22:23Z (ajustes restaurados). En America/La_Paz, de 17:55 a 18:23.
- **Ejecutó:** la sesión A de Claude Code, por delegación técnica de Roderich Rendón (encargo del 2026-10-18 §3 «repetición física acotada», con su indicación de usar el POCO por ser el teléfono conectado). Medición técnica automatizada por `adb`. **Sin inspección personal de Roderich, sin revisión del tutor, sin evaluación con usuarios.**
- **Protocolo:** `docs/evaluation/F10_PROTOCOLOS_EVALUACION.md` v1.3 (`9bfcad2`, Backend), **sin cambios de umbrales, repeticiones ni criterios**, más el suplemento `docs/evaluation/F10_SUPLEMENTO_SERIE3_2026-10-18.md` (PR BE #141; versión `b3013f0` con LISTO limpio de C a las 22:00:33Z y de B a las 22:00:40Z, **antes de la primera medición** (R1, 22:06:35Z); `209e28c` sólo añade §6 con esas horas).
- **Serie:** **3**, acotada a lo afectado por MOB #129 (suplemento §3). Las series 1 (POCO, `dff6802`, 2026-10-17) y 2 (HONOR, `ad5b43d`, 2026-10-18) se conservan tal cual. **R1 de la serie 2 sigue BLOQUEADA** (fin parcial) y no se sustituye por esta: equipo y base distintos. **R2, R3, R4, R5 y R6 no se repiten** (§5).
- **Issues:** BE #48 (F10-QA-04). GATE-F10 (BE #49) sigue **Pending**. MOB #129 (cerrado por el PR #131), MOB #97.

## 1. Resultado (n de aceptación; p90 por rango más cercano, el 9.º de 10)

| Medición | Red | n | Crudos (ms, en orden de ejecución) | Mediana | p90 | Máx. | Errores | Criterio (v1.3 §1.5) | Resultado |
|---|---|---|---|---|---|---|---|---|---|
| **R1** arranque hasta el Dashboard con datos (**fin completo de §1.5**, fijado en el suplemento §3: tarjetas con importes + primera fila de la tabla de existencias con su nombre visible y las celdas recortadas por la barra de pestañas; sin indicador de carga) | N0 | 10 (+1 calentamiento: 1 140,9) | 1101,6 · 1076,9 · 1102,6 · 1051,6 · 1085,5 · 1080,0 · 1085,9 · 1076,2 · 1060,0 · 1065,9 | 1 078,45 | **1 101,6** | 1 102,6 | 0 | p90 ≤ 4 000 | **CUMPLE** |

- **Métrica auxiliar:** `TotalTime` de `am start -W`: 734 · 731 · 735 · 721 · 741 · 755 · 735 · 741 · 733 · 731 (mediana 734,5; p90 741; máx 755; calentamiento 792). No es «Dashboard utilizable».
- Ningún umbral se cambió después de medir. El calentamiento se anota aparte y no entra en las repeticiones de aceptación (§0.8). La mediana lleva dos decimales porque el promedio de los dos valores centrales (1 076,9 y 1 080,0) lo exige.
- **0 peticiones** en el observador entre las 22:06Z y las 22:10Z (modo avión real: `Active default network: none`).

## 2. Versiones y entorno

| Elemento | Valor |
|---|---|
| Mobile medido | Código de `lib/` = **`27c4654`** (corrección de MOB #129, PR #131). **APK compilada desde el worktree limpio en `9cbd565`** (HEAD del PR en ese momento; `9cbd565` y `ae491c0` sólo añaden `docs/evidence/`): `git diff --stat 27c4654 9cbd565 -- lib test` y `git diff --stat 27c4654 196372a -- lib android pubspec.yaml` vacíos. **`main` = `196372af1aa2779b224bbbf050af50eb10aeba3e`** (merge del PR #131 a las 22:09:44Z, después de R1; mismo árbol de `lib/`). Cambios de `lib/` frente a la base de la serie 2 (`ad5b43d`): 5 archivos de `lib/presentation/` (+187/−64), sólo presentación |
| APK | Copia aislada **`com.comunidad.agro.agroquimicos.f10eval3`** («Agrocuentas F10-EVAL3»), **modo profile**, compilada el 2026-10-18 21:58:43–22:00:10Z con `tool/f10_eval/build_profile_apk.sh` y el origen HTTPS del túnel; SHA-256 **`f585c09846a4462a74d6030e717ced105c2071691cb24ce609d5968efe9c17f8`**, 87 913 069 B; `aapt2`: `minSdkVersion 24`, `targetSdkVersion 36`, `application-debuggable`. Firmada con la clave local de depuración: **no distribuible**. Instalada con `adb install -r` (Success, 22:00:31Z, diálogo «Instalar vía USB» de MIUI aceptado por `adb input tap`); después, 16 paquetes `com.comunidad.agro.agroquimicos*`: la app normal y las copias de ensayos anteriores (`.f10eval` de la serie 1 incluida) intactas |
| Backend | `main` **`6c54c00`** (código = `cab433d`; `main` actual `ee948a1` sólo añade docs y `tool/f10_eval_web/`: `git log cab433d..origin/main -- Back/src Back/prisma Web/src` vacío). `dist` compilado sobre `6e4a0e2` (código idéntico). `node dist/main.js`, `NODE_ENV=production`, contenedor nuevo **`agro_a_f10eval3_pg`** (postgres:16-alpine), 11 migraciones, seed demo sintético (12 agricultores, 14 productos, 72 lotes), contraseñas rotadas; API 3134, observador 3135; `SYNC_V1_PRODUCTION_ADMISSION=enabled`, `BACKUP_PRODUCTION_ADMISSION=enabled` sólo en este entorno desechable. Sólo se usó para la activación; no hay R4 |
| Red | N0 para R1. Túnel Cloudflare (`cloudflared` 2026.10.0) sólo para la activación (21:57:45Z–22:23Z) |
| Herramienta | `tool/f10_eval/` en **`758d9fe`** (rama `eval/f10-serie2-mobile-tools`, PR MOB #128 abierto; no está en `main`), copiada al entorno local con `git archive`; no cambia `lib/`. Valores por defecto del POCO: `F10_SCREEN_WIDTH=1080`, vídeo `720x1600`, región de fin de R1 `0,700,1080,1350`, inicio por `am start -W` (modo `launch`). `frames.py` con `--screen-width 1080` |
| Dispositivo (**A1**) | **POCO X5 Pro 5G** (`22101320G`, `redwood`), Android **12** (API **31**), MIUI V14 (`SKQ1.220303.001`), parche de seguridad 2023-03-01; **1080×2400**, 440 dpi, 120 Hz; barra de navegación de tres botones; `font_scale` propio **1,0**. Mismo equipo de la serie 1 |
| PC | Intel Core i7-13700HX, 23,7 GB de RAM, Windows 11 Home; durante V3 ninguna otra sesión compiló, midió ni levantó servicios (B y C avisados por mensaje a las 22:07Z; V3 cerrada a las 22:10:02Z) |

**Condiciones del teléfono** (`f10_eval_s3/condiciones.txt`): cargando por **AC** (`AC powered: true`), batería 100 % durante R1, temperatura 32,0 °C al empezar R1 y 33,0 °C al terminar, `Thermal Status 0`, `low_power 0`; `stay_on_while_plugged_in` 3 durante las series (previo 0); `screen_off_timeout` 600 000 (sin cambio). Las apps en segundo plano no se cerraron (declarado). **Ajustes cambiados y restaurados al terminar (22:23:18Z):** `pointer_location` sin definir → 1 → sin definir; `stay_on` 0 → 3 → 0; modo avión 0 → 1 → 0 (el modo avión del POCO apaga la Wi‑Fi: `wifi_on` pasó a 3 y volvió a 1); `font_scale` 1,0 → 1,3 (sólo en la compatibilidad A1-F) → 1,0.

## 3. Dataset DS-V (protocolo §1.4)

- **Activación (preparación, no caso M1):** 22:02:55Z, cuenta sintética D, titular «Titular», **modalidad propia**. Peticiones: `POST /auth/v2/login 200`, `POST /auth/clients 201`, `POST /auth/v2/session/client 201`, `GET /auth/v2/me 200`. Correo tecleado con el orden «resto → inicio → nombre» para evitar la autocorrección de Gboard (sin incidentes).
- **Siembra** (`seed_dsv_mobile.dart`, semilla 20261016, 22:04:27–22:04:53Z) sobre la base extraída de la copia activada (266 240 B antes), con la app detenida: 100 productos, 5 proveedores, 1 campaña, 300 compras / 600 líneas, 1 000 aplicaciones / 1 000 líneas, 1 612 movimientos, 0 saldos negativos, `integrity_check` ok, `sync_outbox` 0 → 0, `DSV-001` 271 movimientos (260 líneas; máximo de los demás 26), 901 120 B. Devuelta con `adb push` + `run-as cp` (H-6 de la serie 2): **SHA-256 `4db79d7c9ef4f9a046bf9fba7e975a578e87344097737eebfedcbf1b579b37e5` igual en el host y en el dispositivo**; conteos leídos en el dispositivo: 300/600/1000/1000/1612, outbox 0, integridad ok. Misma composición que las series 1 y 2 (la huella difiere de la serie 2 por la activación distinta).
- La campaña DS-V (desde el 30/09/2025, sin fin) contiene la fecha de hoy: no hubo preparación de campañas ni vínculo central (no hay R4 en esta serie).

## 4. Instrumento y fin observable de R1

- **Vídeo:** `screenrecord` a 720×1600 (escalado 2:3 de 1080×2400, como en la serie 1), 12 Mbit/s; `frames.py --screen-width 1080`. Inicio: primer cuadro que cambia respecto del lanzador tras `am start -W` (no incluye la latencia entre la orden y ese cuadro; `TotalTime` se publica aparte). Fin: región `0,700,1080,1350` estable (tarjetas, cabecera «Inventario proyectado», buscador y primera fila; incluye el botón «Nuevo», que se construye con el armazón antes de los datos, como en la serie 1).
- **Fin observable fijado antes de medir** (suplemento §3, dictamen de B y C): tarjetas con importes + **primera fila de la tabla de existencias con su nombre visible y las celdas recortadas por la barra de pestañas**. Apoyo en el código (C): `DashboardScreen` construye tarjetas, cabecera y filas en el mismo cuadro con un único `FutureBuilder`; en anchos < 560 dp el inventario es la lista `_InventoryCards` (UIBUG-023) y cada fila es una sola `Column`: si se ve el nombre, la fila con sus valores está construida; el recorte de la barra es disposición, no carga.
- **Condición (b):** el cuadro de fin conservado de la serie 1 (`r1_00_fin_148.png`, POCO, `dff6802`, en local) muestra el mismo fin (primera fila «DSV-001 Producto sintético» con las etiquetas de celda cortadas por la barra; botón «Nuevo» sobre el buscador): equivalencia afirmada.
- **Condición (c), de paso, superada (22:05:15Z, `font_scale` 1,0, sin medir):** volcado de `uiautomator` sobre `.f10eval3` con el DS-V: cabecera «Inventario proyectado» (y centro 1 763) y «Ver todos» en la misma línea, buscador (1 895), botón «Nuevo» (1 929) y **primera fila «DSV-001 Producto sintético Físico 1.895,8 L …» con el nombre en pantalla (y ≈ 1 990–2 050)** y las celdas bajo la barra de pestañas (desde y 2 050). Captura `a1_c_inicio_1_0.png` (SHA-256 `975b2c8b38bec22dafdc5072078baefadaa843af33b08dc6527833d85a0c9d1c`; no se publica: pantalla con datos sintéticos, como en las series anteriores).
- **Condición (d):** los cuadros de fin exportados de las **11** repeticiones (`r1_00_fin_150` … `r1_10_fin_139`) se revisaron **uno por uno a la vista**: en todos aparecen «Campaña activa: Campaña DSV 2025-2026», Compras 1.292.503,64 Bs, Familias por cobrar 98.513,66 Bs, la cabecera, el buscador y la primera fila «DSV-001 Producto sintético» con las celdas recortadas por la barra; ninguno muestra indicador de carga. Los cuadros no se publican (el lanzador del teléfono muestra contenido personal en los cuadros de inicio).
- **Persistencia:** `eval_counts.sh` por `run-as` antes y después (sólo lectura: sin cambio).

## 5. Serie R1 (N0, 22:06:30–22:09:07Z) y lo que no se repite

- Modo avión desde las 22:06:16Z (`airplane_mode_on=1`, `Active default network: none`); `pointer_location` 1; `stay_on` 3. Cada repetición: `am force-stop`, HOME, 3 s, `screenrecord` y `am start -W` (`series_n0.sh r1 0 10`).
- Calentamiento (rep 0, 22:06:35Z): 1 140,9 ms (`TotalTime` 792). Repeticiones 1–10 (22:06:52Z – 22:08:58Z, una cada ≈ 14 s): sin errores.
- **R2-b: no se repite** (suplemento §3: el recorrido medido —contacto en «Confirmar compra» → compra en la lista— no cambia; los cambios de #129 son previos al inicio observable). **Ensayo de herramienta hecho en V4 (sin medir):** `ui.py purchase-form` de `758d9fe` **no completó por sí solo** la compra de 2 líneas en el POCO a `font_scale` 1,0 (se detuvo con «no se ve la cabecera de la línea 2» tras elegir el producto de la línea 2, con la cantidad sin rellenar); la línea 2 se completó con pasos manuales por `adb` (cantidad y precio tecleados en los campos bajo la cabecera «2 DSV-003») y el formulario llegó a «TOTAL COMPRA 2 productos · 700,00 Bs» (ver `F10_COMPATIBILIDAD_MOBILE_S3.md`, M3). **Consecuencia:** el instrumento de R2-b de `758d9fe` no está confirmado para el POCO con esta base; si R2 se repitiera alguna vez en el POCO, habría que ajustar y ensayar la herramienta antes. No afecta a R1 (modo `launch`, sin formulario).
- **R3, R4, R5, R6: no se repiten** (sin cambio que los afecte; suplemento §3). Conservan su evidencia: R3/R4 de la serie 2 (HONOR) y de la serie 1 (POCO); R5 de B (serie 2); R6 histórico.

## 6. Hallazgos e incidentes del arnés

- **H-1. Herramienta de compra en el POCO** (§5): fallo del instrumento `758d9fe` en la línea 2 a 1,0; a 1,3 sí completó la línea 2, pero el paso manual de respaldo añadió dígitos a campos ya rellenos (55 L × 4 040 Bs/L); se detectó al leer la cabecera de la línea y se corrigió antes de confirmar (nada se escribió con esos valores). Detalle en la evidencia de compatibilidad.
- **H-2. `wifi_on=3`** con el modo avión activo en MIUI (valor propio del sistema; la red activa era «none»). Al desactivar el modo avión volvió a 1.
- **H-3. Rutas MSYS:** con `MSYS_NO_PATHCONV=1` exportado, `python` no encuentra rutas `/c/…` y `eval_counts.sh` no abre su copia temporal; se ejecutaron sin esa variable (la herramienta ya la aplica por línea a las rutas del teléfono).
- **H-4. `F03_APP_PACKAGE`** no se exporta desde `config.sh` cuando el guion se invoca con `bash` desde otro directorio; se exportó a mano para `eval_counts.sh`.
- **H-5. Condición del PC:** B y C inactivas durante V3; sin compilaciones ni suites ajenas.

## 7. Limitaciones

- **Un solo teléfono (POCO, Android 12).** No se generaliza. **A4/A4-F (HONOR) no se repiten con el POCO**; la R1 BLOQUEADA de la serie 2 queda como está.
- **La APK profile** es depurable y está firmada con la clave local; código Dart AOT. El SHA de compilación es `9cbd565`, no el merge `196372a` (mismo `lib/`, `android/` y `pubspec.yaml`).
- **La herramienta no está en `main`** (PR #128 pendiente de Roderich); se registra su SHA `758d9fe`.
- **La grabación añade carga** al teléfono; se declara. **El teléfono cargaba por AC** (`stay_on` 3 por ese motivo).
- **Datos sintéticos; sin red en R1.** Sin inspección personal de Roderich, sin revisión del tutor ni validación institucional. **GATE-F10 sigue Pending; RNF-06 no se declara cumplido globalmente** por esta serie (R1 serie 2 BLOQUEADA; A3/A5 no ejecutadas).

## 8. Archivos

- `f10_eval_s3/r1.csv` (crudo: horas UTC, cuadros, duraciones, `TotalTime`, huella corta del vídeo) y `f10_eval_s3/condiciones.txt`.
- Huellas SHA-256 (archivos con LF): `r1.csv` `805d40cdfe3ea2dd55cd6066adc9a6a77fe19ee094fee37d247d0da78c726584`; `condiciones.txt` `e280fd20f7229dc77200f6179eeedd802025c48b8c86bf23b9df86aa2fbf0cd2`.
- Vídeos (`r1_00.mp4` … `r1_10.mp4`), cuadros y capturas: conservados en local (`agro_a_f10eval3/`), no publicados.
- Compatibilidad del mismo día y equipo: `F10_COMPATIBILIDAD_MOBILE_S3.md`.
- Al terminar (22:23:18Z): `font_scale` 1,0, `pointer_location` sin definir, `stay_on` 0, modo avión 0, Wi‑Fi 1; API, observador y túnel detenidos; contenedor `agro_a_f10eval3_pg` detenido con el volumen conservado; la copia `.f10eval3` queda instalada con sus datos (DS-V + 1 compra de M3).
