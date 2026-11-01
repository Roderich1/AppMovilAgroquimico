# F04-AV — Complemento DEVICE: con y sin conexión, existencia baja total, lote agotado y consultas que no cambian la base

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01, de 17:57Z a 18:14Z (tarde del 2026-11-01 en Bolivia). La relectura de §1 es de las 18:21Z |
| Código | La APK instalada se compiló desde Mobile `ce3b788`. Sus `lib/`, `pubspec.*` y `android/` son idénticos a los de `main` `7344e30`, el merge de #174. Entre los dos commits solo cambian dos archivos de evidencia (`git diff --name-only ce3b788 7344e30`) |
| APK | La misma de la sesión DEVICE de la mañana, sin reinstalar: `com.comunidad.agro.agroquimicos.av1`, con `firstInstallTime` y `lastUpdateTime` 2026-11-01 08:40:27 (hora local). El `base.apk` del teléfono tiene SHA-256 `09eebbfb3a097396b836b8220bd743b41ac5a896d14002429abeb8e2c73dd7ef` (relectura de §1) |
| Dispositivo | **DEVICE**: POCO X5 Pro 5G, modelo `22101320G`, serie `cc14247a`, Android 12 / API 31, zona `America/La_Paz` |
| Datos | Los sintéticos de la sesión DEVICE de la mañana: cuenta `u2-av`, modalidad compartida, «Titular AV», «Hermana Demo» y «Vecino Demo». Solo se añadió una aplicación por la interfaz (§3, AV-A23) |
| Issues | Refs #170, #171 |
| Origen | Comprobación nueva en el teléfono. Complementa `F04_AV_AVISOS_INVENTARIO_DEVICE_2026-11-01.md` sin cambiar ninguno de sus resultados. AV-A15 sigue NOT_RUN en DEVICE |

**AV-A21 a AV-A24 son criterios nuevos.** Se definieron en esta sesión a partir del encargo de Roderich del 2026-11-01 para cerrar #170 y #171:
- comparar los avisos con y sin conexión;
- mostrar la existencia baja total y por responsable;
- agotar un lote por consumo;
- comprobar que consultar o tocar los avisos no escribe.

No forman parte del protocolo AV-A1 a AV-A18 (`PROTOCOLO_ANDROID_SIN_RED.md`).

**Lo que no se hizo:**
- no se cambió el reloj ni se esperó a medianoche;
- no se tecleó ni se usó ningún PIN, porque ninguna acción de esta sesión lo pidió;
- no se arrancaron el Central, el túnel ni Docker;
- no se tocó ningún otro paquete.

**Procedencia de cada dato:**
- **Archivo guardado:** lecturas de la vista, copias de la base, comparación de tablas, capturas y la relectura de §1.
- **Observado en la sesión, sin copia en archivo:** las salidas de `adb` que se citan al principio y al final de la sesión, los mensajes de conectividad y la secuencia de toques. Se marcan con *(observado)*.

## 1. Estado del teléfono

| Ajuste | Al empezar, 17:57Z *(observado)* | Al terminar, 18:14Z *(observado)* | Relectura, 18:21Z (archivo) |
|---|---|---|---|
| `airplane_mode_on` | 0 | 0 | 0 |
| `auto_time` / `auto_time_zone` | 1 / 1 | 1 / 1 | 1 / 1 |
| `font_scale` | 1.0 | 1.0 | 1.0 |
| `stay_on_while_plugged_in` / `screen_off_timeout` | 3 / 600000 | 3 / 600000 | 3 / 600000 |
| `wifi_on` / `mobile_data` | 1 / 1 | 1 / 1 | 1 / 1 |
| Animaciones | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 |
| Teclado | Gboard | Gboard | Gboard |
| `wm size` | 1080x2400 | 1080x2400 | 1080x2400 |
| Paquetes `comunidad.agro` | 27 (26 previos y `.av1`) | 27 | 27 |
| Base en el teléfono | — | — | Un solo archivo, `agroquimicos_v2.db`, modificado a las 14:06 locales (18:06Z), con SHA-256 `5ed3929542f95a94…` (= S3–S7) |

