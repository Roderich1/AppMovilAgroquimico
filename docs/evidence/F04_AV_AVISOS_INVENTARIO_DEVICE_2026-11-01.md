# F04-AV — Comprobación Android sin red de los avisos (DEVICE)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01, de 12:36Z a 13:08Z (mañana del 2026-11-01 en Bolivia) |
| Código | Mobile `ce3b788`, rama `feat/f04-av-avisos-inventario`: `f99fc56` más la retirada del «Nuevo» flotante en «Avisos de inventario» |
| APK | `agrocuentas.av1-profile-arm64.apk`, profile arm64-v8a, 36 190 255 bytes, SHA-256 `09eebbfb3a097396b836b8220bd743b41ac5a896d14002429abeb8e2c73dd7ef`, compilada desde ese HEAD exacto sin cambios versionados (terminó a las 12:39:56Z). El `base.apk` instalado en el teléfono tiene el mismo SHA-256 |
| Paquete | `com.comunidad.agro.agroquimicos.av1`, etiqueta «AC AVISOS». Instalación nueva: no existía en el teléfono (12:40:27Z) |
| Dispositivo | **DEVICE**: POCO X5 Pro 5G, modelo `22101320G`, serie `cc14247a`, Android 12 / API 31, MIUI `V14.0.7.0.SMSMIXM`, arm64-v8a, 1080×2400, zona `America/La_Paz` |
| Central | Propio y desechable: contenedor `agro_a_av_pg` (127.0.0.1:55497, base `agro_av`, 13 migraciones), API 3200 con `dist` de Backend `9233acc`, observador 3201, túnel temporal sólo hacia esa API |
| Datos | Sintéticos: tenant `av-sindicato`, cuenta nueva `u2-av` (la `u1-av` es la del emulador y no se tocó), «Titular AV», «Hermana Demo», «Vecino Demo» |
| Issues | Refs #168, #169, #170, #171 |
| Origen | Comprobación nueva en un teléfono. Es una ejecución distinta de la del EMULADOR (`F04_AV_AVISOS_INVENTARIO_EMULADOR_2026-11-01.md`), cuyos resultados no se modifican |

## 1. Estado inicial del teléfono

Registrado antes de tocar nada:

| Ajuste | Valor inicial |
|---|---|
| `airplane_mode_on` | 0 |
| `auto_time` / `auto_time_zone` | 1 / 1 |
| `font_scale` | 1.0 |
| `stay_on_while_plugged_in` | 3 |
| `screen_off_timeout` | 600000 |
| `wifi_on` / `mobile_data` | 1 / 1 |
| Animaciones (ventana, transición, animador) | 1.0 |
| Teclado | Gboard |
| `wm size` | 1080x2400 |
| Paquetes `comunidad.agro` | 26 (app normal, copias de pruebas anteriores y pilotos, y `voicebench`). No había `.av1` |

## 2. Preparación

1. Docker Desktop arrancado; `av.sh up`: PostgreSQL propio con sus datos del emulador conservados, migraciones (13), API (health 200). El tenant ya existía: no se volvió a sembrar.
2. Se añadió al mismo tenant un segundo agricultor sintético, `u2-av`, con contraseña inutilizable. Así la activación del teléfono no toca la instalación de `u1-av` del emulador.
3. `av.sh tunnel`: origen HTTPS temporal (health 200; el valor no se publica). La APK se compiló con ese origen.
4. Instalación sólo de `.av1`. MIUI no pidió confirmación por pantalla.
5. Activación por la interfaz en modo **compartido**, con contraseña de un solo uso para `u2-av` (no se muestra ni se guarda) y PIN sintético que vive sólo en la memoria de un proceso guardián. El guardián sólo teclea si el campo enfocado es de contraseña (`pin_safe.sh`). Peticiones del observador: `GET /health`, `POST /auth/v2/login`, `POST /auth/clients`, `POST /auth/v2/session/client`, `GET /auth/v2/me`.
6. Siembra sintética relativa al día sobre una copia de la base: SHA-256 antes `343156bc…`, después `fc427632…`, igual en el PC y en el teléfono. El cálculo en HOST de esa base dio lo mismo que en el emulador:

```text
expired:  Glifosato Demo|GLI-VENCIDO|Titular AV|3000|1 ; Glifosato Demo|GLI-VENCIDO|Vecino Demo|1000|1 ; Paraquat Demo|PQ-ARCH|Titular AV|1000|1
dueToday: Atrazina Demo|ATR-HOY|Titular AV|1000|0
near:     Glifosato Demo|GLI-PRONTO|Titular AV|3000|10
unknown:  Mancozeb Demo|Titular AV|5000
low:      Glifosato Demo|Hermana Demo|2000|9000 ; Glifosato Demo|Vecino Demo|1000|9000 ; Mancozeb Demo|Hermana Demo|0|5000
withoutLevel: Atrazina Demo
```

