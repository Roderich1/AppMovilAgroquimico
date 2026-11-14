# F09: voz local en el POCO físico con voz humana (2026-11-05)

**Qué es.** El primer ensayo de «AC VOZ» en un teléfono físico. Roderich habló directamente al micrófono del POCO, sin red. Se registra aparte de las muestras sintéticas del emulador (`F09_VOZ_LOCAL_2026-11-05.md`).

**Qué no es.**
- No es la evaluación de #12: no usa el holdout ni fija umbrales.
- No mide rendimiento, memoria ni batería del teléfono (NOT_MEASURED).
- No cierra GATE-F09 (#17) ni declara RNF-14 cumplido.
- No cambia el modelo ni el código: es la APK `03124a0` de la demostración (ADR-005).

**Procedencia:** DEVICE, verificado el 2026-11-05 sobre el código Mobile `03124a0`. Horas locales del teléfono (America/La_Paz).

| Dato | Valor |
|---|---|
| Teléfono | POCO X5 Pro 5G, modelo `22101320G` (redwood), Android 12 / API 31 |
| APK | `_wt/tools/voz-local-apk/poco-2026-11-05/agrocuentas-voz-03124a0-arm64-v8a-profile.apk` · SHA-256 `6f1fa26ef4756f43c61600c09e9362d9e04d77b49aaa7a4897db4e24bda6b2a9` |
| Por qué no es la ARM64 de la evidencia | La ARM64 verificada (`1f2dd5a7…`) no llevaba compilado el origen del Central y no podía activarse. Se recompiló desde el mismo código `03124a0` añadiendo sólo ese origen. Los modelos y las bibliotecas nativas coinciden byte a byte; sólo cambia `libapp.so`. |
| Instalación | «AC VOZ» (`com.comunidad.agro.agroquimicos.voz`), sin tocar las demás instalaciones del teléfono |
| Cuenta | `agricultor5` de la DEMO, titular sintético «Elena Condori VOZ», inventario propio, siete productos (Mancozeb y Atrazina en kg; el resto en L) |
| Motor | Vosk `small-es-0.42` en vivo + whisper.cpp `ggml-base-q5_1` como revisión de cada frase, con «Revisar cada frase» activado |
| Red durante el ensayo | Verificada antes de empezar: modo avión activado, Wi‑Fi y datos móviles apagados, sin red por defecto y `ping` sin salida. La barra de estado muestra el modo avión en todo el dictado. |
| Método | Grabación **sólo de pantalla** (`screenrecord`, sin pista de audio) y registro de la app filtrado por su proceso. La app sólo registra códigos y milisegundos, no lo dictado. Ningún audio se guardó. |
| Qué no se puede saber | Lo que Roderich dijo exactamente: se supone la frase del guion. El texto de la revisión cuando se rechazó, porque la app no lo registra a propósito. |

## 1. Intentos

Los tiempos de revisión salen del registro de la app (`revision=…ms`). El texto es el que se ve en pantalla, copiado tal cual.

**Columnas:**
- **Parcial:** el texto provisional se vio en pantalla mientras hablaba.
- **Fin:** el tiempo desde «Detener» hasta que el texto llega al borrador, medido en el vídeo.

| # | Hora | Pantalla | Frase esperada | Revisión | Texto que llegó al borrador | Borrador | Errores |
|---|---|---|---|---|---|---|---|
| 1 | 08:11:56 | Compra por voz | «Compré un litro y medio de Glifosato por ciento ochenta bolivianos» | `quantities`, 3 366 ms: se queda el texto de Vosk | «compone un litro de medio de bolsa todo por ciento ochenta y seis boliviano» | Producto «medio de bolsa», no está en el catálogo. Cantidad «un litro». Precio y moneda faltan | producto, cantidad, precio, moneda |
| 2 | 08:12:39 | Compra por voz, el mismo borrador | La misma | `quantities`, 3 271 ms | «compré un litro y medio de glifosato por ciento ochenta o el hierbas» | Línea 2: producto «y medio de glifosato», ambiguo. Cantidad «un litro». Precio 180, ambiguo por L o kg. Falta la moneda | cantidad, producto, moneda |
| 3 | 08:16:02 | Compra por voz, borrador nuevo | La misma | `accepted`, 3 251 ms. El parcial de Vosk era «compré un litro y medio de glifosato por ciento ochenta bolivianos» | «Compre un litro y medio de Glifosato por 180 bolivianos.» | Producto «y medio de glifosato», ambiguo. Cantidad «un litro». Precio 180 y moneda BOB | **cantidad, producto** (ver §2.1) |
| 4 | 08:17:39 | Compra por voz | «Pagué ciento cincuenta bolivianos y todavía debo ochenta» | `quantities`, 3 582 ms | Parcial «pagué ciento cincuenta o el liviano y todavía de ochenta» | Aviso «Los pagos y las consultas por voz no están disponibles. No se cambió el borrador.» | ninguno: fuera de alcance |
| 5 | 08:18:25 | Compra por voz | La misma | `accepted`, 3 172 ms. Parcial «ciento cincuenta boliviano y todavía de ochenta» | El mismo aviso | Sin cambios | ninguno: fuera de alcance |
| 6 | 08:21:11 | Compra por voz | Frase libre de prueba, un saludo fuera del guion | `quantities`, 2 962 ms | Se añadió a «Ya aplicado al borrador» | Sin cambios en los campos | ninguno |
| 7 | 08:21:58 | Compra por voz, el borrador del intento 3 | La frase 1 | `accepted`, 3 085 ms | «Compré 1 litro y medio de Glifosato por 180 bolivianos.» | Línea 2 nueva: producto «y medio de glifosato», ambiguo. Cantidad «1 litro». Precio 180 BOB | **cantidad, producto** (§2.1) |
| 8 | 08:23:31 y 08:23:34 | **Planificación por voz** | «Apliqué doscientos cincuenta mililitros… de Mancozeb», con pausa | Frase 0 `quantities` (3 078 ms) y frase 1 `degenerate` (2 823 ms) | No quedó en el vídeo: cayó entre dos tramos de grabación. Después se ve «de manco ser» en «Ya aplicado al borrador» | Sin líneas | producto (§2.2) |
| 9 | 08:23:48 y 08:23:51 | **Planificación por voz** | La misma | Frase 0 `quantities` (2 852 ms) y frase 1 `degenerate` (2 914 ms) | Frase 0, parcial: «aplique doscientos cincuenta mil litros» → aviso «Eso parece otra operación. No se cambió este borrador de planificación: regístrela desde su propia pantalla.» Frase 1, parcial: «de manco sep» → «de manco sepe» | Sin líneas | unidad («mil litros»), producto (§2.2) |
| 10 | ~08:24 | Planificación por voz | Ninguna: «Hablar» y «Detener» enseguida | — | Nada | Sin cambios | ninguno |

**Lo que no se probó:**
- La frase 2 se dictó en **Planificación por voz**, no en **Aplicación por voz**. La pantalla de aplicación no se usó en este ensayo.
- No se registró ninguna operación: «Registrar compra» y «Crear plan» siguieron desactivados en todo momento.

### Comprobaciones pedidas

- **El texto aparece mientras habla:**
  - Sí, en los intentos 6, 7 y 9, con «Escuchando (todavía puede cambiar)». En el intento 7, por ejemplo, el parcial pasó de «con permiso» a «con pero un litro y» y luego a «con pero un litro y medio de glifosato por ciento ochenta».
  - En los intentos 1 a 3, el panel de texto provisional quedaba **debajo del borde inferior** de la pantalla y sólo se vio al desplazarse, después de «Detener». Es un problema de presentación, no del motor.
- **Tiempo hasta el borrador:** unos 3,5 s desde «Detener», medido en el vídeo en los intentos 1 y 7. El registro da entre 2,8 y 3,6 s de revisión por frase en los nueve casos.
- **Carga de la revisión:** «segunda pasada cargada en 122 ms / 160 ms / 133 ms», una vez por pantalla de voz abierta. No hubo espera visible en el primer intento.
- **Edición y respuesta tardía:**
  - Roderich cambió a mano el precio de la línea 1, de 180 a 170, y quedó marcado «Corregido a mano».
  - Después dictó tres veces más: los intentos 4, 5 y 7. El 170 se conservó; el intento 7 añadió una línea 2 en lugar de tocar la línea editada.
  - En el intento 4 tocó el campo de cantidad mientras la frase estaba «revisando», y el campo no cambió.
  - **No se dio** el caso exacto de una respuesta tardía que escriba en el mismo campo que se está editando.
- **Cancelar y volver a dictar:**
  - Hacia 08:15 borró las dos líneas, volvió a «Registrar por voz» y entró otra vez en «Compra por voz».
  - El borrador empezó vacío y «Ya aplicado al borrador» también: no quedó nada del intento anterior.
  - El intento 10, «Hablar» y «Detener» seguidos, no dejó texto.
- **Texto duplicado y borrador perdido:** no se vieron.
  - Dictar la misma compra dos veces sobre el mismo borrador añade una segunda línea (intento 7), porque cada frase añade líneas. No se trata como duplicado.
- **Teclado:** en los intentos 4 y 5 el teclado numérico quedó abierto sobre la pantalla de voz y tapaba la mitad inferior mientras dictaba.
- **Después del dictado (08:24 a 09:41):** Roderich recorrió otras pantallas de AC VOZ, sin dictado y sin eventos de voz en el registro.
  - En el tramo que empieza a las 09:26:51 aparece un momento fuera de AC VOZ; no se describe.
  - Desde ese tramo la barra de estado ya no muestra el modo avión y sí señal y Wi‑Fi.

## 2. Hallazgos

### 2.1 «un litro y medio» se lee como 1 L, y «y medio de glifosato» como producto. Reproducido en HOST

- **Prioridad:** altera cantidad y producto, así que es de los que se corrigen primero.
- **Cuándo pasa:** con el texto de Vosk (intento 2) y también con el texto revisado y aceptado (intentos 3 y 7). El reconocimiento oyó bien; el error está en la lectura del borrador.
- **Reproducción en HOST** (2026-11-05, sobre `1c8b789`, con `interpretPurchase` y el catálogo de la cuenta; prueba temporal, no incorporada):

| Texto exacto | Cantidad | Producto |
|---|---|---|
| «compré un litro y medio de glifosato por ciento ochenta o el hierbas» | «un litro», sin valor base | ambiguo: «y medio de glifosato» |
| «Compre un litro y medio de Glifosato por 180 bolivianos.» | «un litro» | ambiguo: «y medio de glifosato» |
| «Compré 1 litro y medio de Glifosato por 180 bolivianos.» | «1 litro» | ambiguo: «y medio de glifosato» |
| Control: «compré uno y medio litros de glifosato por ciento ochenta bolivianos» | 1 500 (1,5 L) | Glifosato |

- **Causa probable:**
  - `spanish_numbers.dart` admite «uno y medio» y «coma cinco»;
  - no admite «y medio» **después** de la unidad, que es como se dice normalmente.
- **Propuesta, no aplicada en este lote:**
  - leer «<número> <unidad> y medio(a)» como el número más 0,5;
  - no tomar «y medio» como parte del nombre del producto;
  - cubrirlo con estas cuatro frases en `voice_purchase_draft_test.dart` y en las pruebas de aplicación y planificación.
- **Efecto sobre la revisión:** la regla «nunca cambia cantidades» compara las cantidades con este mismo lector.
  - Con el error, Vosk y la revisión pueden parecer distintos o iguales por el motivo equivocado.
  - Hay que volver a comprobarlo después de corregir.

### 2.2 Pausa antes del producto: «de Mancozeb» queda como una frase suelta y no llega al borrador

- **Exacto en pantalla:**
  - frase 0: «aplique doscientos cincuenta mil litros»;
  - frase 1: «de manco sepe» (intento 9) y «de manco ser» (intento 8).
- **Veredicto de la revisión de la frase 1:** `degenerate`, es decir, repeticiones o longitud desproporcionada frente a las 3 palabras de Vosk. Se quedó el texto de Vosk.
- **Lo que pasó:**
  - la pausa partió la frase en dos;
  - la primera parte se reconoció como otra operación (aplicación) y no cambió el plan;
  - la segunda no contiene producto ni cantidad que lea el borrador.
  - Reproducido en HOST con esos textos: 0 líneas, tanto en planificación como en aplicación.
  - Con la frase entera y bien oída, «apliqué doscientos cincuenta mililitros de mancozeb», la aplicación sí resuelve Mancozeb y la cantidad.
- **Errores de reconocimiento en el texto que se quedó:**
  - «mililitros» se oyó «mil litros»: unidad, y valor ×1 000 si llegara al borrador;
  - «Mancozeb» se oyó «manco sepe/ser».
  - La revisión de la frase 0 se descartó por `quantities`; qué cantidad oyó no se registra.
- **Reproducción con su voz:** pendiente. Necesita a Roderich en el POCO y, esta vez, en **Aplicación por voz**.
- **Sin propuesta de cambio todavía.**
  - Unir una frase sin verbo ni cantidad a la anterior cambiaría cómo se cortan las frases.
  - Primero hay que repetir el caso en la pantalla correcta.

### 2.3 «Ya aplicado al borrador» aparece aunque no se aplicó nada

Los intentos 6, 8 y 9 muestran el texto bajo «Ya aplicado al borrador», pero el borrador no cambió. Es un problema de presentación: el rótulo hace creer que algo se aplicó.

### 2.4 La revisión se descartó por cantidades en 5 de 9 frases

En esos casos se quedó el texto de Vosk, que traía los errores de cantidad y unidad de los intentos 1 y 9. Es el comportamiento acordado: la revisión nunca cambia cantidades. Se anota para la comparación con small y para #12. No se cambia en este lote.

## 3. Red al terminar

- El POCO **se desconectó del USB** hacia las 09:44, antes de poder restaurar la red por `adb`.
- La grabación indica que la red volvió a activarse desde el teléfono hacia las 09:27. No lo comprobamos.
- **Queda para Roderich:** confirmar en el teléfono que el modo avión está desactivado y que el Wi‑Fi y los datos móviles están activos.
- «AC VOZ» sigue instalada para practicar.

## 4. Datos del ensayo

- El vídeo y los fotogramas se usaron para esta descripción y se borraron después. Nada de eso entra en el repositorio.
- El registro de la app filtrado por proceso tampoco se incorpora. Sólo contiene códigos y tiempos, los citados arriba.