## 2. Método

**Copias de la base.** Se sacaron con `run-as`, siempre con la app detenida: `am force-stop` solo de `.av1`.
- La base es un único archivo. En el teléfono no hay `-wal` ni `-journal`.
- Cada par de copias se compara tabla por tabla: las 34 tablas de la app, todas sus filas, más `integrity_check` y `user_version`. Queda fuera `sqlite_sequence`, la tabla interna de contadores de SQLite. La comparación completa está en `%TEMP%\agro_a_av_env\b\cmp_b_s0_s7.txt`.

**Lectura de la vista.** «Inventario → Avisos de inventario» se recorre entera con desplazamientos.
- Se guardan sus textos en orden, sin repetidos y sin coordenadas: la línea de resumen de Inventario y todas las secciones y avisos. La herramienta trunca cada línea hacia los 110 caracteres, igual en todas las lecturas.
- Las lecturas están en `%TEMP%\agro_a_av_env\b\v_*.txt` y se comparan con `diff`.

**«Con conexión».** Wi‑Fi encendido y red validada; «Active default network» con transporte WIFI *(observado)*.
- El Central y el túnel del ensayo estaban **detenidos**: Docker no respondía y los registros de la API y del túnel no tienen actividad desde la mañana.
- Por eso ninguna sincronización pudo cambiar datos entre las lecturas.
- Por lo mismo, no se comprobó la vista durante una sincronización real.

**«Sin conexión».** Modo avión con `cmd connectivity airplane-mode enable`, desde las 18:00:01Z hasta las 18:13Z. Se observó `airplane_mode_on = 1`, «Wi-Fi is disabled» y «Active default network: none» *(observado)*.

| Copia | Momento | SHA-256 (16) | Comparación |
|---|---|---|---|
| S0 | Inicio, con conexión, antes de abrir la app | `46e0abef411f61fb` | Igual a la copia final de la sesión de la mañana (`poco_fin`) |
| S1 | Tras la lectura con conexión | `46e0abef411f61fb` | S0 → S1: sin diferencias |
| S2 | Tras la lectura sin conexión y tres avisos tocados | `46e0abef411f61fb` | S1 → S2: sin diferencias |
| S3 | Tras guardar la aplicación (§3, AV-A23) | `5ed3929542f95a94` | S2 → S3: difieren solo `applications` (2→3), `application_items` (2→3), `application_consumptions` (2→4), `inventory_movements` (13→15) y `account_transactions` (2→3). También avanzan los contadores de `sqlite_sequence` |
| S4 | Tras leer la vista y tocar cuatro avisos, sin conexión | `5ed3929542f95a94` | S3 → S4: sin diferencias |
| S5, S6 | Tras dos aperturas más de la vista, para las capturas | `5ed3929542f95a94` | Sin diferencias |
| S7 | Tras la lectura con conexión después del consumo | `5ed3929542f95a94` | S6 → S7: sin diferencias |

En todas las copias, `integrity_check = ok` y `user_version = 12`. Los hashes también coinciden byte a byte: S0 = S1 = S2 y S3 = … = S7.

## 3. Resultados