## 3. Sin red

Modo avión activado a las 12:45:19Z: `airplane_mode_on = 1`, «Wi-Fi is disabled», «Active default network: none». La zona siguió en `America/La_Paz` y el reloj del teléfono **no se cambió** en ningún momento.

| Tramo | Inicio – fin (UTC) | Peticiones del observador al empezar | Al terminar |
|---|---|---|---|
| Sin red | 12:45:19 – 13:07:48 | 5 (las de la activación) | 5 |

El túnel y el observador siguieron activos durante todo el tramo, de modo que cualquier petición que hubiera salido habría quedado registrada. Al apagar los servicios, el observador seguía en 5.

## 4. Resultados

| ID | Resultado | Lo observado |
|---|---|---|
| AV-A1 | PASS | «Avisos de inventario» se abre y calcula en modo avión. Resumen del inventario: «3 vencidos · 1 vence hoy · 1 por vencer · 3 bajos por responsable · 1 sin fecha registrada» |
| AV-A2 | PASS | «Vencidos (3)»: Glifosato GLI-VENCIDO del titular, 3 L, y del vecino, 1 L, «Venció el 31/10/2026, hace 1 día»; Paraquat PQ-ARCH |
| AV-A3 | PASS | «Próximos a vencer (1)»: GLI-PRONTO «Vence el 11/11/2026, en 10 días», «Aviso: 30 días antes (valor inicial)» |
| AV-A4 | PASS | GLI-LEJOS de Hermana, a 90 días, no aparece en ninguna sección |
| AV-A5 | PASS | «Sin fecha de vencimiento registrada (1)»: Mancozeb del titular, 5 KG |
| AV-A6 | PASS | No hay sección de total bajo. «Existencia baja por responsable (3)»: Glifosato Hermana 2 L y Vecino 1 L, «En toda la instalación: 9 L»; Mancozeb «Hermana Demo no tiene existencias propias; nivel mínimo 2 KG. En toda la instalación: 5 KG» |
| AV-A7 | PASS | «Atrazina Demo no tiene nivel mínimo: no se avisa cuando queda poco…» |
| AV-A8 | PASS | Tocar el último aviso (Mancozeb sin fecha) abre el detalle del producto sin iniciar operaciones. Al volver tras configurar Mancozeb, la vista recalculó: «nivel mínimo 1 KG» |
| AV-A9 | PASS | Corregir el número de GLI-PRONTO pidió datos, motivo y PIN. Detalle: «Se guardó la corrección en 1 lote. Las cantidades no cambiaron.». Historial: «…lote GLI-PRONTO → GLI-PRONTO-poco-…. Motivo: Leido en el envase ensayo AV POCO. Autorizó Titular AV con PIN; 1 lote cambiado.» Base: corrección 1, `LOCAL_PIN`, actor persona 1, 1 fila de lote (lote 2), cantidad 3000 sin cambio |
| AV-A10 | PASS | Corregir GLI-VENCIDO a GLI-VENCIDO-B: «Se guardó la corrección en 2 lotes». Base: corrección 2, filas para el lote 1 (titular) y el lote 6 (vecino, hijo por transferencia), `unproven_lot_count = 0`; cantidades 4000 y 1000 sin cambio. La vista muestra GLI-VENCIDO-B del vecino |
| AV-A11 | PASS | La compra revertida (Atrazina, ATR-REV, «Revertida el 01/11/2026») se consulta con «Número de lote: ATR-REV» y no ofrece «Corregir vencimiento o lote» |
| AV-A12 | PASS | Aplicación sin red de 1 L de Glifosato del titular en «Chaco Titular AV», guardada sin bloqueo («Hay 6 L · quedarán 5 L»). `application_consumptions`: 1000 del lote 1 (GLI-VENCIDO-B, el más antiguo, vencido) |
| AV-A13 | PASS | 0 peticiones nuevas en el tramo sin red (§3) |
| AV-A14 | PASS | «Vence hoy (1)»: Atrazina ATR-HOY del titular, 1 L, «Vence hoy, 01/11/2026», en tarjeta ámbar con icono de advertencia, entre «Vencidos» y «Próximos». Texto de la sección: «Vencen hoy, 01/11/2026, según la fecha del teléfono. Mañana pasan a vencidos.» |
| AV-A15 | NOT_RUN | **El paso de un día al siguiente no se ejecutó en el teléfono**: la instrucción de esta sesión prohíbe cambiar el reloj global, y no se esperó a la medianoche real. Sí se vio el límite con fechas sintéticas relativas al día: ayer → «Vencidos», «hace 1 día»; hoy → «Vence hoy»; dentro de 10 días → «Próximos». El cambio de día está cubierto en HOST (instantes 00:30 y 23:30 locales) y en el EMULADOR |
| AV-A16 | PASS | Paraquat, archivado con nivel 2 L y 1 L: PQ-ARCH en «Vencidos»; Paraquat no aparece en existencia baja ni como «sin nivel mínimo» |
| AV-A17 | PASS | Sobre Mancozeb, como dice el protocolo (mínimo 2 KG, plazo 15). «Guardar» inactivo sin cambios (`enabled="false"`). Con 366 días, al pulsar «Guardar»: «Escriba un número entero de días, de 0 a 365.» y no se pide el PIN. Mínimo 1 y plazo 20 → un solo diálogo de PIN con «Nivel mínimo: 2 KG → 1 KG. Aviso de vencimiento: 15 días → 20 días». Cancelar en el PIN: base sin cambios (2000, 15). Guardar con el PIN: base 1000 y 20 |
| AV-A18 | PASS | En la corrección de GLI-PRONTO, 101 caracteres: «El número de lote admite hasta 100 caracteres; tiene 101. Revise lo escrito: no se recorta.», contador «101/100», el campo conserva los 101 caracteres y «Continuar» queda inactivo. Con 100 caracteres, «Continuar» se activa y se guardó exacto: `length(new_lot_number) = 100`, igual al texto tecleado, y el lote igual |