| ID | Resultado | Lo observado |
|---|---|---|
| AV-A21 | PASS | **Los mismos avisos con y sin conexión, sin cambios en la base entre las consultas.**<br>• Los textos leídos con conexión (17:58Z–17:59Z) y en modo avión (18:01Z) son idénticos: `diff` vacío, 27 líneas. El resumen dice: «3 vencidos · 1 vence hoy · 1 por vencer · 3 bajos por responsable · 1 sin fecha registrad[a]».<br>• Después del consumo se repitió la comparación al revés: primero sin conexión y luego con conexión (18:13Z). También dio `diff` vacío, incluida la sección de existencia baja total.<br>• S0 = S1 = S2 y S6 = S7.<br>• Las capturas del final de la lista con y sin conexión (`pb01`, `pb02`) son idénticas byte a byte, porque la captura de la herramienta sale recortada a 1080×2290, sin barra de estado. Por eso no se ven la hora ni el icono del modo avión. La diferencia de conectividad la acreditan las lecturas y el estado de red *(observado)*, no las capturas |
| AV-A22 | PASS | **Existencia baja en toda la instalación y por responsable, en modalidad compartida.** Es tras el consumo de AV-A23.<br>• La sección «Existencia baja en toda la instalación (1)» muestra el aviso «Glifosato Demo · Total de la instalación», con el texto «Quedan 3 L en toda la instalación; nivel mínimo 3 L».<br>• «Existencia baja por responsable (4)» muestra «Glifosato Demo · Hermana Demo (responsable)», «Glifosato Demo · Titular AV (responsable)» («Titular AV no tiene existencias propias…»), «Glifosato Demo · Vecino Demo (responsable)» y «Mancozeb Demo · Hermana Demo (responsable)». Los tres de Glifosato indican el total de la instalación, 3 L, como se ve en `pb07`.<br>• El resumen de Inventario dice: «2 vencidos · 1 vence hoy · 1 bajo en el total · 4 bajos por responsable · 1 sin fecha reg[istrada]».<br>• En la base, el total de Glifosato es 3000 y su `min_stock_base` también es 3000 |
| AV-A23 | PASS | **Un lote agotado por consumo deja de avisar de su vencimiento.**<br>• Aplicación sin red, por la interfaz: Titular AV, «Chaco Titular AV», 1 ha, Glifosato 5 L.<br>• El formulario mostró «Hay 5 L · quedarán 0 L» y no pidió PIN *(observado)*. El resumen está en `pb03`.<br>• Se tocó «Confirmar aplicación» a las 18:06:56Z, según el reloj del PC. La base registra la aplicación y sus movimientos con fecha `2026-11-01T18:06:59.529800Z`.<br>• En la base (FIFO, por fecha de adquisición):<br>&nbsp;&nbsp;– movimiento 14, `APPLICATION_OUT −2000`, del lote 1 (GLI-VENCIDO-B, vencido el 31/10/2026);<br>&nbsp;&nbsp;– movimiento 15, `APPLICATION_OUT −3000`, del lote 2 (GLI-PRONTO…, vence el 11/11/2026).<br>&nbsp;&nbsp;Los dos lotes quedan en 0.<br>• En la vista, sin conexión:<br>&nbsp;&nbsp;– desaparece el aviso «Glifosato Demo · lote GLI-VENCIDO-B Venció el 31/10/2026, hace 1 día · Quedan 2 L · Titular AV», y «Vencidos» pasa de 3 a 2;<br>&nbsp;&nbsp;– sigue el GLI-VENCIDO-B del vecino (lote 6, 1 L), que es otro lote y todavía tiene cantidad;<br>&nbsp;&nbsp;– desaparece la sección «Próximos a vencer» entera, porque su único lote, GLI-PRONTO, se agotó |
| AV-A24 | PASS | **Consultar o tocar los avisos no cambia la base local.**<br>• Antes del consumo, sin conexión, se tocaron:<br>&nbsp;&nbsp;– el vencido «Glifosato Demo · lote GLI-VENCIDO-B … Titular AV»;<br>&nbsp;&nbsp;– «Glifosato Demo · Vecino Demo (responsable)»;<br>&nbsp;&nbsp;– el último aviso, «Mancozeb Demo · sin número de lote».<br>• Después del consumo se tocaron:<br>&nbsp;&nbsp;– «Glifosato Demo · Total de la instalación»;<br>&nbsp;&nbsp;– «Glifosato Demo · Titular AV (responsable)»;<br>&nbsp;&nbsp;– «Mancozeb Demo · Hermana Demo (responsable)»;<br>&nbsp;&nbsp;– el vencido del vecino.<br>• Cada toque abrió el detalle del producto y «Volver» regresó a la vista *(observado)*.<br>• S1 = S2 y S3 = S4 = S5 = S6: ninguna tabla de la base cambia, ni `inventory_movements` ni las demás. No se comprobaron otros archivos de la app, como las preferencias |