**Comprobaciones derivadas de este bloque:**

| ID | Resultado | Lo observado |
|---|---|---|
| AV-A19 | PASS | **Último aviso visible y tocable, sin «Nuevo» flotante.** En «Avisos de inventario» no hay «Nuevo»; en Inventario sí sigue. Al final de la lista, el último aviso (Mancozeb sin fecha) queda entero sobre la barra inferior, y el toque en su flecha derecha abre el producto. Con `font_scale` 1.0, 1.3 y 2.0. A mitad del desplazamiento ningún aviso queda tapado |
| AV-A20 | PASS | **Persistencia al reabrir.** Con la app detenida (`force-stop`, sin proceso) y abierta otra vez sin red: los dos lotes corregidos (GLI-VENCIDO-B del titular y del vecino, y el número de 100 caracteres de GLI-PRONTO) y el mínimo de 1 KG de Mancozeb siguen en la vista |

**Lo guardado.**
- **Integridad.** La base final pasa `PRAGMA integrity_check = ok`, con `user_version = 12`.
- **Movimientos y lotes.** Entre la siembra y la copia posterior a AV-A10, `inventory_movements` (12 filas), `application_consumptions`, `transfers`, `transfer_items` y `transfer_lot_items` son idénticos. Los lotes sólo cambian en vencimiento y número.
- **Correcciones.** Hay exactamente dos, con tres filas de lote.
- **Configuración.** Mancozeb termina con 1000 y 20.
- **Consumos.** Hay dos: el de la siembra y el de AV-A12.