**AV-A15 (cambio de día) sigue NOT_RUN en DEVICE**, porque no se cambió el reloj ni se esperó a medianoche. Su cobertura en otras procedencias:
- **HOST, con reloj inyectable**, en `test/f04_av_inventory_alerts_test.dart` en `7344e30`:
  - `vence hoy hasta el último instante del día local; al siguiente, vencido` (L1384);
  - `el día es el local del teléfono, no el UTC` (L1417);
  - `clasificación por días de calendario, sin depender del horario` (L1437).

  Las tres pasaron en la CI de `main` (run 41321384121).
- **EMULADOR, con el reloj del emulador cambiado**, que no es inyectable: AV-A15 PASS sobre `f99fc56` (`F04_AV_AVISOS_INVENTARIO_EMULADOR_2026-11-01.md`).

## 4. Capturas

Están en `%TEMP%\agro_a_av_env\capturas_poco2\`, sin versionar, recortadas a 1080×2290 sin barra de estado. Ninguna muestra un PIN ni credenciales.

| Archivo | Qué muestra | SHA-256 |
|---|---|---|
| `pb01_con_conexion_fin_lista.png` | Final de la vista, con conexión | `18a4401a65c00e7b164759c6a39e2c7e0d4a1c869d66de76d756fd0be03aa1ce` |
| `pb02_sin_conexion_fin_lista.png` | Final de la vista, en modo avión | `18a4401a65c00e7b164759c6a39e2c7e0d4a1c869d66de76d756fd0be03aa1ce` (idéntica a `pb01`; ver AV-A21) |
| `pb03_aplicacion_resumen.png` | Paso 3, resumen de la aplicación antes de confirmar | `483de62745479063a30f6cf8d163c8bebfb38a45b6dcecca0c9ff9dfb7eebb51` |
| `pb04_aplicacion_guardada.png` | Inicio tras guardar la aplicación | `a8b6f3686adf81cb47057ef2f3b7e5f9c54afec04e67e288efe5fba9ebb329c1` |
| `pb05_total_y_responsable.png` | «Vencidos (2)», «Vence hoy (1)» y «Existencia baja en toda la instalación (1)» | `1849660db0e5db60ffbd2e4eb76b0fcafa16485b2217ad17f1e7e506c4a2f365` |
| `pb06_por_responsable.png` | El total y el comienzo de «Existencia baja por responsable (4)» | `178083c9adce9eaff484a6952054d18e7babb653cbe0fd3ff78ef1aaf6fbae26` |
| `pb07_por_responsable_filas.png` | Las cuatro filas por responsable | `ce207e2e508acfc7ac2c848c70709ffc7338272db75bfab1c7957defd4a0f328` |

## 5. Ajuste del arnés

`av_device.sh pull`, una herramienta local sin versionar, guardaba como `-wal` y `-journal` el texto de error de `cat`. Pasaba porque `adb exec-out` sale con 0 aunque el archivo no exista.
- **Corrección:** ahora solo los copia si `ls databases/` los lista.
- **Efecto en los datos:** ninguno. Los archivos falsos se borraron y la cadena S0→S7 se comparó de nuevo sin ellos hacia las 18:16Z, con el resultado de la tabla del §2.

## 6. Límites

- **Un solo teléfono:** el POCO, con Android 12.
- **«Con conexión»** significa la red del teléfono activa con el Central del ensayo detenido. No se comprobó la vista durante una sincronización real.
- **Solo la base:** se comparó `agroquimicos_v2.db`, no otros archivos de la app.
- **Datos sin archivo:** varias observaciones de la sesión, marcadas *(observado)*, no tienen copia en archivo.
- **AV-A15** sigue NOT_RUN en DEVICE.
- **Sin evaluación con agricultores.**