Copias de la base en `%TEMP%\agro_a_av_env\device\` (SHA-256 abreviado del archivo principal; el `-wal` se copió al lado y las consultas lo incluyen):

| Copia | SHA-256 |
|---|---|
| `seed/20261101T124435Z` | `fc427632…` |
| `poco_a17_cancelado` | `fc427632…` |
| `poco_a17_guardado` | `92b23ac9…` |
| `poco_a9` | `89fee6ac…` |
| `poco_a10` | `8a8fe22d…` |
| `poco_antes_a12` | `8a8fe22d…` |
| `poco_fin_a12` | `46e0abef…` |
| `poco_fin` | `46e0abef…` |

## 5. Desvíos y ajustes del arnés

- **AV-A9 se hizo con el valor de 100 caracteres de AV-A18.** Fue una sola corrección, como en el emulador.
- **AV-A12 necesitó un chaco del titular, que la siembra no crea.** Se creó por la interfaz, sin red, en Catálogos: «Chaco Titular AV», 1 ha, sintético. Un primer intento de la aplicación se descartó sin guardar al ver que faltaba el chaco.
- **AV-A15 queda NOT_RUN en el teléfono** (§4).
- **Arnés.**
  - La guarda de primer plano buscaba `topResumedActivity`, que Android 12 no muestra. Abortó sin tocar nada y se amplió a `mResumedActivity`.
  - Una ayuda de toque dio dos falsos «no encontrado» por el código de salida de una tubería. No tocó nada y se corrigió.
  - La línea de la siembra dice «EMU»; es una etiqueta fija del arnés, pero la base era la del teléfono.

No hubo incidentes de credenciales. El guardián tecleó el PIN 5 veces, siempre en un campo con `password="true"` enfocado:
- 2 para crearlo;
- 1 en AV-A17;
- 1 en AV-A9;
- 1 en AV-A10.

Ninguna salida, captura ni volcado lo muestra. Las pantallas de PIN no se capturaron.

## 6. Observaciones

- **Un producto archivado sigue apareciendo en el selector de productos de la aplicación** («Paraquat Demo Disponible 1 L»). Es comportamiento existente, fuera de este bloque, y no se cambió.
- **La compra revertida por la siembra muestra «Actor no registrado».** Es un dato sintético: la siembra usa la reversión de pruebas sin autorización.

## 7. Capturas

En `%TEMP%\agro_a_av_env\capturas_poco\`, sin barra de estado. No se commitean. Ninguna muestra un PIN ni una contraseña.

| Captura | SHA-256 |
|---|---|
| `pa01_inventario_resumen` | `ba5f74f5…` |
| `pa02_avisos_arriba` | `09cd4cd6…` |
| `pa03_avisos_medio` | `2ffa5680…` |
| `pa04_avisos_final` | `3688b59d…` |
| `pa05_producto_desde_ultimo_aviso` | `c804462e…` |
| `pa06_config_sin_cambios` | `ddcfda20…` |
| `pa07_config_366` | `172e6b06…` |
| `pa07b_config_366_rechazo` | `84a469de…` |
| `pa08_config_guardada` | `beeb3207…` |
| `pa09_avisos_recalculados` | `49bd9dce…` |
| `pa10_detalle_gli_pronto_antes` | `1e07426b…` |
| `pa11_lote_101` | `e780fe49…` |
| `pa12_motivo_efectos` | `355ab8cb…` |
| `pa13_detalle_gli_pronto_corregido` | `06f43471…` |
| `pa14_historial_gli_pronto` | `3a17214f…` |
| `pa15_detalle_gli_vencido_corregido` | `0bba0bf5…` |
| `pa16_compra_revertida` | `08affa58…` |
| `pa17_reabierta_avisos` | `391748bb…` |
| `pa18_aplicacion_guardada` | `caf0b0db…` |
| `pa19_avisos_final_130` | `1b61cc9e…` |
| `pa20_avisos_final_200` | `49079526…` |

## 8. Cierre

| Paso | Hora (UTC) | Resultado |
|---|---|---|
| App detenida y modo avión desactivado | 13:07:48 | `airplane_mode_on = 0`, red activa |
| Guardián del PIN terminado | | PIN descartado |
| Ajustes del teléfono | | Iguales a los iniciales (§1): `auto_time = 1`, `auto_time_zone = 1`, `font_scale = 1.0`, `stay_on = 3`, `screen_off_timeout = 600000`, Wi‑Fi y datos activos, `wm size` 1080x2400, zona `America/La_Paz` |
| `av.sh down` | | Túnel, observador y API detenidos. Contenedor `agro_a_av_pg` detenido, con los datos conservados en `agro_a_av_pgdata` |
| Docker Desktop | | Detenido; se había arrancado para esta sesión |

**Datos que se conservan:**
- el paquete `.av1` con su base en el teléfono;
- `%TEMP%\agro_a_av_env`;
- el volumen `agro_a_av_pgdata`, con `u1-av` (emulador) y `u2-av` (teléfono).

**Lo que no se tocó:**
- las 26 instalaciones previas del teléfono, incluidas la app normal y los pilotos (después de la sesión hay 27 paquetes: esas 26 y `.av1`);
- EXP, UX, demo, otros contenedores;
- el emulador y su `.av1`.

No se cerró ningún proceso ajeno. El servidor de análisis de Dart del editor ocupaba 7,1 GB durante la compilación, que terminó igual.

## 9. Límites

- **Un solo teléfono y un solo recorrido**, por ADB, sin participante. No es una evaluación con usuarios.
- **AV-A15 (cambio de día) no se ejecutó en el teléfono**, porque no se cambia el reloj global.
- **El volcado de `uiautomator` filtra las líneas con muchas mayúsculas seguidas.** Por eso el valor de 100 y 101 caracteres se escribió con minúsculas y cifras, se leyó del atributo `text` del nodo y se comprobó en la base.
